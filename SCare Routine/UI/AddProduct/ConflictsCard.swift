import SwiftUI

/// Quick Scan / Product Review AI değerlendirmesinde,
/// kullanıcının arşivinde bu yeni ürünle çakışan ürünler için gösterilen kart.
///
/// **Neden var**: Önceki versiyonda kullanıcı "rutininizdeki ürünlerle uyumsuz
/// olabilir" gibi generic bir cümle görüyordu — hangi ürünle çakıştığını,
/// hangi seviyede risk olduğunu anlayamıyordu. Bu kart spesifik ürün adı +
/// kısa gerekçe + severity rozeti ile aksiyon alınabilir bilgi verir.
///
/// **Görsel**: `DuplicateWarningCard` pattern'iyle uyumlu — `Theme.surface`
/// arka plan, başlık satırı + her conflict için tek satırlık item (severity
/// rozeti + ürün adı + reason). `conflicts` boşsa hiçbir şey render etmez
/// (parent koşulsuz çağırabilir).
struct ConflictsCard: View {
    let conflicts: [QuickEvaluateResponse.ConflictItem]

    var body: some View {
        if conflicts.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.alert)
                    Text(L("Arşivindeki şu ürünlerle çakışıyor"))
                        .font(Theme.Typo.caption.weight(.semibold))
                        .foregroundStyle(Theme.alert)
                        .textCase(.uppercase)
                    Spacer()
                }

                ForEach(conflicts) { item in
                    HStack(alignment: .top, spacing: 12) {
                        SeverityBadge(severity: item.severity)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.userProductName)
                                .font(Theme.Typo.body.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.reason)
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.inkSoft)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.alert.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .strokeBorder(Theme.alert.opacity(0.25), lineWidth: 1)
                    )
            )
        }
    }
}

/// Severity rozeti — pill şeklinde, severity rengine boyalı küçük etiket.
///
/// High → alert (kırmızı-pink) — mutlaka söyle.
/// Medium → ink (koyu bordo) — heads-up.
/// Low → inkSoft (orta rose-brown) — FYI.
struct SeverityBadge: View {
    let severity: QuickEvaluateResponse.ConflictItem.Severity

    private var label: String {
        switch severity {
        case .high: return L("Yüksek")
        case .medium: return L("Orta")
        case .low: return L("Düşük")
        }
    }

    private var color: Color {
        switch severity {
        case .high: return Theme.alert
        case .medium: return Theme.ink
        case .low: return Theme.inkSoft
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.15))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(color.opacity(0.4), lineWidth: 0.5)
            )
            .accessibilityLabel(label)
    }
}

#Preview("With conflicts") {
    ConflictsCard(conflicts: [
        .init(
            userProductId: "up_1",
            userProductName: "The Ordinary Retinol 1%",
            reason: "Aynı anda kullanırsan tahriş riski yüksek",
            severity: .high
        ),
        .init(
            userProductId: "up_2",
            userProductName: "Vichy AHA Peeling Solution",
            reason: "Her ikisi de asit içerir — gece tek seçim öneriliyor",
            severity: .medium
        ),
        .init(
            userProductId: "up_3",
            userProductName: "CeraVe Hydrating Cleanser",
            reason: "Benzer nemlendirme rolü — birinden vazgeçebilirsin",
            severity: .low
        ),
    ])
    .padding(20)
    .background(Theme.canvas)
}

#Preview("Empty (renders nothing)") {
    ConflictsCard(conflicts: [])
        .padding(20)
        .background(Theme.canvas)
}
