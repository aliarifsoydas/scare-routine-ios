import Foundation
import SwiftData

/// Tüm SwiftData model'lerinin merkezi schema tanımı.
/// CloudKit kapalı — Cloudflare backend source of truth, SwiftData sadece local cache.
enum SCareSchema {
    static let models: [any PersistentModel.Type] = [
        // User
        User.self,
        UserProfile.self,
        UserConsent.self,

        // Product catalog
        ProductCategory.self,
        Product.self,
        Ingredient.self,
        ProductIngredient.self,

        // User archive
        UserProduct.self,

        // Routines
        Routine.self,
        RoutineStep.self,
        RoutineLog.self,
        WeeklySummary.self,

        // Skin tracking
        SkinLog.self,
        CycleLog.self,

        // AI cache
        Analysis.self
    ]

    @MainActor
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none      // Cloudflare = source of truth
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
