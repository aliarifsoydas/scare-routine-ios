import SwiftUI

/// Onboarding dışındaki feature ekranlarda kullanılan birincil CTA.
/// `OnboardingPrimaryButton`'a görsel olarak benzer ama bağımsızdır —
/// onboarding dosyalarına dokunmadan paylaşılan stil sağlar.
struct PrimaryActionButton: View {
    let title: String
    var systemImage: String? = nil
    var isEnabled: Bool = true
    var isLoading: Bool = false
    var style: Style = .filled
    /// Heavy = anlam yüklü submit (arşive ekle, sil vs.)
    var hapticStyle: HapticStyle = .light
    let action: () -> Void

    enum Style { case filled, outlined }
    enum HapticStyle { case light, heavy, success }

    var body: some View {
        Button {
            switch hapticStyle {
            case .light: Haptics.light()
            case .heavy: Haptics.heavy()
            case .success: Haptics.success()
            }
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(foreground)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(Theme.Typo.button)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: style == .outlined ? 1.5 : 0)
            )
            .foregroundStyle(foreground)
        }
        .buttonStyle(PrimaryPressedScaleButtonStyle())
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(title)
    }

    private var background: some View {
        let enabled = isEnabled && !isLoading
        return RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .fill(style == .filled
                  ? Theme.primaryButtonBackground(enabled)
                  : Color.clear)
    }

    private var foreground: Color {
        let enabled = isEnabled && !isLoading
        switch style {
        case .filled:   return Theme.primaryButtonForeground(enabled)
        case .outlined: return enabled ? Theme.ink : Theme.inkMute
        }
    }

    private var borderColor: Color {
        let enabled = isEnabled && !isLoading
        return enabled ? Theme.ink : Theme.divider
    }
}

/// Onboarding dosyalarındaki `PressedScaleButtonStyle` ile aynı davranış —
/// AddProduct modülünde bağımsız erişim için yeniden tanımlı.
struct PrimaryPressedScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
