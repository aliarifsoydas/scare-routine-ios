import SwiftUI

/// Anasayfa "Hızlı eylemler" 3 sütun grid'in tek hücresi.
///
/// SF Symbol + tek satır etiket. Tap'te haptic + aksiyon.
/// Disabled (yakında) durumunda görsel olarak biraz solmuş görünür.
struct HomeQuickActionTile: View {
    let icon: String
    let label: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Theme.surface)
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Theme.ink)
                        .symbolRenderingMode(.hierarchical)
                }

                Text(label)
                    .font(Theme.Typo.caption.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
            .opacity(isEnabled ? 1.0 : 0.7)
        }
        .buttonStyle(PressedScaleButtonStyle())
        .accessibilityLabel(label)
    }
}
