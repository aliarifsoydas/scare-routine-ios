import SwiftUI

/// Anasayfa "Bugün" hero — greeting'in hemen altında, weekly plan'in bugünkü
/// özetini gösterir.
///
/// İçerik:
///  - Üst satır: "Bugün · Pazartesi" + tarih
///  - dayFocus (örn. "BHA gecesi") — italic vurgu
///  - Rest day → moon icon + nazik "Dinlenme günü" mesajı
///  - Aksi halde → sabah/akşam adım sayıları (☀️ 4 · 🌙 6)
///
/// Plan yoksa (loading veya error) caller skeleton/empty state render eder;
/// bu view sadece `WeeklyPlanDay` ile çalışır.
struct TodayHeroSection: View {
    let day: WeeklyPlanDay
    let todayDateString: String
    let dayDisplayName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Üst satır: chip + gün adı + tarih
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L("Bugün"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.ink))

                Text(dayDisplayName)
                    .font(Theme.Typo.headline)
                    .foregroundStyle(Theme.ink)

                Spacer(minLength: 0)

                Text(todayDateString)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            // dayFocus — varsa
            if !day.dayFocus.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                    Text(day.dayFocus)
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.ink)
                        .italic()
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }

            // Alt: rest day veya adım badge'leri
            if day.restDay {
                restDayPill
            } else {
                stepBadges
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
    }

    // MARK: - Subviews

    @ViewBuilder
    private var restDayPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.inkSoft)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Dinlenme günü"))
                    .font(Theme.Typo.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(L("Bugün nemlendirici yeterli"))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(Theme.canvas.opacity(0.7))
        )
    }

    @ViewBuilder
    private var stepBadges: some View {
        HStack(spacing: 8) {
            stepCountBadge(icon: "sun.max.fill", count: day.morningSteps.count, label: L("Sabah"))
            stepCountBadge(icon: "moon.stars.fill", count: day.eveningSteps.count, label: L("Akşam"))
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func stepCountBadge(icon: String, count: Int, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("\(count)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.canvas.opacity(0.7)))
    }
}
