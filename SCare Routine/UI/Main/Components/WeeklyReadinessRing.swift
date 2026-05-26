import SwiftUI

/// Haftalık plan'ın "ne kadar hazır" hissini full-width kartla gösteren component.
///
/// Eski `Uyum: 30` ufak chip yerine; dairesel progress ring + NL yorumu +
/// actionable eksik kategori hint'i + detay link'i içerir. Tap → detay sheet.
///
/// - Tüm renkler Theme.* palette'ten gelir. Ring rengi score'a göre değişir
///   (yeşil ≥80, sarı 60-79, kırmızı <60).
struct WeeklyReadinessRing: View {
    let score: Int
    let missingCategories: [String]
    let onDetailTap: () -> Void

    private var progress: Double {
        max(0, min(1, Double(score) / 100.0))
    }

    private var ringColor: Color {
        switch score {
        case 80...: return Theme.success
        case 60...: return Theme.inkSoft
        default:    return Theme.alert
        }
    }

    var body: some View {
        Button(action: {
            Haptics.selection()
            onDetailTap()
        }) {
            HStack(alignment: .top, spacing: 16) {
                ringView
                infoColumn
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.surface.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 0.75)
            )
        }
        .buttonStyle(PressedScaleButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Ring

    @ViewBuilder
    private var ringView: some View {
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.18), lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.7), value: progress)
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("/100")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.inkMute)
                    .offset(y: -2)
            }
        }
        .frame(width: 78, height: 78)
    }

    // MARK: - Info column

    @ViewBuilder
    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headlineText)
                .font(Theme.Typo.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let suggestion = suggestionLines {
                ForEach(Array(suggestion.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("+")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ringColor)
                        Text(line)
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.success)
                    Text(L("Tüm temel kategoriler tam"))
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
            }

            HStack(spacing: 3) {
                Text(L("Detayı gör"))
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Copy helpers

    private var headlineText: String {
        switch score {
        case 85...:
            return L("Planın hazır")
        case 60..<85:
            return String(format: L("Planın %lld%% hazır"), score)
        default:
            return L("Planı geliştirmek için ürün ekle")
        }
    }

    /// `nil` → "tüm temel kategoriler tam" mesajı render edilir.
    private var suggestionLines: [String]? {
        guard !missingCategories.isEmpty else { return nil }
        return Array(missingCategories.prefix(2))
    }

    private var accessibilityLabel: String {
        let h = headlineText
        let missing = missingCategories.prefix(2).joined(separator: ", ")
        if missing.isEmpty { return h }
        return "\(h). \(L("Detayı gör")): \(missing)"
    }
}
