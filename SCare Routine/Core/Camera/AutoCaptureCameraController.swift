import UIKit
import AVFoundation
import Vision
import CoreVideo

// MARK: - Delegate

/// `AutoCaptureCameraController` callback'lerini dinleyen sahip.
/// Tüm metodlar **main queue**'da çağrılır.
protocol AutoCaptureCameraControllerDelegate: AnyObject {
    /// Live barcode detection — AVCaptureMetadataOutput'tan ürün barkodu bulundu.
    /// Aynı barkod tekrar yayınlanmaz (controller tekrarları filtreler).
    func cameraController(_ controller: AutoCaptureCameraController, didDetectBarcode barcode: String)

    /// Throttled OCR sonucu — birikmiş text bloklarının son snapshot'ı.
    /// 10. frame'de bir tetiklenir, etiket OCR'ı için.
    func cameraController(_ controller: AutoCaptureCameraController, didUpdateText textBlocks: [String])

    /// Auto/manual capture tamamlandı — UIImage + Vision debug metadata hazır.
    /// Bu callback'ten sonra controller `.captured` state'inde kalır;
    /// retake için `resetCaptureState()` çağırın.
    func cameraController(_ controller: AutoCaptureCameraController, didCapturePhoto image: UIImage, debug: AutoCaptureDebug)

    /// State machine güncellemesi (searching → stabilizing → ready → capturing → captured).
    /// UI overlay (örn. "Tutun stabil..." göstergesi) buna bind edilir.
    func cameraController(_ controller: AutoCaptureCameraController, didUpdateState state: AutoCaptureState)

    /// Anlık instability ratio (0..1). UI'da progress ring/blur seviyesi için.
    /// 0 → sahne tamamen stabil, 1 → maksimum sallantı.
    func cameraController(_ controller: AutoCaptureCameraController, didUpdateInstability ratio: CGFloat)

    /// Belirgin nesnenin bounding box'ı (Vision normalized koordinat, origin
    /// bottom-left). nil → kadrajda belirgin nesne yok. HUD bounding box çizimi için.
    func cameraController(_ controller: AutoCaptureCameraController, didUpdateSalientBox box: CGRect?)
}

// MARK: - State

/// Auto-capture pipeline state machine.
enum AutoCaptureState: Equatable {
    /// Henüz stable değil — history toplanıyor veya kullanıcı kamerayı oynatıyor.
    case searching
    /// History yarıdan fazla dolu ama henüz threshold'un altına inmedi.
    /// UI burada "Sabitleyin..." mesajı gösterir.
    case stabilizing
    /// Sahne stabil — bir sonraki frame'de capture tetiklenecek.
    case readyToCapture
    /// `capturePhoto(with:)` çağrıldı — photo callback bekleniyor.
    case capturing
    /// Photo delegate'e iletildi — `resetCaptureState()` çağrılana kadar pasif.
    case captured
    /// Hata: camera permission denied, device unavailable, vs.
    case error(String)

    static func == (lhs: AutoCaptureState, rhs: AutoCaptureState) -> Bool {
        switch (lhs, rhs) {
        case (.searching, .searching),
             (.stabilizing, .stabilizing),
             (.readyToCapture, .readyToCapture),
             (.capturing, .capturing),
             (.captured, .captured):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Capture Debug Metadata

/// Capture anında toplanan Apple Vision debug datası — fine-tune için backend'e
/// gönderilir (recognize request `capture_debug` field). Foto'yu değiştirmez.
struct AutoCaptureDebug {
    /// Belirgin nesne bounding box (Vision normalized, bottom-left). nil olabilir.
    let salientBox: CGRect?
    /// VNClassifyImageRequest top sonuçları (identifier + confidence 0-1).
    let classifications: [(id: String, confidence: Float)]
    /// Sahne dengesizliği (0 = stabil, 1 = maksimum sallantı).
    let instability: CGFloat
    /// Capture anında sahne stabil miydi.
    let stable: Bool
}

// MARK: - Controller

/// Self-managed AVCaptureSession + Vision pipeline.
/// `DataScannerViewController` yerine kullanılıyor — bizim ihtiyaçlarımız için:
///   - Frame-by-frame Vision translational registration (sahne stabilitesi)
///   - Auto-capture trigger (kullanıcı sabit tutunca otomatik foto)
///   - Live barcode (AVCaptureMetadataOutput, native fast path)
///   - Throttled OCR (her 10. frame, VNRecognizeTextRequest.fast)
///   - High-res photo capture (AVCapturePhotoOutput)
///
/// **Yaşam döngüsü:**
///   - `viewDidLoad`: session + outputs + preview layer kurulur (kamera izni varsa).
///   - `viewWillAppear`: session start.
///   - `viewWillDisappear`: session stop.
///
/// **Threading:** AVCapture delegate callback'leri `sessionQueue`'da gelir.
/// Vision request'leri da aynı queue'da çalışır (serial). Delegate çağrıları main'e
/// `DispatchQueue.main.async` ile aktarılır.
final class AutoCaptureCameraController: UIViewController {

    // MARK: - Public API

    weak var delegate: AutoCaptureCameraControllerDelegate?

    /// `false` ise stability detection çalışmaz, manuel `captureManually()` zorunlu.
    /// UI'da kullanıcı "manuel mod"a geçtiğinde set edilir.
    var autoCaptureEnabled: Bool = true

    /// Kullanıcı UI'daki shutter butonuna basınca çağrılır.
    /// Capture state ne olursa olsun çalışır (capturing/captured hariç, re-entry guard).
    func captureManually() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Manuel capture, .captured/.error state'inde takılmasın. Ön foto
            // çekilince state .captured oluyor, "arkayı çek" ekranında butona
            // basınca triggerCapture'ın .captured guard'ı no-op yapıyordu (reset
            // geç geldiği için ilk tıklamalar düşüyordu). Basışta önce sıfırla.
            switch self.currentState {
            case .captured, .error:
                self.currentState = .searching
                self.stabilityDetector.reset()
                self.framesAfterReady = 0
            default:
                break
            }
            self.triggerCapture()
        }
    }

    /// Photo iletildikten sonra retake için. Stability detector ve state sıfırlanır.
    func resetCaptureState() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.stabilityDetector.reset()
            self.framesAfterReady = 0
            self.collectedTextLines.removeAll()
            self.lastEmittedBarcode = nil
            self.lastRetailBarcode = nil
            self.latestSalientBox = nil
            self.updateState(.searching)
        }
    }

    // MARK: - AV Session

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "scare.camera.session", qos: .userInitiated)

    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var metadataOutput: AVCaptureMetadataOutput?
    private var photoOutput: AVCapturePhotoOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Vision

    /// Frame'ler arasında translational drift'i ölçer.
    /// Maksimum 15 frame history, 20px threshold (sibling agent'ın yazdığı API).
    private let stabilityDetector = SceneStabilityDetector(maximumHistoryLength: 15,
                                                           stabilityThreshold: 20.0)

    /// Vision sequence handler — `VNTranslationalImageRegistrationRequest` zincir tutar.
    private let visionSequenceHandler = VNSequenceRequestHandler()

    /// Önceki frame — registration request'in referansı.
    /// Retain edilir çünkü Vision'ın needs both frames (current + previous).
    private var previousPixelBuffer: CVPixelBuffer?

    /// Throttle sayacı — text recognition her N frame'de bir.
    private var frameCounter: Int = 0
    private static let textRecognitionThrottle: Int = 10
    /// Objectness saliency throttle — her N frame'de bir belirgin nesne ara.
    private static let saliencyThrottle: Int = 6

    /// Birikmiş text — son emit'ten beri.
    private var collectedTextLines: [String] = []

    /// Son emit edilen barkod — duplicate yayını engeller.
    private var lastEmittedBarcode: String?
    /// Son okunan RETAIL barkod (EAN/UPC). QR/Code128 ürün garantisi değil
    /// (kartvizit, poster, kitap), bu yüzden composition guard sadece retail
    /// barkodu "ürün var" sinyali olarak sayar.
    private var lastRetailBarcode: String?

    /// En son tespit edilen belirgin nesnenin bounding box'ı (Vision normalized
    /// koordinat, origin bottom-left). nil → kadrajda belirgin ürün yok.
    private var latestSalientBox: CGRect?
    /// Belirgin nesne sayılması için minimum alan oranı (frame'in %10'u).
    private static let minSubjectAreaRatio: CGFloat = 0.10
    /// Son classification sonuçları (debug metadata — fine-tune için).
    private var latestClassifications: [(id: String, confidence: Float)] = []
    /// Son instability ratio (debug metadata).
    private var latestInstability: CGFloat = 1.0

    // MARK: - Capture State

    private var currentState: AutoCaptureState = .searching
    /// Stable olduktan sonra 1 frame daha bekle — UI flicker'ı önler.
    private var framesAfterReady: Int = 0

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Permission check + session setup
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { [weak self] in self?.configureSession() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.sessionQueue.async { self.configureSession() }
                } else {
                    self.dispatchState(.error("permission_denied"))
                }
            }
        case .denied, .restricted:
            dispatchState(.error("permission_denied"))
        @unknown default:
            dispatchState(.error("permission_unknown"))
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    // MARK: - Session Configuration

    /// `sessionQueue`'da çağrılır. UIKit dokunulmaz.
    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Input: back camera (default wide-angle)
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            dispatchState(.error("camera_unavailable"))
            return
        }
        session.addInput(input)

        // Output 1: Video frames (Vision için)
        let videoOut = AVCaptureVideoDataOutput()
        videoOut.alwaysDiscardsLateVideoFrames = true
        videoOut.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOut.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(videoOut) {
            session.addOutput(videoOut)
            videoDataOutput = videoOut
            // Frame orientation'ı portrait sabitle — Vision input doğru rotate olsun
            if let conn = videoOut.connection(with: .video) {
                Self.setPortrait(conn)
            }
        }

        // Output 2: Metadata (barcode native fast path)
        let metaOut = AVCaptureMetadataOutput()
        if session.canAddOutput(metaOut) {
            session.addOutput(metaOut)
            metaOut.setMetadataObjectsDelegate(self, queue: sessionQueue)
            // CapableObjectTypes addOutput'tan SONRA set edilmeli (Apple gereklilik)
            let desired: [AVMetadataObject.ObjectType] = [
                .ean8, .ean13, .upce, .code128, .code39, .qr
            ]
            metaOut.metadataObjectTypes = desired.filter {
                metaOut.availableMetadataObjectTypes.contains($0)
            }
            metadataOutput = metaOut
        }

        // Output 3: Photo (high-res capture)
        let photoOut = AVCapturePhotoOutput()
        if session.canAddOutput(photoOut) {
            session.addOutput(photoOut)
            // settings.photoQualityPrioritization = .quality kullanabilmek için
            // output'un tavanını da .quality'ye çıkar (default .balanced).
            photoOut.maxPhotoQualityPrioritization = .quality
            if #available(iOS 16.0, *) {
                // Max photo dimension device'ın aktif formatından alınır
                // (AVCapturePhotoOutput'ta query API'si yok — input device'tan).
                if let maxDim = device.activeFormat.supportedMaxPhotoDimensions.last {
                    photoOut.maxPhotoDimensions = maxDim
                }
            }
            photoOutput = photoOut
        }

        session.commitConfiguration()

        // Preview layer (main queue — UIKit dokunması)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let layer = AVCaptureVideoPreviewLayer(session: self.session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = self.view.bounds
            if let conn = layer.connection {
                Self.setPortrait(conn)
            }
            self.view.layer.addSublayer(layer)
            self.previewLayer = layer
        }
    }

    // MARK: - Orientation Helper

    /// Connection'ı portrait'e sabitle. iOS 17+ `videoRotationAngle` (90° = portrait),
    /// öncesinde deprecated `videoOrientation`.
    private static func setPortrait(_ conn: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            if conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            }
        } else {
            if conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
        }
    }

    // MARK: - Capture Trigger

    /// `sessionQueue` üzerinden çağrılmalı.
    /// Re-entry guard: capturing/captured state'lerinde no-op.
    private func triggerCapture() {
        guard let photoOutput else { return }
        switch currentState {
        case .capturing, .captured, .error:
            return
        default:
            break
        }
        updateState(.capturing)

        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        if #available(iOS 16.0, *) {
            settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        }

        // Photo connection orientation portrait sabitle
        if let conn = photoOutput.connection(with: .video) {
            Self.setPortrait(conn)
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - State Mgmt

    /// `sessionQueue`'da çalışır. Delegate'i main'e push eder.
    private func updateState(_ new: AutoCaptureState) {
        guard currentState != new else { return }
        currentState = new
        dispatchState(new)
    }

    /// Thread-safe — delegate'e main'de çağrı yapar.
    private func dispatchState(_ state: AutoCaptureState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.cameraController(self, didUpdateState: state)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension AutoCaptureCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // MANUEL MOD: auto-capture kapalıyken per-frame Vision YOK. Registration +
        // OCR + saliency + classification kamerayı yavaşlatıp capture timing'i
        // bozuyordu (yanlış/eski kare yakalanması). Barcode detection ayrı delegate'te
        // (metadataOutput) devam ediyor. Debug metadata capture anında bir kez,
        // çekilen foto üzerinden hesaplanıyor (computeDebugFromImage).
        guard autoCaptureEnabled else { return }

        // 1) Translational registration — sahne stabilite ölçümü
        if let previous = previousPixelBuffer {
            let request = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: pixelBuffer)
            do {
                try visionSequenceHandler.perform([request], on: previous)
                if let observation = request.results?.first as? VNImageTranslationAlignmentObservation {
                    let tx = observation.alignmentTransform.tx
                    let ty = observation.alignmentTransform.ty
                    stabilityDetector.record(CGPoint(x: tx, y: ty))
                }
            } catch {
                // Registration başarısızlığı normal — özellikle ilk birkaç frame'de
                // veya tamamen siyah karelerde. Sessizce geç.
            }
        }
        // Yeni frame'i sonraki iterasyon için sakla
        previousPixelBuffer = pixelBuffer

        // Instability emit + debug için sakla
        let ratio = stabilityDetector.instabilityRatio
        latestInstability = ratio
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.cameraController(self, didUpdateInstability: ratio)
        }

        // 2) Throttled OCR — her 10. frame
        frameCounter &+= 1
        if frameCounter % Self.textRecognitionThrottle == 0 {
            performTextRecognition(on: pixelBuffer)
        }

        // 3) Throttled objectness saliency — her 6. frame, belirgin nesne ara
        if frameCounter % Self.saliencyThrottle == 0 {
            performSaliency(on: pixelBuffer)
        }

        // 4) Auto-capture state machine
        evaluateAutoCapture()
    }

    /// Stability detector'ın history dolma + stable durumuna göre state'i ilerlet.
    /// Sadece searching/stabilizing/readyToCapture arasında çalışır.
    private func evaluateAutoCapture() {
        switch currentState {
        case .capturing, .captured, .error:
            return
        default:
            break
        }

        let stable = stabilityDetector.isStable
        let instability = stabilityDetector.instabilityRatio

        // COMPOSITION GUARD: kararlı olmak yetmez — kadrajda gerçekten belirgin
        // bir nesne olmalı. Objectness saliency ile tespit edilen anchor box
        // (alan ≥ %10 + merkeze yakın) varsa ürün var demektir. Boş hava/duvar →
        // salient object yok → çekmez. Barkod okunduysa kesin ürün var.
        let hasContent = latestSalientBox != nil || lastRetailBarcode != nil

        if stable && hasContent {
            // Stable + içerik var → readyToCapture'a geç, 1 frame bekle, tetikle.
            if currentState != .readyToCapture {
                updateState(.readyToCapture)
                framesAfterReady = 0
            } else {
                framesAfterReady += 1
                if framesAfterReady >= 1 {
                    triggerCapture()
                }
            }
        } else if stable && !hasContent {
            // Kamera sabit ama kadrajda ürün yok → "ürünü yerleştir" göster.
            framesAfterReady = 0
            updateState(.searching)
        } else {
            // Aktif olarak sallıyor — instability ratio'ya göre state ayır
            // (UX: "Sabitleyin" mesajı history'nin yarısı dolduğunda gözüksün)
            framesAfterReady = 0
            if instability < 0.5 {
                // Yarıdan azı kararsız → kullanıcı sabitlemeye çalışıyor
                updateState(.stabilizing)
            } else {
                updateState(.searching)
            }
        }
    }

    /// Throttled OCR — VNRecognizeTextRequest fast mode.
    /// Sonucu mevcut text bloklarına ekler, delegate'e snapshot iletir.
    private func performTextRecognition(on pixelBuffer: CVPixelBuffer) {
        let request = VNRecognizeTextRequest { [weak self] req, _ in
            guard let self,
                  let observations = req.results as? [VNRecognizedTextObservation] else { return }
            var newLines: [String] = []
            for obs in observations {
                guard let candidate = obs.topCandidates(1).first else { continue }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count >= 3 { newLines.append(text) }
            }
            self.mergeAndEmitText(newLines)
        }
        request.recognitionLevel = .fast
        request.recognitionLanguages = ["tr-TR", "en-US"]
        request.usesLanguageCorrection = false  // Fast mode ile birlikte gereksiz overhead

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up,
                                            options: [:])
        // sessionQueue'da senkron çalıştır (zaten background queue)
        try? handler.perform([request])
    }

    /// Throttled objectness saliency — kadrajdaki belirgin nesneleri bul,
    /// en büyük + merkeze yakın olanı anchor seç, `latestSalientBox`'a yaz,
    /// delegate'e ilet (HUD bounding box için).
    private func performSaliency(on pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up,
                                            options: [:])
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        try? handler.perform([request])
        let objects = (request.results?.first as? VNSaliencyImageObservation)?.salientObjects ?? []
        let anchor = Self.pickAnchorBox(objects)
        // Classification — DEBUG datası (fine-tune). Auto-capture off olduğu için
        // çekme kararı vermez; sadece backend'e gönderilmek üzere toplanır.
        // ROI varsa nesne bölgesini, yoksa full frame'i sınıflandır.
        latestClassifications = Self.classify(handler: handler, roi: anchor)
        updateSalientBox(anchor)
    }

    /// VNClassifyImageRequest ile bölgeyi (veya full frame) sınıflandırır.
    /// Top-5 sonuç (confidence ≥ 0.1) döner — debug/fine-tune datası.
    private static func classify(handler: VNImageRequestHandler, roi: CGRect?) -> [(id: String, confidence: Float)] {
        let req = VNClassifyImageRequest()
        if let roi { req.regionOfInterest = roi }
        do {
            try handler.perform([req])
        } catch {
            return []
        }
        guard let results = req.results else { return [] }
        return results
            .filter { $0.confidence >= 0.1 }
            .prefix(5)
            .map { (id: $0.identifier, confidence: $0.confidence) }
    }

    /// Belirgin nesneler içinden anchor seç: alan × merkez-yakınlığı skoruna göre
    /// en yükseği. Minimum alan eşiğini geçmiyorsa nil (kadrajda gerçek ürün yok).
    /// Dönen box Vision normalized koordinat (origin bottom-left).
    private static func pickAnchorBox(_ objects: [VNRectangleObservation]) -> CGRect? {
        guard !objects.isEmpty else { return nil }
        var best: (box: CGRect, score: CGFloat)?
        for obs in objects {
            let box = obs.boundingBox            // normalized, bottom-left origin
            let area = box.width * box.height
            // Merkez-yakınlığı: kadraj ortasına Manhattan uzaklığı (0 = tam merkez)
            let distToCenter = abs(box.midX - 0.5) + abs(box.midY - 0.5)
            let centerBias = max(0, 1 - distToCenter)   // merkeze yakınsa ~1
            let score = area * (0.5 + 0.5 * centerBias) // alan ağırlıklı + merkez bonusu
            if best == nil || score > best!.score {
                best = (box, score)
            }
        }
        guard let chosen = best, chosen.box.width * chosen.box.height >= minSubjectAreaRatio else {
            return nil
        }
        return chosen.box
    }

    /// latestSalientBox güncelle + delegate'e ilet (main queue).
    private func updateSalientBox(_ box: CGRect?) {
        latestSalientBox = box
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.cameraController(self, didUpdateSalientBox: box)
        }
    }

    /// Yeni text satırlarını birikenle merge et, son 8 satırı tut, delegate'e ilet.
    private func mergeAndEmitText(_ newLines: [String]) {
        var changed = false
        for line in newLines where !collectedTextLines.contains(line) {
            collectedTextLines.append(line)
            changed = true
        }
        if collectedTextLines.count > 8 {
            collectedTextLines.removeFirst(collectedTextLines.count - 8)
            changed = true
        }
        guard changed else { return }
        let snapshot = collectedTextLines
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.cameraController(self, didUpdateText: snapshot)
        }
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

extension AutoCaptureCameraController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        for obj in metadataObjects {
            guard let readable = obj as? AVMetadataMachineReadableCodeObject,
                  let payload = readable.stringValue,
                  !payload.isEmpty,
                  payload != lastEmittedBarcode else { continue }
            lastEmittedBarcode = payload
            // Retail barkod (EAN/UPC) → kesin ürün sinyali. QR/Code128/Code39 →
            // değil (kartvizit, URL, etiket); bunlar composition guard'ı geçmez.
            let retailTypes: [AVMetadataObject.ObjectType] = [.ean8, .ean13, .upce]
            if retailTypes.contains(readable.type) {
                lastRetailBarcode = payload
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.cameraController(self, didDetectBarcode: payload)
            }
            break // İlk valid barkod yeter
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension AutoCaptureCameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            // Hata: state'i error'a düşür, kullanıcı retry yapsın
            updateState(.error("photo_processing_failed: \(error.localizedDescription)"))
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            updateState(.error("photo_data_unavailable"))
            return
        }
        updateState(.captured)
        // AKICILIK ÖNCELİK: image'i HEMEN ilet — kullanıcı sıfır gecikmeyle "arkayı
        // çek" ekranına geçsin. Ağır debug (saliency + classification) capture
        // callback'ini bloke ediyordu (~300-400ms sessionQueue). Artık sadece hafif
        // metadata (instability + stable) gönderiyoruz; saliency/classification
        // capture-time hesaplanmıyor (akıcılık > fine-tune datası).
        let debug = AutoCaptureDebug(
            salientBox: nil,
            classifications: [],
            instability: latestInstability,
            stable: stabilityDetector.isStable
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.cameraController(self, didCapturePhoto: image, debug: debug)
        }
    }

    /// Çekilen foto'dan tek seferlik debug metadata: objectness saliency anchor box +
    /// classification top-5. sessionQueue'da senkron çalışır (capture callback'i orada).
    private static func computeDebugFromImage(_ image: UIImage, instability: CGFloat, stable: Bool) -> AutoCaptureDebug {
        guard let cg = image.cgImage else {
            return AutoCaptureDebug(salientBox: nil, classifications: [], instability: instability, stable: stable)
        }
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        // Saliency → anchor box
        var anchor: CGRect? = nil
        let salReq = VNGenerateObjectnessBasedSaliencyImageRequest()
        if (try? handler.perform([salReq])) != nil,
           let obs = salReq.results?.first as? VNSaliencyImageObservation {
            anchor = pickAnchorBox(obs.salientObjects ?? [])
        }
        // Classification → top-5 (anchor ROI veya full frame)
        let classifications = classify(handler: handler, roi: anchor)
        return AutoCaptureDebug(salientBox: anchor, classifications: classifications, instability: instability, stable: stable)
    }

    /// UIImage'i Vision normalized box'a (bottom-left origin) crop eder, %12 padding
    /// bırakır. Box nil veya geçersizse orijinali döner.
    private static func cropToSalientBox(_ image: UIImage, box: CGRect?) -> UIImage {
        guard let box, box.width > 0, box.height > 0 else { return image }
        // Padding ekle — ürün kenarları/gölgesi kesilmesin
        let padX = box.width * 0.12
        let padY = box.height * 0.12
        var b = CGRect(x: box.minX - padX, y: box.minY - padY,
                       width: box.width + padX * 2, height: box.height + padY * 2)
        b = b.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !b.isNull, b.width > 0, b.height > 0 else { return image }

        // Orientation'ı .up'a normalize et (crop koordinatları tutarlı olsun)
        let normalized = image.scareNormalizedUp()
        guard let cg = normalized.cgImage else { return image }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        // Vision bottom-left origin → CGImage top-left origin: y eksenini çevir
        let cropPx = CGRect(x: b.minX * w,
                            y: (1 - b.maxY) * h,
                            width: b.width * w,
                            height: b.height * h).integral
        guard let cropped = cg.cropping(to: cropPx) else { return image }
        return UIImage(cgImage: cropped, scale: normalized.scale, orientation: .up)
    }
}

// MARK: - UIImage orientation helper

private extension UIImage {
    /// Görüntüyü .up orientation'a redraw eder. EXIF orientation'ı piksel
    /// verisine bake eder — crop/koordinat hesapları güvenli olur.
    func scareNormalizedUp() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
