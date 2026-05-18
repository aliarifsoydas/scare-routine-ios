import Foundation

enum AppConfig {
    /// Backend base URL — env'e göre seçilir.
    /// Dev: local wrangler dev (varsayılan 8787).
    /// Prod: deploy edildikten sonra Cloudflare Workers URL'si buraya yazılacak.
    static var baseURL: URL {
        #if DEBUG
        // Debug build: local wrangler dev (8787) veya canlı backend.
        // Şimdilik canlı backend'i kullanıyoruz — local dev'e geçince bu satırı değiştir.
        return URL(string: "https://scare.xflink.co")!
        #else
        return URL(string: "https://scare.xflink.co")!
        #endif
    }

    static let apiVersion = "v1"
    static let defaultLocale = "tr"
    static let appleBundleID = "com.aliarifsoydas.scareroutine"

    /// Disclaimer metni versiyonu — her güncellemede artırılır,
    /// kullanıcının onayladığı sürüm `UserConsent.version` alanında tutulur.
    static let consentVersion = "1.0"
}
