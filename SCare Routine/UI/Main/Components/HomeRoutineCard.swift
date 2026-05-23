import SwiftUI

/// Anasayfa "Bugün için" bölümündeki sabah/akşam rutin kartı.
///
/// **Plain view** — kendisi tap event almaz. Tap'i dış sarmalayıcı (NavigationLink
/// veya Button) yönetir. Bu sayede NavigationLink içine konulduğunda hit-testing
/// çakışması olmaz.
struct HomeRoutineCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let actionLabel: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(Theme.Typo.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(LocalizedStringKey(subtitle))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(LocalizedStringKey(actionLabel))
                .font(Theme.Typo.caption.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().strokeBorder(Theme.divider, lineWidth: 1)
                )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityLabel(Text(LocalizedStringKey(title)) + Text(verbatim: ", ") + Text(LocalizedStringKey(subtitle)))
    }
}
