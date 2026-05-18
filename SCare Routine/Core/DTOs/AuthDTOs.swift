import Foundation

// MARK: - Apple Sign In

struct AppleAuthRequest: Encodable {
    let identityToken: String
    let authorizationCode: String?
    let displayName: String?
    let email: String?
    let locale: String
}

struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int             // saniye
    let user: AuthUser?            // /refresh endpoint'i user döndürmez
}

struct AuthUser: Decodable, Hashable {
    let id: String
    let email: String?
    let displayName: String?
    let locale: String?            // Backend null/eksik gönderirse decode fail etmesin
    let createdAt: Date?           // /v1/me ve /auth/apple'da int (unix seconds)
    let isNewUser: Bool?           // sadece /auth/apple'da var

    /// Defensive decode — backend her zaman bütün field'ları döndürmeyebilir
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.email = try? c.decodeIfPresent(String.self, forKey: .email)
        self.displayName = try? c.decodeIfPresent(String.self, forKey: .displayName)
        self.locale = try? c.decodeIfPresent(String.self, forKey: .locale)
        self.createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        self.isNewUser = try? c.decodeIfPresent(Bool.self, forKey: .isNewUser)
    }

    /// Sentetik AuthUser (placeholder, sign-in akışı)
    init(id: String, email: String?, displayName: String?, locale: String?, createdAt: Date?, isNewUser: Bool?) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.locale = locale
        self.createdAt = createdAt
        self.isNewUser = isNewUser
    }

    private enum CodingKeys: String, CodingKey {
        case id, email, displayName, locale, createdAt, isNewUser
    }
}

// MARK: - Refresh

struct RefreshRequest: Encodable {
    let refreshToken: String
}

// MARK: - Logout

struct LogoutRequest: Encodable {
    let refreshToken: String
}
