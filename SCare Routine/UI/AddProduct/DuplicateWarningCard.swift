import SwiftUI

/// Quick Scan sırasında, kullanıcının arşivinde aynı ürün zaten varsa
/// gösterilen "duplicate" uyarı kartı.
///
/// **Görsel**: surfaceLow background'lı yuvarlatılmış kart, tray ikonu +
/// iki satırlık metin (üst: küçük caption "Zaten arşivinde var" / alt:
/// ürün adı) + sağda chevron.
///
/// **Davranış**: `onTap` set'liyse tüm kart Button olur, tıklanınca Haptics.light
/// + callback. Aksi halde pasif info kartı.
struct DuplicateWarningCard: View {
    let productId: String
    let productName: String
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button {
                Haptics.light()
                onTap()
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(L("Zaten arşivinde var")). \(productName)")
            .accessibilityHint(productId)
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(L("Zaten arşivinde var")). \(productName)")
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(L("Zaten arşivinde var"))
                    .font(Theme.Typo.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)

                Text(productName)
                    .font(Theme.Typo.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkMute)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surfaceLow)
        )
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack(spacing: 16) {
        DuplicateWarningCard(
            productId: "prod_abc_123",
            productName: "CeraVe Foaming Facial Cleanser",
            onTap: { print("tap → navigate") }
        )

        DuplicateWarningCard(
            productId: "prod_xyz_456",
            productName: "The Ordinary Niacinamide 10% + Zinc 1%",
            onTap: nil  // pasif info kartı
        )
    }
    .padding()
    .background(Theme.canvas)
}
