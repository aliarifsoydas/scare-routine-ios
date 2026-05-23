import Foundation

/// Haftalık takvim (days_active) için ortak yardımcılar.
///
/// Convention: 1 = Pazartesi … 7 = Pazar (ISO 8601). nil veya tüm günler = "her gün".
enum WeekdayFormat {
    static let shortNamesTR = ["", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]
    static let shortNamesEN = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Day index (1=Mon..7=Sun) → localized short name via Localizable.xcstrings.
    /// "Pzt"/"Mon", "Sal"/"Tue", ... runtime locale'a göre çözülür.
    static func localizedShortName(_ day: Int) -> String? {
        switch day {
        case 1: return L("weekday_short_mon")
        case 2: return L("weekday_short_tue")
        case 3: return L("weekday_short_wed")
        case 4: return L("weekday_short_thu")
        case 5: return L("weekday_short_fri")
        case 6: return L("weekday_short_sat")
        case 7: return L("weekday_short_sun")
        default: return nil
        }
    }

    /// daysActive'i kısa etikete çevirir:
    ///  - nil  → "Her gün"
    ///  - [2,5] → "Sal·Cum"
    ///  - 4+ gün → "Nx haftada"
    static func label(_ days: [Int]?, locale: String = "tr") -> String {
        guard let days, !days.isEmpty else { return L("Her gün") }
        if days.count >= 7 { return L("Her gün") }

        let valid = days.filter { (1...7).contains($0) }.sorted()
        if valid.count <= 3 {
            return valid.compactMap { localizedShortName($0) }.joined(separator: "·")
        }
        let fmt = L("%lld× haftada")
        return String(format: fmt, valid.count)
    }

    /// Bugün hangi gün — ISO weekday (1=Pzt..7=Paz).
    static func todayWeekday(in tz: TimeZone = .current) -> Int {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = tz
        cal.firstWeekday = 2  // Monday
        let comp = cal.component(.weekday, from: Date())
        // Apple weekday: 1=Sun..7=Sat → ISO 1=Mon..7=Sun
        return comp == 1 ? 7 : comp - 1
    }

    /// Bu adım bugün için aktif mi?
    static func isActiveToday(_ daysActive: [Int]?) -> Bool {
        guard let daysActive, !daysActive.isEmpty else { return true }
        return daysActive.contains(todayWeekday())
    }
}
