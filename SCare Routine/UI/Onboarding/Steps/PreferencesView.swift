import SwiftUI

/// Adım 5/6 — Saç, vücut, makyaj tercihleri + foto modu.
///
/// Tümü opsiyonel — boş bırakılabilir. CTA her zaman aktif.
/// Sıralı bölümler:
///  1. Saç tipi (single select)
///  2. Saç şikayetleri (multi)
///  3. Vücut şikayetleri (multi)
///  4. Makyaj tercihi (multi)
///  5. Foto modu (mevcut 2 kart)
struct PreferencesView: View {
    @Bindable var flow: OnboardingFlow

    private var hairTypes: [(key: String, label: String, symbol: String?)] {
        [
            ("straight", L("Düz"),           "line.horizontal"),
            ("wavy",     L("Dalgalı"),       "waveform.path"),
            ("curly",    L("Kıvırcık"),      "tornado"),
            ("coily",    L("Sıkı kıvırcık"), "hurricane"),
        ]
    }

    private var hairConcerns: [(key: String, label: String, symbol: String?)] {
        [
            ("dandruff",     L("Kepek"),       "snowflake"),
            ("hair_loss",    L("Dökülme"),     "wind"),
            ("dryness",      L("Kuruluk"),     "drop"),
            ("frizz",        L("Elektrik"),    "bolt"),
            ("oiliness",     L("Yağlanma"),    "drop.degreesign"),
            ("split_ends",   L("Kırık uçlar"), "scissors"),
            ("color_damage", L("Boya hasarı"), "paintpalette"),
        ]
    }

    private var bodyConcerns: [(key: String, label: String, symbol: String?)] {
        [
            ("dryness",        L("Kuruluk"),         "drop"),
            ("stretch_marks",  L("Çatlak"),          "wave.3.forward"),
            ("cellulite",      L("Selülit"),         "rectangle.grid.3x2"),
            ("body_acne",      L("Vücut sivilcesi"), "bandage.fill"),
            ("ingrown_hairs",  L("Batık tüy"),       "pin"),
        ]
    }

    private var makeupPrefs: [(key: String, label: String, symbol: String?)] {
        [
            ("natural",       L("Doğal"),         "leaf"),
            ("full_coverage", L("Tam kapatıcı"),  "circle.fill"),
            ("matte",         L("Mat"),           "circle.dashed"),
            ("dewy",          L("Nemli"),         "sparkles"),
            ("long_lasting",  L("Uzun süreli"),   "clock"),
        ]
    }

    var body: some View {
        OnboardingStepContainer {
            OnboardingStepHeader(
                title: L("Detaylar"),
                subtitle: L("Birkaç soru daha — sonra önerilerin daha iyi olur."),
                symbol: "slider.horizontal.3"
            )

            section(title: L("Saç tipin"), subtitle: nil) {
                FlexibleChipGrid {
                    ForEach(hairTypes, id: \.key) { item in
                        OnboardingChip(
                            title: item.label,
                            symbol: item.symbol,
                            isSelected: flow.selectedHairType == item.key
                        ) {
                            flow.selectedHairType = (flow.selectedHairType == item.key) ? nil : item.key
                        }
                        .track("hairType.\(item.key)")
                    }
                }
            }

            section(title: L("Saç şikayetlerin"), subtitle: L("Birden fazla seçebilirsin")) {
                OnboardingMultiSelectChips(items: hairConcerns, selected: $flow.selectedHairConcerns)
            }

            section(title: L("Vücut şikayetlerin"), subtitle: L("Birden fazla seçebilirsin")) {
                OnboardingMultiSelectChips(items: bodyConcerns, selected: $flow.selectedBodyConcerns)
            }

            section(title: L("Makyaj tercihin"), subtitle: L("Birden fazla seçebilirsin")) {
                OnboardingMultiSelectChips(items: makeupPrefs, selected: $flow.selectedMakeupPrefs)
            }

            // Foto modu
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Fotoğraflarını nasıl saklayalım?"))
                    .font(Theme.Typo.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                BigSelectionCard(
                    title: L("Fotoğrafları sakla"),
                    subtitle: L("Before/after karşılaştırması yapabilirsin."),
                    symbol: "photo.on.rectangle.angled",
                    isSelected: flow.photoMode == .photoKept
                ) { flow.photoMode = .photoKept }
                .track("photoMode.photoKept")

                BigSelectionCard(
                    title: L("Sadece veri sakla"),
                    subtitle: L("Daha gizlilik dostu. Fotoğraf AI analizinden sonra silinir."),
                    symbol: "lock.fill",
                    isSelected: flow.photoMode == .metricsOnly
                ) { flow.photoMode = .metricsOnly }
                .track("photoMode.metricsOnly")
            }
            .padding(.top, 8)

            Text(L("Tüm sorular opsiyonel — boş bırakabilir, sonra profilden değiştirebilirsin."))
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkMute)
                .padding(.top, 4)
        } cta: {
            OnboardingPrimaryButton(title: L("Devam")) {
                flow.goNext()
            }
            .track("continue")
        }
    }

    @ViewBuilder
    private func section<Content: View>(title: String, subtitle: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typo.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkMute)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

#Preview {
    PreferencesView(flow: OnboardingFlow())
        .background(Theme.canvas)
}
