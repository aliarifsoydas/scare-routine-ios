import SwiftUI

/// Quick Scan sonucunda ürünün artı ve eksilerini iki sütun halinde listeler.
///
/// **Görsel**:
/// - "Artılar" başlığı altında yeşil ✓ icon ile pros maddeleri
/// - "Eksiler" başlığı altında kırmızı ⚠ icon ile cons maddeleri
/// - Her iki liste de boşsa tümüyle render edilmez (EmptyView)
/// - Sadece biri doluysa sadece o bölüm gösterilir
/// - Maddeler çok satırlı sarabilir (fixedSize horizontal: false, vertical: true)
struct ProConsList: View {
    let pros: [String]
    let cons: [String]

    var body: some View {
        if pros.isEmpty && cons.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if !pros.isEmpty {
                    section(
                        title: L("Artılar"),
                        items: pros,
                        icon: "checkmark.circle.fill",
                        tint: Theme.success
                    )
                }
                if !cons.isEmpty {
                    section(
                        title: L("Eksiler"),
                        items: cons,
                        icon: "exclamationmark.triangle.fill",
                        tint: Theme.alert
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func section(title: String, items: [String], icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.Typo.caption.weight(.semibold))
                .foregroundStyle(Theme.inkSoft)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 16, height: 16)
                            .padding(.top, 3)  // ikon body baseline'a yakın hizalansın

                        Text(item)
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        ProConsList(
            pros: [
                "Niasinamid yağ dengesini düzenler",
                "Parfümsüz, hassas cildi tahriş etmez",
                "Pegasus kompleksi cilt bariyerini güçlendirir"
            ],
            cons: [
                "Yüksek konsantrasyon ilk kullanımda kuruluk yapabilir",
                "Sabah kullanımda SPF zorunlu"
            ]
        )

        Divider()

        // Sadece pros
        ProConsList(pros: ["Sade içerik", "Vegan"], cons: [])

        Divider()

        // Boş — hiçbir şey render etmemeli
        ProConsList(pros: [], cons: [])

        Text("(yukarıda boş bir alan görmemelisin)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
    .background(Theme.canvas)
}
