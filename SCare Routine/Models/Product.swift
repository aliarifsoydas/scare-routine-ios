import Foundation
import SwiftData

@Model
final class ProductCategory {
    @Attribute(.unique) var id: String       // "skincare" | "haircare" | "bodycare" | "makeup"
    var nameTR: String
    var nameEN: String
    var icon: String?

    init(id: String, nameTR: String, nameEN: String, icon: String? = nil) {
        self.id = id
        self.nameTR = nameTR
        self.nameEN = nameEN
        self.icon = icon
    }
}

@Model
final class Product {
    @Attribute(.unique) var id: String
    var barcode: String?
    var brand: String
    var name: String
    var nameNormalized: String
    var categoryID: String                   // FK to ProductCategory.id
    var subcategory: String?
    var productDescription: String?          // "description" SQL reserve
    var claims: [String] = []
    var volumeML: Double?
    var paoMonths: Int?
    var imageURL: String?
    var source: ProductSource
    var sourceURL: String?
    var verifiedAt: Date?
    var verifiedBy: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ProductIngredient.product)
    var productIngredients: [ProductIngredient] = []

    init(
        id: String,
        brand: String,
        name: String,
        categoryID: String,
        source: ProductSource,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.brand = brand
        self.name = name
        self.nameNormalized = Self.normalize(name)
        self.categoryID = categoryID
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@Model
final class Ingredient {
    @Attribute(.unique) var id: String
    @Attribute(.unique) var inciName: String
    var inciNormalized: String
    var casNumber: String?
    var einecs: String?
    var cosingRef: String?
    var functionTags: [String] = []
    var restrictions: [String] = []
    var isAllergen: Bool = false
    var pregnancySafe: Bool?                 // nil = bilinmiyor
    var comedogenic: Int?                    // 0-5
    var descriptionTR: String?
    var descriptionEN: String?
    var source: String                       // "cosing" | "ai_generated"

    @Relationship(inverse: \ProductIngredient.ingredient)
    var productIngredients: [ProductIngredient] = []

    init(
        id: String,
        inciName: String,
        source: String
    ) {
        self.id = id
        self.inciName = inciName
        self.inciNormalized = inciName.lowercased()
        self.source = source
    }
}

@Model
final class ProductIngredient {
    var product: Product?
    var ingredient: Ingredient?
    var orderIndex: Int

    init(product: Product? = nil, ingredient: Ingredient? = nil, orderIndex: Int) {
        self.product = product
        self.ingredient = ingredient
        self.orderIndex = orderIndex
    }
}

@Model
final class UserProduct {
    @Attribute(.unique) var id: String
    var user: User?
    var productID: String                    // FK to Product.id (global katalog)
    var nickname: String?
    var photoURL: String?                    // R2 key
    var openedAt: Date?
    var finishedAt: Date?
    var rating: Int?                         // 1-5
    var notes: String?
    var addedVia: AddedVia
    var isFavorite: Bool = false
    var isArchived: Bool = false
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \RoutineStep.userProduct)
    var routineSteps: [RoutineStep] = []

    init(
        id: String = UUID().uuidString,
        productID: String,
        addedVia: AddedVia,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.productID = productID
        self.addedVia = addedVia
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
