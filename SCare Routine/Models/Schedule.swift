import Foundation

struct RoutineSchedule: Codable, Hashable, Sendable {
    var days: [Weekday]
    var time: String           // "HH:MM" 24h
    var tz: String             // "Europe/Istanbul"
    var frequency: RoutineFrequency
    var everyNWeeks: Int

    init(
        days: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday],
        time: String = "08:00",
        tz: String = TimeZone.current.identifier,
        frequency: RoutineFrequency = .daily,
        everyNWeeks: Int = 1
    ) {
        self.days = days
        self.time = time
        self.tz = tz
        self.frequency = frequency
        self.everyNWeeks = everyNWeeks
    }
}
