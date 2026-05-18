import SwiftUI

/// Adım 5/6 — Fotoğraf modu tercihi.
/// Kategori seçimi kaldırıldı (arşivden inferred). Sadece foto modu kalır,
/// CTA = "Devam" → FinalPlanView.
struct PreferencesView: View {
    @Bindable var flow: OnboardingFlow

    var body: some View {
        OnboardingStepContainer {
            OnboardingStepHeader(
                title: "Fotoğraflar",
                subtitle: "Çektiğin fotoğrafları nasıl saklayalım?",
                symbol: "photo.on.rectangle.angled"
            )

            BigSelectionCard(
                title: "Fotoğrafları sakla",
                subtitle: "Before/after karşılaştırması yapabilirsin. İstediğin zaman silebilirsin.",
                symbol: "photo.on.rectangle.angled",
                isSelected: flow.photoMode == .photoKept
            ) { flow.photoMode = .photoKept }

            BigSelectionCard(
                title: "Sadece veri sakla",
                subtitle: "Daha gizlilik dostu. Fotoğraf AI analizinden sonra silinir; yorumlar kalır.",
                symbol: "lock.fill",
                isSelected: flow.photoMode == .metricsOnly
            ) { flow.photoMode = .metricsOnly }

            Text("Bu tercihi sonradan ayarlardan değiştirebilirsin.")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkMute)
                .padding(.top, 4)
        } cta: {
            OnboardingPrimaryButton(title: "Devam") {
                flow.goNext()
            }
        }
    }
}

#Preview {
    PreferencesView(flow: OnboardingFlow())
        .background(Theme.canvas)
}
