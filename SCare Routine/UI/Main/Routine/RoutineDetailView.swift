import SwiftUI

/// Tek rutin detay — adımlar, ürünler, "bugün tamamladım" toggle, edit / sil.
///
/// Backend `/v1/me/routines/:id` → { routine, steps }
struct RoutineDetailView: View {
    let routineId: String
    let initialRoutine: RoutineResponse
    let autoFocusAddStep: Bool

    var onDeleted: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var routine: RoutineResponse
    @State private var steps: [RoutineStepResponse] = []
    @State private var userProducts: [UserProductResponse] = []
    @State private var completedSteps: Set<String> = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var showAddProduct: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var didAutoFocus: Bool = false

    init(
        routineId: String,
        initialRoutine: RoutineResponse,
        autoFocusAddStep: Bool = false,
        onDeleted: ((String) -> Void)? = nil
    ) {
        self.routineId = routineId
        self.initialRoutine = initialRoutine
        self.autoFocusAddStep = autoFocusAddStep
        self.onDeleted = onDeleted
        _routine = State(initialValue: initialRoutine)
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    if !steps.isEmpty {
                        stepsSection
                    } else if !isLoading {
                        emptyStepsHint
                    }
                    addStepButton
                    deleteRoutineButton
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(routine.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isLoading { ProgressView().tint(Theme.inkSoft) }
            }
        }
        .task { await loadDetail() }
        .sheet(isPresented: $showAddProduct) {
            AddRoutineStepSheet(
                userProducts: userProducts,
                onSelect: { product, instruction in
                    Task { await addStep(productId: product.id, instruction: instruction) }
                }
            )
        }
        .confirmationDialog(L("Bu rutini sil?"), isPresented: $showDeleteConfirm) {
            Button(L("Sil"), role: .destructive) { Task { await deleteRoutine() } }
            Button(L("Vazgeç"), role: .cancel) {}
        } message: {
            Text(L("Bu işlem geri alınamaz. Adımlar da silinir."))
        }
        .alert(L("Hata"), isPresented: errorBinding) {
            Button(L("Tamam"), role: .cancel) { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: 56, height: 56)
                Text(routine.emoji ?? "✨")
                    .font(.system(size: 28))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(routine.name)
                    .font(Theme.Typo.headline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let sub = headerSubtitle {
                    Text(sub)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
                // Tamamlanma yüzdesi
                if !steps.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(completionPct == 100 ? Theme.success : Theme.inkSoft)
                        // Locale-aware percent: TR "Bugün %75", EN "Today 75%"
                        Text("\(L("Bugün")) \(Double(completionPct) / 100.0, format: .percent.precision(.fractionLength(0)))")
                            .font(Theme.Typo.caption.weight(.medium))
                            .foregroundStyle(completionPct == 100 ? Theme.success : Theme.inkSoft)
                    }
                }
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface.opacity(0.6))
        )
    }

    private var headerSubtitle: String? {
        var parts: [String] = []
        if let t = routine.schedule?.time { parts.append(t) }
        if let c = routine.categoryId {
            parts.append(localizedCategory(c))
        }
        if routine.reminder { parts.append(L("reminder_label")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func localizedCategory(_ c: String) -> String {
        switch c {
        case "skincare": return L("category_option_skincare")
        case "haircare": return L("category_option_haircare")
        case "bodycare": return L("category_option_bodycare")
        case "makeup": return L("category_option_makeup")
        default: return c
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepsSection: some View {
        VStack(spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { (idx, step) in
                stepRow(idx: idx, step: step)
            }
        }
    }

    @ViewBuilder
    private func stepRow(idx: Int, step: RoutineStepResponse) -> some View {
        let isDone = completedSteps.contains(step.id)
        Button {
            Haptics.light()
            toggleStep(step.id)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(isDone ? Theme.success : Theme.divider, lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.success)
                    } else {
                        Text("\(idx + 1)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }

                stepThumbnail(for: step)

                VStack(alignment: .leading, spacing: 4) {
                    Text(productTitle(for: step))
                        .font(Theme.Typo.body.weight(.medium))
                        .foregroundStyle(isDone ? Theme.inkSoft : Theme.ink)
                        .strikethrough(isDone, color: Theme.inkSoft)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let ins = step.instruction, !ins.isEmpty {
                        Text(ins)
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if step.daysActive != nil, !isDailyAllSeven(step.daysActive) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9, weight: .semibold))
                            Text(step.frequencyLabel ?? WeekdayFormat.label(step.daysActive))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(isActiveToday(step) ? Theme.ink : Theme.inkMute)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.surfaceLow))
                    }
                }

                Spacer(minLength: 8)

                if step.isOptional {
                    Text(L("Opt."))
                        .font(Theme.Typo.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMute)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.surface))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.surface.opacity(isActiveToday(step) ? (isDone ? 0.4 : 0.8) : 0.25))
            )
            .opacity(isActiveToday(step) ? 1 : 0.6)
        }
        .buttonStyle(PressedScaleButtonStyle())
    }

    private func isActiveToday(_ step: RoutineStepResponse) -> Bool {
        WeekdayFormat.isActiveToday(step.daysActive)
    }

    private func isDailyAllSeven(_ days: [Int]?) -> Bool {
        guard let days else { return true }
        return days.count >= 7
    }

    private func productTitle(for step: RoutineStepResponse) -> String {
        if let pid = step.userProductId,
           let p = userProducts.first(where: { $0.id == pid }) {
            return p.name ?? p.nickname ?? L("Adsız ürün")
        }
        return step.instruction ?? L("Adım")
    }

    @ViewBuilder
    private func stepThumbnail(for step: RoutineStepResponse) -> some View {
        let product = step.userProductId.flatMap { pid in
            userProducts.first(where: { $0.id == pid })
        }
        let url = product?.photoUrl.flatMap { URL(string: $0) }
        AsyncRemoteImage(url: url, contentMode: .fill)
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 0.5)
            )
    }

    // MARK: - Empty / Add

    @ViewBuilder
    private var emptyStepsHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.inkMute)
            Text(L("Henüz adım yok"))
                .font(Theme.Typo.body.weight(.medium))
                .foregroundStyle(Theme.ink)
            Text(L("Arşivinden ürün ekleyerek başla."))
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    @ViewBuilder
    private var addStepButton: some View {
        Button {
            Haptics.light()
            showAddProduct = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text(L("Adım ekle"))
                    .font(Theme.Typo.button)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(Theme.ink, lineWidth: 1.5)
            )
            .foregroundStyle(Theme.ink)
        }
        .buttonStyle(PressedScaleButtonStyle())
    }

    @ViewBuilder
    private var deleteRoutineButton: some View {
        Button(role: .destructive) {
            Haptics.warning()
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text(L("Rutini sil"))
                    .font(Theme.Typo.button)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(Theme.alert)
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    // MARK: - State helpers

    private var completionPct: Int {
        guard !steps.isEmpty else { return 0 }
        // Sadece bugün aktif + zorunlu adımlar dahil — Salı'ya özel retinol Çarşamba
        // tamamlanmamış sayılmasın.
        let needed = steps.filter { !$0.isOptional && isActiveToday($0) }
        guard !needed.isEmpty else { return 100 }
        let done = needed.filter { completedSteps.contains($0.id) }.count
        return Int(round(Double(done) / Double(needed.count) * 100))
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { loadError != nil }, set: { if !$0 { loadError = nil } })
    }

    private func toggleStep(_ id: String) {
        if completedSteps.contains(id) {
            completedSteps.remove(id)
        } else {
            completedSteps.insert(id)
            if completionPct == 100 {
                Haptics.success()
            }
        }
        Task { await logProgress() }
    }

    @MainActor
    private func loadDetail() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let detail = RoutineService.shared.getRoutine(id: routineId)
            async let products = ProductScanService.shared.listMyProducts()
            let (d, prods) = try await (detail, products)
            routine = d.routine
            steps = d.steps.sorted { $0.orderIndex < $1.orderIndex }
            userProducts = prods
            // Yeni oluşturulan rutin → ürünler yüklendikten sonra adım ekleme
            // sheet'ini otomatik aç. (initial yüklemede bir kez.)
            if autoFocusAddStep, !didAutoFocus, steps.isEmpty {
                didAutoFocus = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    showAddProduct = true
                }
            }
        } catch {
            loadError = L("Detay yüklenemedi")
        }
    }

    @MainActor
    private func addStep(productId: String, instruction: String?) async {
        let newPayloads = steps.map { existing -> RoutineStepPayload in
            var p = RoutineStepPayload()
            p.userProductId = existing.userProductId
            p.instruction = existing.instruction
            p.durationSeconds = existing.durationSeconds
            p.isOptional = existing.isOptional
            return p
        } + [{
            var p = RoutineStepPayload()
            p.userProductId = productId
            p.instruction = instruction
            return p
        }()]
        do {
            steps = try await RoutineService.shared.setSteps(routineId: routineId, steps: newPayloads)
                .sorted { $0.orderIndex < $1.orderIndex }
            Haptics.success()
        } catch {
            loadError = L("Adım eklenemedi")
        }
    }

    @MainActor
    private func deleteRoutine() async {
        do {
            try await RoutineService.shared.deleteRoutine(id: routineId)
            onDeleted?(routineId)
            dismiss()
        } catch {
            loadError = L("Rutin silinemedi")
        }
    }

    @MainActor
    private func logProgress() async {
        let today = Self.todayString()
        var payload = RoutineLogPayload(routineId: routineId, logDate: today)
        payload.completedStepIds = Array(completedSteps)
        // Best effort — sessiz dene
        _ = try? await RoutineService.shared.logRoutine(payload)
    }

    private static func todayString() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - Add step sheet (lightweight)

private struct AddRoutineStepSheet: View {
    let userProducts: [UserProductResponse]
    var onSelect: (UserProductResponse, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""
    @State private var instruction: String = ""

    var filtered: [UserProductResponse] {
        let s = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return userProducts }
        return userProducts.filter {
            ($0.name ?? "").lowercased().contains(s)
                || ($0.brand ?? "").lowercased().contains(s)
                || ($0.nickname ?? "").lowercased().contains(s)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField(L("Talimat (opsiyonel)"), text: $instruction)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if userProducts.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filtered) { product in
                                productRow(product)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .searchable(text: $search, prompt: Text(L("Ürün ara")))
                }
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle(L("Adım ekle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("İptal")) { dismiss() }
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }

    @ViewBuilder
    private func productRow(_ product: UserProductResponse) -> some View {
        Button {
            Haptics.light()
            let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            onSelect(product, trimmed.isEmpty ? nil : trimmed)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                productThumbnail(product)
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name ?? product.nickname ?? L("Adsız"))
                        .font(Theme.Typo.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let b = product.brand, !b.isEmpty {
                        Text(b.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.ink)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.surface.opacity(0.6))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressedScaleButtonStyle())
    }

    @ViewBuilder
    private func productThumbnail(_ product: UserProductResponse) -> some View {
        let url = product.photoUrl.flatMap { URL(string: $0) }
        AsyncRemoteImage(url: url, contentMode: .fill)
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.inkMute)
            Text(L("Arşivinde ürün yok"))
                .font(Theme.Typo.headline)
                .foregroundStyle(Theme.ink)
            Text(L("Adım eklemek için önce ürünlerini Arşive ekle."))
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
