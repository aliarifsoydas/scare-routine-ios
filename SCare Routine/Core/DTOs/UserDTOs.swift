import Foundation

// MARK: - /v1/me response

/// `GET /v1/me` — kullanıcı + profil birleşik
struct MeResponse: Decodable {
    let user: AuthUser
    let profile: ProfileData?
}

struct ProfileData: Decodable, Hashable {
    let skinType: String?
    let skinConcerns: [String]?
    let skinSensitivity: [String: AnyCodable]?
    let hairType: String?
    let hairConcerns: [String]?
    let bodyConcerns: [String]?
    let makeupPref: [String: AnyCodable]?
    let ageRange: String?
    /// Backend SQLite 0/1 int olarak saklar — Bool olarak yorumla.
    let pregnancy: Bool?
    let defaultPhotoMode: String?

    let birthDate: String?            // "YYYY-MM-DD"
    let gender: String?               // "female" | "male" | "non_binary" | "prefer_not_to_say"
    let fitzpatrickType: Int?         // 1-6
    let lifestyle: LifestyleData?
    let country: String?              // ISO 3166-1 alpha-2

    /// Profile yeterince doluysa onboarding'i atlamak için
    var isComplete: Bool {
        return skinType != nil && birthDate != nil
    }

    /// Defensive decoder — backend bazı field'larda farklı type döndürebilir
    /// (örn. pregnancy 0/1 int olarak gelir, Bool? olarak yorumlanır).
    /// Her field individually try? ile decode edilir, başarısız olursa nil olur.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.skinType = try? c.decodeIfPresent(String.self, forKey: .skinType)
        self.skinConcerns = try? c.decodeIfPresent([String].self, forKey: .skinConcerns)
        self.skinSensitivity = try? c.decodeIfPresent([String: AnyCodable].self, forKey: .skinSensitivity)
        self.hairType = try? c.decodeIfPresent(String.self, forKey: .hairType)
        self.hairConcerns = try? c.decodeIfPresent([String].self, forKey: .hairConcerns)
        self.bodyConcerns = try? c.decodeIfPresent([String].self, forKey: .bodyConcerns)
        self.makeupPref = try? c.decodeIfPresent([String: AnyCodable].self, forKey: .makeupPref)
        self.ageRange = try? c.decodeIfPresent(String.self, forKey: .ageRange)

        // pregnancy: Bool veya 0/1 int olabilir — her ikisini de destekle
        if let b = try? c.decodeIfPresent(Bool.self, forKey: .pregnancy) {
            self.pregnancy = b
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .pregnancy) {
            self.pregnancy = (i != 0)
        } else {
            self.pregnancy = nil
        }

        self.defaultPhotoMode = try? c.decodeIfPresent(String.self, forKey: .defaultPhotoMode)
        self.birthDate = try? c.decodeIfPresent(String.self, forKey: .birthDate)
        self.gender = try? c.decodeIfPresent(String.self, forKey: .gender)
        self.fitzpatrickType = try? c.decodeIfPresent(Int.self, forKey: .fitzpatrickType)
        self.lifestyle = try? c.decodeIfPresent(LifestyleData.self, forKey: .lifestyle)
        self.country = try? c.decodeIfPresent(String.self, forKey: .country)
    }

    private enum CodingKeys: String, CodingKey {
        case skinType, skinConcerns, skinSensitivity
        case hairType, hairConcerns, bodyConcerns
        case makeupPref, ageRange, pregnancy
        case defaultPhotoMode, birthDate, gender
        case fitzpatrickType, lifestyle, country
    }
}

struct LifestyleData: Codable, Hashable {
    let smoking: String?              // "never" | "occasionally" | "daily"
    let alcoholFrequency: String?     // "never" | "rarely" | "weekly" | "daily"
    let sleepHoursAvg: Double?
    // waterGlassesPerDay removed — bilimsel kanıt zayıf, feature drop
}

/// JSON içindeki rastgele key/value'leri Swift'te taşımak için.
/// Backend `skin_sensitivity` ve `makeup_pref` alanlarını esnek bıraktığı için gerek.
/// `@unchecked Sendable` çünkü `Any?` Sendable değil ama JSON-decode edilen
/// primitif değerler (String/Int/Double/Bool/nested) güvenli kabul edilir.
struct AnyCodable: Codable, Hashable, @unchecked Sendable {
    let value: Any?

    init(_ value: Any?) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self.value = nil }
        else if let b = try? c.decode(Bool.self) { self.value = b }
        else if let i = try? c.decode(Int.self) { self.value = i }
        else if let d = try? c.decode(Double.self) { self.value = d }
        else if let s = try? c.decode(String.self) { self.value = s }
        else if let arr = try? c.decode([AnyCodable].self) { self.value = arr.map { $0.value } }
        else if let dict = try? c.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else { self.value = nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case nil: try c.encodeNil()
        case let b as Bool: try c.encode(b)
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let arr as [Any?]: try c.encode(arr.map { AnyCodable($0) })
        case let dict as [String: Any?]:
            try c.encode(dict.mapValues { AnyCodable($0) })
        default: try c.encodeNil()
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (nil, nil): return true
        case let (l as String, r as String): return l == r
        case let (l as Int, r as Int): return l == r
        case let (l as Double, r as Double): return l == r
        case let (l as Bool, r as Bool): return l == r
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        if let s = value as? String { hasher.combine(s) }
        else if let i = value as? Int { hasher.combine(i) }
        else if let d = value as? Double { hasher.combine(d) }
        else if let b = value as? Bool { hasher.combine(b) }
    }
}
