import Foundation
import UIKit
import Vision
import OSLog

/// Ürün ekleme akışının veri-katmanı servisi.
///
/// İçerik:
/// - Backend ile konuşan thin wrapper'lar (recognize / by-barcode / upload-sign / me-products)
/// - R2 presigned URL'e raw image PUT
/// - Apple Vision tabanlı offline barcode + OCR pipeline'ı (statik kare analizi)
///
/// `@MainActor` çünkü çoğu çağrı UI tarafından doğrudan await'lenir; Vision request'leri
/// kısa süreli iken büyük image upload'ları main loop'u tıkamasın diye `Task.detached`
/// + `URLSession` background-friendly konfigürasyonu ile yürütülür.
@MainActor
final class ProductScanService {
    static let shared = ProductScanService()

    private let api = APIClient.shared
    private let uploadSession: URLSession
    private let logger = Logger(subsystem: "com.aliarifsoydas.scareroutine", category: "ProductScan")

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = true
        self.uploadSession = URLSession(configuration: cfg)
    }

    // MARK: - Backend çağrıları

    /// `/v1/products/recognize` — barcode + ocr + hint'lerden cascade sonucu döner.
    ///
    /// `ocrBlocks` Apple Vision'ın orijinal line-level çıktısıdır; backend bunu
    /// brand/name heuristic'i için tercih eder. `ocrText` ise blokların `\n` ile
    /// birleştirilmiş hali — eski client'larla uyumluluk için saklanıyor.
    func recognize(
        barcode: String? = nil,
        ocrText: String? = nil,
        ocrBlocks: [String]? = nil,
        brandHint: String? = nil,
        nameHint: String? = nil,
        photoUrl: String? = nil
    ) async throws -> ProductRecognizeResponse {
        let body = ProductRecognizeRequest(
            barcode: barcode,
            ocrText: ocrText,
            ocrBlocks: ocrBlocks,
            brandHint: brandHint,
            nameHint: nameHint,
            photoUrl: photoUrl
        )
        return try await api.request(.recognizeProduct, body: body)
    }

    /// `/v1/products/by-barcode/:bc` — sadece barcode lookup.
    /// Backend ürünü bulamazsa 404 dönebilir; bu durumda `nil` döndürürüz.
    func lookupByBarcode(_ barcode: String) async throws -> RecognizedProduct? {
        do {
            let resp: ProductByBarcodeResponse = try await api.request(.productByBarcode(barcode))
            return resp.product
        } catch APIError.notFound {
            return nil
        }
    }

    /// `/v1/me/products` POST — kullanıcı arşivine ekle.
    /// Backend response'u `{ item: {...} }` ile sarmalanmış, unwrap ediyoruz.
    func addToArchive(_ request: UserProductCreateRequest) async throws -> UserProductResponse {
        let resp: CreateUserProductResponse = try await api.request(.addMyProduct, body: request)
        return resp.item
    }

    /// `/v1/me/products` GET — arşiv listesi.
    func listMyProducts() async throws -> [UserProductResponse] {
        let resp: ListUserProductsResponse = try await api.request(.listMyProducts)
        return resp.products
    }

    /// `/v1/products/:product_id` GET — katalog ürün detayı (INCI dahil).
    ///
    /// Detay sheet'i bunu çağırır. 404 fırlatabilir (katalogdan silinmiş olabilir);
    /// caller yakalar.
    func getProductDetail(productId: String) async throws -> (product: RecognizedProduct, ingredients: [RecognizedIngredient]) {
        let resp: ProductDetailResponse = try await api.request(.productDetail(id: productId))
        guard let product = resp.product else { throw APIError.notFound }
        return (product, resp.ingredients ?? [])
    }

    /// `/v1/me/products/:id` PATCH — kullanıcının arşiv kaydını günceller
    /// (favori toggle, arşive taşı/çıkar, nickname/notes/rating düzenle, opened/finished tarihleri).
    ///
    /// Backend yalnızca gönderilen alanları değiştirir; nil olanlar dokunulmaz.
    /// Caller cevap gövdesine ihtiyaç duymadığı için `void` döner — UI optimistic
    /// güncelleme yapar.
    func updateMyProduct(_ id: String, payload: UserProductUpdateRequest) async throws {
        try await api.requestVoid(.updateMyProduct(id: id), body: payload)
    }

    /// `/v1/me/products/:id` DELETE — arşiv kaydını kalıcı siler.
    func deleteMyProduct(_ id: String) async throws {
        try await api.requestVoid(.deleteMyProduct(id: id))
    }

    // MARK: - Upload

    /// `/v1/uploads/sign` ile presigned PUT URL alır, JPEG'i R2'ye yükler, public URL döndürür.
    /// Hata: iki kez retry'a kadar geri sarar — `ScanError.uploadFailed` ile çıkar.
    func uploadImage(_ image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.82) else {
            throw ScanError.imageEncodingFailed
        }

        let signReq = UploadSignRequest(kind: "product_photo", contentType: "image/jpeg", ext: "jpg")
        let sign: UploadSignResponse = try await api.request(.signUpload, body: signReq)

        guard let url = URL(string: sign.uploadUrl) else {
            throw ScanError.uploadFailed("invalid_presigned_url")
        }

        // PUT — iki kere retry et
        var attempt = 0
        var lastError: Error?
        while attempt < 3 {
            do {
                try await putData(data, to: url, contentType: "image/jpeg")
                return sign.publicUrl
            } catch {
                lastError = error
                attempt += 1
                if attempt < 3 {
                    // 0.4s, sonra 1.0s
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000)
                }
            }
        }
        throw ScanError.uploadFailed(lastError?.localizedDescription ?? "unknown")
    }

    private func putData(_ data: Data, to url: URL, contentType: String) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await uploadSession.upload(for: req, from: data)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ScanError.uploadFailed("status_\(code)")
        }
    }

    // MARK: - Apple Vision

    /// Statik bir UIImage'ten barcode (EAN-8/13, UPC, QR vs.) çıkarır.
    /// Live tarama için DataScannerViewController tercih edilir; bu metod galeri/foto akışı için.
    func detectBarcode(from image: UIImage) async -> String? {
        guard let cg = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNDetectBarcodesRequest { req, _ in
                let value = (req.results as? [VNBarcodeObservation])?
                    .compactMap { $0.payloadStringValue }
                    .first
                continuation.resume(returning: value)
            }
            // En yaygın kozmetik barcode formatları
            request.symbologies = [.ean8, .ean13, .upce, .code128, .code39, .qr]

            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// VNRecognizeTextRequest ile TR + EN dilinde block-level metin çıkarır.
    /// Her `VNRecognizedTextObservation` ayrı bir bloktur — paket etiketinde brand banner,
    /// product name, alt başlık vb. doğal olarak farklı blok'lara denk gelir. Backend bunu
    /// brand/name heuristic'i için kullanır.
    func recognizeTextBlocks(from image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let lines: [String] = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    ?? []
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["tr-TR", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    /// `recognizeTextBlocks`'un newline ile birleşmiş tek-string versiyonu.
    /// Eski çağrıların kırılmaması için tutuluyor; yeni kod direkt blocks kullanmalı.
    func recognizeText(from image: UIImage) async -> String? {
        let blocks = await recognizeTextBlocks(from: image)
        if blocks.isEmpty { return nil }
        return blocks.joined(separator: "\n")
    }

    /// OCR çıktısından brand + name tahmini.
    ///
    /// Basit heuristik:
    /// - Boş/whitespace satırlar atılır
    /// - 3 karakterden kısa satırlar atılır (gürültü)
    /// - En uzun ALL-CAPS satır brand kabul edilir (kozmetiklerde brand genelde büyük punto + caps)
    /// - Brand'in altındaki ilk anlamlı satır name
    /// - Yoksa: ilk satır brand, ikincisi name
    nonisolated static func extractBrandAndName(from text: String) -> (brand: String?, name: String?) {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 }

        guard !lines.isEmpty else { return (nil, nil) }

        // 1) ALL-CAPS satırı arayalım
        if let capsIdx = lines.firstIndex(where: { isMostlyUppercase($0) }) {
            let brand = lines[capsIdx]
            let nameIdx = lines.index(after: capsIdx)
            let name = nameIdx < lines.endIndex ? lines[nameIdx] : nil
            return (brand, name)
        }

        // 2) Fallback: ilk iki satır
        let brand = lines.first
        let name = lines.dropFirst().first
        return (brand, name)
    }

    private nonisolated static func isMostlyUppercase(_ s: String) -> Bool {
        let letters = s.filter { $0.isLetter }
        guard letters.count >= 3 else { return false }
        let uppers = letters.filter { $0.isUppercase }.count
        return Double(uppers) / Double(letters.count) >= 0.7
    }
}

// MARK: - Errors

enum ScanError: LocalizedError {
    case imageEncodingFailed
    case uploadFailed(String)
    case noInput

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: return "Fotoğraf işlenemedi."
        case .uploadFailed(let reason): return "Yükleme başarısız (\(reason))."
        case .noInput: return "Tanıma için yeterli veri yok."
        }
    }
}
