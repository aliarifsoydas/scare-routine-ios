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

    private let hairTypes: [(key: String, label: String, symbol: String?)] = [
        ("straight", "Düz",         "line.horizontal"),
        ("wavy",     "Dalgalı",     "waveform.path"),
        ("curly",    "Kıvırcık",    "tornado"),
        ("coily",    "Sıkı kıvırcık", "hurricane"),
    ]

    private let hairConcerns: [(key: String, label: String, symbol: String?)] = [
        ("dandruff",     "Kepek",       "snowflake"),
        ("hair_loss",    "Dökülme",     "wind"),
        ("dryness",      "Kuruluk",     "drop"),
        ("frizz",        "Elektrik",    "bolt"),
        ("oiliness",     "Yağlanma",    "drop.degreesign"),
        ("split_ends",   "Kırık uçlar", "scissors"),
        ("color_damage", "Boya hasarı", "paintpalette"),
    ]

    private let bodyConcerns: [(key: String, label: String, symbol: String?)] = [
        ("dryness",        "Kuruluk",       "drop"),
        ("stretch_marks",  "Çatlak",        "wave.3.forward"),
        ("cellulite",      "Selülit",       "rectangle.grid.3x2"),
        ("body_acne",      "Vücut sivilcesi", "bandage.fill"),
        ("ingrown_hairs",  "Batık tüy",     "pin"),
    ]

    private let makeupPrefs: [(key: String, label: String, symbol: String?)] = [
        ("natural",       "Doğal",         "leaf"),
        ("full_coverage", "Tam kapatıcı",  "circle.fill"),
        ("matte",         "Mat",           "circle.dashed"),
        ("dewy",          "Nemli",         "sparkles"),
        ("long_lasting",  "Uzun süreli",   "clock"),
    ]

    var body: some View {
        OnboardingStepContainer {
            OnboardingStepHeader(
                title: "Detaylar",
                subtitle: "Birkaç soru daha — sonra önerilerin daha iyi olur.",
                symbol: "slider.horizontal.3"
            )

            section(title: "Saç tipin", subtitle: nil) {
                FlexibleChipGrid {
                    ForEach(hairTypes, id: \.key) { item in
                        OnboardingChip(
                            title: item.label,
                            symbol: item.symbol,
                            isSelected: flow.selectedHairType == item.key
                        ) {
                            flow.selectedHairType = (flow.selectedHairType == item.key) ? nil : item.key
                        }
                    }
                }
            }

            section(title: "Saç şikayetlerin", subtitle: "Birden fazla seçebilirsin") {
                OnboardingMultiSelectChips(items: hairConcerns, selected: $flow.selectedHairConcerns)
            }

            section(title: "Vücut şikayetlerin", subtitle: "Birden fazla seçebilirsin") {
                OnboardingMultiSelectChips(items: bodyConcerns, selected: $flow.selectedBodyConcerns)
            }

            section(title: "Makyaj tercihin", subtitle: "Birden fazla seçebilirsin") {
                OnboardingMultiSelectChips(items: makeupPrefs, selected: $flow.selectedMakeupPrefs)
            }

            // Foto modu
            VStack(alignment: .leading, spacing: 10) {
                Text("Fotoğraflarını nasıl saklayalım?")
                    .font(Theme.Typo.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                BigSelectionCard(
                    title: "Fotoğrafları sakla",
                    subtitle: "Before/after karşılaştırması yapabilirsin.",
                    symbol: "photo.on.rectangle.angled",
                    isSelected: flow.photoMode == .photoKept
                ) { flow.photoMode = .photoKept }

                BigSelectionCard(
                    title: "Sadece veri sakla",
                    subtitle: "Daha gizlilik dostu. Fotoğraf AI analizinden sonra silinir.",
                    symbol: "lock.fill",
                    isSelected: flow.photoMode == .metricsOnly
                ) { flow.photoMode = .metricsOnly }
            }
            .padding(.top, 8)

            Text("Tüm sorular opsiyonel — boş bırakabilir, sonra profilden değiştirebilirsin.")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkMute)
                .padding(.top, 4)
        } cta: {
            OnboardingPrimaryButton(title: "Devam") {
                flow.goNext()
            }
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
