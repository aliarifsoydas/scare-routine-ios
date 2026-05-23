import SwiftUI
import AVFoundation
import UIKit
import Combine

/// Selfie kamera — mirror'lanmış preview + oval yüz guide.
///
/// AVFoundation tabanlı custom UI. Native UIImagePickerController'a benzeri,
/// ama:
///  - Preview yatay mirror (selfie standardı)
///  - Capture sonrası foto da mirror'lanır (preview ile tutarlı)
///  - Oval yüz guide overlay
///  - "Yüzünü çerçeveye al" hint metni
///
/// Kullanım:
///   .sheet(isPresented: $showCamera) {
///       SelfieCameraView { image in
///           // image is mirrored UIImage
///       }
///   }
struct SelfieCameraView: View {
    /// Foto çekildiğinde çağrılır. nil = user iptal etti.
    var onCaptured: (UIImage?) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = SelfieCameraController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Camera preview
            SelfieCameraPreview(controller: controller)
                .ignoresSafeArea()
                .onAppear { controller.start() }
                .onDisappear { controller.stop() }

            // Oval face guide overlay (brand-tinted dim + warm cream outline + soft glow)
            faceGuideOverlay

            // Top bar (compact title + cancel)
            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }

            // Permission denied overlay
            if controller.permissionDenied {
                permissionDeniedCard
            }
        }
        .interactiveDismissDisabled(false)
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            // Compact branded title chip — center
            HStack(spacing: 8) {
                Image(systemName: "face.dashed")
                    .font(.system(size: 13, weight: .semibold))
                Text(L("Selfie modu"))
                    .font(Theme.Typo.caption.weight(.semibold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(Theme.canvas)
            )
            .overlay(
                Capsule().strokeBorder(Theme.divider, lineWidth: 1)
            )

            // Cancel — left
            HStack {
                Button {
                    Haptics.light()
                    controller.stop()
                    onCaptured(nil)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.canvas))
                        .overlay(Circle().strokeBorder(Theme.divider, lineWidth: 1))
                }
                .buttonStyle(PressedScaleButtonStyle())
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 22) {
            // Hint chip — branded surface
            HStack(spacing: 8) {
                if !controller.isReady {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Theme.ink)
                } else {
                    Circle()
                        .fill(Theme.success)
                        .frame(width: 8, height: 8)
                }
                Text(controller.isReady ? L("Yüzünü ovale yerleştir, ışık yüzüne gelsin") : L("Kamera açılıyor..."))
                    .font(Theme.Typo.caption.weight(.medium))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Theme.canvas)
            )
            .overlay(
                Capsule().strokeBorder(Theme.divider, lineWidth: 1)
            )

            shutterButton
        }
        .padding(.bottom, 36)
    }

    // MARK: - Oval guide

    private var faceGuideOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let ovalWidth = w * 0.72
            let ovalHeight = ovalWidth * 1.25

            ZStack {
                // Dim outside oval — warm dim (Theme.ink ~ dusty bordo, opacity)
                Rectangle()
                    .fill(Theme.ink.opacity(0.35))
                    .reverseMask {
                        Ellipse()
                            .frame(width: ovalWidth, height: ovalHeight)
                    }
                    .ignoresSafeArea()

                // Soft glow halo (subtle, brand-cream)
                Ellipse()
                    .strokeBorder(Theme.canvas.opacity(0.5), lineWidth: 18)
                    .frame(width: ovalWidth + 24, height: ovalHeight + 24)
                    .blur(radius: 8)

                // Oval outline — warm cream
                Ellipse()
                    .strokeBorder(Theme.canvas, lineWidth: 2.5)
                    .frame(width: ovalWidth, height: ovalHeight)
            }
        }
    }

    // MARK: - Shutter

    private var shutterButton: some View {
        Button {
            Haptics.heavy()
            controller.capture { image in
                guard let img = image else { return }
                onCaptured(img)
                dismiss()
            }
        } label: {
            ZStack {
                // Outer halo
                Circle()
                    .fill(Theme.canvas.opacity(0.25))
                    .frame(width: 86, height: 86)
                // Ring
                Circle()
                    .strokeBorder(Theme.canvas, lineWidth: 3.5)
                    .frame(width: 74, height: 74)
                // Inner accent
                Circle()
                    .fill(Theme.canvas)
                    .frame(width: 58, height: 58)
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.surface, lineWidth: 1)
                    )
                if controller.isCapturing {
                    ProgressView().tint(Theme.ink)
                }
            }
        }
        .buttonStyle(PressedScaleButtonStyle())
        .disabled(!controller.isReady || controller.isCapturing)
        .opacity(controller.isReady ? 1.0 : 0.5)
        .accessibilityLabel(L("Foto çek"))
    }

    // MARK: - Permission denied

    private var permissionDeniedCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.ink)
                .padding(18)
                .background(Circle().fill(Theme.surface))
            VStack(spacing: 6) {
                Text(L("Kamera erişimi yok"))
                    .font(Theme.Typo.headline)
                    .foregroundStyle(Theme.ink)
                Text(L("Ayarlar'dan kamera iznini aç."))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(L("Ayarları aç"))
                    .font(Theme.Typo.button)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(PressedScaleButtonStyle())
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
        .padding(36)
    }
}

// MARK: - View helper for inverse mask

private struct ReverseMask<Mask: View>: ViewModifier {
    let mask: Mask
    func body(content: Content) -> some View {
        content.mask {
            Rectangle()
                .overlay(mask.blendMode(.destinationOut))
        }
    }
}

private extension View {
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        modifier(ReverseMask(mask: mask()))
    }
}

// MARK: - Camera controller (AVFoundation)

@MainActor
final class SelfieCameraController: NSObject, ObservableObject {
    @Published var isReady: Bool = false
    @Published var isCapturing: Bool = false
    @Published var permissionDenied: Bool = false
    /// Setup sırasında hata olursa açıkça UI'da gösterilir
    @Published var setupError: String? = nil
    /// CameraStageView mode'una göre değişir. setup() öncesi parent set eder.
    var cameraPosition: AVCaptureDevice.Position = .front

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var captureCompletion: ((UIImage?) -> Void)?

    private var isSettingUp = false
    func start() {
        print("[Camera] start() called — session.isRunning=\(session.isRunning) isReady=\(isReady) position=\(cameraPosition.rawValue) isSettingUp=\(isSettingUp)")
        // Guard: zaten setup yapılıyor veya session running ise tekrar yapma.
        // İki paralel setupSession → "Multiple AVCaptureInputs" exception.
        if isSettingUp {
            print("[Camera] start() SKIPPED — setup already in progress")
            return
        }
        if session.isRunning && isReady {
            print("[Camera] start() SKIPPED — already running")
            return
        }
        if !session.isRunning {
            isReady = false
        }
        isSettingUp = true
        Task {
            await requestPermissionAndSetup()
            isSettingUp = false
        }
    }

    func stop() {
        print("[Camera] stop() called — session.isRunning=\(session.isRunning)")
        isReady = false
        if session.isRunning {
            Task.detached { [session] in
                session.stopRunning()
                print("[Camera] session stopped")
            }
        }
    }

    private func requestPermissionAndSetup() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("[Camera] authorization status = \(status.rawValue) (authorized=\(status == .authorized))")
        switch status {
        case .authorized:
            await setupSession()
        case .notDetermined:
            print("[Camera] requesting access...")
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            print("[Camera] access granted = \(granted)")
            if granted {
                await setupSession()
            } else {
                permissionDenied = true
            }
        case .denied, .restricted:
            print("[Camera] permission DENIED/RESTRICTED")
            permissionDenied = true
        @unknown default:
            permissionDenied = true
        }
    }

    private func setupSession() async {
        let position = cameraPosition
        print("[Camera] setupSession start, position=\(position.rawValue)")
        let (ok, errMsg): (Bool, String?) = await withCheckedContinuation { (cont: CheckedContinuation<(Bool, String?), Never>) in
            Task.detached { [session, photoOutput] in
                let discovery = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInTrueDepthCamera, .builtInDualCamera, .builtInWideAngleCamera],
                    mediaType: .video,
                    position: position
                )
                print("[Camera] discovery devices: \(discovery.devices.map { "\($0.localizedName)" })")
                guard let device = discovery.devices.first else {
                    print("[Camera] FAIL: discovery boş")
                    cont.resume(returning: (false, L("Front kamera bulunamadı")))
                    return
                }
                print("[Camera] using device: \(device.localizedName)")
                guard let input = try? AVCaptureDeviceInput(device: device) else {
                    print("[Camera] FAIL: input açılamadı")
                    cont.resume(returning: (false, L("Kamera input açılamadı")))
                    return
                }
                session.beginConfiguration()
                session.sessionPreset = .photo
                session.inputs.forEach { session.removeInput($0) }
                session.outputs.forEach { session.removeOutput($0) }
                guard session.canAddInput(input) else {
                    session.commitConfiguration()
                    print("[Camera] FAIL: canAddInput false")
                    cont.resume(returning: (false, L("Session input kabul etmedi")))
                    return
                }
                session.addInput(input)
                if session.canAddOutput(photoOutput) {
                    session.addOutput(photoOutput)
                }
                session.commitConfiguration()
                session.startRunning()
                print("[Camera] session.startRunning() called, isRunning=\(session.isRunning)")
                cont.resume(returning: (true, nil))
            }
        }
        if ok {
            isReady = true
            setupError = nil
            print("[Camera] setupSession SUCCESS, isReady=true")
        } else {
            isReady = false
            setupError = errMsg
            print("[Camera] setupSession FAIL: \(errMsg ?? "?")")
        }
    }

    func capture(completion: @escaping (UIImage?) -> Void) {
        guard isReady, !isCapturing else { completion(nil); return }
        isCapturing = true
        captureCompletion = completion

        let settings = AVCapturePhotoSettings()
        // Daha sade — flash off, sade jpg
        settings.flashMode = .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

extension SelfieCameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let imageData = photo.fileDataRepresentation()
        let raw = imageData.flatMap { UIImage(data: $0) }
        // Mirror et — preview mirror'lanmış olduğu için kullanıcı algısıyla foto da
        // mirror'lı kaydedilmeli (selfie standardı, Snapchat/Instagram gibi).
        let mirrored: UIImage? = raw.flatMap { img in
            guard let cg = img.cgImage else { return img }
            return UIImage(cgImage: cg, scale: img.scale, orientation: .leftMirrored)
        }
        Task { @MainActor in
            self.isCapturing = false
            self.captureCompletion?(mirrored)
            self.captureCompletion = nil
        }
    }
}

// MARK: - Preview layer (UIViewRepresentable)

struct SelfieCameraPreview: UIViewRepresentable {
    let controller: SelfieCameraController

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = controller.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        // Mirror preview — selfie standardı
        if let conn = view.videoPreviewLayer.connection, conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = true
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
