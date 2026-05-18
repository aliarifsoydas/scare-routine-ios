import SwiftUI

/// Arşiv grid'inde gösterilen kart. Verified rozet + isim + nickname.
struct ProductCard: View {
    let item: UserProductResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                AsyncRemoteImage(url: item.photoUrl.flatMap(URL.init(string:)))
                    .frame(height: 140)
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

            VStack(alignment: .leading, spacing: 2) {
                if let brand = item.brand, !brand.isEmpty {
                    Text(brand.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
                Text(displayTitle)
                    .font(Theme.Typo.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let nick = item.nickname, !nick.isEmpty {
                    Text(nick)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkMute)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private var displayTitle: String {
        if let n = item.name, !n.isEmpty { return n }
        if let nick = item.nickname, !nick.isEmpty { return nick }
        return "Adsız ürün"
    }
}
