import Foundation

/// POST /v1/me/skin-tone-estimate payload'ı — iOS on-device ITA tahmini
/// (Lab/ITA + Fitzpatrick + RGB swatch) ve opsiyonel selfie photo_key.
///
/// Backend `skin_tone_estimates` tablosuna kaydeder ve `user_corrected = false`
/// ise `user_profiles.fitzpatrick_type`'i auto-backfill eder.
struct SkinToneEstimateRequest: Encodable {
    /// R2 anahtarı veya `/v1/uploads/object/...` URL'i. nil → metrics_only kayıt.
    let photo_key: String?
    /// Fitzpatrick tipi 1..6
    let fitzpatrick: Int
    /// ITA (Individual Typology Angle) — derece cinsinden
    let ita: Double
    /// CIELAB ortalama: L*, a*, b*
    let avg_l: Double?
    let avg_a: Double?
    let avg_b: Double?
    /// sRGB ortalama: 0..1 normalized
    let avg_r: Double?
    let avg_g: Double?
    let avg_blue: Double?
    /// Tahmin güveni 0..1
    let confidence: Double
    /// Yüzden sample edilen piksel sayısı (kalite göstergesi)
    let sample_count: Int
    /// İstemci versiyon bilgisi — debug + future analytics
    let app_version: String?
    let os_version: String?
    /// Hangi ekrandan gönderildi: "onboarding" | "profile_edit" | "skin_log"
    let source: String
    /// Kullanıcı tahmini override etti mi?
    let user_corrected: Bool
    let corrected_to: Int?
}
