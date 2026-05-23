import SwiftUI

/// AI rutin önerisi preview — kullanıcı önerilen rutini görür ve onaylar.
///
/// Akış:
/// 1. `targetTime` ile açılır → loading durumu (`AIRecommendService.recommendRoutine`)
/// 2. Response gelince adımlar + suitability + warnings render edilir
/// 3. Kabul edilirse `RoutineService.createRoutine` ile kaydedilir + onAccepted
/// 4. Yetersiz ürün (`too_few_products` 400) → bilgi mesajı
struct AIRecommendPreviewSheet: View {
    let targetTime: TimeSlot
    var onAccepted: ((RoutineResponse) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    enum TimeSlot: String, Identifiable {
        case morning, evening
        var id: String { rawValue }
        var apiValue: String { rawValue }
        var label: String {
            self == .morning
                ? L("timeslot_morning")
                : L("timeslot_evening")
        }
        var emoji: String { self == .morning ? "☀️" : "🌙" }
        var defaultTime: String { self == .morning ? "08:00" : "21:00" }
    }

    private enum Phase {
        case loading
        case ready(AIRecommendRoutineResponse)
        case error(message: String, code: String?)
    }

    @State private var phase: Phase = .loading
    @State private var isSaving: Bool = false
    @State private var userProducts: [UserProductResponse] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                content
            }
            .navigationTitle(L("AI Rutin Önerisi"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("İptal")) { dismiss() }
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .task { await fetchRecommendation() }
    }

    // MARK: - Phases

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            loadingView
        case .ready(let resp):
            readyView(resp)
        case .error(let msg, let code):
            errorView(message: msg, code: code)
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
                .tint(Theme.ink)
            Text("\(targetTime.emoji) \(L("AI rutinini hazırlıyor…"))")
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.inkSoft)
            Text(L("Arşivindeki ürünleri inceliyor, profiline en uygun sıralamayı kuruyor."))
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkMute)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }

    @ViewBuilder
    private func readyView(_ resp: AIRecommendRoutineResponse) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard(resp)

                if !resp.routineNotes.isEmpty {
                    notesCard(resp.routineNotes)
                }

                if !resp.warnings.isEmpty {
                    warningsCard(resp.warnings)
                }

                stepsCard(resp.steps)

                if !resp.missingCategories.isEmpty {
                    missingCard(resp.missingCategories)
                }

                acceptButton(resp)
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func errorView(message: String, code: String?) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: code == "too_few_products" ? "tray" : "exclamationmark.triangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.inkMute)
            Text(code == "too_few_products" ? L("Yeterli ürün yok") : L("Öneri alınamadı"))
                .font(Theme.Typo.headline)
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
            Button(L("Kapat")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private func summaryCard(_ resp: AIRecommendRoutineResponse) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .strokeBorder(scoreColor(resp.suitabilityScore).opacity(0.25), lineWidth: 4)
                    .frame(width: 64, height: 64)
                Circle()
                    .trim(from: 0, to: CGFloat(resp.suitabilityScore) / 100.0)
                    .stroke(scoreColor(resp.suitabilityScore), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 64, height: 64)
                Text("\(resp.suitabilityScore)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(targetTime.emoji) \(targetTime.label) \(L("rutini"))")
                    .font(Theme.Typo.headline)
                    .foregroundStyle(Theme.ink)
                Text(scoreLabel(resp.suitabilityScore))
                    .font(Theme.Typo.caption.weight(.medium))
                    .foregroundStyle(scoreColor(resp.suitabilityScore))
                Text("\(resp.steps.count) \(L("adım"))")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface.opacity(0.6))
        )
    }

    @ViewBuilder
    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Text(L("Neden bu sıralama?"))
                    .font(Theme.Typo.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Text(notes)
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surfaceLow)
        )
    }

    @ViewBuilder
    private func warningsCard(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.alert)
                Text(L("Dikkat"))
                    .font(Theme.Typo.caption.weight(.semibold))
                    .foregroundStyle(Theme.alert)
            }
            ForEach(warnings, id: \.self) { w in
                Text("• \(w)")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.alert.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.alert.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func stepsCard(_ steps: [AIRecommendStep]) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { (idx, step) in
                stepRow(idx: idx, step: step)
            }
        }
    }

    @ViewBuilder
    private func stepRow(idx: Int, step: AIRecommendStep) -> some View {
        let product = userProducts.first(where: { $0.id == step.userProductId })
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.ink)
                        .frame(width: 26, height: 26)
                    Text("\(idx + 1)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.onAccent)
                }

                thumbnail(for: product)

                VStack(alignment: .leading, spacing: 2) {
                    Text(product?.name ?? product?.nickname ?? step.instruction ?? L("Adım"))
                        .font(Theme.Typo.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    if let b = product?.brand, !b.isEmpty {
                        Text(b.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
            }

            Text(step.rationale)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if let label = step.frequencyLabel ?? defaultFrequencyLabel(step.daysActive) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9, weight: .semibold))
                        Text(label)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.surfaceLow))
                }
                ForEach(step.addresses.prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.surface))
                }
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface.opacity(0.6))
        )
    }

    @ViewBuilder
    private func thumbnail(for product: UserProductResponse?) -> some View {
        let url = product?.photoUrl.flatMap { URL(string: $0) }
        AsyncRemoteImage(url: url, contentMode: .fill)
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private func missingCard(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Text(L("Rutini geliştirebilecek eksikler"))
                    .font(Theme.Typo.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Text(items.joined(separator: " · "))
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surfaceLow.opacity(0.5))
        )
    }

    @ViewBuilder
    private func acceptButton(_ resp: AIRecommendRoutineResponse) -> some View {
        Button {
            Haptics.heavy()
            Task { await acceptAndSave(resp) }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView().tint(Theme.onAccent)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text(L("Bu rutini oluştur"))
                        .font(Theme.Typo.button)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .fill(Theme.ink)
            )
            .foregroundStyle(Theme.onAccent)
        }
        .buttonStyle(PressedScaleButtonStyle())
        .disabled(isSaving || resp.steps.isEmpty)
        .opacity(resp.steps.isEmpty ? 0.5 : 1)
    }

    // MARK: - Helpers

    private func scoreColor(_ s: Int) -> Color {
        switch s {
        case 75...: return Theme.success
        case 50...: return Theme.inkSoft
        default:    return Theme.alert
        }
    }

    /// AI frequency_label vermezse, daysActive'den otomatik üret.
    private func defaultFrequencyLabel(_ days: [Int]?) -> String? {
        guard let days, !days.isEmpty, days.count < 7 else {
            return days == nil ? L("frequency_every_day") : nil
        }
        let names = [
            "",
            L("weekday_short_mon"),
            L("weekday_short_tue"),
            L("weekday_short_wed"),
            L("weekday_short_thu"),
            L("weekday_short_fri"),
            L("weekday_short_sat"),
            L("weekday_short_sun"),
        ]
        let labels = days.compactMap { (1...7).contains($0) ? names[$0] : nil }
        if labels.count <= 3 {
            return labels.joined(separator: "·")
        }
        return "\(days.count)\(L("× haftada"))"
    }

    private func scoreLabel(_ s: Int) -> String {
        switch s {
        case 85...: return L("score_label_excellent")
        case 70...: return L("score_label_good")
        case 50...: return L("score_label_neutral")
        default:    return L("score_label_poor")
        }
    }

    // MARK: - Network

    @MainActor
    private func fetchRecommendation() async {
        do {
            async let recom = AIRecommendService.shared.recommendRoutine(
                targetTime: targetTime.apiValue,
                language: appState.locale
            )
            async let products = ProductScanService.shared.listMyProducts()
            let (r, prods) = try await (recom, products)
            userProducts = prods
            phase = .ready(r)
        } catch APIError.server(let code, let msg, _) {
            phase = .error(message: msg, code: code)
        } catch {
            phase = .error(message: error.localizedDescription, code: nil)
        }
    }

    @MainActor
    private func acceptAndSave(_ resp: AIRecommendRoutineResponse) async {
        isSaving = true
        defer { isSaving = false }

        let stepPayloads: [RoutineStepPayload] = resp.steps
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { s in
                var p = RoutineStepPayload()
                p.userProductId = s.userProductId
                p.instruction = s.instruction
                p.daysActive = s.daysActive
                p.frequencyLabel = s.frequencyLabel
                return p
            }

        var schedule = RoutineSchedulePayload()
        schedule.time = targetTime.defaultTime
        schedule.tz = TimeZone.current.identifier
        schedule.frequency = "daily"

        let suggestedName = "\(targetTime.label) \(L("Rutini"))"
        let req = RoutineCreateRequest(
            name: suggestedName,
            categoryId: "skincare",
            schedule: schedule,
            reminder: false,
            colorHex: nil,
            emoji: targetTime.emoji,
            orderIndex: targetTime == .morning ? 0 : 100,
            steps: stepPayloads
        )

        do {
            let (routine, _) = try await RoutineService.shared.createRoutine(req)
            Haptics.success()
            onAccepted?(routine)
            dismiss()
        } catch {
            Haptics.error()
            // İptal etmeden hatayı göster — ileride alert eklenebilir; şimdilik sade.
            phase = .error(message: "\(L("Rutin kaydedilemedi:")) \(error.localizedDescription)", code: nil)
        }
    }
}
