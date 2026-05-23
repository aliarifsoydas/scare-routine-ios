import SwiftUI

// MARK: - Büyük görsel header (animasyonlu icon + title + subtitle)

/// Adım üst başlığı — büyük SF Symbol, animasyonlu hafif "nefes alma" efekti.
/// İkon dairesel surface üzerinde gösterilir, title + subtitle metin altında.
struct OnboardingStepHeader: View {
    let title: String
    let subtitle: String?
    var symbol: String? = nil
    /// İkonu sürekli yumuşakça nefes aldıracak mı?
    var animatesIcon: Bool = true

    @State private var pulse: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let symbol {
                ZStack {
                    Circle()
                        .fill(Theme.surface)
                        .frame(width: 60, height: 60)
                    Image(systemName: symbol)
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Theme.ink)
                        .symbolRenderingMode(.hierarchical)
                }
                .scaleEffect(pulse && animatesIcon ? 1.04 : 1.0)
                .animation(
                    animatesIcon
                        ? .easeInOut(duration: 2.0).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )
                .onAppear { pulse = true }
                .accessibilityHidden(true)
            }

            // Title: Theme.Typo.title (28pt) yerine biraz daha kompakt 24pt — onboarding'de
            // "yarısı yazı" hissi vermesin, önemli içerik (kartlar/sliderlar) yukarı çıksın.
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .default))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Primary buton (tap'te subtle bounce + haptic)

struct OnboardingPrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    var isLoading: Bool = false
    /// Heavy haptic = submit gibi anlam yüklü aksiyonlar için
    var hapticStyle: HapticStyle = .light
    let action: () -> Void

    enum HapticStyle { case light, heavy }

    var body: some View {
        Button {
            switch hapticStyle {
            case .light: Haptics.light()
            case .heavy: Haptics.heavy()
            }
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(Theme.onAccent)
                }
                Text(title)
                    .font(Theme.Typo.button)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.primaryButtonBackground(isEnabled && !isLoading))
            )
            .foregroundStyle(Theme.primaryButtonForeground(isEnabled && !isLoading))
            // Disabled iken Theme.surfaceLow zaten daha sönük bir bg veriyor; ek olarak
            // hafif opacity ile "tıklanamaz" hissi netleşsin. enabled'de tam opaklık.
            .opacity((isEnabled && !isLoading) ? 1.0 : 0.6)
        }
        .buttonStyle(PressedScaleButtonStyle())
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(title)
    }
}

// MARK: - Press scale button style

/// Native ButtonStyle ile basılma sırasında subtle scale.
/// `DragGesture` kullanmadığı için ScrollView'un scroll gesture'unu çalmaz.
struct PressedScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Büyük seçim kartı (cilt tipi vs kategori için)

/// Cilt tipi, kategori ve foto modu seçimleri için 80pt+ yükseklikli büyük kart.
/// Solda 48pt circle içinde 22pt SF Symbol, sağda title + subtitle, seçildiğinde
/// background ink ile dolar ve sağda spring animasyonlu checkmark belirir.
struct BigSelectionCard: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let isSelected: Bool
    /// Multi-select kartlarda farklı haptic istemiyorsak default `.medium` impact
    var hapticEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            if hapticEnabled { Haptics.selection() }
            action()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Theme.onAccent.opacity(0.18) : Theme.surface)
                        .frame(width: 44, height: 44)
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.Typo.headline)
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.Typo.caption)
                            .foregroundStyle(isSelected ? Theme.onAccent.opacity(0.75) : Theme.inkSoft)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                // Checkmark slot'u HER ZAMAN 22pt yer kaplar — selected değilse
                // de boşluk korunur. Bu sayede subtitle hep aynı genişlikte kalır,
                // seçim animasyonunda layout hop etmez.
                ZStack {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(Theme.onAccent)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.4).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(isSelected ? Theme.ink : Theme.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Theme.divider, lineWidth: 1)
            )
            // Seçildiğinde daha belirgin derinlik — kart "ayağa kalksın"
            .shadow(color: isSelected ? Theme.ink.opacity(0.14) : .clear,
                    radius: 10, x: 0, y: 4)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(PressedScaleButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Seçim kartı (geriye dönük uyumluluk — yeni yerlerde BigSelectionCard tercih edin)

struct SelectionCard<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.isSelected = isSelected
        self.action = action
        self.trailing = trailing
    }

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Theme.onAccent.opacity(0.18) : Theme.surface)
                        .frame(width: 44, height: 44)
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typo.headline)
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(Theme.Typo.caption)
                            .foregroundStyle(isSelected ? Theme.onAccent.opacity(0.75) : Theme.inkSoft)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)
                trailing()

                // Sabit slot — layout hop'u önler
                ZStack {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Theme.onAccent)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.4).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .frame(width: 18, height: 18)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(isSelected ? Theme.ink : Theme.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Theme.divider, lineWidth: 1)
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Native scroll helper

extension View {
    /// Onboarding ScrollView'larına uygulanan native iOS davranış paketi:
    /// - Bounce sadece içerik ekranı aşıyorsa
    /// - Klavye etkileşimli sürükleyişle kaybolur
    /// - Scroll indicator gizli
    /// - iOS 17+ contentMargins ile modern padding pattern'i
    func onboardingScrollStyle() -> some View {
        self
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            // Yatay scroll indicator'ını ayrıca explicit kapatıyoruz — iOS 17+
            // bazı build'lerde horizontal eksende `hidden` davranışı override edilebiliyor.
            .scrollIndicators(.never, axes: .horizontal)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, 24, for: .scrollContent)
            .modifier(OnboardingScrollEdgeEffectModifier())
    }
}

/// iOS 26+ `scrollEdgeEffectStyle(.soft, for: .all)` — modern soft fade edge.
/// Daha düşük sistem sürümlerinde no-op (modifier'i uygulamadan döner).
private struct OnboardingScrollEdgeEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Toggle chip

struct OnboardingChip: View {
    let title: String
    let symbol: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.callout)
                }
                Text(title)
                    .font(Theme.Typo.body.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(isSelected ? Theme.ink : Theme.canvas)
            )
            .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.clear : Theme.divider, lineWidth: 1)
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Multi-select chip grid (skin_concerns, hair_concerns, body_concerns, makeup_pref için)

/// Bir Set<String> üzerinde reactive multi-select chip grid.
/// Items: (key, displayLabel) — key payload'a gider, label kullanıcıya gösterilir.
struct OnboardingMultiSelectChips: View {
    let items: [(key: String, label: String, symbol: String?)]
    @Binding var selected: Set<String>

    var body: some View {
        FlexibleChipGrid {
            ForEach(items, id: \.key) { item in
                OnboardingChip(
                    title: item.label,
                    symbol: item.symbol,
                    isSelected: selected.contains(item.key)
                ) {
                    if selected.contains(item.key) {
                        selected.remove(item.key)
                    } else {
                        selected.insert(item.key)
                    }
                }
                .track(item.key, props: ["selected_after": !selected.contains(item.key)])
            }
        }
    }
}

/// Chip'leri row'lara akıtan basit flex layout (SwiftUI Layout API).
struct FlexibleChipGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        FlexLayout(spacing: 8, lineSpacing: 8) { content }
    }
}

/// FlexLayout — chip wrapping için minimal `Layout` impl.
/// Children'ı sırayla yerleştirir, satır dolunca alta geçer.
struct FlexLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var rowWidth: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            let needed = rowWidth == 0 ? size.width : rowWidth + spacing + size.width
            if needed > maxWidth {
                rows.append([size])
                rowWidth = size.width
            } else {
                rows[rows.count - 1].append(size)
                rowWidth = needed
            }
        }
        var height: CGFloat = 0
        for (idx, row) in rows.enumerated() {
            let rowH = row.map { $0.height }.max() ?? 0
            height += rowH
            if idx > 0 { height += lineSpacing }
        }
        var maxRowWidth: CGFloat = 0
        for row in rows {
            let rowSum = row.reduce(CGFloat(0)) { $0 + $1.width }
            let gaps = CGFloat(max(0, row.count - 1)) * spacing
            let rowW = rowSum + gaps
            if rowW > maxRowWidth { maxRowWidth = rowW }
        }
        return CGSize(width: maxRowWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            _ = maxWidth
        }
    }
}
