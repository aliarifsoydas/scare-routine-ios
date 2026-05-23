import SwiftUI

/// Arşiv grid'inde gösterilen kart. Verified rozet + isim + nickname.
struct ProductCard: View {
    let item: UserProductResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                // Beyaz arkaplan + aspect-fit:
                //  • PNG transparent ürünler ürünler için temiz arka plan (eskiden bazı görseller
                //    şeffaf gözüküyordu, theme rengi sızıyordu)
                //  • Uzun/yatay görseller croplanmaz, kare alana sığar (.fit)
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Color.white)
                    .aspectRatio(1, contentMode: .fit)   // her kart kare — alignment grid'i için
                    .overlay(
                        AsyncRemoteImage(
                            url: item.photoUrl.flatMap(URL.init(string:)),
                            contentMode: .fit
                        )
                        .padding(8)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .strokeBorder(Theme.divider, lineWidth: 0.5)
                    )

                if item.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.alert)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(8)
                }
            }

            // Metin bloğu — TÜM kartlarda aynı yükseklik için fixed slots:
            // 1) brand satırı (her zaman görünür, brand yoksa boş placeholder)
            // 2) name 2 satır (lineLimit=2, reservesSpace ile sabit yükseklik)
            // 3) nickname 1 satır (her zaman 1 satırlık alan, boşsa görünmez)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.brand?.uppercased() ?? " ")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)

                Text(displayTitle)
                    .font(Theme.Typo.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.nickname?.isEmpty == false ? item.nickname! : " ")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkMute)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private var displayTitle: String {
        if let n = item.name, !n.isEmpty { return n }
        if let nick = item.nickname, !nick.isEmpty { return nick }
        return L("Adsız ürün")
    }
}
