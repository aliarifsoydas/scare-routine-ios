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
        // Sistem dilini "tr" veya "en"e indirge
        let lang = Locale.preferredLanguages.first?.split(separator: "-").first.map(String.init) ?? "tr"
        self.locale = (lang == "tr") ? "tr" : "en"
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
            // Backend profile dolu ise true set et. Eğer backend boş döndürdüyse
            // local state'i (UserDefaults) BOZMA — onboarding'i sahte tetikleme.
            if me.profile?.isComplete == true {
                self.profileCompleted = true
            }
            self.locale = me.user.locale ?? self.locale
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

    /// Profil edit sonrası çağırılır — yeni /v1/me ile state'i tazele.
    func refreshMe() async {
        do {
            let me = try await UserService.shared.fetchMe()
            self.currentUser = me.user
            self.currentProfile = me.profile
            if me.profile?.isComplete == true {
                self.profileCompleted = true
            }
        } catch {
            print("[AppState] refreshMe failed: \(error.localizedDescription)")
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
        profileCompleted = true

        // Halihazırda authenticated isek phase'i koruyalım; aksi halde bootstrap akışını sürdür
        if case .authenticated = phase {
            // no-op — ContentView needsOnboarding'i yeniden değerlendirecek
        } else if let id = AuthService.shared.currentUserID {
            phase = .authenticated(AuthUser(
                id: id, email: nil, displayName: nil,
                locale: locale, createdAt: .now, isNewUser: true
            ))
        }
    }
}
