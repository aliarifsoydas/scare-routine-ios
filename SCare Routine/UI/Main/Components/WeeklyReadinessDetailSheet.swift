import SwiftUI

/// `WeeklyReadinessRing` tap'inde açılan detay sheet'i.
///
/// Score'un ne anlama geldiğini, eksik kategorileri ve haftalık not'u gösterir.
/// Backend'den ek alan beklemez — mevcut WeeklyPlanResponse alanları üzerinden çalışır.
struct WeeklyReadinessDetailSheet: View {
    let score: Int
    let missingCategories: [String]
    let weeklyNotes: String

    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang

    private var ringColor: Color {
        switch score {
        case 80...: return Theme.success
        case 60...: return Theme.inkSoft
        default:    return Theme.alert
        }
    }

    private var progress: Double {
        max(0, min(1, Double(score) / 100.0))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ringHero
                        levelExplanation
                        if !missingCategories.isEmpty {
                            missingSection
                        }
                        if !weeklyNotes.isEmpty {
                            notesSection
                        }
                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .id(lang.current)
            .navigationTitle(L("Hazırlık seviyesi"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Tamam")) { dismiss() }
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .telemetryScreen("WeeklyPlan.ReadinessDetail")
    }

    @ViewBuilder
    private var ringHero: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(ringColor.opacity(0.2), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 6) {
                Text(headlineText)
                    .font(Theme.Typo.headline)
                    .foregroundStyle(Theme.ink)
                Text(captionText)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface.opacity(0.6))
        )
    }

    @ViewBuilder
    private var levelExplanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            legendRow(color: Theme.success, label: L("Plan hazır"), range: "80–100")
            legendRow(color: Theme.inkSoft, label: L("Geliştirilebilir"), range: "60–79")
            legendRow(color: Theme.alert, label: L("Eksikler var"), range: "0–59")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surfaceLow.opacity(0.5))
        )
    }

    @ViewBuilder
    private func legendRow(color: Color, label: String, range: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(range)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    @ViewBuilder
    private var missingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Text(L("Planı geliştirebilecek eksikler"))
                    .font(Theme.Typo.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            ForEach(missingCategories, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("+")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ringColor)
                    Text(item)
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface.opacity(0.6))
        )
    }

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Text(L("Haftalık not"))
                    .font(Theme.Typo.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Text(weeklyNotes)
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surfaceLow.opacity(0.5))
        )
    }

    private var headlineText: String {
        switch score {
        case 85...: return L("Planın hazır")
        case 60..<85: return String(format: L("Planın %lld%% hazır"), score)
        default: return L("Planı geliştirmek için ürün ekle")
        }
    }

    private var captionText: String {
        if let first = missingCategories.first, missingCategories.count == 1 {
            return String(format: L("+%@ eklersen %lld%%'e çıkar"), first, min(100, score + 12))
        }
        if missingCategories.count >= 2 {
            let combined = missingCategories.prefix(2).joined(separator: " + ")
            return String(format: L("+%@ eklersen %lld%%'e çıkar"), combined, min(100, score + 18))
        }
        return L("Tüm temel kategoriler tam")
    }
}
