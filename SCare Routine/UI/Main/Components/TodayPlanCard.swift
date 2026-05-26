import SwiftUI

/// Anasayfa "Bugün" odaklı section'da sabah ve akşam adımlarını gösteren kart.
///
/// İçinde bir segment switcher (Sabah / Akşam) vardır; varsayılan saat'e göre
/// uygun slot seçilir (sabah < 16, sonra akşam). Step'ler numaralandırılmış
/// liste olarak akar; her step için arşivdeki UserProductResponse'tan thumbnail
/// + isim çekilir. Yoksa rationale'a fallback.
///
/// Rest day veya tüm step'ler boşsa kart `restState` view'ı gösterir; caller
/// onu da render eder.
struct TodayPlanCard: View {
    let day: WeeklyPlanDay
    /// Arşivdeki ürünler — thumbnail + isim eşlemesi için.
    let userProducts: [UserProductResponse]
    /// AppState.locale — locale-aware default segment seçimi yok ama format için.
    let locale: String

    enum Slot: String, Identifiable, CaseIterable {
        case morning, evening
        var id: String { rawValue }
        var label: String { self == .morning ? L("Sabah") : L("Akşam") }
        var icon: String { self == .morning ? "sun.max.fill" : "moon.stars.fill" }
    }

    @State private var slot: Slot = TodayPlanCard.defaultSlot()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            slotPicker
            stepsBody
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface.opacity(0.6))
        )
    }

    // MARK: - Header / segmented switcher

    @ViewBuilder
    private var slotPicker: some View {
        HStack(spacing: 6) {
            ForEach(Slot.allCases) { s in
                slotChip(s)
            }
            Spacer(minLength: 0)
            stepBadge
        }
    }

    @ViewBuilder
    private func slotChip(_ s: Slot) -> some View {
        let isSelected = (s == slot)
        Button {
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.18)) { slot = s }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: s.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(s.label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(isSelected ? Theme.ink : Theme.canvas.opacity(0.7))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var stepBadge: some View {
        let count = currentSteps().count
        if count > 0 {
            Text("\(count) \(L("adım"))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Theme.surfaceLow.opacity(0.7)))
        }
    }

    // MARK: - Steps list

    @ViewBuilder
    private var stepsBody: some View {
        let steps = currentSteps()
        if steps.isEmpty {
            emptySlot
        } else {
            VStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { (idx, step) in
                    stepRow(idx: idx, step: step)
                }
            }
        }
    }

    @ViewBuilder
    private func stepRow(idx: Int, step: WeeklyPlanStep) -> some View {
        let product = userProducts.first(where: { $0.id == step.userProductId })
        let highlight = (step.frequencyLabel ?? "").isEmpty == false
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(highlight ? Theme.ink : Theme.surfaceLow)
                    .frame(width: 22, height: 22)
                Text("\(idx + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(highlight ? Theme.onAccent : Theme.ink)
            }
            .padding(.top, 1)

            thumbnail(for: product)

            VStack(alignment: .leading, spacing: 3) {
                Text(titleFor(step: step, product: product))
                    .font(Theme.Typo.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                if let brand = product?.brand, !brand.isEmpty {
                    Text(brand.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                } else if let inst = step.instruction, !inst.isEmpty {
                    Text(inst)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(2)
                }
                if let freq = step.frequencyLabel, !freq.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9, weight: .semibold))
                        Text(freq)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.canvas.opacity(0.7)))
                    .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var emptySlot: some View {
        HStack(spacing: 10) {
            Image(systemName: slot == .morning ? "sun.max" : "moon")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Theme.inkMute)
            Text(L("Bu slot için adım yok"))
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func thumbnail(for product: UserProductResponse?) -> some View {
        let url = product?.photoUrl.flatMap { URL(string: $0) }
        AsyncRemoteImage(url: url, contentMode: .fill)
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 0.5)
            )
    }

    // MARK: - Helpers

    /// Saat 16'dan önce sabah göster, sonra akşama otomatik geç — kullanıcı her
    /// gün ilk açtığında ilgili slot'u görsün.
    private static func defaultSlot() -> Slot {
        let h = Calendar.current.component(.hour, from: .now)
        return h < 16 ? .morning : .evening
    }

    private func currentSteps() -> [WeeklyPlanStep] {
        switch slot {
        case .morning: return day.morningSteps.sorted { $0.orderIndex < $1.orderIndex }
        case .evening: return day.eveningSteps.sorted { $0.orderIndex < $1.orderIndex }
        }
    }

    /// Step başlığı: product.name > nickname > instruction > "Adım"
    private func titleFor(step: WeeklyPlanStep, product: UserProductResponse?) -> String {
        if let n = product?.name, !n.isEmpty { return n }
        if let nick = product?.nickname, !nick.isEmpty { return nick }
        if let inst = step.instruction, !inst.isEmpty { return inst }
        return L("Adım")
    }
}
