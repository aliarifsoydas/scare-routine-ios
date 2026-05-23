import Foundation
import SwiftUI

/// Uygulama genelinde paylaşılan oturum + locale state.
/// `@Observable` ile iOS 17 modern observation API'si.
@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case launching
        case onboarding
        case authenticated(AuthUser)
    }

    var phase: Phase = .launching
    var locale: String
    var error: APIError?

    /// Sunucudan profil çekilince doldurulur. UserDefaults'ta da persist edilir
    /// — backend decode fail etse bile kullanıcı onboarding'i tekrar görmez.
    var profileCompleted: Bool = UserDefaults.standard.bool(forKey: "scare.profileCompleted") {
        didSet {
            UserDefaults.standard.set(profileCompleted, forKey: "scare.profileCompleted")
        }
    }

    /// ContentView routing'i için: profil tamamlanmamışsa onboarding flow gerek.
    var needsOnboarding: Bool { !profileCompleted }

    /// Sunucudan çekilen gerçek profil bilgisi (ProfileView okuyor).
    /// `bootstrap()` ve `refreshMe()` ile güncellenir.
    var currentProfile: ProfileData?
    var currentUser: AuthUser?

    init() {
        // Bundle.main.preferredLocalizations = iOS Settings'teki app-specific dil
        // (kullanıcı Settings → SCare Routine → Preferred Language seçimi).
        // Locale.preferredLanguages bunu da içerir ama Bundle.main daha kesin.
        let lang = Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "tr"
        let primary = String(lang.prefix(2)).lowercased()
        self.locale = (primary == "tr") ? "tr" : "en"
    }

    // MARK: - Yaşam döngüsü

    /// App açıldığında çağrılır — kayıtlı token varsa /v1/me ile profili çeker,
    /// yoksa Apple Sign In'a yönlendirir.
    ///
    /// **Beyaz ekran koruması**: phase 4 saniye içinde mutlaka `.launching`'den
    /// çıkar (network başarısız bile olsa). Kullanıcı asla takılmaz.
    func bootstrap() async {
        guard AuthService.shared.isLoggedIn else {
            phase = .onboarding
            return
        }

        // Optimistic UI: placeholder ile authenticated'e geç (LaunchView'dan çık).
        // Sonra arka planda /v1/me ile gerçek bilgi çekilirken kullanıcı zaten
        // onboarding veya main ekranında.
        if let id = AuthService.shared.currentUserID {
            phase = .authenticated(AuthUser(
                id: id, email: nil, displayName: nil,
                locale: locale, createdAt: .now, isNewUser: false
            ))
        } else {
            phase = .onboarding
            return
        }

        // /v1/me — best effort. 5 saniyelik timeout. Başarısızsa placeholder kalır.
        do {
            let me = try await withTimeout(seconds: 5) {
                try await UserService.shared.fetchMe()
            }
            // Backend authoritative — /v1/me başarılı döndüyse profile durumunu
            // local state'e aynen yansıt. Eğer backend profile null/incomplete
            // ise (ör. onboarding submit fail edip yarıda kalmışsa) local
            // profileCompleted'i de false yap → onboarding'e tekrar gönder.
            self.profileCompleted = (me.profile?.isComplete == true)

            // Sistem dili (iOS Settings) ile backend user.locale farklıysa
            // backend'i güncelle. AI prompt'ları user.locale'e göre dil seçer
            // → kullanıcı iOS'ta English'e geçti ama backend hâlâ "tr" diyor
            // → AI Türkçe cevap dönüyor (yanlış).
            let systemLocale = self.locale   // init'te Bundle.main.preferredLocalizations'tan set edildi
            if let backendLocale = me.user.locale, backendLocale != systemLocale {
                print("[Locale] system=\(systemLocale) backend=\(backendLocale) → syncing to system")
                // Task (MainActor inherit) — ProfileUpdateRequest + UserService.shared
                // ikisi de @MainActor isolated. Detached olursa Swift 6'da error.
                Task {
                    var payload = ProfileUpdateRequest()
                    payload.locale = systemLocale
                    try? await UserService.shared.updateProfile(payload)
                }
            }
            // Eğer kullanıcı /me/profile edit'inde değiştirdiyse onu da yansıt
            self.locale = me.user.locale ?? systemLocale
            self.currentUser = me.user
            self.currentProfile = me.profile
            phase = .authenticated(me.user)
        } catch APIError.unauthorized {
            // Token expire — temizle, sign-in'a dön
            await AuthService.shared.signOut()
            phase = .onboarding
        } catch {
            // Network / timeout / başka — placeholder kalır, kullanıcı kullanmaya devam eder
            // Log için stdout'a yaz
            print("[AppState] /v1/me bootstrap failed: \(error.localizedDescription)")
        }
    }

    /// async iş için timeout sarmalayıcısı. Süre içinde tamamlanmazsa `APIError.requestFailed` fırlatır.
    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw APIError.requestFailed(NSError(domain: "Timeout", code: -1))
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    // MARK: - Auth aksiyonları

    func signIn(_ user: AuthUser) {
        phase = .authenticated(user)
        // Backend'de profil zaten dolu olabilir (kullanıcı eskiden onboarding yapmış,
        // çıkış yapıp tekrar girmiş). /v1/me ile profile fetch et —
        // isComplete=true ise onboarding'i atla.
        Task { await refreshMe() }
    }

    func signOut() async {
        await AuthService.shared.signOut()
        profileCompleted = false       // UserDefaults da temizlenir (didSet)
        currentProfile = nil
        currentUser = nil
        phase = .onboarding
    }

    // MARK: - HealthKit sync

    /// HealthKit'ten daily sleep history backend'e push (geriye dönük 90/14 gün).
    /// İlk açılışta 90 gün, sonraki foreground'larda 14 gün delta — idempotent upsert.
    func syncHealthKitHistory() async {
        await HealthMetricsSyncService.shared.syncSleepHistory()
    }

    /// HealthKit'ten son 7 günün uyku ortalamasını alıp backend profile'a yansıt.
    /// Apple Watch sleep tracking güncel veriyi düzenli atar → app foreground'da
    /// her açılışta çağrılır, profile.lifestyle.sleep_hours_avg refresh olur.
    ///
    /// İdempotent: değer değişmediyse network atmaz, küçük fark için tetiklenmez.
    func syncHealthKitSleepToProfile() async {
        guard HealthKitService.shared.isAvailable else { return }
        guard let fresh = await HealthKitService.shared.currentAverageSleepHours(days: 7) else { return }
        guard fresh > 0 else { return }

        // Mevcut değerle karşılaştır (lifestyle JSON içinde sleep_hours_avg)
        let currentRaw = currentProfile?.lifestyle as? [String: Any]
        let currentValue = currentRaw?["sleep_hours_avg"] as? Double
        if let existing = currentValue, abs(existing - fresh) < 0.15 {
            return   // <9 dk fark → gönderme, gereksiz
        }

        var payload = ProfileUpdateRequest()
        payload.lifestyle = LifestylePayload(sleepHoursAvg: fresh)
        do {
            try await UserService.shared.updateProfile(payload)
            print("[HealthKit] sleep synced: \(String(format: "%.1f", fresh))h/day (7d avg)")
            await refreshMe()
        } catch {
            print("[HealthKit] sleep sync failed: \(error.localizedDescription)")
        }
    }

    /// Profil edit sonrası çağırılır — yeni /v1/me ile state'i tazele.
    /// Foreground transition'larda da çağırılarak admin push queue sync edilir.
    func refreshMe() async {
        do {
            let me = try await UserService.shared.fetchMe()
            self.currentUser = me.user
            self.currentProfile = me.profile
            // Backend authoritative — boşsa local'i de sıfırla (bkz. bootstrap notu).
            self.profileCompleted = (me.profile?.isComplete == true)
        } catch {
            print("[AppState] refreshMe failed: \(error.localizedDescription)")
        }
        // Notification queue + template refresh — fire-and-forget
        Task {
            await NotificationService.shared.loadTemplates(locale: self.locale)
            await NotificationService.shared.syncPendingQueue()
        }
    }

    func setLocale(_ newLocale: String) {
        locale = newLocale
        // Sunucu tarafına da yansıt — sessizce, hata varsa görmezden gel (best effort)
        Task {
            // TODO: PATCH /me/profile with new locale (DTO eklenince)
        }
    }

    // MARK: - Onboarding tamamlama

    /// Onboarding adımları tamamlandığında çağrılır.
    /// 1. Profil PATCH
    /// 2. Her consent için ayrı POST
    /// 3. Başarılıysa `profileCompleted = true`
    func completeOnboarding(_ flow: OnboardingFlow) async throws {
        let profileBody = flow.buildProfileRequest()
        try await APIClient.shared.requestVoid(.updateProfile, body: profileBody)

        let version = ISO8601DateFormatter().string(from: .now)
            .split(separator: "T").first.map(String.init) ?? "v1"
        let consents = flow.buildConsentRequests(version: version)
        for c in consents {
            // Sessizce devam et — bir consent fail olsa bile onboarding'i kilitlemeyelim
            do {
                try await APIClient.shared.requestVoid(.postConsent, body: c)
            } catch {
                // Loglanır ama akış kırılmaz
                print("[AppState] Consent post failed for \(c.consentType): \(error)")
            }
        }

        locale = flow.locale
        // NOT: profileCompleted'i BU FONKSİYON DEĞIL,
        // PreparingPlanView.onComplete'inde finalize ediyoruz —
        // animation tamamlanmadan ContentView main'e geçmesin diye.
    }

    /// Onboarding submit + preparing animation'ın HER İKİSİ tamamlanınca
    /// PreparingPlanView'in onComplete callback'inden çağrılır.
    /// Bu noktada profileCompleted = true → ContentView main'e geçer.
    func finalizeOnboarding() {
        profileCompleted = true
        if case .authenticated = phase {
            // no-op — ContentView reactive olarak main'e geçer
        } else if let id = AuthService.shared.currentUserID {
            phase = .authenticated(AuthUser(
                id: id, email: nil, displayName: nil,
                locale: locale, createdAt: .now, isNewUser: true
            ))
        }

        // Notification permission iste + Tier 0 sched (0 ürün aktivasyon)
        // Fire-and-forget: UX bloklanmaz, izin reddedilse de uygulama çalışır.
        Task {
            await NotificationService.shared.loadTemplates(locale: locale)
            let granted = await NotificationService.shared.requestAuthorization()
            if granted {
                await NotificationService.shared.scheduleTier0Activation()
            }
        }
    }
}
