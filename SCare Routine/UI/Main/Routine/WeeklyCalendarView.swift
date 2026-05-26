import SwiftUI

/// Haftalık takvim — AI tarafından üretilen `WeeklyPlanResponse`'i render eder.
///
/// Görünüm katmanları:
/// 1. **Suitability score chip** (üst sağ) — 0-100, renk-coded
/// 2. **Active rotation banner** (sticky üstte, tap → genişler + weeklyNotes gösterir)
/// 3. **7-day strip** — her gün için renk-kodlu aktif madde göstergeleri + yoğunluk dot'u
/// 4. **Bugünün özeti** — seçili günün hero kartı
/// 5. **Gizli "AI yerine kendi rutinim"** toggle — eski self-routine aggregation altta
///
/// Tap edilen gün için modal `WeeklyDayDetailSheet` açılır.
struct WeeklyCalendarView: View {
    @Environment(AppState.self) private var appState
    @Environment(LanguageManager.self) private var lang

    // MARK: - Stored weekly plan state
    //
    // Bu view artık AI suggest etmiyor — yalnızca kullanıcının kabul ettiği
    // `StoredWeeklyPlan`'i okur. Plan yoksa empty state göstererek kullanıcıyı
    // ana sayfaya yönlendirir (orada AcceptPlanSheet açılır).
    @State private var storedPlan: StoredWeeklyPlan?
    @State private var isLoadingPlan: Bool = true
    @State private var planError: String?
    @State private var selectedDay: Int = WeekdayFormat.todayWeekday()
    @State private var detailDay: WeeklyPlanDay?
    @State private var rotationExpanded: Bool = false
    @State private var showSelfRoutines: Bool = false
    @State private var readinessDetailVisible: Bool = false

    /// Geriye uyumluluk: tüm UI bloklarının okuduğu plan tek bir yerden gelsin.
    private var weeklyPlan: WeeklyPlanResponse? { storedPlan?.plan }

    // Loading status rotation (Spotify-style)
    @State private var statusIndex: Int = 0
    @State private var statusTimer: Timer?

    // MARK: - Self-routine fallback (önceki backbone — gizli toggle altında)
    @State private var routines: [RoutineResponse] = []
    @State private var stepsByRoutine: [String: [RoutineStepResponse]] = [:]
    @State private var userProducts: [UserProductResponse] = []
    @State private var isLoadingSelf: Bool = false

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .id(lang.current)
        .navigationTitle(L("Haftalık"))
        .navigationBarTitleDisplayMode(.large)
        .task(id: appState.locale) { await loadStoredPlan() }
        .task { await loadSelfRoutines() }
        .refreshable { await loadStoredPlan() }
        .sheet(item: $detailDay) { day in
            WeeklyDayDetailSheet(
                day: day,
                weekDate: dateFor(day: day.dayOfWeek),
                userProducts: userProducts
            )
            .environment(appState)
            .environment(lang)
        }
        // SwiftUI sınırı: aynı view'a 2 .sheet modifier uygulanırsa ikincisi
        // sessizce yok sayılır. İkinci sheet'i ayrı bir background view'a
        // bağlayarak presentation hierarchy'sini ayır → her ikisi de çalışır.
        // ("Detayı gör" tap'inin hiçbir şey yapmaması bu yüzdendi.)
        .background(
            Color.clear
                .sheet(isPresented: $readinessDetailVisible) {
                    if let plan = weeklyPlan {
                        WeeklyReadinessDetailSheet(
                            score: plan.suitabilityScore,
                            missingCategories: plan.missingCategories,
                            weeklyNotes: plan.weeklyNotes
                        )
                        .environment(lang)
                    }
                }
        )
        .telemetryScreen("WeeklyPlan")
    }

    @ViewBuilder
    private var content: some View {
        if isLoadingPlan && weeklyPlan == nil {
            loadingView
        } else if let plan = weeklyPlan {
            planScrollView(plan)
        } else if let err = planError {
            errorView(err)
        } else {
            // Stored plan yok → kullanıcıyı ana sayfaya geri çağır.
            // Ana sayfada AcceptPlanSheet otomatik açılır.
            emptyStoredPlanView
        }
    }

    @ViewBuilder
    private var emptyStoredPlanView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.inkMute)
                .symbolRenderingMode(.hierarchical)
            Text(L("Önce haftalık planını oluştur"))
                .font(Theme.Typo.headline)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(L("Haftalık planını oluşturmak için ana sayfaya dön"))
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Spacer()
        }
    }

    // MARK: - Loading

    @ViewBuilder
    private var loadingView: some View {
        ScrollView {
            VStack(spacing: 16) {
                skeletonStrip
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                VStack(spacing: 14) {
                    ProgressView()
                        .tint(Theme.ink)
                    Text(loadingStatuses[statusIndex])
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.inkSoft)
                        .transition(.opacity)
                        .id(statusIndex)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.top, 48)
                Spacer(minLength: 32)
            }
        }
        .onAppear { startStatusRotation() }
        .onDisappear { stopStatusRotation() }
    }

    @ViewBuilder
    private var skeletonStrip: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { _ in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.surfaceLow)
                        .frame(width: 24, height: 10)
                    Circle()
                        .fill(Theme.surfaceLow)
                        .frame(width: 32, height: 32)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.surfaceLow)
                        .frame(width: 18, height: 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.surface.opacity(0.4))
                )
            }
        }
    }

    private var loadingStatuses: [String] {
        [
            L("Cilt loguna bakıyor..."),
            L("Aktif maddeleri analiz ediyor..."),
            L("Haftalık ritim kuruluyor..."),
            L("Retinol ve asit günleri ayrılıyor..."),
            L("Son detayları gözden geçiriyor..."),
        ]
    }

    private func startStatusRotation() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
                    statusIndex = (statusIndex + 1) % loadingStatuses.count
                }
            }
        }
    }

    private func stopStatusRotation() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    // MARK: - Error

    @ViewBuilder
    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.inkMute)
            Text(L("Haftalık plan alınamadı"))
                .font(Theme.Typo.headline)
                .foregroundStyle(Theme.ink)
            Text(msg)
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Haptics.light()
                Task { await loadStoredPlan() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text(L("Tekrar dene"))
                        .font(Theme.Typo.button)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .fill(Theme.ink)
                )
                .foregroundStyle(Theme.onAccent)
            }
            .track("retry")
            Spacer()
            Spacer()
        }
    }

    // MARK: - Plan scroll

    @ViewBuilder
    private func planScrollView(_ plan: WeeklyPlanResponse) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                WeeklyReadinessRing(
                    score: plan.suitabilityScore,
                    missingCategories: plan.missingCategories
                ) {
                    readinessDetailVisible = true
                    Telemetry.shared.tap("WeeklyPlan.readiness_tapped", props: [
                        "score": plan.suitabilityScore,
                    ])
                }

                if !plan.activeRotationSummary.isEmpty {
                    rotationBanner(plan)
                }

                weekStrip(plan)

                if let day = plan.days.first(where: { $0.dayOfWeek == selectedDay }) {
                    selectedDayHero(day)
                }

                if !plan.warnings.isEmpty {
                    weeklyWarningsCard(plan.warnings)
                }

                if !plan.missingCategories.isEmpty {
                    missingCard(plan.missingCategories)
                }

                if let hint = cachedHintText(plan) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                        Text(hint)
                            .font(Theme.Typo.caption)
                    }
                    .foregroundStyle(Theme.inkMute)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                selfRoutinesToggleSection

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Active rotation banner

    @ViewBuilder
    private func rotationBanner(_ plan: WeeklyPlanResponse) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.25)) {
                rotationExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(L("Bu hafta"))
                        .font(Theme.Typo.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .textCase(.uppercase)
                    Spacer()
                    Image(systemName: rotationExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                Text(plan.activeRotationSummary)
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if rotationExpanded, !plan.weeklyNotes.isEmpty {
                    Divider().background(Theme.divider)
                    Text(plan.weeklyNotes)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.surface.opacity(0.75))
            )
        }
        .buttonStyle(PressedScaleButtonStyle())
        .track("rotation_banner_tapped")
    }

    // MARK: - Week strip

    @ViewBuilder
    private func weekStrip(_ plan: WeeklyPlanResponse) -> some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { d in
                let dayPlan = plan.days.first(where: { $0.dayOfWeek == d })
                dayCell(d, dayPlan: dayPlan)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int, dayPlan: WeeklyPlanDay?) -> some View {
        let isSelected = (day == selectedDay)
        let isToday = (day == WeekdayFormat.todayWeekday())
        let activeKinds = activeKindsFor(dayPlan: dayPlan)
        let intensity = intensityFor(dayPlan: dayPlan)
        let isRest = dayPlan?.restDay == true

        Button {
            Haptics.light()
            selectedDay = day
            if let dayPlan {
                detailDay = dayPlan
                Telemetry.shared.tap("WeeklyPlan.day_tapped", props: ["day": day])
            }
        } label: {
            VStack(spacing: 6) {
                Text(shortDayName(day))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.onAccent : Theme.inkSoft)

                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Theme.ink : (isToday ? Theme.surface : Color.clear))
                            .frame(width: 36, height: 36)
                        if isToday && !isSelected {
                            Circle()
                                .strokeBorder(Theme.ink, lineWidth: 1.5)
                                .frame(width: 36, height: 36)
                        }
                        if isRest {
                            Text("🌙")
                                .font(.system(size: 16))
                                .opacity(isSelected ? 1.0 : 0.7)
                        } else {
                            Text("\(day)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(isSelected ? Theme.onAccent : Theme.ink)
                        }
                    }
                    .opacity(isRest && !isSelected ? 0.55 : 1.0)

                    // Yoğunluk dot'ları (sağ üst köşe)
                    if !isRest && intensity > 0 {
                        intensityDots(intensity)
                            .offset(x: 4, y: -2)
                    }
                }

                // Aktif madde renk göstergeleri + altında kısa etiket label
                if !activeKinds.isEmpty {
                    VStack(spacing: 3) {
                        HStack(spacing: 3) {
                            ForEach(activeKinds.prefix(3), id: \.self) { kind in
                                Circle()
                                    .fill(colorFor(kind: kind))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .frame(height: 8)
                        Text(shortLabelText(for: activeKinds))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.onAccent.opacity(0.85) : Theme.inkSoft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                } else if isRest {
                    VStack(spacing: 3) {
                        Text("—")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.onAccent.opacity(0.6) : Theme.inkMute.opacity(0.6))
                            .frame(height: 8)
                        Text(L("Dinlen"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.onAccent.opacity(0.85) : Theme.inkSoft)
                            .lineLimit(1)
                    }
                } else {
                    VStack(spacing: 3) {
                        Text("—")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(isSelected ? Theme.onAccent.opacity(0.5) : Theme.inkMute.opacity(0.5))
                            .frame(height: 8)
                        Text(" ")
                            .font(.system(size: 9))
                            .frame(height: 10)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Theme.ink : Theme.surface.opacity(0.45))
            )
        }
        .buttonStyle(PressedScaleButtonStyle())
    }

    @ViewBuilder
    private func intensityDots(_ level: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<min(level, 3), id: \.self) { _ in
                Circle()
                    .fill(Theme.success)
                    .frame(width: 4, height: 4)
            }
        }
        .padding(3)
        .background(
            Capsule().fill(Theme.canvas.opacity(0.85))
        )
    }

    private func shortDayName(_ day: Int) -> String {
        let locale = appState.locale
        let names = locale == "en"
            ? WeekdayFormat.shortNamesEN
            : WeekdayFormat.shortNamesTR
        guard (1...7).contains(day) else { return "?" }
        return names[day]
    }

    // MARK: - Selected day hero

    @ViewBuilder
    private func selectedDayHero(_ day: WeeklyPlanDay) -> some View {
        Button {
            Haptics.light()
            detailDay = day
            Telemetry.shared.tap("WeeklyPlan.hero_tapped", props: ["day": day.dayOfWeek])
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    if day.restDay {
                        Text("🌙")
                            .font(.system(size: 22))
                    } else {
                        Text("✨")
                            .font(.system(size: 22))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizedDayName(day))
                            .font(Theme.Typo.headline)
                            .foregroundStyle(Theme.ink)
                        if let dateStr = formattedWeekDate(day.dayOfWeek) {
                            Text(dateStr)
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkMute)
                }

                if day.restDay {
                    HStack(alignment: .top, spacing: 8) {
                        Text("🌙")
                            .font(.system(size: 14))
                        Text(L("Dinlenme günü — sadece nemlendirme önerilir"))
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                            .fill(Theme.surfaceLow)
                    )
                } else {
                    HStack(spacing: 12) {
                        slotMiniSummary(
                            icon: "sun.max.fill",
                            label: L("Sabah"),
                            count: day.morningSteps.count
                        )
                        slotMiniSummary(
                            icon: "moon.stars.fill",
                            label: L("Akşam"),
                            count: day.eveningSteps.count
                        )
                    }
                }

                if !day.dayFocus.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "scope")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                        Text(day.dayFocus)
                            .font(Theme.Typo.caption.weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Theme.surfaceLow)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Aktif madde rozet'leri
                let kinds = activeKindsFor(dayPlan: day)
                if !kinds.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(kinds, id: \.self) { k in
                            activeKindChip(k)
                        }
                        Spacer()
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.surface.opacity(0.6))
            )
        }
        .buttonStyle(PressedScaleButtonStyle())
    }

    @ViewBuilder
    private func slotMiniSummary(icon: String, label: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Theme.Typo.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                Text(String(format: L("%lld adım"), count))
                    .font(Theme.Typo.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(Theme.surfaceLow.opacity(0.7))
        )
    }

    @ViewBuilder
    private func activeKindChip(_ kind: ActiveKind) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(colorFor(kind: kind))
                .frame(width: 6, height: 6)
            Text(kind.displayLabel)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(colorFor(kind: kind).opacity(0.18))
        )
        .overlay(
            Capsule().strokeBorder(colorFor(kind: kind).opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Weekly warnings

    @ViewBuilder
    private func weeklyWarningsCard(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.alert)
                Text(L("Haftalık uyarılar"))
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
    private func missingCard(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Text(L("Planı geliştirebilecek eksikler"))
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

    // MARK: - Self routines fallback toggle

    @ViewBuilder
    private var selfRoutinesToggleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptics.selection()
                withAnimation(.easeInOut(duration: 0.25)) {
                    showSelfRoutines.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showSelfRoutines ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L("AI yerine kendi rutinim"))
                        .font(Theme.Typo.caption.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(Theme.inkSoft)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .fill(Theme.surfaceLow.opacity(0.4))
                )
            }
            .buttonStyle(PressedScaleButtonStyle())
            .track("toggle_self_routines", props: ["expanded": !showSelfRoutines])

            if showSelfRoutines {
                if conflictBetweenAIAndSelf {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                        Text(L("Kendi rutinin AI planından farklı görünüyor"))
                            .font(Theme.Typo.caption)
                    }
                    .foregroundStyle(Theme.alert)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                            .fill(Theme.alert.opacity(0.08))
                    )
                }
                if isLoadingSelf && routines.isEmpty {
                    HStack {
                        ProgressView().tint(Theme.inkSoft).scaleEffect(0.8)
                        Text(L("Yükleniyor…"))
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.inkSoft)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                } else {
                    selfSlotSection(title: L("Sabah"), systemImage: "sun.max.fill", isMorning: true)
                    selfSlotSection(title: L("Akşam"), systemImage: "moon.stars.fill", isMorning: false)
                }
            }
        }
    }

    @ViewBuilder
    private func selfSlotSection(title: String, systemImage: String, isMorning: Bool) -> some View {
        let activeRoutines = routinesForSlot(isMorning: isMorning)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.inkSoft)
                Text(title)
                    .font(Theme.Typo.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }

            if activeRoutines.isEmpty {
                Text(L("Bu slot için rutin yok"))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkMute)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                            .fill(Theme.surface.opacity(0.3))
                    )
            } else {
                ForEach(activeRoutines) { routine in
                    selfRoutineDayCard(routine)
                }
            }
        }
    }

    @ViewBuilder
    private func selfRoutineDayCard(_ routine: RoutineResponse) -> some View {
        let steps = activeSelfSteps(for: routine, day: selectedDay)
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
                    Text(String(format: L("%lld adım"), steps.count))
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
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(Theme.surface.opacity(0.6))
            )
        }
        .buttonStyle(PressedScaleButtonStyle())
    }

    // MARK: - Self routine helpers

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

    private func activeSelfSteps(for routine: RoutineResponse, day: Int) -> [RoutineStepResponse] {
        let all = stepsByRoutine[routine.id] ?? []
        return all
            .filter { step in
                guard let days = step.daysActive, !days.isEmpty else { return true }
                return days.contains(day)
            }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    /// AI plan ile kendi rutinin step sayısı keskin farklıysa (≥ 3) basit warning.
    private var conflictBetweenAIAndSelf: Bool {
        guard let plan = weeklyPlan, !routines.isEmpty else { return false }
        let aiStepCount = plan.days.reduce(0) { $0 + $1.morningSteps.count + $1.eveningSteps.count }
        let selfStepCount = routines.reduce(0) { acc, r in
            acc + (stepsByRoutine[r.id]?.count ?? 0) * 7
        }
        // Aktif madde rotation farkı kabaca tetiklensin
        return abs(aiStepCount - selfStepCount) >= 7 && selfStepCount > 0
    }

    // MARK: - Active kind detection
    //
    // Shared helper'a delegate edilir: `Core/Utilities/ActiveKindDetector.swift`.
    // Aynı detection HomeWeeklyStrip'te de kullanılır — tek source of truth.

    private func colorFor(kind: ActiveKind) -> Color { kind.color }

    private func activeKindsFor(dayPlan: WeeklyPlanDay?) -> [ActiveKind] {
        guard let day = dayPlan else { return [] }
        return ActiveKindDetector.kinds(for: day)
    }

    /// Cell altında gösterilen kısa label — birden çok aktif varsa ilkin sonuna "+" konur.
    private func shortLabelText(for kinds: [ActiveKind]) -> String {
        guard let first = kinds.first else { return "—" }
        return kinds.count > 1 ? "\(first.shortLabel)+" : first.shortLabel
    }

    /// Step sayısına göre yoğunluk seviyesi — 1=düşük, 2=orta, 3=yüksek.
    private func intensityFor(dayPlan: WeeklyPlanDay?) -> Int {
        guard let day = dayPlan, !day.restDay else { return 0 }
        let total = day.morningSteps.count + day.eveningSteps.count
        switch total {
        case 0: return 0
        case 1...2: return 1
        case 3...4: return 2
        default: return 3
        }
    }

    // MARK: - Date / locale helpers

    /// Seçili haftadaki bir günün gerçek `Date`'i (Pazartesi-başlangıçlı).
    private func dateFor(day: Int) -> Date? {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let today = Date()
        let todayWeekday = WeekdayFormat.todayWeekday()
        let delta = day - todayWeekday
        return cal.date(byAdding: .day, value: delta, to: today)
    }

    private func formattedWeekDate(_ day: Int) -> String? {
        guard let date = dateFor(day: day) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: appState.locale == "en" ? "en" : "tr")
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: date)
    }

    private func localizedDayName(_ day: WeeklyPlanDay) -> String {
        // Backend dayName geliyor olabilir — yoksa locale'a göre türet.
        if !day.dayName.isEmpty {
            return day.dayName
        }
        let names = appState.locale == "en"
            ? ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
            : ["", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]
        guard (1...7).contains(day.dayOfWeek) else { return "?" }
        return names[day.dayOfWeek]
    }

    private func cachedHintText(_ plan: WeeklyPlanResponse) -> String? {
        guard let meta = plan.meta, meta.cached else { return nil }
        let relative: String
        if let date = meta.cachedAt {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .full
            f.locale = Locale(identifier: appState.locale == "en" ? "en" : "tr")
            relative = f.localizedString(for: date, relativeTo: Date())
        } else {
            relative = "—"
        }
        return String(format: L("Son güncelleme: %@"), relative)
    }

    private func scoreColor(_ s: Int) -> Color {
        switch s {
        case 80...: return Theme.success
        case 60...: return Theme.inkSoft
        default:    return Theme.alert
        }
    }

    // MARK: - Data loading

    @MainActor
    private func loadStoredPlan() async {
        // 1. Optimistic mirror — UserDefaults instant render.
        if storedPlan == nil, let cached = UserWeeklyPlanService.shared.loadCachedMirror() {
            storedPlan = cached
            isLoadingPlan = false
            if let today = cached.plan.days.first(where: { $0.dayOfWeek == WeekdayFormat.todayWeekday() }) {
                selectedDay = today.dayOfWeek
            }
        } else if storedPlan == nil {
            isLoadingPlan = true
        }
        planError = nil
        defer { isLoadingPlan = false }

        // 2. Backend authoritative GET — sync mirror.
        do {
            if let fresh = try await UserWeeklyPlanService.shared.getCurrent() {
                storedPlan = fresh
                if let today = fresh.plan.days.first(where: { $0.dayOfWeek == WeekdayFormat.todayWeekday() }) {
                    selectedDay = today.dayOfWeek
                }
                Telemetry.shared.tap("WeeklyPlan.loaded", props: [
                    "score": fresh.plan.suitabilityScore,
                    "days": fresh.plan.days.count,
                    "source": fresh.source,
                ])
            } else {
                // 404 — kullanıcı henüz kabul etmemiş; empty state göster.
                storedPlan = nil
            }
        } catch APIError.server(let code, let msg, _) {
            planError = code == "no_active_plan"
                ? L("Önce haftalık planını oluştur")
                : msg
        } catch {
            // Stale mirror varsa onu göstermeye devam; sessiz fail.
            if storedPlan == nil {
                planError = error.localizedDescription
            }
        }
    }

    @MainActor
    private func loadSelfRoutines() async {
        if routines.isEmpty { isLoadingSelf = true }
        defer { isLoadingSelf = false }
        do {
            async let rts = RoutineService.shared.listRoutines()
            async let prods = ProductScanService.shared.listMyProducts()
            let (rlist, plist) = try await (rts, prods)
            routines = rlist.sorted { $0.orderIndex < $1.orderIndex }
            userProducts = plist
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
            // Sessiz fail — self-routine fallback opsiyonel
        }
    }
}

// MARK: - Day detail sheet

/// Tap edilen günün detay sheet'i — morning/evening step listeleri + warnings.
struct WeeklyDayDetailSheet: View {
    let day: WeeklyPlanDay
    let weekDate: Date?
    let userProducts: [UserProductResponse]

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(LanguageManager.self) private var lang

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerCard

                        if day.restDay {
                            restDayHero
                        } else {
                            stepsSection(
                                icon: "sun.max.fill",
                                title: L("Sabah"),
                                steps: day.morningSteps
                            )
                            stepsSection(
                                icon: "moon.stars.fill",
                                title: L("Akşam"),
                                steps: day.eveningSteps
                            )
                        }

                        if !day.warnings.isEmpty {
                            warningsCard(day.warnings)
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .id(lang.current)
            .navigationTitle(localizedDayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Tamam")) { dismiss() }
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .telemetryScreen("WeeklyPlan.DayDetail")
    }

    @ViewBuilder
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(day.restDay ? "🌙" : "✨")
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizedDayName)
                        .font(Theme.Typo.headline)
                        .foregroundStyle(Theme.ink)
                    if let d = weekDate {
                        Text(formattedDate(d))
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer()
            }
            if !day.dayFocus.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "scope")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                    Text(day.dayFocus)
                        .font(Theme.Typo.caption.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.surfaceLow))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface.opacity(0.6))
        )
    }

    @ViewBuilder
    private var restDayHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("🌙")
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Dinlenme günü"))
                        .font(Theme.Typo.headline)
                        .foregroundStyle(Theme.ink)
                    Text(L("Cilt bariyerin için bugün sadece nemlendirme önerilir"))
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surfaceLow)
        )
    }

    @ViewBuilder
    private func stepsSection(icon: String, title: String, steps: [WeeklyPlanStep]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.inkSoft)
                Text(title)
                    .font(Theme.Typo.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(String(format: L("%lld adım"), steps.count))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
            }

            if steps.isEmpty {
                Text(L("Bu slot için adım yok"))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkMute)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                            .fill(Theme.surface.opacity(0.3))
                    )
            } else {
                ForEach(Array(steps.enumerated()), id: \.element.id) { (idx, step) in
                    stepRow(idx: idx, step: step)
                }
            }
        }
    }

    @ViewBuilder
    private func stepRow(idx: Int, step: WeeklyPlanStep) -> some View {
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
                    Text(productDisplayName(product: product, step: step, idx: idx))
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

            if !step.rationale.isEmpty {
                Text(step.rationale)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let inst = step.instruction, !inst.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                    Text(inst)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 6) {
                if let label = step.frequencyLabel, !label.isEmpty {
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

    private func productDisplayName(product: UserProductResponse?, step: WeeklyPlanStep, idx: Int) -> String {
        if let p = product {
            if let n = p.name, !n.isEmpty { return n }
            if let nk = p.nickname, !nk.isEmpty { return nk }
        }
        if let inst = step.instruction, !inst.isEmpty {
            return inst
        }
        return String(format: L("Ürün #%lld"), idx + 1)
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

    private var localizedDayName: String {
        if !day.dayName.isEmpty { return day.dayName }
        let names = appState.locale == "en"
            ? ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
            : ["", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]
        guard (1...7).contains(day.dayOfWeek) else { return "?" }
        return names[day.dayOfWeek]
    }

    private func formattedDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: appState.locale == "en" ? "en" : "tr")
        f.setLocalizedDateFormatFromTemplate("d MMMM")
        return f.string(from: d)
    }
}
