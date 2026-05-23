import SwiftUI
import AVFoundation
import UIKit
import Combine

/// Tek kamera UI konsepti. Tüm uygulamada aynı görsel dil:
///  - Inline preview (sheet/cover değil, parent layout'una otur)
///  - Branded oval / rect overlay (mode'a göre)
///  - Front camera için otomatik mirror (preview + capture)
///  - Üst başlık ve alt aksiyon parent'tan gelir — modal/full-screen modu yok
///
/// Kullanım:
///   @StateObject var camera = SelfieCameraController()
///
///   CameraStageView(controller: camera, mode: .selfieFaceOval)
///   Button("Çek") {
///     camera.capture { image in ... }
///   }
struct CameraStageView: View {
    enum Mode {
        /// Front camera, mirror, oval yüz guide
        case selfieFaceOval
        /// Front camera, mirror, rect guide (geniş selfie)
        case selfieRect
        /// Back camera, normal (genel foto)
        case basic
    }

    /// Parent owner — shutter trigger ve state ona ait.
    @ObservedObject var controller: SelfieCameraController
    let mode: Mode

    var body: some View {
        ZStack {
            Color.black

            CameraStagePreview(controller: controller)
                .onAppear {
                    controller.cameraPosition = (mode == .basic) ? .back : .front
                    controller.start()
                }
                .onDisappear { controller.stop() }

            overlay

            // Hint chip — sadece yükleniyor / permission denied state'leri için
            VStack {
                Spacer()
                stateChip
                    .padding(.bottom, 14)
            }

            if controller.permissionDenied {
                permissionDeniedCard.transition(.opacity)
            } else if let setupErr = controller.setupError {
                setupErrorCard(setupErr).transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlay: some View {
        switch mode {
        case .selfieFaceOval: ovalOverlay
        case .selfieRect: rectOverlay
        case .basic: EmptyView()
        }
    }

    private var ovalOverlay: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let ovalW = s * 0.78
            let ovalH = ovalW * 1.18
            ZStack {
                // Soft dim — sade, glow yok
                Rectangle()
                    .fill(Theme.ink.opacity(0.32))
                    .reverseMask {
                        Ellipse().frame(width: ovalW, height: ovalH)
                    }
                // İnce outline — sade ve minimal
                Ellipse()
                    .strokeBorder(Theme.canvas.opacity(0.85), lineWidth: 1.5)
                    .frame(width: ovalW, height: ovalH)
            }
        }
    }

    private var rectOverlay: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let w = s * 0.88
            let h = w
            ZStack {
                Rectangle()
                    .fill(Theme.ink.opacity(0.32))
                    .reverseMask {
                        RoundedRectangle(cornerRadius: 18).frame(width: w, height: h)
                    }
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Theme.canvas.opacity(0.85), lineWidth: 1.5)
                    .frame(width: w, height: h)
            }
        }
    }

    @ViewBuilder
    private var stateChip: some View {
        if !controller.isReady && !controller.permissionDenied {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7).tint(Theme.ink)
                Text(L("Kamera açılıyor..."))
                    .font(Theme.Typo.caption.weight(.medium))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.canvas))
            .overlay(Capsule().strokeBorder(Theme.divider, lineWidth: 1))
        }
    }

    private func setupErrorCard(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.alert)
            Text(L("Kamera başlatılamadı"))
                .font(Theme.Typo.headline)
                .foregroundStyle(Theme.ink)
            Text(msg)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.canvas))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.divider, lineWidth: 1))
        .padding(20)
    }

    private var permissionDeniedCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.ink)
                .padding(14)
                .background(Circle().fill(Theme.surface))
            Text(L("Kamera erişimi yok"))
                .font(Theme.Typo.headline)
                .foregroundStyle(Theme.ink)
            Text(L("Ayarlar'dan kamera iznini aç."))
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(L("Ayarları aç"))
                    .font(Theme.Typo.button)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(PressedScaleButtonStyle())
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.canvas))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.divider, lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        .padding(20)
    }
}

// MARK: - Reverse mask

private struct CSReverseMask<Mask: View>: ViewModifier {
    let mask: Mask
    func body(content: Content) -> some View {
        content.mask { Rectangle().overlay(mask.blendMode(.destinationOut)) }
    }
}
private extension View {
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        modifier(CSReverseMask(mask: mask()))
    }
}

// MARK: - Preview layer

struct CameraStagePreview: UIViewRepresentable {
    let controller: SelfieCameraController

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.videoPreviewLayer.session = controller.session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        // Restart sırasında session kaybolmuşsa tekrar bağla
        if uiView.videoPreviewLayer.session !== controller.session {
            uiView.videoPreviewLayer.session = controller.session
        }
        if let conn = uiView.videoPreviewLayer.connection, conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = (controller.cameraPosition == .front)
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Branded shutter button (reusable)

/// Tüm kamera ekranlarında aynı shutter — caller buton tetikler.
struct CameraShutterButton: View {
    let isReady: Bool
    let isCapturing: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.heavy()
            action()
        } label: {
            ZStack {
                Circle().fill(Theme.ink.opacity(0.08)).frame(width: 86, height: 86)
                Circle().strokeBorder(Theme.ink, lineWidth: 3).frame(width: 74, height: 74)
                Circle().fill(Theme.ink).frame(width: 58, height: 58)
                if isCapturing {
                    ProgressView().tint(Theme.onAccent)
                }
            }
        }
        .buttonStyle(PressedScaleButtonStyle())
        .disabled(!isReady || isCapturing)
        .opacity(isReady ? 1.0 : 0.5)
        .accessibilityLabel(L("Foto çek"))
    }
}
