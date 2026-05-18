import Foundation

/// AI'ın selfie/foto'dan çıkardığı yapılandırılmış gözlem.
/// **Sayısal skor yok** — sadece niteleyici tarif. Trendler kullanıcının
/// kendi self-değerlendirmesinden çizilir.
struct AIObservation: Codable, Hashable, Sendable {
    var observations: [String]
    var lightingQuality: ImageQuality
    var imageUsable: Bool
    var confidence: AIConfidence
    var disclaimerVersion: String
    var generatedAt: Date

    enum CodingKeys: String, CodingKey {
        case observations
        case lightingQuality = "lighting_quality"
        case imageUsable = "image_usable"
        case confidence
        case disclaimerVersion = "disclaimer_version"
        case generatedAt = "generated_at"
    }
}
