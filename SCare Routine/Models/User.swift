import Foundation
import SwiftData

@Model
final class User {
    @Attribute(.unique) var id: String       // Apple sub claim
    var email: String?
    var displayName: String?
    var locale: String                       // "tr" | "en"
    var createdAt: Date
    var deletedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \UserProfile.user)
    var profile: UserProfile?

    @Relationship(deleteRule: .cascade, inverse: \UserConsent.user)
    var consents: [UserConsent] = []

    @Relationship(deleteRule: .cascade, inverse: \UserProduct.user)
    var products: [UserProduct] = []

    @Relationship(deleteRule: .cascade, inverse: \Routine.user)
    var routines: [Routine] = []

    @Relationship(deleteRule: .cascade, inverse: \RoutineLog.user)
    var routineLogs: [RoutineLog] = []

    @Relationship(deleteRule: .cascade, inverse: \SkinLog.user)
    var skinLogs: [SkinLog] = []

    @Relationship(deleteRule: .cascade, inverse: \CycleLog.user)
    var cycleLogs: [CycleLog] = []

    init(
        id: String,
        email: String? = nil,
        displayName: String? = nil,
        locale: String = "tr",
        createdAt: Date = .now
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.locale = locale
        self.createdAt = createdAt
    }
}

@Model
final class UserProfile {
    var user: User?
    var skinType: SkinType?
    var skinConcerns: [String] = []
    var skinSensitivity: [String] = []
    var hairType: HairType?
    var hairConcerns: [String] = []
    var bodyConcerns: [String] = []
    var makeupPref: [String] = []
    var ageRange: AgeRange?
    var pregnancy: Bool = false
    var defaultPhotoMode: PhotoMode = PhotoMode.metricsOnly
    var updatedAt: Date

    init(user: User? = nil, updatedAt: Date = .now) {
        self.user = user
        self.updatedAt = updatedAt
    }
}

@Model
final class UserConsent {
    @Attribute(.unique) var id: String
    var user: User?
    var consentType: ConsentType
    var granted: Bool
    var version: String
    var grantedAt: Date
    var revokedAt: Date?

    init(
        id: String = UUID().uuidString,
        consentType: ConsentType,
        granted: Bool,
        version: String,
        grantedAt: Date = .now
    ) {
        self.id = id
        self.consentType = consentType
        self.granted = granted
        self.version = version
        self.grantedAt = grantedAt
    }
}
