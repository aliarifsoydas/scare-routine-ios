import Foundation

// MARK: - Profil enum'ları

enum SkinType: String, Codable, CaseIterable, Identifiable {
    case oily, dry
    case combo = "combination"   // backend "combination" bekler
    case normal, sensitive
    var id: String { rawValue }
}

enum HairType: String, Codable, CaseIterable, Identifiable {
    case straight, wavy, curly, coily
    var id: String { rawValue }
}

enum AgeRange: String, Codable, CaseIterable, Identifiable {
    case under18 = "<18"
    case a18_24 = "18-24"
    case a25_34 = "25-34"
    case a35_44 = "35-44"
    case a45_54 = "45-54"
    case over55 = "55+"
    var id: String { rawValue }
}

// MARK: - Ürün enum'ları

enum ProductCategoryID: String, Codable, CaseIterable, Identifiable {
    case skincare, haircare, bodycare, makeup
    var id: String { rawValue }
}

enum ProductSource: String, Codable {
    case obf
    case serperExtracted = "serper_extracted"
    case userContributed = "user_contributed"
    case manual
}

enum AddedVia: String, Codable {
    case camera, barcode, manual, serper
}

// MARK: - Rutin & log enum'ları

enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday
    var id: Int { rawValue }
    var shortNameTR: String {
        switch self {
        case .monday: return L("weekday_short_mon")
        case .tuesday: return L("weekday_short_tue")
        case .wednesday: return L("weekday_short_wed")
        case .thursday: return L("weekday_short_thu")
        case .friday: return L("weekday_short_fri")
        case .saturday: return L("weekday_short_sat")
        case .sunday: return L("weekday_short_sun")
        }
    }
}

enum RoutineFrequency: String, Codable {
    case daily, weekly, biweekly, monthly
}

enum Mood: String, Codable, CaseIterable {
    case great = "😊", neutral = "😐", bad = "😔"
}

// MARK: - Cilt log enum'ları

enum SkinLogCategory: String, Codable, CaseIterable {
    case face, scalp, body
}

enum PhotoMode: String, Codable {
    case metricsOnly = "metrics_only"
    case photoKept = "photo_kept"
}

enum ImageQuality: String, Codable {
    case good, low, harsh
}

enum AIConfidence: String, Codable {
    case low, medium, high
}

// MARK: - Cycle enum'ları

enum CyclePhase: String, Codable, CaseIterable {
    case menstrual, follicular, ovulation, luteal
}

enum FlowIntensity: String, Codable, CaseIterable {
    case spotting, light, medium, heavy
}

enum CycleSource: String, Codable {
    case manual
    case healthkitSync = "healthkit_sync"
}

// MARK: - Consent enum'ları

enum ConsentType: String, Codable {
    case account
    case aiProcessing = "ai_processing"
    case selfieStorage = "selfie_storage"
    case cycleTracking = "cycle_tracking"
}

// MARK: - Analiz enum'ları

enum AnalysisScope: String, Codable {
    case product, ingredient, routine, selfie, compatibility
}
