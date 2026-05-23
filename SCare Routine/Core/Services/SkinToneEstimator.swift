import Foundation
import UIKit
import Vision
import CoreImage

/// Selfie'den cilt tonu tahmini.
///
/// Pipeline (Sony Research skin-tone-extraction yaklaşımı, native Swift port):
///  1. `VNDetectFaceLandmarksRequest` ile yüz + landmark bul
///  2. Cheek + forehead bölgesinden ~500 piksel sample
///  3. Lab color space → ITA (Individual Typology Angle) hesapla
///  4. ITA → Fitzpatrick (1-6) literatür mapping
///
/// On-device, ML modeli yok. Aydınlatma kalitesine duyarlı — manual override şart.
@MainActor
enum SkinToneEstimator {

    struct Result {
        let ita: Double               // Individual Typology Angle (genelde -60 .. +80)
        let avgL: Double              // Lab L* (0..100)
        let avgA: Double              // Lab a*
        let avgB: Double              // Lab b*
        let avgRGB: (r: Double, g: Double, b: Double)  // 0..1 normalized
        let fitzpatrick: Int          // 1..6
        let confidence: Double        // 0..1, sample boyutu + variance üzerinden
        let sampleCount: Int          // kaç piksel kullanıldı
    }

    enum EstimationError: Error, LocalizedError {
        case noFaceFound
        case noLandmarks
        case noUsablePixels
        case visionFailed(Error)

        var errorDescription: String? {
            switch self {
            case .noFaceFound: return L("Yüz bulunamadı. Yüzünü çerçeveye al ve tekrar dene.")
            case .noLandmarks: return L("Yüz tespit edildi ama detaylar okunamadı. Daha iyi aydınlatma dene.")
            case .noUsablePixels: return L("Cilt pikselleri okunamadı. Yüzünü daha yakın getir.")
            case .visionFailed(let err):
                let fmt = L("Görüntü analizi hatası: %@")
                return String(format: fmt, err.localizedDescription)
            }
        }
    }

    // MARK: - Public

    static func estimate(from image: UIImage) async throws -> Result {
        guard let cgImage = image.cgImage else { throw EstimationError.noFaceFound }

        // 1. Vision face landmarks
        let landmarks = try await detectLandmarks(cgImage: cgImage)
        guard let firstFace = landmarks.first else { throw EstimationError.noFaceFound }

        // 2. Cheek + forehead region sample
        let pixels = samplePixels(cgImage: cgImage, face: firstFace)
        guard pixels.count >= 50 else { throw EstimationError.noUsablePixels }

        // 3. Convert to Lab
        var labs: [(L: Double, a: Double, b: Double)] = []
        var rgbs: [(r: Double, g: Double, b: Double)] = []
        for rgb in pixels {
            let lab = rgbToLab(r: rgb.r, g: rgb.g, b: rgb.b)
            labs.append(lab)
            rgbs.append(rgb)
        }

        // 4. Mean Lab
        let avgL = labs.map { $0.L }.reduce(0, +) / Double(labs.count)
        let avgA = labs.map { $0.a }.reduce(0, +) / Double(labs.count)
        let avgB = labs.map { $0.b }.reduce(0, +) / Double(labs.count)

        // 5. ITA
        let ita = atan2(avgL - 50.0, avgB) * 180.0 / .pi

        // 6. Map → Fitzpatrick (Del Bino & Bernerd 2018 + Chardon scale)
        let fitzpatrick = mapItaToFitzpatrick(ita: ita)

        // 7. RGB mean
        let avgR = rgbs.map { $0.r }.reduce(0, +) / Double(rgbs.count)
        let avgG = rgbs.map { $0.g }.reduce(0, +) / Double(rgbs.count)
        let avgBlue = rgbs.map { $0.b }.reduce(0, +) / Double(rgbs.count)

        // 8. Confidence — sample size + Lab variance
        let lVariance = variance(labs.map { $0.L }, mean: avgL)
        // Düşük varyans = piksel'ler homojen = daha güvenilir.
        // 200+ piksel ve <100 varyans güvenli kabul edelim.
        let sizeConf = min(1.0, Double(pixels.count) / 200.0)
        let varConf = max(0.0, min(1.0, 1.0 - lVariance / 200.0))
        let confidence = sizeConf * 0.5 + varConf * 0.5

        return Result(
            ita: ita,
            avgL: avgL,
            avgA: avgA,
            avgB: avgB,
            avgRGB: (avgR, avgG, avgBlue),
            fitzpatrick: fitzpatrick,
            confidence: confidence,
            sampleCount: pixels.count
        )
    }

    // MARK: - Vision

    private static func detectLandmarks(cgImage: CGImage) async throws -> [VNFaceObservation] {
        try await withCheckedThrowingContinuation { cont in
            let req = VNDetectFaceLandmarksRequest { request, error in
                if let error = error {
                    cont.resume(throwing: EstimationError.visionFailed(error))
                    return
                }
                cont.resume(returning: (request.results as? [VNFaceObservation]) ?? [])
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([req])
            } catch {
                cont.resume(throwing: EstimationError.visionFailed(error))
            }
        }
    }

    // MARK: - Pixel sampling

    /// Yüzün yanak (sol+sağ) ve alın bölgelerinden piksel sample eder.
    /// Apple Vision normalized koordinatları kullanıyor (0..1, BL origin).
    private static func samplePixels(
        cgImage: CGImage,
        face: VNFaceObservation
    ) -> [(r: Double, g: Double, b: Double)] {
        let w = cgImage.width
        let h = cgImage.height

        // Yüz bounding box (Vision normalized → pixel coord, BL → TL)
        let faceRect = face.boundingBox
        let fx = Int(faceRect.minX * CGFloat(w))
        let fy = Int((1.0 - faceRect.maxY) * CGFloat(h))  // BL→TL flip
        let fw = Int(faceRect.width * CGFloat(w))
        let fh = Int(faceRect.height * CGFloat(h))

        // 3 region: sol yanak, sağ yanak, alın
        // Yüz kutusunun içinde sabit oranlı sub-rect'ler.
        let regions: [CGRect] = [
            // sol yanak
            CGRect(x: fx + Int(Double(fw) * 0.20),
                   y: fy + Int(Double(fh) * 0.50),
                   width: Int(Double(fw) * 0.15),
                   height: Int(Double(fh) * 0.18)),
            // sağ yanak
            CGRect(x: fx + Int(Double(fw) * 0.65),
                   y: fy + Int(Double(fh) * 0.50),
                   width: Int(Double(fw) * 0.15),
                   height: Int(Double(fh) * 0.18)),
            // alın (kaşların hemen üstü)
            CGRect(x: fx + Int(Double(fw) * 0.30),
                   y: fy + Int(Double(fh) * 0.10),
                   width: Int(Double(fw) * 0.40),
                   height: Int(Double(fh) * 0.15)),
        ]

        guard let data = cgImage.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return [] }
        let bpp = cgImage.bitsPerPixel / 8   // bytes per pixel (4 = RGBA)
        let rowBytes = cgImage.bytesPerRow

        var pixels: [(r: Double, g: Double, b: Double)] = []
        pixels.reserveCapacity(800)

        for rect in regions {
            let stride = max(2, Int(rect.height) / 12)  // grid sample, ~144 px/region
            var y = Int(rect.minY)
            while y < Int(rect.maxY) {
                var x = Int(rect.minX)
                while x < Int(rect.maxX) {
                    if x >= 0, y >= 0, x < w, y < h {
                        let offset = y * rowBytes + x * bpp
                        let r = Double(ptr[offset]) / 255.0
                        let g = Double(ptr[offset + 1]) / 255.0
                        let b = Double(ptr[offset + 2]) / 255.0
                        // Çok karanlık (gölge) veya çok parlak (yansıma) pikselleri at
                        let luma = 0.299 * r + 0.587 * g + 0.114 * b
                        if luma > 0.15 && luma < 0.95 {
                            pixels.append((r, g, b))
                        }
                    }
                    x += stride
                }
                y += stride
            }
        }
        return pixels
    }

    // MARK: - Color math

    /// sRGB → CIE Lab (D65 illuminant).
    /// Reference: https://www.easyrgb.com/en/math.php
    private static func rgbToLab(r: Double, g: Double, b: Double) -> (L: Double, a: Double, b: Double) {
        // sRGB → linear RGB
        func toLinear(_ c: Double) -> Double {
            return c > 0.04045 ? pow((c + 0.055) / 1.055, 2.4) : c / 12.92
        }
        let lr = toLinear(r), lg = toLinear(g), lb = toLinear(b)

        // Linear RGB → XYZ (D65)
        let X = (lr * 0.4124 + lg * 0.3576 + lb * 0.1805) * 100.0
        let Y = (lr * 0.2126 + lg * 0.7152 + lb * 0.0722) * 100.0
        let Z = (lr * 0.0193 + lg * 0.1192 + lb * 0.9505) * 100.0

        // XYZ → Lab (D65 reference white)
        let Xn = 95.047, Yn = 100.000, Zn = 108.883
        func f(_ t: Double) -> Double {
            return t > 0.008856 ? pow(t, 1.0 / 3.0) : (7.787 * t + 16.0 / 116.0)
        }
        let fx = f(X / Xn), fy = f(Y / Yn), fz = f(Z / Zn)
        let L = 116.0 * fy - 16.0
        let a = 500.0 * (fx - fy)
        let bL = 200.0 * (fy - fz)
        return (L, a, bL)
    }

    /// ITA → Fitzpatrick (Del Bino 2013 / Chardon ölçeği).
    /// ITA > 55: Type I (very light)
    /// 41–55: Type II (light)
    /// 28–41: Type III (intermediate)
    /// 10–28: Type IV (tan)
    /// -30..10: Type V (brown)
    /// < -30: Type VI (dark)
    private static func mapItaToFitzpatrick(ita: Double) -> Int {
        switch ita {
        case 55...:    return 1
        case 41..<55:  return 2
        case 28..<41:  return 3
        case 10..<28:  return 4
        case -30..<10: return 5
        default:       return 6
        }
    }

    private static func variance(_ xs: [Double], mean: Double) -> Double {
        guard xs.count > 1 else { return 0 }
        let sum = xs.reduce(0) { $0 + pow($1 - mean, 2) }
        return sum / Double(xs.count - 1)
    }
}
