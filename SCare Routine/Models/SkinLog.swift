import Foundation
import SwiftData

@Model
final class SkinLog {
    @Attribute(.unique) var id: String
    var user: User?
    var logDate: String                      // "YYYY-MM-DD"
    var category: SkinLogCategory

    // Foto modu — default metrics_only (gözlemler kalır, foto silinir)
    var selfieURL: String?                   // R2 key (yalnızca photoMode == .photoKept)
    var photoMode: PhotoMode = PhotoMode.metricsOnly

    // AI gözlemleri — sayı VERMEZ, sadece niteleyici tarif
    var aiObservations: AIObservation?
    var aiImageQuality: ImageQuality?
    var aiConfidence: AIConfidence?

    // Kullanıcının öz-değerlendirmesi (1-5) — trend grafikleri buradan çizilir
    var selfHydration: Int?
    var selfRedness: Int?
    var selfOiliness: Int?
    var selfBreakouts: Int?
    var selfOverall: Int?

    var subjectiveNotes: String?
    var symptoms: [String] = []
    var sleepHours: Double?
    var stressLevel: Int?

    // Cycle korelasyon (auto-derived)
    var cyclePhase: CyclePhase?
    var cycleDay: Int?

    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        logDate: String,
        category: SkinLogCategory = .face,
        photoMode: PhotoMode = .metricsOnly,
        createdAt: Date = .now
    ) {
        self.id = id
        self.logDate = logDate
        self.category = category
        self.photoMode = photoMode
        self.createdAt = createdAt
    }
}
