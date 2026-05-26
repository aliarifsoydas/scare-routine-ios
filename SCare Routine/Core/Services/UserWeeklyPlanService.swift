import Foundation
import OSLog

/// User-accepted persistent weekly plan servisi.
///
/// `AIRecommendService.recommendWeeklyPlan` AI'dan **suggest** alır;
/// kullanıcı kabul ettiği planı backend'e POST eder ve sonraki açılışlarda
/// **GET ile aynı planı** geri okur — AI tekrar çağrılmaz, loading flash yok.
///
/// Backend kontratı:
/// - GET    /v1/me/weekly-plan  → 200 plan / 404 no_active_plan
/// - POST   /v1/me/weekly-plan  → 200 (UPSERT — replace mevcut planı)
/// - DELETE /v1/me/weekly-plan  → 204
///
/// Offline ilk açılış için UserDefaults mirror'ı tutar. App boot UserDefaults'tan
/// instant okur, paralelde backend GET ile sync eder; çelişki varsa backend kazanır.
@MainActor
final class UserWeeklyPlanService {
    static let shared = UserWeeklyPlanService()

    private let api = APIClient.shared
    private let logger = Logger(subsystem: "com.aliarifsoydas.scareroutine", category: "UserWeeklyPlan")

    private let defaultsKey = "scare.weeklyPlan"

    private init() {}

    // MARK: - Backend

    /// Kullanıcının kabul ettiği planı oku. 404 → henüz yok (nil).
    ///
    /// Diğer hataları (401, network) caller yakalar; bu fonksiyon throw eder.
    /// Başarılı sonuç UserDefaults'a da mirror edilir — bir sonraki açılış için.
    func getCurrent() async throws -> StoredWeeklyPlan? {
        do {
            let resp: UserWeeklyPlanResponse = try await api.request(.meWeeklyPlanGet)
            let stored = StoredWeeklyPlan(
                plan: resp.plan,
                locale: resp.locale,
                source: resp.source,
                acceptedAt: resp.acceptedAt,
                modelUsed: resp.modelUsed
            )
            writeMirror(stored)
            return stored
        } catch APIError.notFound {
            // Backend 404: kullanıcı henüz plan kabul etmedi.
            // UserDefaults'taki eski mirror'ı temizle — backend authoritative.
            clearMirror()
            return nil
        } catch APIError.server(let code, _, _) where code == "no_active_plan" {
            // Backend bazen 400/422 + custom code ile dönebilir; aynı semantik.
            clearMirror()
            return nil
        }
    }

    /// AI'dan gelen `WeeklyPlanResponse`'i backend'e kabul olarak yaz.
    ///
    /// Backend UPSERT yapar; aynı user için ikinci POST mevcut planı **replace** eder
    /// → "Yeniden öner → Kabul et" akışında ekstra DELETE'e gerek yok.
    ///
    /// `modelUsed` opsiyonel — analitik için (`gemini-2.5-flash` gibi). AI response
    /// meta'sında bu bilgi olmadığı için caller bilinen değeri geçirir, yoksa nil.
    @discardableResult
    func accept(
        _ plan: WeeklyPlanResponse,
        locale: String,
        modelUsed: String? = nil,
        source: String = "ai_generated"
    ) async throws -> StoredWeeklyPlan {
        let body = UserWeeklyPlanRequest(
            plan: plan,
            locale: locale,
            source: source,
            modelUsed: modelUsed
        )
        let resp: UserWeeklyPlanAcceptResponse = try await api.request(.meWeeklyPlanAccept, body: body)
        let stored = StoredWeeklyPlan(
            plan: plan,
            locale: resp.locale,
            source: resp.source,
            acceptedAt: resp.acceptedAt,
            modelUsed: modelUsed
        )
        writeMirror(stored)
        return stored
    }

    /// Mevcut planı sil (DELETE). 204 bekleriz.
    /// Sonraki `getCurrent()` 404 dönecek; HomeView "AI suggest" akışına geri girer.
    func discard() async throws {
        do {
            try await api.requestVoid(.meWeeklyPlanDiscard)
        } catch APIError.notFound {
            // Plan zaten yok → discard idempotent
        }
        clearMirror()
    }

    // MARK: - UserDefaults mirror
    //
    // App boot'ta `loadCachedMirror()` ile instant okunur; paralelde `getCurrent()`
    // ile backend authoritative değerle senkronlanır.
    //
    // Format: WeeklyPlanResponse'un raw JSON'u + metadata wrapper. WeeklyPlanResponse
    // sadece Decodable olduğu için manuel serialize edilir; backend response'unu
    // tekrar yazıp tekrar okuruz (round-trip stabil).

    /// Senkron — app boot'ta blocking okunabilir, network'ten önce gösterilir.
    nonisolated func loadCachedMirror() -> StoredWeeklyPlan? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let wrapper = try? JSONDecoder.cacheDecoder.decode(MirrorWrapper.self, from: data) else {
            return nil
        }
        return StoredWeeklyPlan(
            plan: wrapper.plan,
            locale: wrapper.locale,
            source: wrapper.source,
            acceptedAt: wrapper.acceptedAt,
            modelUsed: wrapper.modelUsed
        )
    }

    private func writeMirror(_ stored: StoredWeeklyPlan) {
        // Round-trip için planı re-encode etmek gerek; WeeklyPlanResponse Encodable
        // değil. Trick: zaten backend'den gelen response data'sını cache'lemek en
        // güvenli yol, ama burada `WeeklyPlanResponse` -> JSON re-serialize daha
        // pratik (cache invalidation problemlerini önler).
        let wrapper = MirrorWrapper(
            plan: stored.plan,
            locale: stored.locale,
            source: stored.source,
            acceptedAt: stored.acceptedAt,
            modelUsed: stored.modelUsed
        )
        do {
            let data = try JSONEncoder.cacheEncoder.encode(wrapper)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            logger.warning("weekly plan cache write failed: \(String(describing: error))")
        }
    }

    private func clearMirror() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

// MARK: - Mirror wrapper

/// UserDefaults cache wrapper. WeeklyPlanResponse'u tutmak için iç içe
/// Codable mimik tipini kullanır — WeeklyPlanResponse'un kendisini değiştirmiyoruz.
private struct MirrorWrapper: Codable {
    let plan: WeeklyPlanResponse
    let locale: String
    let source: String
    let acceptedAt: Date
    let modelUsed: String?

    enum CodingKeys: String, CodingKey {
        case plan, locale, source, acceptedAt, modelUsed
    }

    init(
        plan: WeeklyPlanResponse,
        locale: String,
        source: String,
        acceptedAt: Date,
        modelUsed: String?
    ) {
        self.plan = plan
        self.locale = locale
        self.source = source
        self.acceptedAt = acceptedAt
        self.modelUsed = modelUsed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.plan = try c.decode(WeeklyPlanResponse.self, forKey: .plan)
        self.locale = (try? c.decodeIfPresent(String.self, forKey: .locale)) ?? "tr"
        self.source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? "ai_generated"
        if let d = try? c.decode(Date.self, forKey: .acceptedAt) {
            self.acceptedAt = d
        } else {
            self.acceptedAt = .now
        }
        self.modelUsed = try? c.decodeIfPresent(String.self, forKey: .modelUsed)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // WeeklyPlanResponse Encodable değil → MirrorPlanPayload üzerinden encode.
        try c.encode(MirrorPlanPayload(plan), forKey: .plan)
        try c.encode(locale, forKey: .locale)
        try c.encode(source, forKey: .source)
        try c.encode(acceptedAt, forKey: .acceptedAt)
        try c.encodeIfPresent(modelUsed, forKey: .modelUsed)
    }
}

/// Cache için WeeklyPlanResponse'un Encodable kopyası. Production API payload'ından
/// (UserWeeklyPlanDTOs içindeki) farklı olarak `_meta` cache info'sunu da yazar —
/// böylece "Son güncelleme: X önce" gibi UI hint'leri offline'da da çalışır.
private struct MirrorPlanPayload: Codable {
    let days: [MirrorDay]
    let weeklyNotes: String
    let activeRotationSummary: String
    let suitabilityScore: Int
    let missingCategories: [String]
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case days, weeklyNotes, activeRotationSummary
        case suitabilityScore, missingCategories, warnings
    }

    init(_ resp: WeeklyPlanResponse) {
        self.days = resp.days.map(MirrorDay.init)
        self.weeklyNotes = resp.weeklyNotes
        self.activeRotationSummary = resp.activeRotationSummary
        self.suitabilityScore = resp.suitabilityScore
        self.missingCategories = resp.missingCategories
        self.warnings = resp.warnings
    }
}

private struct MirrorDay: Codable {
    let dayOfWeek: Int
    let dayName: String
    let restDay: Bool
    let morningSteps: [MirrorStep]
    let eveningSteps: [MirrorStep]
    let dayFocus: String
    let warnings: [String]

    init(_ d: WeeklyPlanDay) {
        self.dayOfWeek = d.dayOfWeek
        self.dayName = d.dayName
        self.restDay = d.restDay
        self.morningSteps = d.morningSteps.map(MirrorStep.init)
        self.eveningSteps = d.eveningSteps.map(MirrorStep.init)
        self.dayFocus = d.dayFocus
        self.warnings = d.warnings
    }
}

private struct MirrorStep: Codable {
    let userProductId: String
    let orderIndex: Int
    let instruction: String?
    let rationale: String
    let addresses: [String]
    let frequencyLabel: String?

    init(_ s: WeeklyPlanStep) {
        self.userProductId = s.userProductId
        self.orderIndex = s.orderIndex
        self.instruction = s.instruction
        self.rationale = s.rationale
        self.addresses = s.addresses
        self.frequencyLabel = s.frequencyLabel
    }
}

// MARK: - Coders

private extension JSONEncoder {
    /// Cache I/O için snake_case dönüşümü — backend ile aynı.
    static let cacheEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
}

private extension JSONDecoder {
    static let cacheDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}
