/// Apple WWDC "Recognizing Objects in Live Capture" pattern'ine dayanan
/// scene stability detector.
///
/// AVCaptureVideoDataOutputSampleBufferDelegate her frame için Vision
/// framework üzerinden bir önceki frame'e göre translation hesaplar
/// (VNImageTranslationAlignmentObservation.alignmentTransform.tx/.ty).
/// Bu detector son N frame'in translation'larını biriktirir; ortalama
/// Manhattan distance threshold altına düştüğünde sahne "stable" sayılır
/// ve auto-capture tetiklenebilir.
///
/// Dependency: sadece Foundation + CoreGraphics.
/// Thread-safety: yok — caller tek queue'dan (örn. capture queue) çağırmalı.

import Foundation
import CoreGraphics

final class SceneStabilityDetector {

    // MARK: - Configuration

    /// Stability kararı için bakılacak son frame sayısı. Default: 15 (Apple WWDC pattern).
    let maximumHistoryLength: Int

    /// Manhattan distance threshold (piksel). Default: 20.
    let stabilityThreshold: CGFloat

    // MARK: - State

    /// Son N frame'in translation point'leri. En eski = index 0, en yeni = son index.
    private var transpositionHistory: [CGPoint] = []

    // MARK: - Lifecycle

    init(maximumHistoryLength: Int = 15, stabilityThreshold: CGFloat = 20.0) {
        self.maximumHistoryLength = maximumHistoryLength
        self.stabilityThreshold = stabilityThreshold
        // Allocation'ı en başta yap, runtime'da realloc olmasın.
        self.transpositionHistory.reserveCapacity(maximumHistoryLength)
    }

    // MARK: - Recording

    /// AVCapture frame'den çıkarılan translation point'ini ekle.
    /// History dolduktan sonra en eski entry düşer (FIFO).
    func record(_ transposition: CGPoint) {
        transpositionHistory.append(transposition)
        if transpositionHistory.count > maximumHistoryLength {
            // Sadece en eski elemanı at — ufak history boyutunda removeFirst() yeterli.
            transpositionHistory.removeFirst(transpositionHistory.count - maximumHistoryLength)
        }
    }

    /// History'yi sıfırla. Capture sonrası veya re-arm için kullan.
    func reset() {
        transpositionHistory.removeAll(keepingCapacity: true)
    }

    // MARK: - State

    /// Son N frame stable ise true. History dolu değilse her zaman false.
    var isStable: Bool {
        guard transpositionHistory.count == maximumHistoryLength else { return false }
        return manhattanDistance < stabilityThreshold
    }

    /// History size. Debug/UI feedback için (örn. progress bar).
    var historyCount: Int {
        transpositionHistory.count
    }

    /// Stability progress (0.0 - 1.0). UI HUD'unda "yaklaşıyor" göstergesi için.
    /// 0 = perfect stable (hiç hareket yok), 1 = unstable (threshold'da veya üstünde).
    /// History dolmamışsa 1.0 döner (henüz stable kabul edilemez).
    var instabilityRatio: CGFloat {
        guard transpositionHistory.count == maximumHistoryLength else { return 1.0 }
        guard stabilityThreshold > 0 else { return 1.0 }
        let ratio = manhattanDistance / stabilityThreshold
        return min(max(ratio, 0.0), 1.0)
    }

    // MARK: - Private

    /// History'deki tx/ty ortalamalarının Manhattan distance'ı.
    /// Caller history dolu olduğundan emin olmalı (yoksa 0 döner).
    private var manhattanDistance: CGFloat {
        let count = transpositionHistory.count
        guard count > 0 else { return 0 }

        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for point in transpositionHistory {
            sumX += point.x
            sumY += point.y
        }

        let countCG = CGFloat(count)
        let avgX = sumX / countCG
        let avgY = sumY / countCG
        return abs(avgX) + abs(avgY)
    }
}
