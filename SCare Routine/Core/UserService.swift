import Foundation

/// Kullanıcı / profil verisi alıp güncelleyen servis.
/// Apple Sign In sonrası AppState.bootstrap()'tan çağrılır.
@MainActor
final class UserService {
    static let shared = UserService()
    private init() {}

    /// Sunucudan kullanıcının kendisini ve profilini birleşik çek.
    func fetchMe() async throws -> MeResponse {
        try await APIClient.shared.request(.me)
    }

    /// Profil alanlarını günceller (PATCH /v1/me/profile).
    /// Onboarding sonunda ve "ayarlar" ekranından çağrılır.
    func updateProfile(_ payload: ProfileUpdateRequest) async throws {
        try await APIClient.shared.requestVoid(.updateProfile, body: payload)
    }
}
