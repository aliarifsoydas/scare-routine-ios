import Foundation
import UIKit

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

    /// Cilt tonu tahminini selfie ile birlikte backend'e kaydeder.
    ///
    /// Akış:
    /// 1. Selfie varsa R2'ye upload (SkinLogService.uploadSelfie) → publicUrl
    /// 2. POST /v1/me/skin-tone-estimate (estimate + photo_key)
    ///
    /// Backend yan etkisi: `user_corrected=false` ise `user_profiles.fitzpatrick_type`
    /// auto-backfill edilir.
    ///
    /// Hatalar fırlatılır — caller best-effort yapmak isterse try? ile çağırabilir.
    func submitSkinToneEstimate(
        image: UIImage?,
        result: SkinToneEstimator.Result,
        source: String,
        userCorrected: Bool = false,
        correctedTo: Int? = nil
    ) async throws {
        // 1) Selfie upload (best-effort — başarısızsa metrics-only kaydet)
        var photoKey: String? = nil
        if let img = image {
            do {
                photoKey = try await SkinLogService.shared.uploadSelfie(img)
            } catch {
                print("[SkinTone] selfie upload failed, continuing metrics-only: \(error.localizedDescription)")
            }
        }

        // 2) Estimate POST
        let payload = SkinToneEstimateRequest(
            photo_key: photoKey,
            fitzpatrick: result.fitzpatrick,
            ita: result.ita,
            avg_l: result.avgL,
            avg_a: result.avgA,
            avg_b: result.avgB,
            avg_r: Double(result.avgRGB.r),
            avg_g: Double(result.avgRGB.g),
            avg_blue: Double(result.avgRGB.b),
            confidence: result.confidence,
            sample_count: result.sampleCount,
            app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            os_version: UIDevice.current.systemVersion,
            source: source,
            user_corrected: userCorrected,
            corrected_to: correctedTo
        )
        try await APIClient.shared.requestVoid(.postSkinToneEstimate, body: payload)
    }
}
