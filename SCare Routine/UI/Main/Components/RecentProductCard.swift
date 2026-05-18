import SwiftUI

/// Anasayfa "Son arşive eklenenler" yatay scroll'undaki tek ürün kartı.
///
/// 96pt geniş, görsel + brand + name. Tap'te haptic (henüz detail sheet yok).
struct RecentProductCard: View {
    let item: UserProductResponse
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                AsyncRemoteImage(url: item.photoUrl.flatMap(URL.init(string:)))
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                            .strokeBorder(Theme.divider, lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    if let brand = item.brand, !brand.isEmpty {
                        Text(brand.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                    }
                    Text(displayTitle)
                        .font(Theme.Typo.caption.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 96, alignment: .leading)
            }
        }
        .buttonStyle(PressedScaleButtonStyle())
        .accessibilityLabel(displayTitle)
    }

    private var displayTitle: String {
        if let n = item.name, !n.isEmpty { return n }
        if let nick = item.nickname, !nick.isEmpty { return nick }
        return "Adsız ürün"
    }
}

/// "Yeni ekle" CTA kartı — son ürünler şeridinin sonunda gösterilir.
struct RecentAddCard: View {
    let onTap: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            onTap()
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .fill(Theme.surface)
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: 96, height: 96)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .strokeBorder(Theme.divider, lineWidth: 0.5)
                )

                Text("Ürün ekle")
                    .font(Theme.Typo.caption.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 96, alignment: .leading)
            }
        }
        .buttonStyle(PressedScaleButtonStyle())
        .accessibilityLabel("Yeni ürün ekle")
    }
}
