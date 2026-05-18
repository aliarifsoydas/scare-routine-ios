import Foundation

// MARK: - POST /v1/me/skin-logs

/// Backend `POST /v1/me/skin-logs` body'si.
///
/// `logDate` kullanıcı timezone'unda "YYYY-MM-DD". `photoMode` profile'deki
/// `defaultPhotoMode`'dan kopyalanır — backend selfie post-process pipeline'ı
/// "metrics_only" geldiğinde gözlemleri çıkardıktan sonra R2'deki fotoyu siler,
/// "photo_kept"te orijinal saklı kalır.
///
/// Tüm self-* metrikler 1-5 ölçeğinde, opsiyonel. `subjectiveNotes` kullanıcının
/// serbest metni. `symptoms` chip multi-select listesi (örn. ["kuruluk", "kaşıntı"]).
///
/// API client snake_case strategy uyguladığı için Swift'te camelCase tutulur,
/// backend'e snake_case gider (logDate → log_date, vs).
struct SkinLogCreateRequest: Encodable {
    let logDate: String
    let category: String              // "face" | "scalp" | "body"
    let selfieUrl: String?
    let photoMode: String             // "metrics_only" | "photo_kept"
    let selfHydration: Int?           // 1-5
    let selfRedness: Int?
    let selfOiliness: Int?
    let selfBreakouts: Int?
    let selfOverall: Int?
    let symptoms: [String]?
    let sleepHours: Double?
    let stressLevel: Int?             // 1-5
    let subjectiveNotes: String?
}

// MARK: - GET /v1/me/skin-logs item

/// Backend'in döndürdüğü tek bir cilt logu kaydı.
///
/// Backend D1 row'unu olduğu gibi yolladığı için tüm metrik alanlar opsiyonel.
/// `aiObservations` backend post-process pipeline'ı tarafından doldurulan JSON
/// objesi; metrics_only modunda foto silinmeden önceki AI gözlemleri buraya yazılır.
///
/// `init(from:)` defensive — her field individually `try?` ile decode edilir,
/// uyumsuz tip varsa nil olur. Bu pattern `ProfileData` ve `UserProductResponse`
/// ile tutarlı.
struct SkinLogResponse: Decodable, Identifiable, Hashable {
    let id: String
    let logDate: String
    let category: String
    let selfieUrl: String?
    let photoMode: String?
    let selfHydration: Int?
    let selfRedness: Int?
    let selfOiliness: Int?
    let selfBreakouts: Int?
    let selfOverall: Int?
    let symptoms: [String]?
    let sleepHours: Double?
    let stressLevel: Int?
    let subjectiveNotes: String?
    let aiObservations: AIObservationsPayload?
    let aiImageQuality: String?
    let aiConfidence: String?
    let cyclePhase: String?
    let cycleDay: Int?
    let createdAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id))
            ?? (try? String(c.decode(Int.self, forKey: .id)))
            ?? UUID().uuidString
        self.logDate = (try? c.decodeIfPresent(String.self, forKey: .logDate)) ?? ""
        self.category = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? "face"
        self.selfieUrl = try? c.decodeIfPresent(String.self, forKey: .selfieUrl)
        self.photoMode = try? c.decodeIfPresent(String.self, forKey: .photoMode)
        self.selfHydration = try? c.decodeIfPresent(Int.self, forKey: .selfHydration)
        self.selfRedness = try? c.decodeIfPresent(Int.self, forKey: .selfRedness)
        self.selfOiliness = try? c.decodeIfPresent(Int.self, forKey: .selfOiliness)
        self.selfBreakouts = try? c.decodeIfPresent(Int.self, forKey: .selfBreakouts)
        self.selfOverall = try? c.decodeIfPresent(Int.self, forKey: .selfOverall)

        // symptoms: [String] direkt array veya JSON-string (D1 TEXT) olabilir
        if let arr = try? c.decodeIfPresent([String].self, forKey: .symptoms) {
            self.symptoms = arr
        } else if let raw = try? c.decodeIfPresent(String.self, forKey: .symptoms),
                  let data = raw.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode([String].self, from: data) {
            self.symptoms = parsed
        } else {
            self.symptoms = nil
        }

        self.sleepHours = try? c.decodeIfPresent(Double.self, forKey: .sleepHours)
        self.stressLevel = try? c.decodeIfPresent(Int.self, forKey: .stressLevel)
        self.subjectiveNotes = try? c.decodeIfPresent(String.self, forKey: .subjectiveNotes)

        // aiObservations: nested object veya D1'de TEXT JSON string
        if let nested = try? c.decodeIfPresent(AIObservationsPayload.self, forKey: .aiObservations) {
            self.aiObservations = nested
        } else if let raw = try? c.decodeIfPresent(String.self, forKey: .aiObservations),
                  let data = raw.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(AIObservationsPayload.self, from: data) {
            self.aiObservations = parsed
        } else {
            self.aiObservations = nil
        }

        self.aiImageQuality = try? c.decodeIfPresent(String.self, forKey: .aiImageQuality)
        self.aiConfidence = try? c.decodeIfPresent(String.self, forKey: .aiConfidence)
        self.cyclePhase = try? c.decodeIfPresent(String.self, forKey: .cyclePhase)
        self.cycleDay = try? c.decodeIfPresent(Int.self, forKey: .cycleDay)
        self.createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, logDate, category, selfieUrl, photoMode
        case selfHydration, selfRedness, selfOiliness, selfBreakouts, selfOverall
        case symptoms, sleepHours, stressLevel, subjectiveNotes
        case aiObservations, aiImageQuality, aiConfidence
        case cyclePhase, cycleDay, createdAt
    }
}

/// `ai_observations` JSON payload'u. Backend Gemini Flash'ın gözlem JSON çıktısını
/// burada saklar. Tüm alanlar opsiyonel — metrics_only modda da photo_kept modda da
/// aynı şekil döner; foto silinmiş olsa bile gözlemler kalıcı.
struct AIObservationsPayload: Decodable, Hashable {
    let observations: [String]?
    let lightingQuality: String?
    let imageUsable: Bool?
    let confidence: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.observations = try? c.decodeIfPresent([String].self, forKey: .observations)
        self.lightingQuality = try? c.decodeIfPresent(String.self, forKey: .lightingQuality)
        if let b = try? c.decodeIfPresent(Bool.self, forKey: .imageUsable) {
            self.imageUsable = b
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .imageUsable) {
            self.imageUsable = (i != 0)
        } else {
            self.imageUsable = nil
        }
        self.confidence = try? c.decodeIfPresent(String.self, forKey: .confidence)
    }

    private enum CodingKeys: String, CodingKey {
        case observations, lightingQuality, imageUsable, confidence
    }
}

// MARK: - Cevap sarmalayıcıları

/// `GET /v1/me/skin-logs` → `{ items: [...] }`
struct ListSkinLogsResponse: Decodable {
    let items: [SkinLogResponse]
}

/// `POST /v1/me/skin-logs` → `{ item: {...} }`
struct CreateSkinLogResponse: Decodable {
    let item: SkinLogResponse
}

// MARK: - Trendler

/// `GET /v1/me/skin-trends?metric=&days=` — günlük seriye ait nokta listesi.
/// `points` her gün için bir kayıt; o gün veri yoksa `value=nil` döner.
struct SkinTrendsResponse: Decodable {
    let metric: String
    let points: [TrendPoint]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.metric = (try? c.decodeIfPresent(String.self, forKey: .metric)) ?? ""
        self.points = (try? c.decodeIfPresent([TrendPoint].self, forKey: .points)) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case metric, points
    }
}

struct TrendPoint: Decodable, Hashable {
    let date: String          // "YYYY-MM-DD"
    let value: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.date = (try? c.decodeIfPresent(String.self, forKey: .date)) ?? ""
        if let d = try? c.decodeIfPresent(Double.self, forKey: .value) {
            self.value = d
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .value) {
            self.value = Double(i)
        } else {
            self.value = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case date, value
    }
}
