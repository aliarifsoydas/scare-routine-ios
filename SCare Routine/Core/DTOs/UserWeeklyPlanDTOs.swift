import Foundation

/// `GET /v1/me/weekly-plan` response — backend kullanıcının kabul ettiği planı
/// `user_weekly_plans` tablosundan döner. 404 → kullanıcı henüz plan kabul etmedi.
///
/// `plan` alanı `WeeklyPlanResponse` ile birebir aynı shape; backend POST sırasında
/// AI response'unu olduğu gibi JSON column'a yazar, GET'te de aynı şekilde geri verir.
struct UserWeeklyPlanResponse: Decodable {
    let plan: WeeklyPlanResponse
    let locale: String
    let source: String
    /// Plan ne zaman kabul edildi — `secondsSince1970` (APIClient decoder default'u).
    let acceptedAt: Date
    let modelUsed: String?

    enum CodingKeys: String, CodingKey {
        case plan, locale, source, acceptedAt, modelUsed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.plan = try c.decode(WeeklyPlanResponse.self, forKey: .plan)
        self.locale = (try? c.decodeIfPresent(String.self, forKey: .locale)) ?? "tr"
        self.source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? "ai_generated"
        if let d = try? c.decode(Date.self, forKey: .acceptedAt) {
            self.acceptedAt = d
        } else if let raw = try? c.decode(Double.self, forKey: .acceptedAt) {
            // Backend epoch saniye olarak yazıyor olabilir
            self.acceptedAt = Date(timeIntervalSince1970: raw)
        } else {
            self.acceptedAt = .now
        }
        self.modelUsed = try? c.decodeIfPresent(String.self, forKey: .modelUsed)
    }
}

/// `POST /v1/me/weekly-plan` request body — kullanıcı suggest edilen planı kabul etti.
///
/// Backend UPSERT yapar; aynı user için ikinci POST mevcut planı replace eder.
struct UserWeeklyPlanRequest: Encodable {
    let plan: WeeklyPlanResponse
    let locale: String
    let source: String?
    let modelUsed: String?

    enum CodingKeys: String, CodingKey {
        case plan, locale, source, modelUsed
    }

    init(
        plan: WeeklyPlanResponse,
        locale: String,
        source: String? = "ai_generated",
        modelUsed: String? = nil
    ) {
        self.plan = plan
        self.locale = locale
        self.source = source
        self.modelUsed = modelUsed
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // WeeklyPlanResponse Encodable değil — `_meta` hariç tüm alanları manuel encode et.
        // Backend'e mirror için intermediate dictionary yerine custom encoder kullanılır.
        try c.encode(WeeklyPlanResponsePayload(plan), forKey: .plan)
        try c.encode(locale, forKey: .locale)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encodeIfPresent(modelUsed, forKey: .modelUsed)
    }
}

/// `POST /v1/me/weekly-plan` 200 response.
struct UserWeeklyPlanAcceptResponse: Decodable {
    let acceptedAt: Date
    let locale: String
    let source: String

    enum CodingKeys: String, CodingKey {
        case acceptedAt, locale, source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let d = try? c.decode(Date.self, forKey: .acceptedAt) {
            self.acceptedAt = d
        } else if let raw = try? c.decode(Double.self, forKey: .acceptedAt) {
            self.acceptedAt = Date(timeIntervalSince1970: raw)
        } else {
            self.acceptedAt = .now
        }
        self.locale = (try? c.decodeIfPresent(String.self, forKey: .locale)) ?? "tr"
        self.source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? "ai_generated"
    }
}

/// View-model — backend `UserWeeklyPlanResponse` + UserDefaults cache için ortak tip.
///
/// HomeView ve WeeklyCalendarView bu struct'ı tüketir; AI suggest sırasındaki
/// `WeeklyPlanResponse` ile karıştırılmaması için ayrı tutuldu.
struct StoredWeeklyPlan: Hashable {
    let plan: WeeklyPlanResponse
    let locale: String
    let source: String
    let acceptedAt: Date
    let modelUsed: String?

    // Hashable: WeeklyPlanResponse'un kendisi Hashable değil; pratik bir
    // disambiguator yerine acceptedAt + locale yeterli (her zaman unique).
    func hash(into hasher: inout Hasher) {
        hasher.combine(acceptedAt)
        hasher.combine(locale)
        hasher.combine(source)
    }

    static func == (lhs: StoredWeeklyPlan, rhs: StoredWeeklyPlan) -> Bool {
        lhs.acceptedAt == rhs.acceptedAt &&
        lhs.locale == rhs.locale &&
        lhs.source == rhs.source
    }
}

// MARK: - WeeklyPlanResponse encode payload
//
// `WeeklyPlanResponse` yalnızca Decodable — backend'den okumak için tasarlandı.
// Accept POST'unda planı geri yazmak gerek; bu yardımcı struct ona Encodable
// mirror sağlar. Tek source-of-truth `WeeklyPlanResponse` kalır.

private struct WeeklyPlanResponsePayload: Encodable {
    let days: [WeeklyPlanDayPayload]
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
        self.days = resp.days.map(WeeklyPlanDayPayload.init)
        self.weeklyNotes = resp.weeklyNotes
        self.activeRotationSummary = resp.activeRotationSummary
        self.suitabilityScore = resp.suitabilityScore
        self.missingCategories = resp.missingCategories
        self.warnings = resp.warnings
    }
}

private struct WeeklyPlanDayPayload: Encodable {
    let dayOfWeek: Int
    let dayName: String
    let restDay: Bool
    let morningSteps: [WeeklyPlanStepPayload]
    let eveningSteps: [WeeklyPlanStepPayload]
    let dayFocus: String
    let warnings: [String]

    init(_ d: WeeklyPlanDay) {
        self.dayOfWeek = d.dayOfWeek
        self.dayName = d.dayName
        self.restDay = d.restDay
        self.morningSteps = d.morningSteps.map(WeeklyPlanStepPayload.init)
        self.eveningSteps = d.eveningSteps.map(WeeklyPlanStepPayload.init)
        self.dayFocus = d.dayFocus
        self.warnings = d.warnings
    }
}

private struct WeeklyPlanStepPayload: Encodable {
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
