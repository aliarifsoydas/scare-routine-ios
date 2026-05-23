import Foundation
import Vision
import UIKit

/// Vision framework ile UIImage'den barkod tarar.
/// Live AVCaptureMetadataOutput scan'in yedek/fallback'i — foto modunda devreye girer.
///
/// `ProductScanService.detectBarcode`'tan farkı: bu helper YALNIZCA product barcode
/// symbology'lerini (EAN13/EAN8/UPC-E) kabul eder. QR/Code128/Code39 gibi non-product
/// kodlar reddedilir. Payload numeric ve 8-14 hane olmalı.
///
/// Kullanım: AddProductFlowView'de live scan miss verirse veya kullanıcı barkodu
/// kareye almadan fotoyu çekerse, foto üzerinde sessizce çalışır.
@MainActor
enum BarcodeImageScanner {
    /// Bir veya daha fazla resimde barkod ara. İlk valid EAN/UPC'yi döner, yoksa nil.
    /// EAN13/UPC-A/UPC-E/EAN8 öncelikli. QR/Code128 gibi non-product kodlar reddedilir.
    static func scan(images: [UIImage]) async -> String? {
        for img in images {
            if let result = await scan(image: img) {
                return result
            }
        }
        return nil
    }

    static func scan(image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let request = VNDetectBarcodesRequest { req, _ in
                guard let observations = req.results as? [VNBarcodeObservation] else {
                    cont.resume(returning: nil); return
                }
                // Product barcode symbology'lerini öncelikle filtrele.
                // (QR ve Code128 gibi şeyleri at — ürün barkodu olmayabilir)
                let productSymbologies: Set<VNBarcodeSymbology> = [.ean13, .ean8, .upce]
                let candidates = observations.compactMap { obs -> String? in
                    guard productSymbologies.contains(obs.symbology),
                          let payload = obs.payloadStringValue,
                          payload.allSatisfy({ $0.isNumber }),
                          payload.count >= 8, payload.count <= 14
                    else { return nil }
                    return payload
                }
                cont.resume(returning: candidates.first)
            }
            // Tüm product symbology'leri etkinleştir (Apple-supported full set).
            // Filter callback'te yapılır — burada genişletmek detection recall'unu artırır.
            request.symbologies = [.ean13, .ean8, .upce, .codabar, .code39, .code93, .code128]
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }
}
