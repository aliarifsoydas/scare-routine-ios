import Foundation

// MARK: - Quick Evaluate (pre-check + LLM verdict)

/// `/v1/products/quick-evaluate` cevabı.
///
/// Backend mevcut bir katalog ürünü için kullanıcının cilt tipi/concern'lerine göre
/// hızlı bir uygunluk skoru (`fitScore`) + verdict döndürür. `via` alanı kararın
/// pre-check (heuristic) mi yoksa LLM'den mi geldiğini gösterir; arşivde aynı
/// ürün varsa `duplicate` verdict + duplicate kayıt ID'si döner.
///
/// JSON snake_case alanları (`category_id`, `photo_url`, `fit_score`,
/// `duplicate_product_id`, `duplicate_product_name`) APIClient'ın
/// `convertFromSnakeCase` stratejisi ile otomatik camelCase'e map edilir;
/// burada açık `CodingKeys` tanımlamıyoruz.
struct QuickEvaluateResponse: Codable, Sendable {
    struct Product: Codable, Sendable {
        let id: String
        let name: String
        let brand: String?
        let categoryId: String?
        let photoUrl: String?
    }

    let product: Product
    /// 0-100 arası uygunluk skoru.
    let fitScore: Int
    let verdict: Verdict
    let pros: [String]
    let cons: [String]
    /// Eğer kullanıcının arşivinde aynı ürün varsa onun user_product ID'si.
    let duplicateProductId: String?
    let duplicateProductName: String?
    let reasons: [String]
    let via: Via

    enum Verdict: String, Codable, Sendable {
        case greatFit = "great_fit"
        case goodFit = "good_fit"
        case neutral
        case skip
        case duplicate
    }

    enum Via: String, Codable, Sendable {
        case preCheck = "pre_check"
        case llm
    }
}

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
    /// R2 object key (örn. `product_photo/<uid>/<file>.jpg`). Front foto.
    let photoKey: String?
    /// Arka etiket foto'su (opsiyonel). Verildiğinde Vision multipass INCI'yi
    /// arkadan, brand+name'i ön taraftan okur.
    let photoKeyBack: String?
    /// BG-removed image R2 key — fine-tune training data için saklanır.
    let photoKeyClean: String?
    /// Arka etiketten yapılan OCR block'ları (iOS Vision çıktısı).
    let ocrBlocksBack: [String]?
    /// Apple VNGenerateImageFeaturePrintRequest (revision 2 → 768 float).
    /// Backend Vectorize cosine ANN ile DB-first visual match — OCR/Lens'ten önce.
    let featurePrint: [Float]?
    /// Background-removed FeaturePrint — kullanıcı el-tutup çekti, white-bg compose ile
    /// katalog stüdyo fotosuna yakınlık çok artar. Paralel Vectorize query, daha yüksek score.
    let featurePrintClean: [Float]?
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
    /// Runtime path: bu çağrıda hangi yoldan tanındı?
    let via: String?
    /// Phase 3A: tarama log ID. Confirm/correct sırasında bu ID kullanılır.
    let attemptId: String?
    /// Sibling adaylar — winner kesin değilse user'a "şunlardan biri mi?" diye sorulur.
    let suggestions: [RecognizedProduct]?

    /// Review özeti — kullanıcının skin_type'ına göre filtrelenmiş, fallback'lı.
    let reviewSummary: ReviewSummary?
    /// Bu üründeki içeriklerden, kullanıcının cilt tipinde uyarı gerektirenler.
    let warnings: [IngredientWarning]?

    init(
        product: RecognizedProduct? = nil,
        ingredients: [RecognizedIngredient]? = nil,
        confidence: String? = nil,
        source: String? = nil,
        via: String? = nil,
        attemptId: String? = nil,
        suggestions: [RecognizedProduct]? = nil,
        reviewSummary: ReviewSummary? = nil,
        warnings: [IngredientWarning]? = nil
    ) {
        self.product = product
        self.ingredients = ingredients
        self.confidence = confidence
        self.source = source
        self.via = via
        self.attemptId = attemptId
        self.suggestions = suggestions
        self.reviewSummary = reviewSummary
        self.warnings = warnings
    }

    var inciList: [String] {
        (ingredients ?? [])
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { $0.inciName }
    }
}

struct RecognizedIngredient: Decodable, Hashable {
    let id: Int
    let inciName: String
    let orderIndex: Int
}

struct KeyActive: Decodable, Hashable {
    let name: String
    let percent: Double?
    let role: String?
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

    // MARK: - Structured product facts (backend 0004 migration)
    let keyActives: [KeyActive]?
    let allergensFlags: [String]?
    let suitableSkinTypes: [String]?
    let unsuitableSkinTypes: [String]?
    let concernsAddressed: [String]?
    let ph: Double?
    /// 1 = safe, 0 = unsafe, nil = unknown
    let pregnancySafe: Bool?
    let vegan: Bool?
    let crueltyFree: Bool?
    let fragranceFree: Bool?
    let sulfateFree: Bool?
    let siliconeFree: Bool?
    let alcoholFree: Bool?

    // MARK: - Back-label / usage fields (migration 0006)
    /// "Nasıl kullanılır" / "Kullanım" bölümü — ürün etiketinden veya marka resmi sayfasından
    let usageDirections: String?
    /// "Uyarılar" / "Warnings" — patch test, göze kaçma, hassas cilt uyarısı vb.
    let warnings: String?
    /// "Saklama" / "Storage" — sıcaklık, güneş ışığı talimatı
    let storageInstructions: String?
    /// Etikette belirtilen hedef ("Erkek", "Bebek", "Kids", "Hassas")
    let targetAudience: String?
    /// Üretici / distribütör adı (KKM zorunluluğu)
    let manufacturer: String?

    // MARK: - Formula clustering + crowdsource verification (migration 0007)
    /// INCI listesinin canonical SHA-256 hash'i
    let inciHash: String?
    /// Aynı formülün versiyonları arasındaki grouping ID
    let formulaClusterId: String?
    /// Cluster içindeki version (1, 2, 3...)
    let formulaVersion: Int?
    /// 'TR' | 'EU' | 'US' | 'global'
    let region: String?
    /// Bu formülü kaç tarama doğruladı (crowdsource)
    let verifiedCount: Int?
    /// Unix seconds — en son scan/onay
    let lastVerifiedAt: Int?
    /// INCI listesindeki maddelerden kaçı CosIng exact match
    let inciCleanCount: Int?
    /// Levenshtein ≤ 2 ile düzeltildi (OCR typo)
    let inciTypoCount: Int?
    /// CosIng'de hiç eşleşme yok
    let inciInvalidCount: Int?

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
        self.claims = Self.decodeJsonStringArray(c, key: .claims)
        self.volumeMl = try? c.decodeIfPresent(Double.self, forKey: .volumeMl)
        self.paoMonths = try? c.decodeIfPresent(Int.self, forKey: .paoMonths)
        self.verifiedAt = try? c.decodeIfPresent(Int.self, forKey: .verifiedAt)
        self.source = try? c.decodeIfPresent(String.self, forKey: .source)

        // Structured facts — backend TEXT (JSON string) veya array döndürebilir.
        if let arr = try? c.decodeIfPresent([KeyActive].self, forKey: .keyActives) {
            self.keyActives = arr
        } else if let raw = try? c.decodeIfPresent(String.self, forKey: .keyActives),
                  let data = raw.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode([KeyActive].self, from: data) {
            self.keyActives = parsed
        } else {
            self.keyActives = nil
        }
        self.allergensFlags = Self.decodeJsonStringArray(c, key: .allergensFlags)
        self.suitableSkinTypes = Self.decodeJsonStringArray(c, key: .suitableSkinTypes)
        self.unsuitableSkinTypes = Self.decodeJsonStringArray(c, key: .unsuitableSkinTypes)
        self.concernsAddressed = Self.decodeJsonStringArray(c, key: .concernsAddressed)
        self.ph = try? c.decodeIfPresent(Double.self, forKey: .ph)
        self.pregnancySafe = Self.decodeBoolish(c, forKey: .pregnancySafe)
        self.vegan = Self.decodeBoolish(c, forKey: .vegan)
        self.crueltyFree = Self.decodeBoolish(c, forKey: .crueltyFree)
        self.fragranceFree = Self.decodeBoolish(c, forKey: .fragranceFree)
        self.sulfateFree = Self.decodeBoolish(c, forKey: .sulfateFree)
        self.siliconeFree = Self.decodeBoolish(c, forKey: .siliconeFree)
        self.alcoholFree = Self.decodeBoolish(c, forKey: .alcoholFree)
        self.usageDirections = try? c.decodeIfPresent(String.self, forKey: .usageDirections)
        self.warnings = try? c.decodeIfPresent(String.self, forKey: .warnings)
        self.storageInstructions = try? c.decodeIfPresent(String.self, forKey: .storageInstructions)
        self.targetAudience = try? c.decodeIfPresent(String.self, forKey: .targetAudience)
        self.manufacturer = try? c.decodeIfPresent(String.self, forKey: .manufacturer)
        self.inciHash = try? c.decodeIfPresent(String.self, forKey: .inciHash)
        self.formulaClusterId = try? c.decodeIfPresent(String.self, forKey: .formulaClusterId)
        self.formulaVersion = try? c.decodeIfPresent(Int.self, forKey: .formulaVersion)
        self.region = try? c.decodeIfPresent(String.self, forKey: .region)
        self.verifiedCount = try? c.decodeIfPresent(Int.self, forKey: .verifiedCount)
        self.lastVerifiedAt = try? c.decodeIfPresent(Int.self, forKey: .lastVerifiedAt)
        self.inciCleanCount = try? c.decodeIfPresent(Int.self, forKey: .inciCleanCount)
        self.inciTypoCount = try? c.decodeIfPresent(Int.self, forKey: .inciTypoCount)
        self.inciInvalidCount = try? c.decodeIfPresent(Int.self, forKey: .inciInvalidCount)
    }

    private static func decodeBoolish(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Bool? {
        if let b = try? c.decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        return nil
    }

    private static func decodeJsonStringArray(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> [String]? {
        if let arr = try? c.decodeIfPresent([String].self, forKey: key) { return arr }
        if let raw = try? c.decodeIfPresent(String.self, forKey: key),
           let data = raw.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String].self, from: data) {
            return parsed
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, brand, name, categoryId, subcategory
        case imageUrl, claims, volumeMl, paoMonths
        case verifiedAt, source
        case keyActives, allergensFlags
        case suitableSkinTypes, unsuitableSkinTypes
        case concernsAddressed, ph
        case pregnancySafe, vegan, crueltyFree
        case fragranceFree, sulfateFree, siliconeFree, alcoholFree
        case usageDirections, warnings, storageInstructions, targetAudience, manufacturer
        case inciHash, formulaClusterId, formulaVersion, region
        case verifiedCount, lastVerifiedAt
        case inciCleanCount, inciTypoCount, inciInvalidCount
    }
}

/// `GET /v1/products/by-barcode/:barcode` — barcode ile direkt ürün + INCI listesi döner.
struct ProductByBarcodeResponse: Decodable {
    let product: RecognizedProduct?
    let ingredients: [RecognizedIngredient]?
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

// MARK: - Review summary + ingredient warnings (recognize response'a eklenir)

/// Bir ürünün review özeti — kullanıcının cilt tipine filtrelenmiş.
/// `source`: "direct" (bu ürünün kendi yorumları), "cluster" (aynı formül kümesi),
/// "ingredient" (sadece içerik bazlı türetildi), "none" (yorum yok).
struct ReviewSummary: Decodable, Hashable {
    let source: String
    let count: Int
    let avgRating: Double?
    let posCount: Int
    let negCount: Int
    let topConcerns: [ReviewTopItem]
    let topPros: [ReviewTopItem]
}

struct ReviewTopItem: Decodable, Hashable {
    let key: String
    let count: Int
}

/// Bu üründeki bir içerik için, kullanıcının cilt tipinde toplanan uyarı sinyali.
struct IngredientWarning: Decodable, Hashable, Identifiable {
    let ingredientName: String
    let concern: String
    /// Bu içeriği içeren tüm yorumların yüzde kaçı bu concern'i belirtmiş (0-1).
    let ratio: Double
    /// Bu sinyali destekleyen toplam yorum sayısı.
    let count: Int
    /// 0 (ortalama) — 3 (ciddi). Negative review ratings'den türetilir.
    let avgSeverity: Double

    var id: String { "\(ingredientName)|\(concern)" }
}
