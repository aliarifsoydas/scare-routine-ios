import SwiftUI
import UIKit

/// Cilt tonu selfie tahmini — onboarding step.
///
/// Akış:
///  1. View açılır → kamera otomatik başlar (izin diyaloğu gözükür)
///  2. İzin verilirse → inline kamera + shutter butonu
///  3. İzin verilmezse → manuel 6 Fitzpatrick ton seçim ekranı
///  4. Foto çekilince → analyzing → result
struct SkinToneEstimateView: View {
    @Bindable var flow: OnboardingFlow

    private enum Phase {
        case capturing   // varsayılan: kamera açık (veya izin yoksa manuel)
        case analyzing   // çekildi, ITA hesaplanıyor
        case result      // tahmin gösterildi, accept / retake
    }
    @State private var phase: Phase = .capturing
    @State private var capturedImage: UIImage? = nil
    @State private var result: SkinToneEstimator.Result? = nil
    @State private var errorMessage: String? = nil
    @State private var manualSelection: Int? = nil

    @StateObject private var customCamera = SelfieCameraController()

    /// 6 Fitzpatrick tonu (manuel fallback)
    private let manualOptions: [(Int, String, String, Color)] = [
        (1, "Tip 1 — Çok açık", "Hep yanar, asla bronzlaşmaz",
         Color(red: 1.00, green: 0.92, blue: 0.86)),
        (2, "Tip 2 — Açık", "Kolay yanar, az bronzlaşır",
         Color(red: 0.98, green: 0.85, blue: 0.74)),
        (3, "Tip 3 — Açık-orta", "Bazen yanar, kademeli bronzlaşır",
         Color(red: 0.88, green: 0.72, blue: 0.56)),
        (4, "Tip 4 — Orta", "Az yanar, kolay bronzlaşır",
         Color(red: 0.74, green: 0.55, blue: 0.40)),
        (5, "Tip 5 — Koyu", "Nadiren yanar, koyu bronzlaşır",
         Color(red: 0.55, green: 0.37, blue: 0.27)),
        (6, "Tip 6 — Çok koyu", "Asla yanmaz, hep koyu",
         Color(red: 0.30, green: 0.20, blue: 0.15))
    ]

    var body: some View {
        OnboardingStepContainer {
            switch phase {
            case .capturing:
                if customCamera.permissionDenied {
                    manualContent
                } else {
                    cameraContent
                }
            case .analyzing:
                analyzingContent
            case .result:
                resultContent
            }

            if let msg = errorMessage {
                Text(msg)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.alert)
                    .padding(.top, 8)
            }
        } cta: {
            ctaSection
        }
    }

    // MARK: - Phase content

    private var cameraContent: some View {
        VStack(spacing: 16) {
            OnboardingStepHeader(
                title: L("Yüzünü çerçeveye al"),
                subtitle: L("Cilt tonunu otomatik hesaplıyoruz — foto sadece cihazında işlenir."),
                symbol: "viewfinder"
            )
            CameraStageView(controller: customCamera, mode: .selfieFaceOval)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
        }
    }

    private var manualContent: some View {
        VStack(spacing: 16) {
            OnboardingStepHeader(
                title: L("Cilt tonunu seç"),
                subtitle: L("Kameraya izin vermek istemezsen kendin seçebilirsin."),
                symbol: "circle.lefthalf.filled"
            )
            VStack(spacing: 8) {
                ForEach(manualOptions, id: \.0) { opt in
                    manualCard(type: opt.0, title: opt.1, subtitle: opt.2, swatch: opt.3)
                }
            }
        }
    }

    private var analyzingContent: some View {
        VStack(spacing: 18) {
            OnboardingStepHeader(
                title: L("Analiz ediliyor"),
                subtitle: L("Yüz tespit + Lab/ITA hesaplama"),
                symbol: "sparkles"
            )

            if let img = capturedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.divider, lineWidth: 1))
            }
            ProgressView().tint(Theme.ink)
        }
    }

    private var resultContent: some View {
        VStack(spacing: 14) {
            OnboardingStepHeader(
                title: L("Tahminin hazır"),
                subtitle: nil,
                symbol: "checkmark.seal.fill"
            )

            if let r = result {
                resultCard(r)
            }
        }
    }

    private func resultCard(_ r: SkinToneEstimator.Result) -> some View {
        let swatch = Color(red: r.avgRGB.r, green: r.avgRGB.g, blue: r.avgRGB.b)
        return VStack(spacing: 14) {
            HStack(spacing: 14) {
                if let img = capturedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 84, height: 84)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Theme.divider, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Cilt tonun"))
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                    HStack(spacing: 8) {
                        Circle().fill(swatch).frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(Theme.divider, lineWidth: 1))
                        Text(fitzpatrickLabel(r.fitzpatrick))
                            .font(Theme.Typo.headline)
                            .foregroundStyle(Theme.ink)
                    }
                    // Locale-aware percent format: TR'de "%50", EN'de "50%"
                    Text("Tip \(r.fitzpatrick) · ITA \(Int(r.ita))° · güven \(r.confidence, format: .percent.precision(.fractionLength(0)))")
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .monospacedDigit()
                }
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.canvas))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.divider, lineWidth: 1))

            if r.confidence < 0.5 {
                Text(L("Güven düşük — daha aydınlık ortamda tekrar dene veya sonradan manuel düzelt."))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.alert)
            }
        }
    }

    private func manualCard(type: Int, title: String, subtitle: String, swatch: Color) -> some View {
        Button {
            Haptics.selection()
            manualSelection = type
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(swatch)
                        .frame(width: 40, height: 40)
                        .overlay(Circle().strokeBorder(Theme.divider, lineWidth: 1))
                    if manualSelection == type {
                        Circle()
                            .strokeBorder(Theme.onAccent, lineWidth: 2)
                            .frame(width: 40, height: 40)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Typo.headline)
                        .foregroundStyle(manualSelection == type ? Theme.onAccent : Theme.ink)
                    Text(subtitle)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(manualSelection == type ? Theme.onAccent.opacity(0.75) : Theme.inkSoft)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if manualSelection == type {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.onAccent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(manualSelection == type ? Theme.ink : Theme.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(manualSelection == type ? Color.clear : Theme.divider, lineWidth: 1)
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: manualSelection)
        }
        .buttonStyle(PressedScaleButtonStyle())
    }

    // MARK: - CTA

    @ViewBuilder
    private var ctaSection: some View {
        switch phase {
        case .capturing:
            if customCamera.permissionDenied {
                manualCTA
            } else {
                shutterCTA
            }
        case .analyzing:
            EmptyView()
        case .result:
            resultCTA
        }
    }

    private var shutterCTA: some View {
        VStack(spacing: 10) {
            CameraShutterButton(
                isReady: customCamera.isReady,
                isCapturing: customCamera.isCapturing
            ) {
                customCamera.capture { image in
                    if let img = image {
                        capturedImage = img
                        phase = .analyzing
                        analyze(img)
                    }
                }
            }
            Button {
                flow.goNext()
            } label: {
                Text(L("Şimdilik atla"))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkMute)
            }
            .buttonStyle(PressedScaleButtonStyle())
            .track("skinTone.skip")
        }
    }

    private var manualCTA: some View {
        VStack(spacing: 10) {
            OnboardingPrimaryButton(title: L("Devam")) {
                applyManualAndContinue()
            }
            .disabled(manualSelection == nil)
            .opacity(manualSelection == nil ? 0.45 : 1)
            .track("skinTone.manualAccept")
            Button {
                flow.goNext()
            } label: {
                Text(L("Şimdilik atla"))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkMute)
            }
            .buttonStyle(PressedScaleButtonStyle())
            .track("skinTone.skip")
        }
    }

    private var resultCTA: some View {
        VStack(spacing: 10) {
            OnboardingPrimaryButton(title: L("Devam")) {
                applyAndContinue()
            }
            .track("skinTone.accept")
            Button {
                capturedImage = nil
                result = nil
                errorMessage = nil
                phase = .capturing
            } label: {
                Text(L("Tekrar çek"))
                    .font(Theme.Typo.caption.weight(.medium))
                    .foregroundStyle(Theme.inkSoft)
            }
            .buttonStyle(PressedScaleButtonStyle())
            .track("skinTone.retake")
        }
    }

    // MARK: - Actions

    private func analyze(_ image: UIImage) {
        errorMessage = nil
        Task {
            do {
                let r = try await SkinToneEstimator.estimate(from: image)
                await MainActor.run {
                    self.result = r
                    self.phase = .result
                    Telemetry.shared.custom("skinTone.estimated", props: [
                        "source": "onboarding",
                        "fitzpatrick": r.fitzpatrick,
                        "ita": Int(r.ita),
                        "confidence": r.confidence,
                        "sample_count": r.sampleCount,
                    ])
                    Telemetry.shared.flush()
                }
                // Selfie + estimate'i backend'e kaydet (fire-and-forget, UX'i bloklamaz)
                try? await UserService.shared.submitSkinToneEstimate(
                    image: image,
                    result: r,
                    source: "onboarding"
                )
            } catch {
                await MainActor.run {
                    self.phase = .capturing
                    let msg = (error as? LocalizedError)?.errorDescription ?? "Analiz başarısız."
                    self.errorMessage = msg
                    self.capturedImage = nil
                    Telemetry.shared.error("skinTone.failed", message: msg, props: ["source": "onboarding"])
                    Telemetry.shared.flush()
                }
            }
        }
    }

    private func applyAndContinue() {
        guard let r = result else { return }
        flow.estimatedFitzpatrick = r.fitzpatrick
        flow.estimatedSkinToneConfidence = r.confidence
        flow.goNext()
    }

    private func applyManualAndContinue() {
        guard let t = manualSelection else { return }
        flow.estimatedFitzpatrick = t
        flow.estimatedSkinToneConfidence = 1.0   // manuel seçim → tam güven
        Telemetry.shared.custom("skinTone.manual", props: ["fitzpatrick": t])
        Telemetry.shared.flush()
        flow.goNext()
    }

    private func fitzpatrickLabel(_ t: Int) -> String {
        switch t {
        case 1: return "Tip 1 · Çok açık"
        case 2: return "Tip 2 · Açık"
        case 3: return "Tip 3 · Açık-orta"
        case 4: return "Tip 4 · Orta"
        case 5: return "Tip 5 · Koyu"
        case 6: return "Tip 6 · Çok koyu"
        default: return "Tip \(t)"
        }
    }
}
