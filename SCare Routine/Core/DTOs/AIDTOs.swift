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

/// `POST /v1/ai/recommend-routine` response payload.
struct AIRecommendRoutineResponse: Decodable {
    let steps: [AIRecommendStep]
    let routineNotes: String
    let suitabilityScore: Int
    let missingCategories: [String]
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case steps, routineNotes, suitabilityScore, missingCategories, warnings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.steps = (try? c.decodeIfPresent([AIRecommendStep].self, forKey: .steps)) ?? []
        self.routineNotes = (try? c.decodeIfPresent(String.self, forKey: .routineNotes)) ?? ""
        self.suitabilityScore = (try? c.decodeIfPresent(Int.self, forKey: .suitabilityScore)) ?? 0
        self.missingCategories = (try? c.decodeIfPresent([String].self, forKey: .missingCategories)) ?? []
        self.warnings = (try? c.decodeIfPresent([String].self, forKey: .warnings)) ?? []
    }
}
