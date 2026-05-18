import UIKit

/// Onboarding ve genel UI için merkezî haptic helper'ı.
///
/// Tüm çağrılar `@MainActor` üzerinden iletilir; arka plan dokunmasına ihtiyaç yok.
/// Simulator'de haptic motor yoktur — çağrılar sessizce no-op olur.
@MainActor
enum Haptics {

    // MARK: - Impact

    /// Selection card / chip seçimi gibi orta yoğunluklu dokunuş
    static func selection() {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        g.impactOccurred()
    }

    /// Primary buton tıklaması, geçişler — hafif dokunuş
    static func light() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        g.impactOccurred()
    }

    /// Submit gibi ağır aksiyonlar için daha güçlü dokunuş
    static func heavy() {
        let g = UIImpactFeedbackGenerator(style: .heavy)
        g.prepare()
        g.impactOccurred()
    }

    // MARK: - Notification

    /// Onboarding submit başarılı, profil güncellendi vb.
    static func success() {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.success)
    }

    /// Submit hatası, validation error
    static func error() {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.error)
    }

    /// Uyarı — örn. atlanabilir adımı atlama
    static func warning() {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.warning)
    }
}
