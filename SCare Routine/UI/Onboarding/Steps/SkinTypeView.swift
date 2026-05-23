import SwiftUI

/// Adım 3/6 — ANCHOR: Cilt tipi seçimi.
///
/// Cal AI / Yazio 2026 anchor pattern'i: temel soru + mini reveal.
/// Şikayet sweep'i sonrası native iOS hissi:
/// - Önemli olan (5 kart) hemen yukarıda
/// - Yazı minimal: subtitle bir cümle, why box tek satır
/// - "Emin değilim" 6. büyük kart değil, sade text link
struct SkinTypeView: View {
    @Bindable var flow: OnboardingFlow

    /// 5 ana cilt tipi — sabit sıra (yağlı, kuru, karma, normal, hassas)
    private let types: [SkinType] = [.oily, .dry, .combo, .normal, .sensitive]

    /// Skin concerns vocab — backend `skin_concerns` JSON array değerleri.
    /// Key payload'a gider; label kullanıcıya gösterilir.
    private let concerns: [(key: String, label: String, symbol: String?)] = [
        ("acne",        "Sivilce",          "bandage.fill"),
        ("blackheads",  "Siyah nokta",      "circle.dotted.circle"),
        ("oiliness",    "Yağlanma",         "drop.degreesign"),
        ("dryness",     "Kuruluk",          "drop"),
        ("sensitivity", "Hassasiyet",       "exclamationmark.shield"),
        ("redness",     "Kızarıklık",       "flame"),
        ("dark_spots",  "Lekeler",          "sparkle.magnifyingglass"),
        ("wrinkles",    "Kırışıklık",       "scribble.variable"),
        ("large_pores", "Gözenek",          "circle.grid.cross"),
        ("dullness",    "Mat görünüm",      "moon.zzz"),
    ]

    var body: some View {
        OnboardingStepContainer {
            OnboardingStepHeader(
                title: "Cildini biraz tanıyalım",
                subtitle: "Önerilerin temelini bu oluşturur.",
                symbol: "drop.fill"
            )

            VStack(spacing: 10) {
                ForEach(types) { type in
                    BigSelectionCard(
                        title: type.displayTR,
                        subtitle: type.subtitleTR,
                        symbol: type.symbol,
                        isSelected: flow.selectedSkinType == type
                    ) {
                        flow.selectedSkinType = type
                        flow.skinTypeAcknowledgedUnknown = false
                    }
                }
            }

            unsureLink
                .padding(.top, -2) // 10pt kart spacing + 8pt ⇒ ~18pt görsel boşluk

            concernsSection
                .padding(.top, 8)
        } cta: {
            VStack(spacing: 12) {
                // Mini reveal — CTA'nın hemen üstünde STICKY, scroll'la kaybolmaz.
                // Bir tip seçildiyse görünür, "Emin değilim"de gizli.
                if let t = flow.selectedSkinType, !flow.skinTypeAcknowledgedUnknown {
                    OnboardingRevealCard(
                        title: "\(t.displayTR) seçtin",
                        message: t.revealTextTR,
                        symbol: "checkmark.seal.fill"
                    )
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.94, anchor: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .offset(y: 6)),
                        removal: .opacity
                    ))
                }

                OnboardingPrimaryButton(
                    title: "Devam",
                    isEnabled: flow.canProceedFromSkinType
                ) {
                    flow.goNext()
                }
            }
            .animation(
                .spring(response: 0.45, dampingFraction: 0.78),
                value: flow.selectedSkinType
            )
            .animation(
                .spring(response: 0.45, dampingFraction: 0.78),
                value: flow.skinTypeAcknowledgedUnknown
            )
        }
    }

    /// Cilt şikayetleri — opsiyonel multi-select. Kullanıcı atlayabilir.
    /// "En az bir tane seçmek zorunda değil" hissi için header subtle.
    private var concernsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hangi konularda destek istersin?")
                    .font(Theme.Typo.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Birden fazla seçebilirsin (opsiyonel)")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkMute)
            }
            OnboardingMultiSelectChips(
                items: concerns,
                selected: $flow.selectedSkinConcerns
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Sade text link — büyük kart değil, native iOS "skip-y" hissi.
    /// Tıklandığında kart seçimleri iptal olur, Devam butonu yine açık olur.
    private var unsureLink: some View {
        Button {
            flow.acknowledgeSkinTypeUnknown()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: flow.skinTypeAcknowledgedUnknown
                      ? "checkmark.circle.fill"
                      : "questionmark.circle")
                    .font(.system(size: 13, weight: .regular))
                Text("Emin değilim")
                    .font(Theme.Typo.caption.weight(.medium))
            }
            .foregroundStyle(flow.skinTypeAcknowledgedUnknown ? Theme.ink : Theme.inkSoft)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(.spring(response: 0.3, dampingFraction: 0.8),
                       value: flow.skinTypeAcknowledgedUnknown)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressedScaleButtonStyle())
        .accessibilityLabel("Emin değilim, sonra belirleriz")
    }
}

#Preview {
    SkinTypeView(flow: OnboardingFlow())
        .background(Theme.canvas)
}
