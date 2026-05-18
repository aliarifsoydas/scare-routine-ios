import SwiftUI

/// Anasayfa "Bugün için" bölümündeki sabah/akşam rutin kartı.
///
/// Henüz rutin oluşturulmadığında "Oluştur" CTA ile birlikte placeholder gösterir.
/// İleride routine data modeli eklendiğinde adımları liste olarak gösterir.
struct HomeRoutineCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
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
                    Text(title)
                        .font(Theme.Typo.headline)
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(actionLabel)
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
        }
        .buttonStyle(PressedScaleButtonStyle())
        .accessibilityLabel("\(title), \(subtitle)")
    }
}
