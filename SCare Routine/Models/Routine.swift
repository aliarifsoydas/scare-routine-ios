import Foundation
import SwiftData

@Model
final class Routine {
    @Attribute(.unique) var id: String
    var user: User?
    var name: String                         // "Sabah cilt", "Akşam saç"
    var categoryID: String?                  // FK to ProductCategory.id (opsiyonel)
    var schedule: RoutineSchedule
    var reminder: Bool = true
    var colorHex: String?
    var emoji: String?
    var orderIndex: Int = 0
    var isActive: Bool = true
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \RoutineStep.routine)
    var steps: [RoutineStep] = []

    @Relationship(deleteRule: .cascade, inverse: \RoutineLog.routine)
    var logs: [RoutineLog] = []

    init(
        id: String = UUID().uuidString,
        name: String,
        schedule: RoutineSchedule = RoutineSchedule(),
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.schedule = schedule
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class RoutineStep {
    @Attribute(.unique) var id: String
    var routine: Routine?
    var userProduct: UserProduct?
    var orderIndex: Int
    var instruction: String?
    var durationSeconds: Int?
    var isOptional: Bool = false

    init(
        id: String = UUID().uuidString,
        orderIndex: Int,
        instruction: String? = nil,
        durationSeconds: Int? = nil,
        isOptional: Bool = false
    ) {
        self.id = id
        self.orderIndex = orderIndex
        self.instruction = instruction
        self.durationSeconds = durationSeconds
        self.isOptional = isOptional
    }
}

@Model
final class RoutineLog {
    @Attribute(.unique) var id: String
    var user: User?
    var routine: Routine?
    var logDate: String                      // "YYYY-MM-DD" — kullanıcı timezone'unda
    var completedStepIDs: [String] = []
    var skippedStepIDs: [String] = []
    var completionPct: Int                   // 0-100
    var mood: Mood?
    var weather: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        logDate: String,
        completionPct: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.logDate = logDate
        self.completionPct = completionPct
        self.createdAt = createdAt
    }
}

@Model
final class WeeklySummary {
    @Attribute(.unique) var id: String
    var user: User?
    var weekStart: String                    // "YYYY-MM-DD" (Pazartesi)
    var routinesTotal: Int
    var routinesDone: Int
    var completionPct: Int
    var notes: String?

    init(
        id: String = UUID().uuidString,
        weekStart: String,
        routinesTotal: Int,
        routinesDone: Int,
        completionPct: Int,
        notes: String? = nil
    ) {
        self.id = id
        self.weekStart = weekStart
        self.routinesTotal = routinesTotal
        self.routinesDone = routinesDone
        self.completionPct = completionPct
        self.notes = notes
    }
}
