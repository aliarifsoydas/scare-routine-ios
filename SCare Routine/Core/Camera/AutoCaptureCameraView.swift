/// AutoCaptureCameraController'ın SwiftUI wrapper'ı. HUD overlay ve binding'ler içerir.
///
/// AddProductFlowView (front + back foto capture) için tasarlandı:
///  - Barcode + text recognition (mode .auto) veya sadece barcode (mode .barcodeOnly)
///  - Scene stability detection → auto-capture
///  - HUD: status text, corner brackets, instability dot indicator
///  - Manual shutter button + retake reset
///
/// Tüm state UIKit controller'da yaşar; SwiftUI yalnızca binding ile dinler. Haptic
/// feedback Coordinator içinde — view re-render'larından bağımsız tek atış.

import SwiftUI
import UIKit

// MARK: - Wrapper

struct AutoCaptureCameraView: UIViewControllerRepresentable {

    enum Mode: Equatable {
        /// Barcode + text + auto-capture
        case auto
        /// Sadece barcode (text recognition kapalı — pahalı OCR'ı atla)
        case barcodeOnly
    }

    @Binding var detectedBarcode: String?
    @Binding var detectedText: String?
    var mode: Mode = .auto
    var autoCaptureEnabled: Bool = true
    var onCapturePhoto: (UIImage, AutoCaptureDebug) -> Void

    /// Manuel capture trigger — UI butonu set ederse coordinator capture'ı tetikler.
    /// `updateUIViewController`'da gözlemlenir, tetikten sonra `false`'a döndürülür.
    @Binding var requestManualCapture: Bool

    /// Captured sonrası retake için reset signal — değişince controller state sıfırlanır.
    @Binding var resetTrigger: Int

    /// Auto-capture state UI'a expose etmek için (HUD'da gösterilir)
    @Binding var captureState: AutoCaptureState

    /// Sahne dengesizliği oranı (0..1) — HUD'daki dot indicator'ı sürer
    @Binding var instabilityRatio: CGFloat

    /// Belirgin nesnenin bounding box'ı (Vision normalized, bottom-left origin).
    /// nil → kadrajda belirgin ürün yok. HUD canlı bounding box çizimi için.
    @Binding var salientBox: CGRect?

    // MARK: - Hayat döngüsü

    func makeUIViewController(context: Context) -> AutoCaptureCameraController {
        let vc = AutoCaptureCameraController()
        vc.delegate = context.coordinator
        vc.autoCaptureEnabled = autoCaptureEnabled
        context.coordinator.controller = vc
        context.coordinator.lastResetTrigger = resetTrigger
        return vc
    }

    func updateUIViewController(_ uiViewController: AutoCaptureCameraController, context: Context) {
        // Auto-capture toggle senkronu — binding sonradan değişebilir
        uiViewController.autoCaptureEnabled = autoCaptureEnabled

        // Reset trigger — parent reset attı mı?
        if resetTrigger != context.coordinator.lastResetTrigger {
            context.coordinator.lastResetTrigger = resetTrigger
            uiViewController.resetCaptureState()
        }

        // Manuel capture trigger — UI butonu set ettiyse tetikle
        if requestManualCapture, !context.coordinator.didFireManualThisCycle {
            context.coordinator.didFireManualThisCycle = true
            uiViewController.captureManually()
            // Bayrağı bir sonraki run loop'ta düşür, böylece tek tetik garanti
            DispatchQueue.main.async {
                self.requestManualCapture = false
                context.coordinator.didFireManualThisCycle = false
            }
        }
    }

    static func dismantleUIViewController(_ uiViewController: AutoCaptureCameraController, coordinator: Coordinator) {
        uiViewController.delegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, AutoCaptureCameraControllerDelegate {
        var parent: AutoCaptureCameraView
        weak var controller: AutoCaptureCameraController?

        /// Reset trigger'ın son gözlenen değeri — `updateUIViewController`'da karşılaştırılır
        var lastResetTrigger: Int = 0

        /// Manuel capture bayrağının aynı update cycle'da iki kez ateşlenmesini engeller
        var didFireManualThisCycle: Bool = false

        /// readyToCapture'a geçişte haptic'in iki kez tetiklenmesini engeller
        private var lastStateForHaptic: String = ""

        init(_ parent: AutoCaptureCameraView) { self.parent = parent }

        // MARK: Delegate

        func cameraController(_ controller: AutoCaptureCameraController, didDetectBarcode barcode: String) {
            DispatchQueue.main.async {
                self.parent.detectedBarcode = barcode
            }
        }

        func cameraController(_ controller: AutoCaptureCameraController, didUpdateText textBlocks: [String]) {
            // Auto modu: text recognition açık. barcodeOnly modunda controller hiç emit etmez,
            // yine de defansif olarak burada da filtreliyoruz.
            guard parent.mode == .auto else { return }
            let joined = textBlocks.joined(separator: "\n")
            DispatchQueue.main.async {
                self.parent.detectedText = joined.isEmpty ? nil : joined
            }
        }

        func cameraController(_ controller: AutoCaptureCameraController, didCapturePhoto image: UIImage, debug: AutoCaptureDebug) {
            DispatchQueue.main.async {
                self.parent.onCapturePhoto(image, debug)
            }
        }

        func cameraController(_ controller: AutoCaptureCameraController, didUpdateState state: AutoCaptureState) {
            // Haptic: readyToCapture'a girince medium impact — sadece bu state'e GİRİŞTE
            let stateKey = Self.key(for: state)
            if stateKey == "readyToCapture", lastStateForHaptic != "readyToCapture" {
                Task { @MainActor in
                    let g = UIImpactFeedbackGenerator(style: .medium)
                    g.prepare()
                    g.impactOccurred()
                }
            }
            lastStateForHaptic = stateKey

            DispatchQueue.main.async {
                self.parent.captureState = state
            }
        }

        func cameraController(_ controller: AutoCaptureCameraController, didUpdateInstability ratio: CGFloat) {
            DispatchQueue.main.async {
                self.parent.instabilityRatio = ratio
            }
        }

        func cameraController(_ controller: AutoCaptureCameraController, didUpdateSalientBox box: CGRect?) {
            DispatchQueue.main.async {
                self.parent.salientBox = box
            }
        }

        // State'i string key'e çevir — switch case'in tüm pattern'ini her seferinde
        // yazmamak için.
        private static func key(for state: AutoCaptureState) -> String {
            switch state {
            case .searching: return "searching"
            case .stabilizing: return "stabilizing"
            case .readyToCapture: return "readyToCapture"
            case .capturing: return "capturing"
            case .captured: return "captured"
            case .error: return "error"
            }
        }
    }
}

// MARK: - HUD Overlay

/// Auto-capture HUD — status text + corner brackets + instability dot indicator.
///
/// HUD camera preview'ın üstüne ZStack overlay olarak yerleştirilir. State binding'i
/// `AutoCaptureCameraView`'den gelir; Vision çıktısı UIKit Controller'da işlenir.
struct AutoCaptureHUD: View {
    let state: AutoCaptureState
    let instabilityRatio: CGFloat
    /// Belirgin nesnenin bounding box'ı (Vision normalized, bottom-left origin).
    /// nil → çizilmez. Kullanıcıya "şu nesneyi görüyorum" feedback'i.
    var salientBox: CGRect? = nil

    /// Yeşil bracket'ların pulsing animasyonu için trigger flag
    @State private var pulse: Bool = false

    /// Capturing state'ine geçişte beyaz flash overlay
    @State private var flashOpacity: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 1) Üst — durum etiketi (chip)
                VStack {
                    statusChip
                        .padding(.top, 16)
                    Spacer()
                }

                // 2) Orta — corner brackets (l-shape çerçeve, state'e göre renk)
                cornerBrackets(in: geo.size)

                // 2b) Belirgin nesne bounding box — Vision'ın gördüğü ürünü işaretler
                salientBoxOverlay(in: geo.size)

                // 3) Alt — instability dot indicator
                VStack {
                    Spacer()
                    instabilityIndicator
                        .padding(.bottom, 140) // Shutter button'un üzerinde kalsın
                }

                // 4) Capture flash — capturing state'e geçince beyaz overlay
                Color.white
                    .opacity(flashOpacity)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            pulse = true
        }
        .onChange(of: AutoCaptureCameraView.Coordinator.stateKey(state)) { _, newKey in
            // Capturing'e geçişte 180ms boyunca beyaz flash
            if newKey == "capturing" {
                withAnimation(.easeOut(duration: 0.08)) { flashOpacity = 0.85 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.easeIn(duration: 0.18)) { flashOpacity = 0 }
                }
            }
        }
    }

    // MARK: Status chip

    private var statusChip: some View {
        HStack(spacing: 8) {
            statusDot
            Text(statusText)
                .font(Theme.Typo.caption.weight(.semibold))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule().fill(Theme.canvas.opacity(0.94))
        )
        .overlay(
            Capsule().strokeBorder(Theme.divider, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
        .animation(.easeInOut(duration: 0.18), value: statusText)
    }

    private var statusText: String {
        switch state {
        case .searching: return L("autoCapture.status.searching")
        case .stabilizing: return L("autoCapture.status.stabilizing")
        case .readyToCapture: return L("autoCapture.status.readyToCapture")
        case .capturing: return L("autoCapture.status.capturing")
        case .captured: return L("autoCapture.status.readyToCapture") // Captured kısa süreli, "Hazır!" tutuyoruz
        case .error(let msg): return msg
        }
    }

    /// Status dot rengi — state'e göre değişir, küçük görsel ipucu
    private var statusDot: some View {
        Circle()
            .fill(statusDotColor)
            .frame(width: 8, height: 8)
    }

    private var statusDotColor: Color {
        switch state {
        case .searching: return Theme.inkMute
        case .stabilizing: return Theme.success
        case .readyToCapture: return Theme.success
        case .capturing: return Theme.accent
        case .captured: return Theme.success
        case .error: return Theme.alert
        }
    }

    // MARK: Salient box overlay

    /// Vision'ın tespit ettiği belirgin nesneyi bounding box ile işaretler.
    /// Vision koordinatı normalized + bottom-left origin → SwiftUI top-left'e çevrilir.
    /// Preview `.resizeAspectFill` olduğu için yaklaşık konumlama (görsel cue yeterli).
    @ViewBuilder
    private func salientBoxOverlay(in size: CGSize) -> some View {
        if let box = salientBox, box.width > 0, box.height > 0 {
            let rectW = box.width * size.width
            let rectH = box.height * size.height
            // bottom-left → top-left: y eksenini çevir
            let originX = box.minX * size.width
            let originY = (1 - box.maxY) * size.height
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isReadyOrCapturing ? Theme.success : Color.white.opacity(0.7),
                        style: StrokeStyle(lineWidth: 2.5, dash: isReadyOrCapturing ? [] : [7, 5]))
                .frame(width: rectW, height: rectH)
                .position(x: originX + rectW / 2, y: originY + rectH / 2)
                .animation(.easeOut(duration: 0.15), value: box)
                .allowsHitTesting(false)
        }
    }

    // MARK: Corner brackets

    /// Köşelerde l-shape bracket'lar — frame'i çerçeveler. State'e göre renk + pulsing.
    @ViewBuilder
    private func cornerBrackets(in size: CGSize) -> some View {
        // Frame ölçüsü: kısa kenar * 0.72, 4:3 oran
        let shortSide = min(size.width, size.height)
        let frameWidth = shortSide * 0.78
        let frameHeight = frameWidth * 1.1

        let bracketSize: CGFloat = 30
        let bracketThickness: CGFloat = 3.5

        let isReady = isReadyOrCapturing
        let bracketColor: Color = isReady ? Theme.success : Color.white.opacity(0.55)
        let scale: CGFloat = (isReady && pulse) ? 1.04 : 1.0

        ZStack {
            // 4 köşe — her biri ayrı l-shape Path
            BracketShape(corner: .topLeft, size: bracketSize)
                .stroke(bracketColor, style: StrokeStyle(lineWidth: bracketThickness, lineCap: .round))
                .frame(width: bracketSize, height: bracketSize)
                .position(x: (size.width - frameWidth) / 2 + bracketSize / 2,
                          y: (size.height - frameHeight) / 2 + bracketSize / 2)

            BracketShape(corner: .topRight, size: bracketSize)
                .stroke(bracketColor, style: StrokeStyle(lineWidth: bracketThickness, lineCap: .round))
                .frame(width: bracketSize, height: bracketSize)
                .position(x: size.width - (size.width - frameWidth) / 2 - bracketSize / 2,
                          y: (size.height - frameHeight) / 2 + bracketSize / 2)

            BracketShape(corner: .bottomLeft, size: bracketSize)
                .stroke(bracketColor, style: StrokeStyle(lineWidth: bracketThickness, lineCap: .round))
                .frame(width: bracketSize, height: bracketSize)
                .position(x: (size.width - frameWidth) / 2 + bracketSize / 2,
                          y: size.height - (size.height - frameHeight) / 2 - bracketSize / 2)

            BracketShape(corner: .bottomRight, size: bracketSize)
                .stroke(bracketColor, style: StrokeStyle(lineWidth: bracketThickness, lineCap: .round))
                .frame(width: bracketSize, height: bracketSize)
                .position(x: size.width - (size.width - frameWidth) / 2 - bracketSize / 2,
                          y: size.height - (size.height - frameHeight) / 2 - bracketSize / 2)
        }
        .scaleEffect(scale)
        .animation(
            isReady
                ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                : .easeInOut(duration: 0.25),
            value: scale
        )
    }

    /// readyToCapture veya capturing state'inde brackets yeşil + pulsing
    private var isReadyOrCapturing: Bool {
        switch state {
        case .readyToCapture, .capturing, .captured: return true
        default: return false
        }
    }

    // MARK: Instability indicator

    /// Yatay bar üzerinde dot — 0 (ortada) → 1 (kenarda).
    /// "Sabit tut" mesajının görsel karşılığı.
    private var instabilityIndicator: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 140, height: 4)

                // Center marker (perfect stable target)
                Circle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .offset(x: 140 / 2 - 4)

                // Dot — instability ratio'ya göre kayar
                Circle()
                    .fill(dotColor)
                    .frame(width: 12, height: 12)
                    // ratio 0 = ortada, ratio 1 = en sağda (veya tasarımda offset olarak kullanılır)
                    .offset(x: dotOffset)
                    .animation(.easeOut(duration: 0.12), value: instabilityRatio)
            }

            // Aşırı titreme uyarısı — yalnızca ratio çok yüksekken
            if instabilityRatio > 0.8 {
                Text(L("autoCapture.hint.tooMuchMotion"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.alert)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.canvas.opacity(0.9)))
            }
        }
    }

    /// Dot'un x ofseti — track ortasından başlayıp dengesizlik arttıkça sağ kenara kayar.
    /// Negatif/pozitif kayma simetrik değil, sadece sağa açıyoruz — dengesizliği "mesafe"
    /// olarak görselleştirir.
    private var dotOffset: CGFloat {
        let ratio = max(0, min(1, instabilityRatio))
        // 140 - 12 padding olduğu için max offset 140 - 12 = 128
        return CGFloat(ratio) * (140 - 12)
    }

    /// Dengesizlik arttıkça dot kırmızı, sabit ise yeşil
    private var dotColor: Color {
        if instabilityRatio < 0.25 {
            return Theme.success
        } else if instabilityRatio < 0.6 {
            return Theme.canvas
        } else {
            return Theme.alert
        }
    }
}

// MARK: - Bracket l-shape

/// Tek köşede l-shape bracket çizen Shape. Köşe türüne göre iki segment çizilir.
private struct BracketShape: Shape {
    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    let corner: Corner
    let size: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let s = rect.width
        switch corner {
        case .topLeft:
            // ┌  — yatay üst + dikey sol
            p.move(to: CGPoint(x: 0, y: s))
            p.addLine(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: s, y: 0))
        case .topRight:
            // ┐ — yatay üst + dikey sağ
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: s, y: 0))
            p.addLine(to: CGPoint(x: s, y: s))
        case .bottomLeft:
            // └ — dikey sol + yatay alt
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 0, y: s))
            p.addLine(to: CGPoint(x: s, y: s))
        case .bottomRight:
            // ┘ — dikey sağ + yatay alt
            p.move(to: CGPoint(x: s, y: 0))
            p.addLine(to: CGPoint(x: s, y: s))
            p.addLine(to: CGPoint(x: 0, y: s))
        }
        return p
    }
}

// MARK: - Manual capture button

/// Klasik kamera shutter — 64pt outer + 56pt inner.
/// AddProductFlowView'da bottom-center yerleştirilir; `tap`'te `requestManualCapture = true`.
struct AutoCaptureShutterButton: View {
    /// Coordinator'a manuel capture sinyali gönder
    var onTap: () -> Void

    /// Capturing state'inde butonu disable + ProgressView göster
    var isCapturing: Bool = false

    var body: some View {
        Button {
            Haptics.heavy()
            onTap()
        } label: {
            ZStack {
                // Outer halo
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 78, height: 78)

                // Outer ring (64pt)
                Circle()
                    .strokeBorder(Color.white, lineWidth: 3.5)
                    .frame(width: 64, height: 64)

                // Inner fill (56pt)
                Circle()
                    .fill(Color.white)
                    .frame(width: 56, height: 56)

                if isCapturing {
                    ProgressView()
                        .tint(Theme.ink)
                }
            }
        }
        .disabled(isCapturing)
        .accessibilityLabel(L("Foto çek"))
    }
}

// MARK: - Helper: state key (HUD'ın onChange'i için)

extension AutoCaptureCameraView.Coordinator {
    /// HUD'da `onChange` ile state geçişlerini izlemek için stable string key.
    /// Equatable olmayan associated value'lu enum'da (.error(String)) doğrudan
    /// karşılaştırma cazip değil — burada özetliyoruz.
    static func stateKey(_ state: AutoCaptureState) -> String {
        switch state {
        case .searching: return "searching"
        case .stabilizing: return "stabilizing"
        case .readyToCapture: return "readyToCapture"
        case .capturing: return "capturing"
        case .captured: return "captured"
        case .error: return "error"
        }
    }
}
