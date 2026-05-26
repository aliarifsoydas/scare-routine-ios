import SwiftUI

/// Anasayfa "Haftalık" mini şerit — 7 günü tek satırda gösterir.
///
/// Bugün vurgulu (büyük circle + ink fill), diğerleri küçük (Theme.surface).
/// Aktif/rest day farkı küçük bir nokta ile belirtilir. Tap → tüm satırı
/// `WeeklyCalendarView`'a göndermek için NavigationLink ile sarmalanır
/// (parent içeriği `HomeRoute.weeklyCalendar` üzerinden routes).
///
/// 7-gün ISO weekday convention: 1=Pzt..7=Paz.
struct HomeWeeklyStrip: View {
    /// Backend dönen 7 günün özetleri. Az/eksik gün varsa cell "—" gösterir.
    let days: [WeeklyPlanDay]
    /// ISO weekday (1..7) — bugün hangi gün.
    let todayWeekday: Int
    /// AppState.locale — gün kısaltmaları + erişilebilirlik metni için.
    let locale: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...7, id: \.self) { day in
                dayCell(day)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let isToday = (day == todayWeekday)
        let info = days.first(where: { $0.dayOfWeek == day })
        let isRest = info?.restDay ?? false
        let hasContent = info != nil
        let kinds: [ActiveKind] = info.map { ActiveKindDetector.kinds(for: $0) } ?? []

        VStack(spacing: 5) {
            Text(shortName(day))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isToday ? Theme.ink : Theme.inkSoft)
                .tracking(0.3)

            ZStack {
                if isToday {
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 34, height: 34)
                    Text(dayNumberSymbol(isRest: isRest, hasContent: hasContent))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.onAccent)
                } else {
                    Circle()
                        .fill(Theme.surface.opacity(0.6))
                        .frame(width: 28, height: 28)
                    Text(dayNumberSymbol(isRest: isRest, hasContent: hasContent))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink.opacity(hasContent ? 0.85 : 0.4))
                }
            }
            .frame(height: 36)

            // Aktif madde renk dot + altında 2-3 karakter kısaltma.
            // Rest day → ay ikonu + "Rest" label. Hiç veri → "—".
            VStack(spacing: 2) {
                if isRest {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(isToday ? Theme.ink : Theme.inkSoft)
                        .frame(height: 8)
                } else if !kinds.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(kinds.prefix(3), id: \.self) { kind in
                            Circle()
                                .fill(kind.color)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .frame(height: 8)
                } else if hasContent {
                    Circle()
                        .fill(isToday ? Theme.ink : Theme.inkSoft.opacity(0.55))
                        .frame(width: 5, height: 5)
                        .frame(height: 8)
                } else {
                    Color.clear.frame(height: 8)
                }

                Text(miniLabel(isRest: isRest, hasContent: hasContent, kinds: kinds))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(isToday ? Theme.ink : Theme.inkSoft.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(day: day, isToday: isToday, info: info))
    }

    /// Cell altında gösterilen 2-3 karakter etiket.
    private func miniLabel(isRest: Bool, hasContent: Bool, kinds: [ActiveKind]) -> String {
        if isRest { return L("Dinlen") }
        if let first = kinds.first {
            return kinds.count > 1 ? "\(first.shortLabel)+" : first.shortLabel
        }
        if hasContent { return "·" }
        return "—"
    }

    // MARK: - Helpers

    /// Bugün vurgulu hücrede gün numarası göster, diğerlerinde küçük rakam (1..7).
    /// Hiç veri yoksa "—" (placeholder).
    private func dayNumberSymbol(isRest: Bool, hasContent: Bool) -> String {
        guard hasContent else { return "—" }
        return isRest ? "·" : "•"
    }

    /// Locale'a göre kısa gün ismi (Pzt/Mon …).
    private func shortName(_ day: Int) -> String {
        let table = locale == "en"
            ? WeekdayFormat.shortNamesEN
            : WeekdayFormat.shortNamesTR
        guard (1...7).contains(day) else { return "?" }
        return table[day]
    }

    /// Erişilebilirlik metni: "Bugün, Pazartesi, Dinlenme günü" gibi.
    private func accessibilityLabel(day: Int, isToday: Bool, info: WeeklyPlanDay?) -> String {
        var parts: [String] = []
        if isToday { parts.append(L("Bugün")) }
        parts.append(longName(day))
        if let info {
            if info.restDay {
                parts.append(L("Dinlenme günü"))
            } else {
                let s = info.morningSteps.count + info.eveningSteps.count
                parts.append("\(s) \(L("adım"))")
            }
        }
        return parts.joined(separator: ", ")
    }

    private func longName(_ day: Int) -> String {
        switch day {
        case 1: return locale == "en" ? "Monday" : "Pazartesi"
        case 2: return locale == "en" ? "Tuesday" : "Salı"
        case 3: return locale == "en" ? "Wednesday" : "Çarşamba"
        case 4: return locale == "en" ? "Thursday" : "Perşembe"
        case 5: return locale == "en" ? "Friday" : "Cuma"
        case 6: return locale == "en" ? "Saturday" : "Cumartesi"
        case 7: return locale == "en" ? "Sunday" : "Pazar"
        default: return "?"
        }
    }
}
