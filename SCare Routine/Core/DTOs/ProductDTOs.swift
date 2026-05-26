import Foundation
import CoreGraphics

// MARK: - Quick Evaluate (pre-check + LLM verdict)

/// `/v1/products/quick-evaluate` cevabı.
///
/// Backend mevcut bir katalog ürünü için kullanıcının cilt tipi/concern'lerine göre
/// hızlı bir uygunluk skoru (`fitScore`) + verdict döndürür. `via` alanı kararın
/// pre-check (heuristic) mi yoksa LLM'den mi geldiğini gösterir; arşivde aynı
/// ürün varsa `duplicate` verdict + duplicate kayıt ID'si döner.
///
/// JSON snake_case alanları (`category_id`, `photo_url`, `fit_score`,
/// `duplicate_product_id`, `duplicate_product_name`, `conflicts_with`)
/// APIClient'ın `convertFromSnakeCase` stratejisi ile otomatik camelCase'e
/// map edilir; burada açık `CodingKeys` tanımlamıyoruz.
struct QuickEvaluateResponse: Decodable, Sendable {
    struct Product: Decodable, Sendable {
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
    /// Kullanıcının arşivinde bulunan, bu yeni ürünle çakışan ürünler.
    /// Eski backend versiyonu bu field'ı dönmezse boş array olarak decode edilir
    /// (defensive — flow bozulmaz).
    let conflictsWith: [ConflictItem]
    /// Cache hint — backend cevabı önbellekten mi geldi, hangi kaynaktan?
    /// Eski versiyon dönmezse nil; iOS bu hint'i sadece debug için kullanır.
    let meta: Meta?

    enum Verdict: String, Decodable, Sendable {
        case greatFit = "great_fit"
        case goodFit = "good_fit"
        case neutral
        case skip
        case duplicate
    }

    enum Via: String, Decodable, Sendable {
        case preCheck = "pre_check"
        case llm
    }

    /// Arşivdeki bir ürünle çakışma sinyali. Backend `severity` ile şiddetini
    /// belirtir — high (mutlaka söyle) / medium (heads-up) / low (FYI).
    struct ConflictItem: Decodable, Sendable, Identifiable, Hashable {
        var id: String { userProductId }
        let userProductId: String
        let userProductName: String
        let reason: String
        let severity: Severity

        enum Severity: String, Decodable, Sendable {
            case high, medium, low
        }
    }

    /// Backend `_meta` zarfı (varsa). `cached=true` + `source` (`idempotency_60s`,
    /// `fresh`, `speculative_hit`) — debug logging için.
    struct Meta: Decodable, Sendable {
        let cached: Bool?
        let source: String?
    }

    // MARK: - Defensive decoding
    //
    // Eski backend `conflicts_with` / `_meta` dönmezse decode patlamasın diye
    // explicit init veriyoruz. `convertFromSnakeCase` zaten field isimlerini
    // map ediyor; burada sadece "yoksa default" davranışını ekliyoruz.

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.product = try c.decode(Product.self, forKey: .product)
        self.fitScore = try c.decode(Int.self, forKey: .fitScore)
        self.verdict = try c.decode(Verdict.self, forKey: .verdict)
        self.pros = (try? c.decodeIfPresent([String].self, forKey: .pros)) ?? []
        self.cons = (try? c.decodeIfPresent([String].self, forKey: .cons)) ?? []
        self.duplicateProductId = try? c.decodeIfPresent(String.self, forKey: .duplicateProductId)
        self.duplicateProductName = try? c.decodeIfPresent(String.self, forKey: .duplicateProductName)
        self.reasons = (try? c.decodeIfPresent([String].self, forKey: .reasons)) ?? []
        self.via = (try? c.decodeIfPresent(Via.self, forKey: .via)) ?? .llm
        self.conflictsWith = (try? c.decodeIfPresent([ConflictItem].self, forKey: .conflictsWith)) ?? []
        // `_meta` özel durum: `.convertFromSnakeCase` leading underscore'u
        // koruyor — `meta` key'i ile bulunamaz. Önce `meta`, sonra `_meta` dene.
        // Bu sayede backend `meta` veya `_meta` ile gönderse de çalışır.
        if let m = try? c.decodeIfPresent(Meta.self, forKey: .meta) {
            self.meta = m
        } else if let m = try? c.decodeIfPresent(Meta.self, forKey: .underscoreMeta) {
            self.meta = m
        } else {
            self.meta = nil
        }
    }

    /// Memberwise initializer — preview/test'lerde ve `QuickScanResultPanel`
    /// fallback'lerinde elle örnek üretmek için gerekli. Synthesized init
    /// custom `init(from:)` eklenince kayboluyor.
    init(
        product: Product,
        fitScore: Int,
        verdict: Verdict,
        pros: [String],
        cons: [String],
        duplicateProductId: String?,
        duplicateProductName: String?,
        reasons: [String],
        via: Via,
        conflictsWith: [ConflictItem] = [],
        meta: Meta? = nil
    ) {
        self.product = product
        self.fitScore = fitScore
        self.verdict = verdict
        self.pros = pros
        self.cons = cons
        self.duplicateProductId = duplicateProductId
        self.duplicateProductName = duplicateProductName
        self.reasons = reasons
        self.via = via
        self.conflictsWith = conflictsWith
        self.meta = meta
    }

    private enum CodingKeys: String, CodingKey {
        case product, fitScore, verdict, pros, cons
        case duplicateProductId, duplicateProductName
        case reasons, via, conflictsWith
        // Hem `meta` hem de `_meta` (leading underscore convertFromSnakeCase
        // tarafından korunur) — backend hangisini yollarsa onunla decode et.
        case meta
        case underscoreMeta = "_meta"
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
    /// Capture anı Apple Vision debug datası (saliency + classification + stability).
    /// Fine-tune için backend'de saklanır; recognition'ı etkilemez.
    let captureDebug: CaptureDebugPayload?
}

/// Capture debug metadata — backend `capture_debug` JSON. APIClient encoder
/// convertToSnakeCase ile alan adları snake_case'e döner (salientBox → salient_box).
struct CaptureDebugPayload: Encodable {
    /// Vision normalized bounding box [x, y, w, h] (bottom-left origin) veya nil.
    let salientBox: [Double]?
    let classifications: [Classification]
    let instability: Double
    let stable: Bool

    struct Classification: Encodable {
        let id: String
        let confidence: Double
    }

    /// Camera controller'ın AutoCaptureDebug struct'ından dönüştürür.
    init(from debug: AutoCaptureDebug) {
        if let b = debug.salientBox {
            salientBox = [Double(b.minX), Double(b.minY), Double(b.width), Double(b.height)]
        } else {
            salientBox = nil
        }
        classifications = debug.classifications.map {
            Classification(id: $0.id, confidence: Double($0.confidence))
        }
        instability = Double(debug.instability)
        stable = debug.stable
    }
}

/// Backend ürün tanıma cevabı — tüm tanıma endpoint'lerinin (`recognize`,
/// `by-barcode`, `search?top_match=true`) ortak shape'i.
///
/// Backend format: `{ product, ingredients[], source, confidence, via,
/// attempt_id, suggestions[], verification, review_summary, warnings[], _meta }`
///
/// iOS bunu defensive olarak parse eder; spec'teki "non-optional" alanlar bile
/// (`product`, `confidence`, `source`, `via`) iOS tarafında **optional** tutulur
/// çünkü hata/edge-case akışlarında view layer manuel olarak `product=nil` ile
/// `ProductRecognizeResponse(...)` literal'ı üretebiliyor. Backward compat için.
struct ProductIdentifyResponse: Decodable, Sendable {
    let product: RecognizedProduct?
    let ingredients: [RecognizedIngredient]?
    /// "low" | "medium" | "high"  (geçersiz değer → "low" default)
    let confidence: String?
    /// "barcode_explicit" | "barcode_ocr_parsed" | "recognize_full" |
    /// "search_top_hit" | "manual_added"
    let source: String?
    /// Runtime path: bu çağrıda hangi yoldan tanındı?
    let via: String?
    /// Phase 3A: tarama log ID. Confirm/correct sırasında bu ID kullanılır.
    let attemptId: String?
    /// Sibling adaylar — winner kesin değilse user'a "şunlardan biri mi?" diye sorulur.
    let suggestions: [RecognizedProduct]?
    /// LLM verification info (cross-check pass — ürün gerçekten match mi?)
    let verification: VerificationInfo?
    /// Review özeti — kullanıcının skin_type'ına göre filtrelenmiş, fallback'lı.
    let reviewSummary: ReviewSummary?
    /// Bu üründeki içeriklerden, kullanıcının cilt tipinde uyarı gerektirenler.
    let warnings: [IngredientWarning]?
    /// Cache hint + debug source — backend `_meta` zarfı.
    let meta: Meta?

    /// LLM cross-check verdict — backend ikinci geçişte ürünü doğrular.
    struct VerificationInfo: Decodable, Sendable {
        let performed: Bool
        /// "yes" | "no" | "uncertain" — geçersiz değer veya boş → nil
        let match: String?
        let reason: String?
        let latencyMs: Int?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.performed = (try? c.decodeIfPresent(Bool.self, forKey: .performed)) ?? false
            // Sadece beyaz listedeki değerleri kabul et — backend tipo'su client'ı kırmasın.
            let rawMatch = try? c.decodeIfPresent(String.self, forKey: .match)
            if let m = rawMatch, ["yes", "no", "uncertain"].contains(m.lowercased()) {
                self.match = m.lowercased()
            } else {
                self.match = nil
            }
            self.reason = try? c.decodeIfPresent(String.self, forKey: .reason)
            self.latencyMs = try? c.decodeIfPresent(Int.self, forKey: .latencyMs)
        }

        init(performed: Bool, match: String?, reason: String?, latencyMs: Int?) {
            self.performed = performed
            self.match = match
            self.reason = reason
            self.latencyMs = latencyMs
        }

        private enum CodingKeys: String, CodingKey {
            case performed, match, reason, latencyMs
        }
    }

    /// Backend `_meta` zarfı — cache durumu + kaynak.
    struct Meta: Decodable, Sendable {
        let cached: Bool?
        let source: String?
    }

    init(
        product: RecognizedProduct? = nil,
        ingredients: [RecognizedIngredient]? = nil,
        confidence: String? = nil,
        source: String? = nil,
        via: String? = nil,
        attemptId: String? = nil,
        suggestions: [RecognizedProduct]? = nil,
        verification: VerificationInfo? = nil,
        reviewSummary: ReviewSummary? = nil,
        warnings: [IngredientWarning]? = nil,
        meta: Meta? = nil
    ) {
        self.product = product
        self.ingredients = ingredients
        self.confidence = confidence
        self.source = source
        self.via = via
        self.attemptId = attemptId
        self.suggestions = suggestions
        self.verification = verification
        self.reviewSummary = reviewSummary
        self.warnings = warnings
        self.meta = meta
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.product = try? c.decodeIfPresent(RecognizedProduct.self, forKey: .product)
        self.ingredients = try? c.decodeIfPresent([RecognizedIngredient].self, forKey: .ingredients)

        // confidence: "low"/"medium"/"high" dışında → "low" default
        let rawConf = try? c.decodeIfPresent(String.self, forKey: .confidence)
        if let r = rawConf {
            let low = r.lowercased()
            self.confidence = (["low", "medium", "high"].contains(low)) ? low : "low"
        } else {
            self.confidence = nil
        }

        self.source = try? c.decodeIfPresent(String.self, forKey: .source)
        self.via = try? c.decodeIfPresent(String.self, forKey: .via)
        self.attemptId = try? c.decodeIfPresent(String.self, forKey: .attemptId)
        self.suggestions = try? c.decodeIfPresent([RecognizedProduct].self, forKey: .suggestions)
        self.verification = try? c.decodeIfPresent(VerificationInfo.self, forKey: .verification)
        self.reviewSummary = try? c.decodeIfPresent(ReviewSummary.self, forKey: .reviewSummary)
        self.warnings = try? c.decodeIfPresent([IngredientWarning].self, forKey: .warnings)

        // `_meta` özel durum — `convertFromSnakeCase` leading underscore'u korur.
        if let m = try? c.decodeIfPresent(Meta.self, forKey: .meta) {
            self.meta = m
        } else if let m = try? c.decodeIfPresent(Meta.self, forKey: .underscoreMeta) {
            self.meta = m
        } else {
            self.meta = nil
        }
    }

    var inciList: [String] {
        (ingredients ?? [])
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { $0.inciName }
    }

    private enum CodingKeys: String, CodingKey {
        case product, ingredients, confidence, source, via
        case attemptId, suggestions, verification
        case reviewSummary, warnings
        case meta
        case underscoreMeta = "_meta"
    }
}

// MARK: - Backward compat typealiases
//
// Eski callsite'lar (QuickScanResultPanel, ProductReviewView, AddProductFlowView)
// `ProductRecognizeResponse` ve `ProductByBarcodeResponse` ile compile ediyor.
// Agent C bunları zamanla `ProductIdentifyResponse`'a migrate edecek; o güne kadar
// typealias ile aynı tip olarak çalışır.
typealias ProductRecognizeResponse = ProductIdentifyResponse
typealias ProductByBarcodeResponse = ProductIdentifyResponse

// MARK: - Search response

/// `/v1/products/search` cevabı.
///
/// `topMatch=true` query param verildiğinde backend tek-bir-en-iyi-eşleşmeyi
/// `ProductIdentifyResponse` formatında (`top_match`) embed eder; aksi halde
/// nil. `products` listesi paralel olarak gönderilir (manual ekleme UI'ı).
struct ProductSearchResponse: Decodable, Sendable {
    let products: [RecognizedProduct]
    let topMatch: ProductIdentifyResponse?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.products = (try? c.decodeIfPresent([RecognizedProduct].self, forKey: .products)) ?? []
        self.topMatch = try? c.decodeIfPresent(ProductIdentifyResponse.self, forKey: .topMatch)
    }

    private enum CodingKeys: String, CodingKey {
        case products, topMatch
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
