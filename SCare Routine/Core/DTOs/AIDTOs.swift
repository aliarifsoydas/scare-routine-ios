import Foundation

/// `POST /v1/ai/recommend-routine` request body.
struct AIRecommendRoutineRequest: Encodable {
    let targetTime: String  // "morning" | "evening"
    let language: String?
    let focus: String?

    enum CodingKeys: String, CodingKey {
        case targetTime, language, focus
    }
}

/// Tek bir öneri adımı — backend'den dönen veri.
struct AIRecommendStep: Decodable, Identifiable, Hashable {
    /// SwiftUI ForEach için stable id — userProductId + orderIndex
    var id: String { "\(userProductId)#\(orderIndex)" }

    let userProductId: String
    let orderIndex: Int
    let instruction: String?
    let rationale: String
    let addresses: [String]
    /// Haftalık aktif günler [1..7]. nil = her gün.
    let daysActive: [Int]?
    /// "2× haftada", "Sal + Cum" gibi etiket.
    let frequencyLabel: String?

    enum CodingKeys: String, CodingKey {
        case userProductId, orderIndex, instruction, rationale, addresses, daysActive, frequencyLabel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.userProductId = try c.decode(String.self, forKey: .userProductId)
        self.orderIndex = try c.decode(Int.self, forKey: .orderIndex)
        self.instruction = try? c.decodeIfPresent(String.self, forKey: .instruction)
        self.rationale = try c.decode(String.self, forKey: .rationale)
        self.addresses = (try? c.decodeIfPresent([String].self, forKey: .addresses)) ?? []
        if let arr = try? c.decodeIfPresent([Int].self, forKey: .daysActive) {
            self.daysActive = arr.isEmpty ? nil : arr
        } else {
            self.daysActive = nil
        }
        self.frequencyLabel = try? c.decodeIfPresent(String.self, forKey: .frequencyLabel)
    }
}

/// Backend response için cache metadata. `cached: true` ise sonuç önceki
/// bir çağrıdan döndürülmüştür ve `cachedAt` üretildiği zamanı içerir.
struct AIRecommendRoutineMeta: Decodable {
    let cached: Bool
    let cachedAt: Date?

    enum CodingKeys: String, CodingKey {
        case cached, cachedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.cached = (try? c.decodeIfPresent(Bool.self, forKey: .cached)) ?? false
        if let raw = try? c.decodeIfPresent(String.self, forKey: .cachedAt) {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.cachedAt = iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        } else {
            self.cachedAt = nil
        }
    }
}

// MARK: - Weekly Plan

/// `POST /v1/ai/recommend-weekly-plan` request body.
///
/// Backend `WeeklyPlanBody` zod schema'sı `language` field bekler (recommend-routine
/// ile tutarlı). iOS tarafında parametre adı `locale` olarak okunur ama wire'a
/// `language` key'iyle yazılır.
struct AIRecommendWeeklyPlanRequest: Encodable {
    let locale: String
    let focus: String?

    enum CodingKeys: String, CodingKey {
        case language, focus
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(locale, forKey: .language)
        try c.encodeIfPresent(focus, forKey: .focus)
    }
}

/// Tek bir günün morning/evening içindeki adım. `AIRecommendStep`'e benzer ama
/// `addresses` ve `frequencyLabel` alanları nullable/optional davranışla decode edilir.
struct WeeklyPlanStep: Decodable, Identifiable, Hashable {
    /// SwiftUI ForEach için stable id — userProductId + orderIndex
    var id: String { "\(userProductId)#\(orderIndex)" }

    let userProductId: String
    let orderIndex: Int
    let instruction: String?
    let rationale: String
    let addresses: [String]
    let frequencyLabel: String?

    enum CodingKeys: String, CodingKey {
        case userProductId, orderIndex, instruction, rationale, addresses, frequencyLabel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.userProductId = try c.decode(String.self, forKey: .userProductId)
        self.orderIndex = (try? c.decodeIfPresent(Int.self, forKey: .orderIndex)) ?? 0
        self.instruction = try? c.decodeIfPresent(String.self, forKey: .instruction)
        self.rationale = (try? c.decodeIfPresent(String.self, forKey: .rationale)) ?? ""
        self.addresses = (try? c.decodeIfPresent([String].self, forKey: .addresses)) ?? []
        self.frequencyLabel = try? c.decodeIfPresent(String.self, forKey: .frequencyLabel)
    }
}

/// Haftalık planın bir günü. `dayOfWeek` 1..7 (Mon..Sun) — ISO weekday.
struct WeeklyPlanDay: Decodable, Identifiable, Hashable {
    /// SwiftUI ForEach için stable id — dayOfWeek
    var id: Int { dayOfWeek }

    let dayOfWeek: Int
    let dayName: String
    let restDay: Bool
    let morningSteps: [WeeklyPlanStep]
    let eveningSteps: [WeeklyPlanStep]
    let dayFocus: String
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case dayOfWeek, dayName, restDay
        case morningSteps, eveningSteps
        case dayFocus, warnings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.dayOfWeek = (try? c.decodeIfPresent(Int.self, forKey: .dayOfWeek)) ?? 1
        self.dayName = (try? c.decodeIfPresent(String.self, forKey: .dayName)) ?? ""
        // restDay: backend bool veya 0/1 int dönebilir
        if let b = try? c.decodeIfPresent(Bool.self, forKey: .restDay) {
            self.restDay = b
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .restDay) {
            self.restDay = (i != 0)
        } else {
            self.restDay = false
        }
        self.morningSteps = (try? c.decodeIfPresent([WeeklyPlanStep].self, forKey: .morningSteps)) ?? []
        self.eveningSteps = (try? c.decodeIfPresent([WeeklyPlanStep].self, forKey: .eveningSteps)) ?? []
        self.dayFocus = (try? c.decodeIfPresent(String.self, forKey: .dayFocus)) ?? ""
        self.warnings = (try? c.decodeIfPresent([String].self, forKey: .warnings)) ?? []
    }
}

/// `POST /v1/ai/recommend-weekly-plan` response payload — 7 günlük plan + meta.
struct WeeklyPlanResponse: Decodable {
    let days: [WeeklyPlanDay]
    let weeklyNotes: String
    let activeRotationSummary: String
    let suitabilityScore: Int
    let missingCategories: [String]
    let warnings: [String]
    /// Opsiyonel cache metadata — `recommend-routine` ile aynı pattern.
    let meta: AIRecommendRoutineMeta?

    enum CodingKeys: String, CodingKey {
        case days, weeklyNotes, activeRotationSummary
        case suitabilityScore, missingCategories, warnings
        case meta = "_meta"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.days = (try? c.decodeIfPresent([WeeklyPlanDay].self, forKey: .days)) ?? []
        self.weeklyNotes = (try? c.decodeIfPresent(String.self, forKey: .weeklyNotes)) ?? ""
        self.activeRotationSummary = (try? c.decodeIfPresent(String.self, forKey: .activeRotationSummary)) ?? ""
        self.suitabilityScore = (try? c.decodeIfPresent(Int.self, forKey: .suitabilityScore)) ?? 0
        self.missingCategories = (try? c.decodeIfPresent([String].self, forKey: .missingCategories)) ?? []
        self.warnings = (try? c.decodeIfPresent([String].self, forKey: .warnings)) ?? []
        self.meta = try? c.decodeIfPresent(AIRecommendRoutineMeta.self, forKey: .meta)
    }
}

// MARK: - Recommend Routine

/// `POST /v1/ai/recommend-routine` response payload.
struct AIRecommendRoutineResponse: Decodable {
    let steps: [AIRecommendStep]
    let routineNotes: String
    let suitabilityScore: Int
    let missingCategories: [String]
    let warnings: [String]
    /// Opsiyonel cache metadata — backend response'unda `_meta.cached: true` varsa
    /// UI "Son güncelleme: 2 saat önce" gibi bir hint gösterebilir.
    let meta: AIRecommendRoutineMeta?

    enum CodingKeys: String, CodingKey {
        case steps, routineNotes, suitabilityScore, missingCategories, warnings
        case meta = "_meta"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.steps = (try? c.decodeIfPresent([AIRecommendStep].self, forKey: .steps)) ?? []
        self.routineNotes = (try? c.decodeIfPresent(String.self, forKey: .routineNotes)) ?? ""
        self.suitabilityScore = (try? c.decodeIfPresent(Int.self, forKey: .suitabilityScore)) ?? 0
        self.missingCategories = (try? c.decodeIfPresent([String].self, forKey: .missingCategories)) ?? []
        self.warnings = (try? c.decodeIfPresent([String].self, forKey: .warnings)) ?? []
        self.meta = try? c.decodeIfPresent(AIRecommendRoutineMeta.self, forKey: .meta)
    }
}
