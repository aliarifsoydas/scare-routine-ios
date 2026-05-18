import Foundation
import AuthenticationServices

/// Apple Sign In ve session yönetimi.
@MainActor
final class AuthService {
    static let shared = AuthService()
    private init() {}

    /// Apple identity token + locale ile backend'e login isteği gönderir,
    /// dönen JWT'leri Keychain'e kaydeder. Mevcut/yeni kullanıcıyı döner.
    func signInWithApple(
        credential: ASAuthorizationAppleIDCredential,
        locale: String
    ) async throws -> AuthUser {
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw APIError.invalidResponse
        }

        let codeString: String? = {
            guard let data = credential.authorizationCode else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        // Apple "ilk girişte" displayName ve email gönderir, sonraki girişlerde nil
        let displayName: String? = {
            guard let name = credential.fullName else { return nil }
            let parts = [name.givenName, name.familyName].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " ")
        }()

        let body = AppleAuthRequest(
            identityToken: identityToken,
            authorizationCode: codeString,
            displayName: displayName,
            email: credential.email,
            locale: locale
        )

        let resp: AuthResponse = try await APIClient.shared.request(.authApple, body: body)

        guard let user = resp.user else {
            throw APIError.invalidResponse
        }

        try KeychainHelper.save(resp.accessToken, for: .accessToken)
        try KeychainHelper.save(resp.refreshToken, for: .refreshToken)
        try KeychainHelper.save(user.id, for: .userID)

        return user
    }

    /// Backend'den çıkış yap + tokenları temizle.
    /// Sunucu hatası gelse bile local state'i temizle (kullanıcı offline olabilir).
    func signOut() async {
        if let refresh = KeychainHelper.read(.refreshToken) {
            let body = LogoutRequest(refreshToken: refresh)
            try? await APIClient.shared.requestVoid(.authLogout, body: body)
        }
        KeychainHelper.deleteAll()
    }

    /// Hesap silme — geri dönüşü yok. Sunucuda cascade purge tetikler.
    func deleteAccount() async throws {
        try await APIClient.shared.requestVoid(.deleteAccount)
        KeychainHelper.deleteAll()
    }

    var isLoggedIn: Bool {
        KeychainHelper.read(.accessToken) != nil
    }

    var currentUserID: String? {
        KeychainHelper.read(.userID)
    }
}
