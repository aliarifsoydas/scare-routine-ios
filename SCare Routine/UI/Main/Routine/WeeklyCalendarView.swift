import SwiftUI

/// Haftalık takvim — 7 günlük strip + seçili günün sabah/akşam rutinlerini gösterir.
///
/// Her step'in `daysActive` alanına göre filtrelenir (nil = her gün, [1..7] = belirli).
/// Bugün vurgulu, seçili gün ayrı stil. Strip + alt detay yatay olarak değil dikey
/// olarak tek scroll, kompakt görünüm.
struct WeeklyCalendarView: View {
    @Environment(AppState.self) private var appState

    @State private var routines: [RoutineResponse] = []
    @State private var stepsByRoutine: [String: [RoutineStepResponse]] = [:]
    @State private var userProducts: [UserProductResponse] = []
    @State private var selectedDay: Int = WeekdayFormat.todayWeekday()
    @State private var isLoading: Bool = true
    @State private var loadError: String?

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            if isLoading && routines.isEmpty {
                ProgressView().tint(Theme.inkSoft)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        weekStrip
                        slotSection(title: "Sabah", systemImage: "sun.max.fill", isMorning: true)
                        slotSection(title: "Akşam", systemImage: "moon.stars.fill", isMorning: false)
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle(L("Haftalık"))
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
        .refreshable { await load() }
        .alert(L("Hata"), isPresented: errorBinding) {
            Button(L("Tamam"), role: .cancel) { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
    }

    // MARK: - Strip

    @ViewBuilder
    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let isSelected = (day == selectedDay)
        let isToday = (day == WeekdayFormat.todayWeekday())
        let stepCount = totalActiveSteps(forDay: day)

        Button {
            Haptics.light()
            selectedDay = day
        } label: {
            VStack(spacing: 6) {
                Text(shortDayName(day))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.onAccent : Theme.inkSoft)
                ZStack {
                    Circle()
                        .fill(isSelected ? Theme.ink : (isToday ? Theme.surface : Color.clear))
                        .frame(width: 32, height: 32)
                    if isToday && !isSelected {
                        Circle()
                            .strokeBorder(Theme.ink, lineWidth: 1.5)
                            .frame(width: 32, height: 32)
                    }
                    Text("\(day)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                }
                if stepCount > 0 {
                    Text("\(stepCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isSelected ? Theme.onAccent.opacity(0.8) : Theme.inkSoft)
                } else {
                    Text(" ")
                        .font(.system(size: 9))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.ink : Theme.surface.opacity(0.4))
            )
        }
        .buttonStyle(PressedScaleButtonStyle())
    }

    private func shortDayName(_ day: Int) -> String {
        let locale = appState.locale
        let names = locale == "en"
            ? WeekdayFormat.shortNamesEN
            : WeekdayFormat.shortNamesTR
        guard (1...7).contains(day) else { return "?" }
        return names[day]
    }

    // MARK: - Slot sections

    @ViewBuilder
    private func slotSection(title: String, systemImage: String, isMorning: Bool) -> some View {
        let activeRoutines = routinesForSlot(isMorning: isMorning)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.inkSoft)
                Text(LocalizedStringKey(title))
                    .font(Theme.Typo.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
            }

            if activeRoutines.isEmpty {
                emptySlotRow(title: title)
            } else {
                ForEach(activeRoutines) { routine in
                    routineDayCard(routine)
                }
            }
        }
    }

    @ViewBuilder
    private func emptySlotRow(title: String) -> some View {
        HStack {
            Text(L("Bu slot için rutin yok"))
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkMute)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface.opacity(0.3))
        )
    }

    @ViewBuilder
    private func routineDayCard(_ routine: RoutineResponse) -> some View {
        let steps = activeSteps(for: routine, day: selectedDay)
        NavigationLink(value: HomeView.HomeRoute.routineDetail(id: routine.id)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(routine.emoji ?? "✨")
                        .font(.system(size: 18))
                    Text(routine.name)
                        .font(Theme.Typo.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text("\(steps.count) \(L("adım"))")
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkMute)
                }

                if steps.isEmpty {
                    Text(L("Bu günde aktif adım yok"))
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkMute)
                } else {
                    HStack(spacing: -6) {
                        ForEach(Array(steps.prefix(5).enumerated()), id: \.element.id) { (i, step) in
                            stepThumb(step)
                                .zIndex(Double(5 - i))
                        }
                        if steps.count > 5 {
                            Text("+\(steps.count - 5)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Theme.surfaceLow))
                                .overlay(Circle().strokeBorder(Theme.canvas, lineWidth: 2))
                        }
                        Spacer()
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.surface.opacity(0.6))
            )
        }
        .buttonStyle(PressedScaleButtonStyle())
    }

    @ViewBuilder
    private func stepThumb(_ step: RoutineStepResponse) -> some View {
        let product = step.userProductId.flatMap { pid in
            userProducts.first(where: { $0.id == pid })
        }
        let url = product?.photoUrl.flatMap { URL(string: $0) }
        AsyncRemoteImage(url: url, contentMode: .fill)
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.canvas, lineWidth: 2))
    }

    // MARK: - Filtering

    private func routinesForSlot(isMorning: Bool) -> [RoutineResponse] {
        routines.filter { isMorningRoutine($0) == isMorning }
    }

    private func isMorningRoutine(_ r: RoutineResponse) -> Bool {
        if let t = r.schedule?.time,
           let h = Int(t.split(separator: ":").first.map(String.init) ?? "") {
            return h < 14
        }
        let n = r.name.lowercased()
        return n.contains("sabah") || n.contains("morning")
    }

    private func activeSteps(for routine: RoutineResponse, day: Int) -> [RoutineStepResponse] {
        let all = stepsByRoutine[routine.id] ?? []
        return all
            .filter { step in
                guard let days = step.daysActive, !days.isEmpty else { return true }
                return days.contains(day)
            }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private func totalActiveSteps(forDay day: Int) -> Int {
        routines.reduce(0) { acc, r in acc + activeSteps(for: r, day: day).count }
    }

    // MARK: - Data

    private var errorBinding: Binding<Bool> {
        Binding(get: { loadError != nil }, set: { if !$0 { loadError = nil } })
    }

    @MainActor
    private func load() async {
        if routines.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            async let rts = RoutineService.shared.listRoutines()
            async let prods = ProductScanService.shared.listMyProducts()
            let (rlist, plist) = try await (rts, prods)
            routines = rlist.sorted { $0.orderIndex < $1.orderIndex }
            userProducts = plist
            // Her rutinin step'lerini paralel çek
            await withTaskGroup(of: (String, [RoutineStepResponse]).self) { group in
                for r in rlist {
                    group.addTask {
                        do {
                            let detail = try await RoutineService.shared.getRoutine(id: r.id)
                            return (r.id, detail.steps)
                        } catch {
                            return (r.id, [])
                        }
                    }
                }
                var map: [String: [RoutineStepResponse]] = [:]
                for await (id, steps) in group {
                    map[id] = steps
                }
                stepsByRoutine = map
            }
        } catch {
            loadError = L("Yüklenemedi")
        }
    }
}
