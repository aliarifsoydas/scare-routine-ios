import Foundation

// MARK: - Profile update

/// `PATCH /v1/me/profile` body
///
/// Backend snake_case bekliyor; `JSONEncoder.keyEncodingStrategy = .convertToSnakeCase`
/// camelCase -> snake_case dönüştürdüğü için Swift tarafında camelCase tutuyoruz.
/// Tüm alanlar opsiyonel — sadece doldurulanlar payload'a girer.
struct ProfileUpdateRequest: Encodable {
    var displayName: String?            // users.display_name update
    var skinType: String?
    var skinConcerns: [String]?
    var hairType: String?
    var hairConcerns: [String]?
    var bodyConcerns: [String]?
    var makeupPref: [String: Bool]?
    var birthDate: String?              // ISO date "YYYY-MM-DD"
    var gender: String?                 // "female" | "male" | "non_binary" | "prefer_not_to_say"
    var fitzpatrickType: Int?           // 1-6
    var lifestyle: LifestylePayload?
    var country: String?                // ISO 3166-1 alpha-2
    var pregnancy: Bool?
    var defaultPhotoMode: String?       // "metrics_only" | "photo_kept"
    var locale: String?                 // "tr" | "en"
    var categories: [String]?           // ["skincare","haircare",...]

    /// nil olan alanları payload dışında bırak — encoder'a hangi key'lerin gideceğini açıkça söyle
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(skinType, forKey: .skinType)
        try c.encodeIfPresent(skinConcerns, forKey: .skinConcerns)
        try c.encodeIfPresent(hairType, forKey: .hairType)
        try c.encodeIfPresent(hairConcerns, forKey: .hairConcerns)
        try c.encodeIfPresent(bodyConcerns, forKey: .bodyConcerns)
        try c.encodeIfPresent(makeupPref, forKey: .makeupPref)
        try c.encodeIfPresent(birthDate, forKey: .birthDate)
        try c.encodeIfPresent(gender, forKey: .gender)
        try c.encodeIfPresent(fitzpatrickType, forKey: .fitzpatrickType)
        try c.encodeIfPresent(lifestyle, forKey: .lifestyle)
        try c.encodeIfPresent(country, forKey: .country)
        try c.encodeIfPresent(pregnancy, forKey: .pregnancy)
        try c.encodeIfPresent(defaultPhotoMode, forKey: .defaultPhotoMode)
        try c.encodeIfPresent(locale, forKey: .locale)
        try c.encodeIfPresent(categories, forKey: .categories)
    }

    private enum CodingKeys: String, CodingKey {
        case displayName
        case skinType, skinConcerns
        case hairType, hairConcerns
        case bodyConcerns, makeupPref
        case birthDate, gender, fitzpatrickType
        case lifestyle, country, pregnancy
        case defaultPhotoMode, locale, categories
    }
}

struct LifestylePayload: Encodable {
    var smoking: String?              // "never" | "occasionally" | "daily"
    var alcoholFrequency: String?     // "never" | "rarely" | "weekly" | "daily"
    var sleepHoursAvg: Double?        // 4-12
    // waterGlassesPerDay removed — bilimsel kanıt zayıf, feature drop
}

// MARK: - Consent

/// `POST /v1/me/consent` body
struct ConsentRequest: Encodable {
    let consentType: String         // ConsentType.rawValue
    let granted: Bool
    let version: String             // örn. "2026-05-17"
}
