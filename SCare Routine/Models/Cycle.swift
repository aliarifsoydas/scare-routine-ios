import Foundation
import SwiftData

@Model
final class CycleLog {
    @Attribute(.unique) var id: String
    var user: User?
    var startDate: String                    // "YYYY-MM-DD"
    var endDate: String?                     // nil = ongoing
    var cycleLength: Int?                    // gün
    var flowIntensity: FlowIntensity?
    var symptoms: [String] = []
    var notes: String?
    var source: CycleSource = CycleSource.manual
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        startDate: String,
        endDate: String? = nil,
        source: CycleSource = .manual,
        createdAt: Date = .now
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.source = source
        self.createdAt = createdAt
    }
}
