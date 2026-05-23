import SwiftUI

/// Adım 1/6 — Açılış. Logo + selamlama + dil seçimi + CTA. Hepsi bir ekrana sığar.
///
/// Tasarım kararları:
/// - Logo üstte (110pt), yumuşak "nefes" animasyonu — animasyonun anchor görevi
/// - Hemen altında kişisel selamlama ("Hoş geldin, {ad}")
/// - Tek satırlık (kısa) pitch
/// - Dil seçimi BÜYÜK ve görünür — kullanıcının "TR/EN ilk soru olmalı, kaynamamalı"
///   şikayetine yanıt: Welcome'da iki büyük `BigSelectionCard` yan yana
/// - Alt sabit CTA: "Başlayalım"
///
/// İçerik kısa olduğu için scroll yok; `OnboardingStepContainer(scrollable: false)`.
struct WelcomeView: View {
    let flow: OnboardingFlow
    /// AppState'ten gelen kullanıcı adı (varsa). nil ise jenerik selamlama.
    var userName: String? = nil

    @State private var logoPulse: Bool = false
    @State private var contentVisible: Bool = false

    var body: some View {
        OnboardingStepContainer(
            scrollable: false,
            contentSpacing: 0
        ) {
            VStack(spacing: 0) {
                Spacer(minLength: 8)

                // Logo — yumuşak nefes alma animasyonu
                logo
                    .opacity(contentVisible ? 1 : 0)
                    .offset(y: contentVisible ? 0 : 10)

                Spacer().frame(height: 20)

                // Selamlama + tek satır pitch
                VStack(spacing: 8) {
                    Text(greeting)
                        .font(Theme.Typo.title)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)

                    Text(pitch)
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 12)

                Spacer().frame(height: 24)

                // Dil seçimi — alt alta iki büyük kart (native iOS pattern)
                // Seçim hem `flow.locale` (backend payload için) hem `LanguageManager.current`'a
                // yazılır → onboarding'in geri kalanı anında seçilen dilde render olur.
                VStack(spacing: 10) {
                    BigSelectionCard(
                        title: L("Türkçe"),
                        subtitle: L("Devam etmek için dilini seç"),
                        symbol: "globe",
                        isSelected: flow.locale == "tr"
                    ) {
                        flow.locale = "tr"
                        LanguageManager.shared.current = .tr
                    }

                    BigSelectionCard(
                        title: L("English"),
                        subtitle: L("Choose your language to continue"),
                        symbol: "globe",
                        isSelected: flow.locale == "en"
                    ) {
                        flow.locale = "en"
                        LanguageManager.shared.current = .en
                    }
                }
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 14)

                Spacer(minLength: 12)

                // Süre vaadi (küçük chip)
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption2.weight(.medium))
                    Text(L("Yaklaşık 45 saniye"))
                        .font(Theme.Typo.caption.weight(.medium))
                }
                .foregroundStyle(Theme.inkMute)
                .opacity(contentVisible ? 1 : 0)

                Spacer().frame(height: 12)

                OnboardingPrimaryButton(title: L("Başlayalım"), hapticStyle: .light) {
                    flow.goNext()
                }
                .track("continue")
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 16)

                Spacer().frame(height: 4)
            }
        } cta: {
            EmptyView()
        }
        .onAppear {
            logoPulse = true
            withAnimation(.easeOut(duration: 0.55)) {
                contentVisible = true
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var logo: some View {
        Group {
            if UIImage(named: "Logo") != nil {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
            } else {
                ZStack {
                    Circle()
                        .fill(Theme.surface)
                        .frame(width: 120, height: 120)
                    Image(systemName: "camera.macro")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(Theme.ink)
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
        .scaleEffect(logoPulse ? 1.05 : 1.0)
        .shadow(color: Theme.ink.opacity(0.08), radius: 18, x: 0, y: 6)
        .animation(
            .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
            value: logoPulse
        )
        .accessibilityHidden(true)
    }

    /// Kullanıcı adı biliniyorsa kişiselleştirilmiş selamlama, aksi halde jenerik.
    private var greeting: String {
        if let name = userName, !name.isEmpty {
            return "\(L("Hoş geldin")), \(name)"
        }
        return L("Hoş geldin")
    }

    /// Kısa pitch — tek satır, 5-7 kelime.
    private var pitch: String {
        L("Kişisel cilt asistanın, birlikte başlayalım.")
    }
}

#Preview {
    WelcomeView(flow: OnboardingFlow(), userName: "Ali")
        .background(Theme.canvas)
}
