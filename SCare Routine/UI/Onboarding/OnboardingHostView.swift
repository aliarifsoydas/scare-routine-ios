import SwiftUI

/// Onboarding'in ana ekranı. AppState bağlanmış olarak çağrılır.
///
/// 6 adımlık akış: welcome → essentials → skinType → healthSync → preferences → finalPlan.
/// Submit `FinalPlanView`'in CTA'sında gerçekleşir.
///
/// LAYOUT: Top bar HER step için **sabit 56pt** yükseklik kaplar. İçeride sadece
/// progress + back/skip görünür/gizli olur. Bu, eski "üst slider bi yukarı bi aşağı
/// kayıyor" hatasını çözer — VStack'in birinci elemanı her zaman aynı boyutta.
public struct OnboardingHostView: View {
    @Environment(AppState.self) private var appState
    @State private var flow = OnboardingFlow()
    @State private var errorAlert: String?
    /// "Hadi başlayalım" basıldıktan sonra sahte hazırlanma animasyonu görünür mü
    @State private var showPreparing: Bool = false

    /// Top bar'a ayrılmış sabit dikey alan (tüm step'lerde aynı)
    private let topBarHeight: CGFloat = 56

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                // Normal onboarding akışı
                VStack(spacing: 0) {
                    topBarSlot
                        .frame(height: topBarHeight)
                        .padding(.horizontal, 20)

                    Group {
                        switch flow.step {
                        case .welcome:     WelcomeView(flow: flow, userName: displayName)
                        case .essentials:  EssentialsView(flow: flow)
                        case .skinType:    SkinTypeView(flow: flow)
                        case .healthSync:  HealthSyncView(flow: flow)
                        case .skinTone:    SkinToneEstimateView(flow: flow)
                        case .preferences: PreferencesView(flow: flow)
                        case .finalPlan:   FinalPlanView(flow: flow, userName: displayName, onStart: submit)
                        }
                    }
                    .transition(transitionForCurrentDirection)
                    .id(flow.step)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Telemetry: step değişince Group .id refresh olur, .telemetryScreen
                    // modifier onAppear'da screen event log'lar. Child view'lar Env'den
                    // bu prefix'i alır, içindeki .track("...") modifier'ları otomatik birleşir.
                    .telemetryScreen("Onboarding.\(flow.step)")
                }
                .opacity(showPreparing ? 0 : 1)

                // Hazırlanıyor animasyonu — submit basıldıktan sonra üstte
                if showPreparing {
                    PreparingPlanView {
                        // Animation %100'e ulaşıp tamamlandı → şimdi profileCompleted
                        // set edilir, ContentView main'e geçer.
                        appState.finalizeOnboarding()
                        Task { await appState.bootstrap() }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                }
            }
            .animation(.easeInOut(duration: 0.35), value: showPreparing)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .tint(Theme.accent)
        .onAppear {
            // Cihaz locale'i flow'a aktar
            flow.locale = appState.locale
            // İlk screen view (step view'lerin kendi .telemetryScreen'leri ile devam)
        }
        .alert(L("Bir sorun oluştu"), isPresented: Binding(
            get: { errorAlert != nil },
            set: { if !$0 { errorAlert = nil } }
        )) {
            Button(L("Tamam")) { errorAlert = nil }
        } message: {
            Text(errorAlert ?? "")
        }
    }

    // MARK: - Top bar slot (sabit yükseklik, içerik step'e göre)

    @ViewBuilder
    private var topBarSlot: some View {
        if flow.step.showsTopBar {
            topBar
        } else {
            // Welcome: top bar slot'u görünmez ama YER kaplar (layout sabitliği için)
            Color.clear
        }
    }

    // MARK: - Top bar (geri + ortalı progress)
    //
    // Sol ve sağ slot AYNI genişlik (44pt) tutar — progress bar gerçekten
    // ekran ortasında kalır. Üst "Atla" butonu artık YOK; HealthSync'in
    // alttaki secondary butonu skip işini yapar.

    private var topBar: some View {
        HStack(spacing: 12) {
            // Sol slot — geri butonu (yer kaplar her zaman)
            Button {
                flow.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.surface))
            }
            .disabled(!flow.step.canGoBack)
            .opacity(flow.step.canGoBack ? 1 : 0)
            .frame(width: 44, alignment: .leading)
            .accessibilityLabel(L("Geri"))

            // Orta: kalın linear progress (Cal AI tarzı). Sayaç KALDIRILDI —
            // bar tek başına yeterince anlatıyor.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.divider)
                        .frame(height: 5)
                    Capsule()
                        .fill(Theme.ink)
                        .frame(width: max(0, proxy.size.width * flow.step.progress),
                               height: 5)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85),
                                   value: flow.step.progress)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .frame(height: 36)
            .overlay(alignment: .trailing) {
                // FinalPlan'da küçük yeşil check rozeti — başarı sinyali
                if flow.step == .finalPlan {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.success)
                        .padding(.trailing, 4)
                }
            }

            // Sağ slot — boş ama eşit genişlik (simetri için)
            Color.clear.frame(width: 44, height: 1)
        }
    }

    // MARK: - Transition (yöne göre)

    private var transitionForCurrentDirection: AnyTransition {
        switch flow.direction {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    // MARK: - Kullanıcı adı (welcome + finalPlan selamlaması)

    /// Authenticated state'inden displayName çıkar; yoksa nil.
    /// Apple Sign In ilk girişte ad gönderir, sonraki girişlerde nil olur — bu yüzden
    /// kontrol gerekir.
    private var displayName: String? {
        if case .authenticated(let user) = appState.phase {
            if let full = user.displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !full.isEmpty {
                return full.split(separator: " ").first.map(String.init)
            }
        }
        return nil
    }

    // MARK: - Submit (FinalPlanView'dan tetiklenir)

    private func submit() {
        // Preparing animasyonunu hemen göster — backend submit'i paralel olarak çalışsın
        showPreparing = true

        // Telemetry — submit tıklandı + dolu olan alanlar
        Telemetry.shared.tap("onboarding.submit", props: [
            "skin_type": flow.selectedSkinType?.rawValue ?? "unknown",
            "skin_concerns_count": flow.selectedSkinConcerns.count,
            "hair_type": flow.selectedHairType ?? "none",
            "hair_concerns_count": flow.selectedHairConcerns.count,
            "body_concerns_count": flow.selectedBodyConcerns.count,
            "makeup_prefs_count": flow.selectedMakeupPrefs.count,
            "has_health_data": flow.healthKit != nil,
            "has_manual_data": flow.manualBirthDate != nil || flow.manualBiologicalSex != nil,
        ])
        let submitTiming = Telemetry.shared.startTiming("onboarding.submit_to_complete")

        Task {
            flow.submitError = nil
            flow.isSubmitting = true
            defer { flow.isSubmitting = false }

            // Yerel locale'i de senkronize et
            appState.setLocale(flow.locale)

            do {
                try await appState.completeOnboarding(flow)
                await MainActor.run {
                    Telemetry.shared.endTiming(submitTiming, props: ["result": "success"])
                    Telemetry.shared.flush()
                }
                // Başarılı — preparing animasyonu onComplete'ında bootstrap çağırır
                // ve MainTabView'a geçer (AppState.phase değişiminde)
            } catch {
                // Hata → preparing'i kapat, alert göster
                showPreparing = false
                let msg: String
                if let api = error as? APIError {
                    msg = api.errorDescription ?? L("Bilinmeyen bir hata oluştu.")
                } else {
                    msg = error.localizedDescription
                }
                flow.submitError = msg
                errorAlert = msg
                await MainActor.run {
                    Telemetry.shared.endTiming(submitTiming, props: ["result": "error"])
                    Telemetry.shared.error("onboarding.submit_failed", message: msg)
                }
                Haptics.error()
            }
        }
    }
}
