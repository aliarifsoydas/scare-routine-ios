import Foundation
import UIKit
import UserNotifications
import AVFoundation
import Photos
import HealthKit

/// APNs device token'ı backend'e gönderir.
///
/// Akış:
/// 1. iOS app açılışta `registerForRemoteNotifications()` çağırır (permission verildikten sonra)
/// 2. `AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken` Apple'dan token alır
/// 3. Bu service backend'e POST /v1/me/devices/register ile gönderir
/// 4. Backend `user_devices` tablosuna upsert eder
///
/// Token cihaz başına unique; aynı user farklı cihaz için ayrı satır oluşur.
@MainActor
final class DeviceRegistrationService {
    static let shared = DeviceRegistrationService()
    private init() {}

    /// APNs `Data` → hex string format ("ab12cd34..." şeklinde, lowercase).
    func tokenString(from data: Data) -> String {
        return data.map { String(format: "%02hhx", $0) }.joined()
    }

    /// Backend'e token kaydet. Hata fırlatmaz, sessizce log atar.
    ///
    /// Environment otomatik tespit edilir: DEBUG build → "sandbox", Release/
    /// TestFlight/App Store → "production". Backend her cihaza doğru APNs
    /// sunucusunu (api.sandbox.push.apple.com vs api.push.apple.com) gönderir.
    ///
    /// İzinler de gönderilir — admin dashboard'da kullanıcının hangi izinleri
    /// verdiğini görebilmek için. Her register'da güncel snapshot.
    func register(token: String) async {
        let environment: String
        #if DEBUG
        environment = "sandbox"
        #else
        environment = "production"
        #endif

        let permissions = await collectPermissions()

        let payload = DeviceRegisterRequest(
            device_token: token,
            platform: "ios",
            environment: environment,
            app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            os_version: UIDevice.current.systemVersion,
            device_model: UIDevice.current.model,
            permissions: permissions
        )
        do {
            try await APIClient.shared.requestVoid(.registerDevice, body: payload)
            print("[Device] registered APNs token (\(token.prefix(8))…) env=\(environment)")
            Telemetry.shared.custom("device.registered", props: ["environment": environment])
        } catch {
            print("[Device] register failed: \(error.localizedDescription)")
            Telemetry.shared.error("device.register_failed", message: error.localizedDescription, props: [:])
        }
    }

    /// iOS sistem permission'larını sözlük olarak toplar — admin dashboard'da gösterilir.
    /// Per-permission değerler: "authorized" | "denied" | "not_determined" | "provisional" | "limited"
    private func collectPermissions() async -> [String: String] {
        var result: [String: String] = [:]

        // Notifications
        let notifStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        result["notifications"] = notifAuthString(notifStatus)

        // Camera
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        result["camera"] = avAuthString(camStatus)

        // Photo Library — kullandığımız SwiftUI PhotosPicker app izni gerektirmez
        // (system-level picker). PHPhotoLibrary status her zaman notDetermined
        // döner çünkü classic dialog hiç açılmaz. Bu yüzden raporlamıyoruz.
        // (Eski API'ye dönersek burada gerçek status verilebilir.)

        // HealthKit — Apple read iznini direkt rapor etmez (privacy). En iyi proxy:
        // HealthKitService.connectionStatus() → statusForAuthorizationRequest
        //  .requested → kullanıcı dialog'u görmüş (allow VEYA deny — fark etmez)
        //  .notRequested → henüz sorulmadı
        let hkStatus = await HealthKitService.shared.connectionStatus()
        switch hkStatus {
        case .requested: result["health_share"] = "authorized"
        case .notRequested: result["health_share"] = "not_determined"
        case .unsupported: result["health_share"] = "unavailable"
        case .unknown: result["health_share"] = "unknown"
        }

        return result
    }

    private func notifAuthString(_ s: UNAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .notDetermined: return "not_determined"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }
    private func avAuthString(_ s: AVAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .notDetermined: return "not_determined"
        case .restricted: return "restricted"
        @unknown default: return "unknown"
        }
    }
}

/// POST /v1/me/devices/register body.
private struct DeviceRegisterRequest: Encodable {
    let device_token: String
    let platform: String
    let environment: String   // "sandbox" | "production"
    let app_version: String?
    let os_version: String?
    let device_model: String?
    let permissions: [String: String]?
}
