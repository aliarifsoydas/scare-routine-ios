import SwiftUI

/// AI'dan gelen `WeeklyPlanResponse`'i kullanıcıya gösterip "Kabul et veya yenile"
/// kararı aldıran modal sheet.
///
/// Akış:
/// 1. HomeView `UserWeeklyPlanService.getCurrent()` 404 dönerse veya kullanıcı
///    "Yenile" derse AI suggest çalışır ve gelen response bu sheet'e iletilir.
/// 2. "Kabul et ve başla" → `UserWeeklyPlanService.accept(plan)` çağrılır → parent
///    state güncellenir → dismiss.
/// 3. "Tekrar üret" → AI suggest tekrar tetiklenir, sheet içinde loading gösterilir
///    ve yeni response geldiğinde içerik tazelenir.
///
/// Görsel disiplin: WeeklyReadinessRing + activeRotationSummary + 7-day mini özet +
/// missing/warnings — `WeeklyCalendarView` ile aynı dil, tek source-of-truth.
struct AcceptPlanSheet: View {
    /// Sheet açılırken AI'dan gelen ilk plan. Kullanıcı "Tekrar üret" derse
    /// state güncellenir; bu prop ilk seed değer için.
    let initialPlan: WeeklyPlanResponse

    /// İlk haftalık plan mı (henüz hiç kabul edilmiş plan yok) yoksa kullanıcı
    /// mevcut planı yenilemek istiyor mu? Başlık ve subtitle copy'sini değiştirir.
    let isFirstPlan: Bool

    /// AI çağrısı sırasında kullanılan locale — POST'a da geçirilir.
    let locale: String

    /// Kabul edildiğinde StoredWeeklyPlan ile parent'a haber ver.
    var onAccepted: (StoredWeeklyPlan) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(LanguageManager.self) private var lang

    @State private var plan: WeeklyPlanResponse
    @State private var isRegenerating: Bool = false
    @State private var isAccepting: Bool = false
    @State private var errorMessage: String?

    init(
        initialPlan: WeeklyPlanResponse,
        isFirstPlan: Bool,
        locale: String,
        onAccepted: @escaping (StoredWeeklyPlan) -> Void
    ) {
        self.initialPlan = initialPlan
        self.isFirstPlan = isFirstPlan
        self.locale = locale
        self.onAccepted = onAccepted
        self._plan = State(initialValue: initialPlan)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                if isRegenerating {
                    regeneratingView
                } else {
                    contentScroll
                }
            }
            .id(lang.current)
            .navigationTitle(isFirstPlan ? L("İlk haftalık planın hazır") : L("Yeni öneri hazır"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("İptal")) { dismiss() }
                        .foregroundStyle(Theme.ink)
                        .disabled(isAccepting)
                }
            }
        }
        .interactiveDismissDisabled(isAccepting)
        .telemetryScreen("WeeklyPlan.AcceptSheet")
    }

    // MARK: - Content

    @ViewBuilder
    private var contentScroll: some View {
        ScrollView {
            VStack(spacing: 16) {
                introBanner

                WeeklyReadinessRing(
                    score: plan.suitabilityScore,
                    missingCategories: plan.missingCategories,
                    onDetailTap: {}
                )
                .allowsHitTesting(false) // Sheet içinde tap'a gerek yok — info only

                if !plan.activeRotationSummary.isEmpty {
                    rotationCard
                }

                miniWeekStrip

                if !plan.missingCategories.isEmpty {
                    missingCard
                }

                if !plan.warnings.isEmpty {
                    warningsCard
                }

                if let err = errorMessage {
                    errorBanner(err)
                }

                actions
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var introBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isFirstPlan
                 ? L("AI cilt tipine ve ürünlerine göre haftalık ritmi kurdu.")
                 : L("Yeni bir haftalık plan önerisi hazır."))
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var rotationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(L("Aktif rotasyon"))
                    .font(Theme.Typo.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .textCase(.uppercase)
                Spacer()
            }
            Text(plan.activeRotationSummary)
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface.opacity(0.75))
        )
    }

    @ViewBuilder
    private var miniWeekStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Haftalık plan"))
                .font(Theme.Typo.caption.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(Theme.inkSoft)
            HomeWeeklyStrip(
                days: plan.days,
                todayWeekday: WeekdayFormat.todayWeekday(),
                locale: locale
            )
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.surface.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.divider.opacity(0.6), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var missingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Text(L("Planı geliştirebilecek eksikler"))
                    .font(Theme.Typo.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Text(plan.missingCategories.joined(separator: " · "))
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
    private var warningsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.alert)
                Text(L("Uyarılar"))
                    .font(Theme.Typo.caption.weight(.semibold))
                    .foregroundStyle(Theme.alert)
            }
            ForEach(plan.warnings, id: \.self) { w in
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
    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.alert)
            Text(msg)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.alert.opacity(0.08))
        )
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.light()
                Task { await acceptPlan() }
            } label: {
                HStack(spacing: 8) {
                    if isAccepting {
                        ProgressView()
                            .tint(Theme.onAccent)
                            .scaleEffect(0.85)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(L("Kabul et ve başla"))
                        .font(Theme.Typo.button)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .fill(Theme.ink)
                )
                .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(PressedScaleButtonStyle())
            .disabled(isAccepting || isRegenerating)
            .track("weekly_plan.accept")

            Button {
                Haptics.selection()
                Task { await regenerate() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text(L("Tekrar üret"))
                        .font(Theme.Typo.button)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
            .disabled(isAccepting || isRegenerating)
            .track("weekly_plan.regenerate")
        }
        .padding(.top, 4)
    }

    // MARK: - Regenerating view

    @ViewBuilder
    private var regeneratingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .tint(Theme.ink)
                .scaleEffect(1.1)
            Text(L("Yeni plan üretiliyor…"))
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.inkSoft)
            Spacer()
            Spacer()
        }
    }

    // MARK: - Actions

    @MainActor
    private func acceptPlan() async {
        isAccepting = true
        errorMessage = nil
        defer { isAccepting = false }
        do {
            let stored = try await UserWeeklyPlanService.shared.accept(
                plan,
                locale: locale
            )
            Telemetry.shared.custom("weekly_plan.accepted", props: [
                "score": plan.suitabilityScore,
                "first": isFirstPlan,
                "days": plan.days.count,
            ])
            onAccepted(stored)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            Telemetry.shared.error("weekly_plan.accept_failed", message: error.localizedDescription)
        }
    }

    @MainActor
    private func regenerate() async {
        isRegenerating = true
        errorMessage = nil
        defer { isRegenerating = false }
        do {
            let fresh = try await AIRecommendService.shared.recommendWeeklyPlan(
                locale: locale,
                focus: "refresh"
            )
            self.plan = fresh
            Telemetry.shared.custom("weekly_plan.regenerated", props: [
                "score": fresh.suitabilityScore,
            ])
        } catch {
            errorMessage = error.localizedDescription
            Telemetry.shared.error("weekly_plan.regenerate_failed", message: error.localizedDescription)
        }
    }
}
