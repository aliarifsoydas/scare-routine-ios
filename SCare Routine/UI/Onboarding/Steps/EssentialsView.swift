import SwiftUI

/// Adım 2/6 — Sadeleştirilmiş essentials ekranı.
///
/// Dil seçimi artık `WelcomeView`'da yapılır. Burada yalnızca iki onay alınır:
/// hesap (zorunlu) + AI işleme (opsiyonel). Tıbbi disclaimer ve yasal linkler
/// minimal şekilde gösterilir. Hedef: ekran scroll etmeden tek bakışta okunabilsin.
struct EssentialsView: View {
    @Bindable var flow: OnboardingFlow

    var body: some View {
        OnboardingStepContainer {
            OnboardingStepHeader(
                title: "Başlamadan önce",
                subtitle: "İki onay verman yeterli.",
                symbol: "checkmark.shield"
            )

            consentCards
            disclaimerLine
            linksRow
        } cta: {
            OnboardingPrimaryButton(
                title: "Devam",
                isEnabled: flow.canProceedFromEssentials
            ) {
                flow.goNext()
            }
        }
    }

    // MARK: - Consent

    private var consentCards: some View {
        VStack(spacing: 12) {
            consentRow(
                title: "Verilerimi saklamayı kabul ediyorum",
                description: "Hesap, rutin ve profil bilgilerin uygulamada saklanır.",
                isOn: $flow.consentAccount,
                isRequired: true
            )

            consentRow(
                title: "AI cilt analizine izin ver",
                description: "İstediğin zaman ayarlardan kapatabilirsin.",
                isOn: $flow.consentAIProcessing,
                isRequired: false
            )
        }
    }

    private func consentRow(
        title: String,
        description: String,
        isOn: Binding<Bool>,
        isRequired: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Theme.Typo.headline)
                        .foregroundStyle(Theme.ink)
                    if isRequired {
                        Text("Zorunlu")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.alert.opacity(0.12)))
                            .foregroundStyle(Theme.alert)
                    }
                }
                Text(description)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Theme.ink)
                .accessibilityLabel(title)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
        )
    }

    // MARK: - Disclaimer (kompakt tek satır)

    private var disclaimerLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.alert)
            Text("SCare Routine tıbbi tavsiye değildir.")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(Theme.alert.opacity(0.06))
        )
    }

    // MARK: - Links (tek satır, native)

    private var linksRow: some View {
        HStack(spacing: 8) {
            Link("Gizlilik", destination: URL(string: "https://scare.xflink.co/privacy")!)
            Text("·").foregroundStyle(Theme.inkSoft)
            Link("Şartlar", destination: URL(string: "https://scare.xflink.co/terms")!)
            Text("·").foregroundStyle(Theme.inkSoft)
            Link("KVKK", destination: URL(string: "https://scare.xflink.co/kvkk")!)
            Spacer(minLength: 0)
        }
        .font(Theme.Typo.caption)
        .tint(Theme.ink)
    }
}

#Preview {
    EssentialsView(flow: OnboardingFlow())
        .background(Theme.canvas)
}
