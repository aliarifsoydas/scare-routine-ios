import SwiftUI
import Vision
import VisionKit
import AVFoundation
import PhotosUI

/// VisionKit DataScannerViewController'ı SwiftUI sarmalar.
/// Live barcode + machine-readable text recognition yapar; bulunan ilk veriyi
/// `detectedBarcode` veya `detectedText` binding'lerine yazar.
///
/// Cihaz DataScanner'ı desteklemiyorsa (eski cihazlar, simulator) `isSupported`
/// kontrolü ile dışarıdan handle edilir — bu wrapper kendi başına fallback yapmaz.
struct CameraScannerView: UIViewControllerRepresentable {

    enum Mode: Equatable {
        /// Barcode + text birlikte taranır
        case auto
        /// Sadece barcode (etiket OCR'ı pahalı, hızlı barcode lookup hedefi)
        case barcodeOnly
    }

    @Binding var detectedBarcode: String?
    @Binding var detectedText: String?
    var mode: Mode = .auto
    var onCapturePhoto: ((UIImage) -> Void)? = nil

    /// Snapshot çekme tetiği — UI tarafı `true` set ederse coordinator
    /// preview'tan en yakın frame'i yakalar.
    @Binding var requestSnapshot: Bool

    /// Reset trigger — parent değiştirince (front→back geçişi gibi) scanner restart
    /// olur, eski highlights/recognized items temizlenir, capture state reset olur.
    var resetGeneration: Int = 0

    // MARK: - Hayat döngüsü

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        var types: Set<DataScannerViewController.RecognizedDataType> = [
            .barcode(symbologies: [.ean8, .ean13, .upce, .code128, .code39, .qr])
        ]
        if mode == .auto {
            types.insert(.text(languages: ["tr-TR", "en-US"]))
        }

        let scanner = DataScannerViewController(
            recognizedDataTypes: types,
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            // Highlights kapalı: ekranda görsel overlay yok. OCR arka planda devam.
            // Apple'ın "clear all highlights" public API'sı yok; restart de tutarsız
            // temizliyor — bu nedenle baştan göstermiyoruz.
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if requestSnapshot, !context.coordinator.isCapturing, let onCapturePhoto {
            context.coordinator.isCapturing = true
            context.coordinator.captureSnapshot { image in
                DispatchQueue.main.async {
                    context.coordinator.isCapturing = false
                    self.requestSnapshot = false
                    if let image { onCapturePhoto(image) }
                }
            }
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: CameraScannerView
        weak var scanner: DataScannerViewController?
        private var collectedTextLines: [String] = []
        private var lastEmittedBarcode: String?
        var lastResetGeneration: Int = 0
        var isCapturing: Bool = false

        init(_ parent: CameraScannerView) { self.parent = parent }

        /// Scanner'ı sıfırla — eski highlights, recognized items, capture state temizle.
        /// Front→back geçişinde çağrılır.
        func resetScanner() {
            guard let scanner else { return }
            scanner.stopScanning()
            collectedTextLines.removeAll()
            lastEmittedBarcode = nil
            isCapturing = false
            try? scanner.startScanning()
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                switch item {
                case .barcode(let bc):
                    if let payload = bc.payloadStringValue, payload != lastEmittedBarcode {
                        lastEmittedBarcode = payload
                        DispatchQueue.main.async {
                            self.parent.detectedBarcode = payload
                        }
                    }
                case .text(let txt):
                    let line = txt.transcript
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if line.count >= 3 && !collectedTextLines.contains(line) {
                        collectedTextLines.append(line)
                        // En son 8 satır yeter — gürültüyü kırp
                        if collectedTextLines.count > 8 {
                            collectedTextLines.removeFirst(collectedTextLines.count - 8)
                        }
                        let joined = collectedTextLines.joined(separator: "\n")
                        DispatchQueue.main.async {
                            self.parent.detectedText = joined
                        }
                    }
                @unknown default: break
                }
            }
        }

        // MARK: Snapshot

        /// Preview'tan UIImage çıkar. iOS 17+ DataScannerViewController.capturePhoto(completion:)
        /// destekler; ama bu API throws + async — basit completion ile sarıyoruz.
        func captureSnapshot(_ completion: @escaping (UIImage?) -> Void) {
            guard let scanner else { completion(nil); return }
            Task {
                do {
                    let photo = try await scanner.capturePhoto()
                    completion(photo)
                } catch {
                    completion(nil)
                }
            }
        }
    }
}

// MARK: - Kamera izni helper

enum CameraPermission {
    case authorized, denied, notDetermined, restricted

    static var current: CameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    static func request() async -> CameraPermission {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }
}

// MARK: - PhotosPicker → UIImage helper

/// `PhotosPicker` ile seçilen PhotosPickerItem'dan UIImage çözümle.
extension PhotosPickerItem {
    func loadUIImage() async -> UIImage? {
        guard let data = try? await self.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return nil }
        return image
    }
}
