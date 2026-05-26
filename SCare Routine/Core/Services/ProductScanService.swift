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
/// **NOT @MainActor**: class daha önce `@MainActor` idi; bu durumda `Task.detached`
/// içinden çağrılan Vision metodları gizlice main thread'e hop ediyor ve UI'ı
/// kilitliyor (7-10s freeze sebebi). Vision metodları artık `nonisolated` ve
/// gerçekten arka planda çalışıyor.
final class ProductScanService: @unchecked Sendable {
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

    /// Vision CoreML modellerini önceden ısıt — ilk çağrıda 2-5s JIT/load var.
    /// Camera ekranı açılırken fire-and-forget olarak çağır → kullanıcı ilk fotoğrafta
    /// cold-start gecikmesi yaşamaz.
    nonisolated func prewarmVisionModels() {
        Task.detached(priority: .userInitiated) {
            // 64x64 placeholder image ile model load tetikle
            let size = CGSize(width: 64, height: 64)
            let renderer = UIGraphicsImageRenderer(size: size)
            let placeholder = renderer.image { ctx in
                UIColor.gray.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
            guard let cg = placeholder.cgImage else { return }
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            // FP request
            let fpReq = VNGenerateImageFeaturePrintRequest()
            if #available(iOS 17.0, *) {
                fpReq.revision = VNGenerateImageFeaturePrintRequestRevision2
            }
            // OCR request
            let textReq = VNRecognizeTextRequest()
            textReq.recognitionLevel = .accurate
            textReq.recognitionLanguages = ["tr-TR", "en-US"]
            // Barcode request
            let barcodeReq = VNDetectBarcodesRequest()
            // BG-removed (iOS 17+)
            var reqs: [VNRequest] = [fpReq, textReq, barcodeReq]
            if #available(iOS 17.0, *) {
                reqs.append(VNGenerateForegroundInstanceMaskRequest())
            }
            try? handler.perform(reqs)
        }
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
        photoUrl: String? = nil,
        photoKey: String? = nil,
        photoKeyBack: String? = nil,
        photoKeyClean: String? = nil,
        ocrBlocksBack: [String]? = nil,
        featurePrint: [Float]? = nil,
        featurePrintClean: [Float]? = nil,
        captureDebug: AutoCaptureDebug? = nil
    ) async throws -> ProductIdentifyResponse {
        let body = ProductRecognizeRequest(
            barcode: barcode,
            ocrText: ocrText,
            ocrBlocks: ocrBlocks,
            brandHint: brandHint,
            nameHint: nameHint,
            photoUrl: photoUrl,
            photoKey: photoKey,
            photoKeyBack: photoKeyBack,
            photoKeyClean: photoKeyClean,
            ocrBlocksBack: ocrBlocksBack,
            featurePrint: featurePrint,
            featurePrintClean: featurePrintClean,
            captureDebug: captureDebug.map { CaptureDebugPayload(from: $0) }
        )
        return try await api.request(.recognizeProduct, body: body)
    }

    /// `/v1/products/quick-evaluate` — mevcut bir katalog ürünü için kullanıcının
    /// cilt tipine göre fit-score + verdict döndürür (Quick Scan akışı).
    ///
    /// Bu endpoint recognize'dan farklı: recognize ürünü TANIR, quick-evaluate ürünü
    /// TANINMIŞ olarak alıp yorumlar. Genelde recognize → user product seçim → bu
    /// endpoint'le hızlı önizleme. Arşive otomatik EKLEMEZ; preview için.
    func quickEvaluate(productId: String) async throws -> QuickEvaluateResponse {
        struct Body: Encodable {
            let productId: String
        }
        return try await api.request(.quickEvaluateProduct, body: Body(productId: productId))
    }

    /// iOS Apple VNGenerateImageFeaturePrintRequest — 768-d (revision 2, iOS 17+).
    /// Returns nil on older iOS or processing failure.
    func featurePrint(from image: UIImage) async -> [Float]? {
        guard let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest { request, error in
                guard error == nil,
                      let observation = request.results?.first as? VNFeaturePrintObservation,
                      observation.elementType == .float else {
                    continuation.resume(returning: nil)
                    return
                }
                let count = observation.elementCount
                let data = observation.data
                var vec = [Float](repeating: 0, count: count)
                _ = vec.withUnsafeMutableBytes { buf in
                    data.copyBytes(to: buf)
                }
                continuation.resume(returning: vec)
            }
            request.imageCropAndScaleOption = .centerCrop
            if #available(iOS 17.0, *) {
                request.revision = VNGenerateImageFeaturePrintRequestRevision2
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Background-removed image — beyaz arka plana compose edilmiş hali (UIImage).
    /// Hem FP üretmek hem R2'ye fine-tune training data olarak upload için kullanılır.
    ///
    /// **Multiple instance handling:** Apple Vision el/ürün gibi farklı objeleri ayrı
    /// instance olarak yakalıyor. `allInstances` el+ürün hepsini birleştiriyor → biz
    /// **en büyük instance'ı** (genelde ürün) seçiyoruz. Bu el ve gürültüyü filtreler.
    /// Returns nil on iOS <17 or mask fail.
    @available(iOS 17.0, *)
    func backgroundRemovedImage(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let maskRequest = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([maskRequest])
        } catch {
            return nil
        }
        guard let observation = maskRequest.results?.first else { return nil }

        // En büyük instance'ı seç (el ve diğer küçük objeler atılır, sadece ürün kalır).
        let chosenInstances = pickLargestInstance(observation: observation)

        let masked: CVPixelBuffer
        do {
            masked = try observation.generateMaskedImage(
                ofInstances: chosenInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
        } catch {
            return nil
        }
        let ciContext = CIContext()
        let ciImage = CIImage(cvPixelBuffer: masked)
        let whiteBg = CIImage(color: .white).cropped(to: ciImage.extent)
        let composed = ciImage.composited(over: whiteBg)
        guard let cg = ciContext.createCGImage(composed, from: composed.extent) else {
            return nil
        }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    /// `instanceMask` pixel-level index buffer; her piksel hangi instance'a ait olduğunu
    /// söyler (0=arka plan). Pixel count'a göre en büyük instance'ı bul.
    /// Fallback: instance'lar küçükse allInstances dön (boş geçmesin).
    @available(iOS 17.0, *)
    private func pickLargestInstance(observation: VNInstanceMaskObservation) -> IndexSet {
        let allInstances = observation.allInstances
        if allInstances.count <= 1 { return allInstances }

        // instanceMask CVPixelBuffer (per-pixel instance index)
        let buffer = observation.instanceMask
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return allInstances }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)

        var counts: [Int: Int] = [:]
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        // Sample every 4th pixel — speed (~4x faster, accuracy enough for ranking)
        for y in stride(from: 0, to: height, by: 4) {
            let row = ptr.advanced(by: y * bytesPerRow)
            for x in stride(from: 0, to: width, by: 4) {
                let idx = Int(row[x])
                if idx > 0 { counts[idx, default: 0] += 1 }
            }
        }

        guard let largest = counts.max(by: { $0.value < $1.value })?.key else {
            return allInstances
        }
        return IndexSet(integer: largest)
    }

    /// Image'ı en uzun kenar maxDimension olacak şekilde küçült (aspect korunur).
    /// Capture'dan hemen sonra çağrılır: full-res (12MP) image'ı 1500px'e çek.
    /// Vision pipeline (BG-removed + OCR + FP) 12MP'de 2-5s sürüyordu, 1500px'de
    /// 300-800ms. Aynı zamanda thumbnail decode'u hızlandırır.
    nonisolated func downscaleForProcessing(_ image: UIImage, maxDimension: CGFloat = 1500) -> UIImage {
        downscale(image, maxDimension: maxDimension)
    }

    /// Visual FP için: image'ın orta kısmını 1:1 kare olarak kırp.
    /// Kullanıcı ürünü genelde merkezliyor; kenarlardaki gürültü (diğer ürünler,
    /// el, arka plan) FP embedding'ini kirletiyor. Square crop + BG-removal birlikte
    /// daha temiz embedding üretir.
    /// OCR için kullanma — etiket metni kenarlarda olabilir.
    nonisolated func centerSquareCrop(_ image: UIImage) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let side = min(w, h)
        let x = (w - side) / 2.0
        let y = (h - side) / 2.0
        let cropRect = CGRect(x: x * image.scale, y: y * image.scale,
                              width: side * image.scale, height: side * image.scale)
        guard let cg = image.cgImage?.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Recognition için 1500px yeterli, network upload 5-10x hızlanır.
    nonisolated private func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = max(size.width, size.height)
        if scale <= maxDimension { return image }
        let ratio = maxDimension / scale
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Convenience: BG-removed image + FP — single pass.
    @available(iOS 17.0, *)
    func featurePrintBackgroundRemoved(from image: UIImage) async -> (image: UIImage, vec: [Float])? {
        guard let cleaned = backgroundRemovedImage(from: image) else { return nil }
        guard let vec = await featurePrint(from: cleaned) else { return nil }
        return (cleaned, vec)
    }

    /// BG-removed image R2 upload bittikten sonra recognition_attempts'a bağla.
    /// iOS detached upload akışı — recognize'ı bekletmez.
    func attachCleanPhoto(attemptId: String, photoKey: String) async {
        struct Body: Encodable { let photoKeyClean: String }
        do {
            try await api.requestVoid(.attachCleanPhoto(id: attemptId), body: Body(photoKeyClean: photoKey))
        } catch {
            logger.warning("attach clean photo failed: \(String(describing: error))")
        }
    }

    /// Speculative recognize kabul edildikten sonra back fotoğraf upload bitince DB'ye bağla.
    func attachBackPhoto(attemptId: String, photoKey: String) async {
        struct Body: Encodable { let photoKeyBack: String }
        do {
            try await api.requestVoid(.attachBackPhoto(id: attemptId), body: Body(photoKeyBack: photoKey))
        } catch {
            logger.warning("attach back photo failed: \(String(describing: error))")
        }
    }

    /// Phase 3B: kullanıcı recognize sonucunu onayladı/düzeltti.
    /// confirmed=true → data flywheel'e contribute edilebilir.
    /// confirmed=false + correctedProductId → wrong match, signal for tuning.
    func confirmRecognition(attemptId: String, correct: Bool, correctedProductId: String? = nil) async {
        struct Body: Encodable {
            let correct: Bool
            let correctedProductId: String?
        }
        do {
            try await api.requestVoid(
                .confirmRecognitionAttempt(id: attemptId),
                body: Body(correct: correct, correctedProductId: correctedProductId)
            )
        } catch {
            logger.warning("confirm attempt failed: \(String(describing: error))")
        }
    }

    /// `/v1/products/by-barcode/:bc` — barkod + INCI listesi + (opsiyonel) VLM cross-check.
    ///
    /// `photoKey` verilirse backend ürünü bulduğunda VLM ile foto'yu çapraz kontrol
    /// eder ve `verification` alanı dolu döner. Bu sayede yanlış barcode hit'leri
    /// (örn. paylaşımlı UPC) tespit edilir.
    ///
    /// Backend bulamazsa 404 → boş `ProductIdentifyResponse` döner (product=nil).
    ///
    /// **NOT**: Aynı isimle tuple-returning overload (backward compat) altta tanımlı.
    /// Yeni callsite'lar `photoKey:` label'ı ile veya context'le `ProductIdentifyResponse`
    /// dönüşünü kullanır. Eski destructure (`let (p, i) = ...`) tuple overload'a düşer.
    func lookupByBarcode(_ barcode: String, photoKey: String? = nil) async throws -> ProductIdentifyResponse {
        do {
            if let photoKey {
                struct Body: Encodable { let photoKey: String }
                return try await api.request(.productByBarcode(barcode), body: Body(photoKey: photoKey))
            } else {
                return try await api.request(.productByBarcode(barcode))
            }
        } catch APIError.notFound {
            return ProductIdentifyResponse(
                product: nil,
                ingredients: nil,
                confidence: "low",
                source: "barcode_explicit"
            )
        }
    }

    /// Backward-compat tuple overload — Agent C eski AddProductFlowView callsite'ını
    /// migrate edene kadar `let (p, ings) = ... lookupByBarcode(bc)` destructure'u
    /// çalışsın diye duruyor. Internal'da yeni `ProductIdentifyResponse` decode'unu
    /// kullanır, sadece dönüş şekli tuple. Swift overload resolution: tuple destructure
    /// context'i bu signature'a yönlendirir; yeni callsite'lar tek değer/`photoKey:`
    /// kullanarak unified overload'a düşer.
    @available(*, deprecated, message: "Use lookupByBarcode(_:photoKey:) returning ProductIdentifyResponse")
    func lookupByBarcode(_ barcode: String) async throws -> (product: RecognizedProduct?, ingredients: [RecognizedIngredient]?) {
        let resp = try await lookupByBarcode(barcode, photoKey: nil)
        return (resp.product, resp.ingredients)
    }

    /// `/v1/products/search?q=...&top_match=true` — manuel arama, opsiyonel top-match.
    ///
    /// `topMatch=true` verildiğinde backend en iyi adayı tam recognize formatında
    /// (`ProductIdentifyResponse`) embed eder; UI bunu "şu mu?" prompt'u için kullanır.
    /// Liste her durumda `products` field'ında gelir.
    func search(query: String, topMatch: Bool = false) async throws -> ProductSearchResponse {
        return try await api.request(.searchProducts(query: query, topMatch: topMatch))
    }

    /// `/v1/me/products` POST — kullanıcı arşivine ekle.
    /// Backend response'u `{ item: {...} }` ile sarmalanmış, unwrap ediyoruz.
    func addToArchive(_ request: UserProductCreateRequest) async throws -> UserProductResponse {
        let resp: CreateUserProductResponse = try await api.request(.addMyProduct, body: request)
        // İlk ürün eklendi → Tier 0 aktivasyon bildirimleri artık gereksiz, iptal et.
        // Fire-and-forget: NotificationService @MainActor, ProductScanService değil.
        Task { @MainActor in NotificationService.shared.cancelTier0() }
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

    /// Upload meta — `publicUrl` (auth'lu Worker URL, gösterim için) + `key` (R2 obje key,
    /// recognize/AI Vision için backend'e geçilir; AI provider hiç public URL görmez).
    struct UploadedImage {
        let publicUrl: String
        let key: String
    }

    /// `/v1/uploads/sign` ile presigned PUT URL alır, JPEG'i R2'ye yükler.
    /// Hata: iki kez retry'a kadar geri sarar — `ScanError.uploadFailed` ile çıkar.
    func uploadImage(_ image: UIImage, kind: String = "product_photo") async throws -> UploadedImage {
        // VLM verification + R2 storage için: 1:1 crop + 1024 downscale.
        // - 1:1 crop → ürün merkezde, kenardaki background/diğer ürünler temizlenir
        //   (Apple FP zaten center-crop yapıyor ama R2'deki foto VLM'e de gidiyor,
        //   explicit crop daha güvenli)
        // - 1024×1024 → VLM image token ~1500, latency ~2.5s, OCR güvenli (768 OCR
        //   yazılarını bozuyordu, 1024 net kalır)
        // - JPEG 0.65 → ~80KB upload, mobil network'te <500ms upload
        // iOS-local OCR pipeline (downscaleForProcessing 1500 default) bu değişimden
        // etkilenmez — sadece R2'ye giden foto küçülür.
        let cropped = centerSquareCrop(image)
        let resized = downscale(cropped, maxDimension: 1024)
        guard let data = resized.jpegData(compressionQuality: 0.65) else {
            throw ScanError.imageEncodingFailed
        }

        let signReq = UploadSignRequest(kind: kind, contentType: "image/jpeg", ext: "jpg")
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
                return UploadedImage(publicUrl: sign.publicUrl, key: sign.key)
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
        case .imageEncodingFailed: return L("Fotoğraf işlenemedi.")
        case .uploadFailed(let reason):
            let fmt = L("Yükleme başarısız (%@).")
            return String(format: fmt, reason)
        case .noInput: return L("Tanıma için yeterli veri yok.")
        }
    }
}
