import Foundation

// MARK: - Recognize

/// `/v1/products/recognize` request body — en az bir alan zorunlu (barcode, ocr*, hint, veya photoUrl).
///
/// `ocrBlocks` Apple Vision'ın block-level çıktısıdır. Backend brand/name heuristic'i için
/// bunu tercih eder; `ocrText` legacy/birleştirilmiş satır.
struct ProductRecognizeRequest: Encodable {
    let barcode: String?
    let ocrText: String?
    let ocrBlocks: [String]?
    let brandHint: String?
    let nameHint: String?
    let photoUrl: String?
}

/// Backend cascade'in döndürdüğü sonuç.
///
/// Backend format: `{ product, ingredients[], source, confidence }`
/// — product D1 row'u (image_url, category_id, verified_at), ingredients ayrı array.
/// iOS bunu defensive olarak parse eder; tüm field'lar optional.
struct ProductRecognizeResponse: Decodable {
    let product: RecognizedProduct?
    let ingredients: [RecognizedIngredient]?
    let confidence: String?
    let source: String?

    /// Convenience: ingredients listesini sıralı INCI string'lerine çevir
    var inciList: [String] {
        (ingredients ?? [])
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { $0.inciName }
    }

    /// Backend henüz "suggestions" döndürmüyor — UI bunu condition'la kontrol ediyor
    var suggestions: [RecognizedProduct]? { nil }
}

struct RecognizedIngredient: Decodable, Hashable {
    let id: Int
    let inciName: String
    let orderIndex: Int
}

struct RecognizedProduct: Decodable, Hashable, Identifiable {
    let id: String
    let brand: String?
    let name: String?
    let categoryId: String?         // backend: category_id
    let subcategory: String?
    let imageUrl: String?
    let claims: [String]?
    let volumeMl: Double?
    let paoMonths: Int?
    /// Backend verified_at INTEGER veya null (unix seconds). Bool olarak yorumla.
    let verifiedAt: Int?
    let source: String?

    var verified: Bool { verifiedAt != nil }
    var category: String? { categoryId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.brand = try? c.decodeIfPresent(String.self, forKey: .brand)
        self.name = try? c.decodeIfPresent(String.self, forKey: .name)
        self.categoryId = try? c.decodeIfPresent(String.self, forKey: .categoryId)
        self.subcategory = try? c.decodeIfPresent(String.self, forKey: .subcategory)
        self.imageUrl = try? c.decodeIfPresent(String.self, forKey: .imageUrl)
        // Backend D1'de claims TEXT (JSON string) — parse et veya raw array
        if let arr = try? c.decodeIfPresent([String].self, forKey: .claims) {
            self.claims = arr
        } else if let raw = try? c.decodeIfPresent(String.self, forKey: .claims),
                  let data = raw.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode([String].self, from: data) {
            self.claims = parsed
        } else {
            self.claims = nil
        }
        self.volumeMl = try? c.decodeIfPresent(Double.self, forKey: .volumeMl)
        self.paoMonths = try? c.decodeIfPresent(Int.self, forKey: .paoMonths)
        self.verifiedAt = try? c.decodeIfPresent(Int.self, forKey: .verifiedAt)
        self.source = try? c.decodeIfPresent(String.self, forKey: .source)
    }

    private enum CodingKeys: String, CodingKey {
        case id, brand, name, categoryId, subcategory
        case imageUrl, claims, volumeMl, paoMonths
        case verifiedAt, source
    }
}

/// `GET /v1/products/by-barcode/:barcode` — barcode ile direkt ürün döner.
/// Backend cevap zarfını aynı RecognizedProduct şeklinde sarmalıyor.
struct ProductByBarcodeResponse: Decodable {
    let product: RecognizedProduct?
}

// MARK: - Upload sign

struct UploadSignRequest: Encodable {
    /// "product_photo" | "skin_photo" gibi
    let kind: String
    /// "image/jpeg" | "image/png" — backend MIME beyaz listesi var
    let contentType: String
    /// "jpg" | "jpeg" | "png" — opsiyonel hint
    let ext: String?
}

struct UploadSignResponse: Decodable {
    /// Presigned PUT URL — istemci buraya raw image PUT'lar
    let uploadUrl: String
    /// Public GET path (R2/CloudFront) — backend'e gönderilecek photo_url alanı
    let publicUrl: String
    /// Bucket key — debug için
    let key: String
    /// Presign son geçerlilik — nullable, secondsSince1970
    let expiresAt: Date?
}

// MARK: - Kullanıcı arşivi

struct UserProductCreateRequest: Encodable {
    /// Katalogdan eşleşmiş ürün ID'si — yoksa nil (manuel girişte)
    let productId: String?
    /// Kullanıcının ürüne taktığı takma ad ("Sabah serumu" gibi)
    let nickname: String?
    /// R2 public URL
    let photoUrl: String?
    /// Açılış tarihi — unix seconds
    let openedAt: Int?
    /// 1..5
    let rating: Int?
    /// Serbest metin notlar
    let notes: String?
    /// "scan" | "manual" | "search"
    let addedVia: String

    // Manuel ekleme için ek alanlar — backend product_id yoksa katalog kaydı oluşturur
    let manualBrand: String?
    let manualName: String?
    let manualCategory: String?
}

/// Backend'in arşiv POST cevabı + listele cevabı item'ı.
/// Backend D1 row'unu olduğu gibi yolladığı için 0/1 int + null'lara karşı defensive.
struct UserProductResponse: Decodable, Identifiable, Hashable {
    let id: String
    let productId: String?
    let brand: String?
    let name: String?
    let nickname: String?
    let photoUrl: String?
    let isFavorite: Bool
    let isArchived: Bool
    let addedVia: String?
    let createdAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.productId = try? c.decodeIfPresent(String.self, forKey: .productId)
        self.brand = try? c.decodeIfPresent(String.self, forKey: .brand)
        self.name = try? c.decodeIfPresent(String.self, forKey: .name)
        self.nickname = try? c.decodeIfPresent(String.self, forKey: .nickname)
        self.photoUrl = try? c.decodeIfPresent(String.self, forKey: .photoUrl)
        // SQLite 0/1 int veya Bool olabilir
        self.isFavorite = Self.decodeBoolish(c, forKey: .isFavorite) ?? false
        self.isArchived = Self.decodeBoolish(c, forKey: .isArchived) ?? false
        self.addedVia = try? c.decodeIfPresent(String.self, forKey: .addedVia)
        self.createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
    }

    private static func decodeBoolish(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Bool? {
        if let b = try? c.decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, productId, brand, name, nickname, photoUrl
        case isFavorite, isArchived, addedVia, createdAt
    }
}

/// `GET /v1/me/products` → backend `{ items: [...] }` ile sarılı döner.
struct ListUserProductsResponse: Decodable {
    let items: [UserProductResponse]
    var products: [UserProductResponse] { items } // legacy alias
}

/// `POST /v1/me/products` → backend `{ item: {...} }` ile sarılı döner.
struct CreateUserProductResponse: Decodable {
    let item: UserProductResponse
}

/// `PATCH /v1/me/products/:id` body — tüm alanlar opsiyonel,
/// sadece değiştirilmek istenen field'lar gönderilir (partial update).
///
/// Field encoding'i `APIClient` üzerindeki snake_case strategy ile sağlanır
/// (örn. `isFavorite` → `is_favorite`).
struct UserProductUpdateRequest: Encodable {
    var nickname: String?
    var rating: Int?
    var notes: String?
    var isFavorite: Bool?
    var isArchived: Bool?
    /// Unix seconds — ürünün açıldığı tarih (PAO için)
    var openedAt: Int?
    /// Unix seconds — ürünün bittiği tarih
    var finishedAt: Int?
}

/// `GET /v1/products/:product_id` cevap zarfı.
/// Backend tek ürünü `{ product, ingredients[] }` formatında döndürür —
/// `ProductRecognizeResponse` ile aynı şekil ama opsiyonel meta alanları yok.
struct ProductDetailResponse: Decodable {
    let product: RecognizedProduct?
    let ingredients: [RecognizedIngredient]?
}
