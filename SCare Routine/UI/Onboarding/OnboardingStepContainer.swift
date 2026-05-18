import SwiftUI

/// Tüm onboarding step'lerinin kullandığı tek layout primitivi.
///
/// Bu container `topBar` çizmez — top bar `OnboardingHostView` tarafından SABIT
/// yükseklikte (56pt) tüm step'lerin ÜSTÜNE yerleştirilir. Böylece adım değiştikçe
/// top bar yer değiştirmez (eski "bi yukarı bi aşağı kayma" hatası çözüldü).
///
/// Sorumluluklar:
/// - Horizontal padding **20pt** (her step için aynı)
/// - VStack içerik spacing'i için `contentSpacing` (default 20pt)
/// - `scrollable = true`: ScrollView içinde içerik + alt 100pt nefes (CTA için boşluk)
/// - `scrollable = false`: Welcome / FinalPlan gibi merkezlenmiş ekranlar
/// - CTA `safeAreaInset(.bottom)` ile pin'lenir + canvas fade gradient (içerik altında
///   silinir görüntüsü)
///
/// CTA verilmek istenmediğinde `EmptyView` döndüren `cta` closure'u geçirin
/// (örn. Welcome'da CTA içerikle birlikte ortada gösterilir).
struct OnboardingStepContainer<Content: View, CTA: View>: View {
    let scrollable: Bool
    let contentSpacing: CGFloat
    @ViewBuilder var content: () -> Content
    @ViewBuilder var cta: () -> CTA

    init(
        scrollable: Bool = true,
        contentSpacing: CGFloat = 20,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder cta: @escaping () -> CTA = { EmptyView() }
    ) {
        self.scrollable = scrollable
        self.contentSpacing = contentSpacing
        self.content = content
        self.cta = cta
    }

    var body: some View {
        Group {
            if scrollable {
                ScrollView {
                    VStack(alignment: .leading, spacing: contentSpacing) {
                        content()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    // Top bar (56pt sabit) ile içerik arasındaki boşluk minimal — header
                    // hemen top bar'a yapışsın, ekranın yarısı boşluk hissi vermesin.
                    .padding(.top, 4)
                    .padding(.bottom, 100) // CTA için nefes alanı
                }
                .onboardingScrollStyle()
            } else {
                VStack(spacing: contentSpacing) {
                    content()
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Yalnızca CTA gerçekten görünür view döndürdüyse alttaki gradient yerleşir;
            // EmptyView'da Group içeriği boş kalır, gradient hesaplanmaz.
            let ctaView = cta()
            VStack(spacing: 0) {
                ctaView
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
            .background(
                LinearGradient(
                    colors: [
                        Theme.canvas.opacity(0),
                        Theme.canvas.opacity(0.95),
                        Theme.canvas
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            )
        }
    }
}

// MARK: - Why / hint info box

/// Her step'in başında gösterilen "neden bunu soruyorum" kartı.
/// Cal AI / Headspace tarzında: kullanıcıya context ver, sürtünmeyi azalt.
struct OnboardingWhyBox: View {
    let text: String
    var symbol: String = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 16, alignment: .center)
                .padding(.top, 1)
            Text(text)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        // İpucu hissi — hâkim element değil, içeriği desteklesin
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(Theme.surface.opacity(0.6))
        )
    }
}

// MARK: - Mini reveal card

/// SkinType seçildiğinde ortaya çıkan kişisel teyit satırı.
///
/// **Eski**: Ink-fill kart + yeşil success bar + H-MAX dalga — "AI tasarımı" hissediyordu,
/// kart aşırı büyüktü.
/// **Yeni**: Sade inline satır — ✓ ikonu + tek satır metin. Native iOS notification
/// stili, "konuşur gibi" verir, kart hissi yok.
struct OnboardingRevealCard: View {
    let title: String
    let message: String
    var symbol: String = "checkmark.circle.fill"

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)

            Text("\(title). ")
                .font(Theme.Typo.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
            +
            Text(message)
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .lineLimit(3)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .offset(y: 4)),
            removal: .opacity
        ))
    }
}
