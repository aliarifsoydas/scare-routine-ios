import Foundation

// MARK: - Schedule

/// `RoutineScheduleSchema` zod shape ile birebir.
/// Backend JSON encode/decode camelCase ↔ snake_case (APIClient default).
struct RoutineSchedulePayload: Codable, Hashable {
    /// 1 = Monday, 7 = Sunday
    var days: [Int]?
    /// "HH:mm" format ("07:30")
    var time: String?
    /// IANA timezone ("Europe/Istanbul")
    var tz: String?
    /// "daily" | "weekly" | "every_n_weeks" | "custom"
    var frequency: String?
    var everyNWeeks: Int?
}

// MARK: - Step

struct RoutineStepResponse: Decodable, Identifiable, Hashable {
    let id: String
    let routineId: String?
    let userProductId: String?
    let orderIndex: Int
    let instruction: String?
    let durationSeconds: Int?
    let isOptional: Bool
    /// Haftalık takvim — [1..7], Pzt=1..Paz=7. nil = her gün.
    let daysActive: [Int]?
    /// "2× haftada", "Sal + Cum" gibi insan-okunabilir etiket.
    let frequencyLabel: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.routineId = try? c.decodeIfPresent(String.self, forKey: .routineId)
        self.userProductId = try? c.decodeIfPresent(String.self, forKey: .userProductId)
        self.orderIndex = (try? c.decodeIfPresent(Int.self, forKey: .orderIndex)) ?? 0
        self.instruction = try? c.decodeIfPresent(String.self, forKey: .instruction)
        self.durationSeconds = try? c.decodeIfPresent(Int.self, forKey: .durationSeconds)
        // SQLite 0/1 int veya Bool olabilir
        if let b = try? c.decodeIfPresent(Bool.self, forKey: .isOptional) {
            self.isOptional = b
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .isOptional) {
            self.isOptional = (i != 0)
        } else {
            self.isOptional = false
        }
        // daysActive: backend TEXT (JSON string) veya direct array dönebilir
        if let arr = try? c.decodeIfPresent([Int].self, forKey: .daysActive) {
            self.daysActive = arr.isEmpty ? nil : arr
        } else if let raw = try? c.decodeIfPresent(String.self, forKey: .daysActive),
                  let data = raw.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([Int].self, from: data) {
            self.daysActive = arr.isEmpty ? nil : arr
        } else {
            self.daysActive = nil
        }
        self.frequencyLabel = try? c.decodeIfPresent(String.self, forKey: .frequencyLabel)
    }

    private enum CodingKeys: String, CodingKey {
        case id, routineId, userProductId, orderIndex, instruction,
             durationSeconds, isOptional, daysActive, frequencyLabel
    }
}

struct RoutineStepPayload: Encodable {
    var userProductId: String?
    var instruction: String?
    var durationSeconds: Int?
    var isOptional: Bool = false
    /// Haftalık takvim — [1..7], Pzt=1..Paz=7. nil = her gün.
    var daysActive: [Int]?
    var frequencyLabel: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(userProductId, forKey: .userProductId)
        try c.encodeIfPresent(instruction, forKey: .instruction)
        try c.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try c.encode(isOptional, forKey: .isOptional)
        try c.encodeIfPresent(daysActive, forKey: .daysActive)
        try c.encodeIfPresent(frequencyLabel, forKey: .frequencyLabel)
    }

    private enum CodingKeys: String, CodingKey {
        case userProductId, instruction, durationSeconds, isOptional, daysActive, frequencyLabel
    }
}

// MARK: - Routine

struct RoutineResponse: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let categoryId: String?
    let schedule: RoutineSchedulePayload?
    let reminder: Bool
    let colorHex: String?
    let emoji: String?
    let orderIndex: Int
    let isActive: Bool
    let createdAt: Int?
    let updatedAt: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? L("Rutin")
        self.categoryId = try? c.decodeIfPresent(String.self, forKey: .categoryId)

        // Schedule: backend TEXT (JSON string) veya direct object dönebilir
        if let s = try? c.decodeIfPresent(RoutineSchedulePayload.self, forKey: .schedule) {
            self.schedule = s
        } else if let raw = try? c.decodeIfPresent(String.self, forKey: .schedule),
                  let data = raw.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode(RoutineSchedulePayload.self, from: data) {
            self.schedule = parsed
        } else {
            self.schedule = nil
        }

        // Reminder: 0/1 int veya Bool
        if let b = try? c.decodeIfPresent(Bool.self, forKey: .reminder) { self.reminder = b }
        else if let i = try? c.decodeIfPresent(Int.self, forKey: .reminder) { self.reminder = (i != 0) }
        else { self.reminder = false }

        self.colorHex = try? c.decodeIfPresent(String.self, forKey: .colorHex)
        self.emoji = try? c.decodeIfPresent(String.self, forKey: .emoji)
        self.orderIndex = (try? c.decodeIfPresent(Int.self, forKey: .orderIndex)) ?? 0

        if let b = try? c.decodeIfPresent(Bool.self, forKey: .isActive) { self.isActive = b }
        else if let i = try? c.decodeIfPresent(Int.self, forKey: .isActive) { self.isActive = (i != 0) }
        else { self.isActive = true }

        self.createdAt = try? c.decodeIfPresent(Int.self, forKey: .createdAt)
        self.updatedAt = try? c.decodeIfPresent(Int.self, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, categoryId, schedule, reminder
        case colorHex, emoji, orderIndex, isActive
        case createdAt, updatedAt
    }
}

struct RoutineCreateRequest: Encodable {
    let name: String
    var categoryId: String?
    var schedule: RoutineSchedulePayload?
    var reminder: Bool = false
    var colorHex: String?
    var emoji: String?
    var orderIndex: Int = 0
    var steps: [RoutineStepPayload] = []

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(categoryId, forKey: .categoryId)
        try c.encodeIfPresent(schedule, forKey: .schedule)
        try c.encode(reminder, forKey: .reminder)
        try c.encodeIfPresent(colorHex, forKey: .colorHex)
        try c.encodeIfPresent(emoji, forKey: .emoji)
        try c.encode(orderIndex, forKey: .orderIndex)
        try c.encode(steps, forKey: .steps)
    }

    private enum CodingKeys: String, CodingKey {
        case name, categoryId, schedule, reminder, colorHex, emoji, orderIndex, steps
    }
}

struct RoutineUpdateRequest: Encodable {
    var name: String?
    var categoryId: String?
    var schedule: RoutineSchedulePayload?
    var reminder: Bool?
    var colorHex: String?
    var emoji: String?
    var orderIndex: Int?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(categoryId, forKey: .categoryId)
        try c.encodeIfPresent(schedule, forKey: .schedule)
        try c.encodeIfPresent(reminder, forKey: .reminder)
        try c.encodeIfPresent(colorHex, forKey: .colorHex)
        try c.encodeIfPresent(emoji, forKey: .emoji)
        try c.encodeIfPresent(orderIndex, forKey: .orderIndex)
    }

    private enum CodingKeys: String, CodingKey {
        case name, categoryId, schedule, reminder, colorHex, emoji, orderIndex
    }
}

// MARK: - Endpoint wrappers

struct ListRoutinesResponse: Decodable {
    let routines: [RoutineResponse]
}

struct RoutineDetailResponse: Decodable {
    let routine: RoutineResponse
    let steps: [RoutineStepResponse]?
}

struct CreateRoutineResponse: Decodable {
    let routine: RoutineResponse
    let steps: [RoutineStepResponse]?
}

// MARK: - Log

struct RoutineLogPayload: Encodable {
    let routineId: String
    let logDate: String                     // "YYYY-MM-DD"
    var completedStepIds: [String] = []
    var skippedStepIds: [String] = []
    var mood: String?
    var weather: String?
}

struct RoutineLogResponse: Decodable, Identifiable, Hashable {
    let id: String
    let routineId: String?
    let logDate: String?
    let completedStepIds: [String]?
    let skippedStepIds: [String]?
    let completionPct: Int?
    let mood: String?
    let weather: String?
    let createdAt: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.routineId = try? c.decodeIfPresent(String.self, forKey: .routineId)
        self.logDate = try? c.decodeIfPresent(String.self, forKey: .logDate)
        // Backend SQLite TEXT (JSON array) — array veya string olabilir
        self.completedStepIds = Self.decodeJsonStringArray(c, key: .completedStepIds)
        self.skippedStepIds = Self.decodeJsonStringArray(c, key: .skippedStepIds)
        self.completionPct = try? c.decodeIfPresent(Int.self, forKey: .completionPct)
        self.mood = try? c.decodeIfPresent(String.self, forKey: .mood)
        self.weather = try? c.decodeIfPresent(String.self, forKey: .weather)
        self.createdAt = try? c.decodeIfPresent(Int.self, forKey: .createdAt)
    }

    private static func decodeJsonStringArray(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> [String]? {
        if let arr = try? c.decodeIfPresent([String].self, forKey: key) { return arr }
        if let raw = try? c.decodeIfPresent(String.self, forKey: key),
           let data = raw.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String].self, from: data) {
            return parsed
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, routineId, logDate, completedStepIds, skippedStepIds
        case completionPct, mood, weather, createdAt
    }
}
