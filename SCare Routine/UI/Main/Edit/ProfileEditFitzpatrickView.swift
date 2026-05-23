import SwiftUI
import UIKit

/// Cilt tonu (Fitzpatrick) düzenleme sheet'i — 6 ton seçeneği + selfie tahmini.
///
/// Fitzpatrick skalası UV hassasiyeti için kullanılır. Her satır kendi tonunda
/// daireli swatch + TR açıklama gösterir. Backend "fitzpatrick_type": 1..6 bekler.
///
/// Selfie modu: VNDetectFaceLandmarks + Lab/ITA matematiği ile cilt tonu
/// tahmin eder. Tahmin sonucu doğru kart otomatik seçilir, kullanıcı override edebilir.
struct ProfileEditFitzpatrickView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Selfie tahmin state — sistem kamerası (UIImagePicker) ile sheet
    private enum CamPhase { case idle, analyzing, result }
    @State private var camPhase: CamPhase = .idle
    @State private var showCamera: Bool = false
    @State private var estimate: SkinToneEstimator.Result? = nil
    @State private var estimateError: String? = nil

    /// (tip, başlık, alt başlık, swatch rengi)
    private let options: [(Int, String, String, Color)] = [
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
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L("UV hassasiyetini ve SPF önerilerini kişiselleştirmek için cilt tonunu seç."))
                            .font(Theme.Typo.body)
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.top, 4)

                        // Selfie ile tahmin CTA / sonuç
                        selfieEstimateBlock

                        VStack(spacing: 10) {
                            ForEach(options, id: \.0) { opt in
                                fitzCard(type: opt.0,
                                         title: opt.1,
                                         subtitle: opt.2,
                                         swatch: opt.3)
                            }
                        }

                        if let msg = errorMessage {
                            Text(msg)
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.alert)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(L("Cilt tonu"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("İptal")) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(L("Kaydet"), action: save)
                            .disabled(selected == nil)
                            .fontWeight(.semibold)
                    }
                }
            }
            .onAppear {
                selected = appState.currentProfile?.fitzpatrickType
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showCamera) {
            SkinSelfieCameraPicker { image in
                showCamera = false
                analyzeSelfie(image)
            }
        }
    }

    // MARK: - Selfie tahmin bloğu

    @ViewBuilder
    private var selfieEstimateBlock: some View {
        switch camPhase {
        case .idle:
            if let r = estimate {
                estimateResultRow(r)
            } else {
                idleCTA
            }
            if let msg = estimateError {
                Text(msg)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.alert)
            }
        case .analyzing:
            HStack(spacing: 12) {
                ProgressView().tint(Theme.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Analiz ediliyor"))
                        .font(Theme.Typo.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text(L("Yüz tespit + Lab/ITA"))
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                }
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
        case .result:
            if let r = estimate {
                estimateResultRow(r)
            }
        }
    }

    private var idleCTA: some View {
        Button {
            showCamera = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "face.dashed")
                    .font(.system(size: 18))
                Text(L("Selfie ile tahmin et"))
                    .font(Theme.Typo.body.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkMute)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.divider, lineWidth: 1))
            .foregroundStyle(Theme.ink)
        }
        .buttonStyle(PressedScaleButtonStyle())
    }

    private func estimateResultRow(_ r: SkinToneEstimator.Result) -> some View {
        let swatch = Color(red: r.avgRGB.r, green: r.avgRGB.g, blue: r.avgRGB.b)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Circle().fill(swatch).frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(Theme.divider, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: L("Tahmin: Tip %d"), r.fitzpatrick))
                        .font(Theme.Typo.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    // Locale-aware percent format: TR'de "%50", EN'de "50%"
                    Text(String(format: L("ITA %d° · güven %@"), Int(r.ita), r.confidence.formatted(.percent.precision(.fractionLength(0)))))
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .monospacedDigit()
                }
                Spacer()
                Button {
                    showCamera = true
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.inkMute)
                }
            }
            if r.confidence < 0.5 {
                Text(L("Düşük güven — aşağıdan manuel seçmen önerilir."))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.alert)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.divider, lineWidth: 1))
    }

    private func analyzeSelfie(_ image: UIImage) {
        camPhase = .analyzing
        Telemetry.shared.custom("skinTone.capture", props: ["source": "profile_edit"])
        _analyzeSelfieInternal(image)
    }

    private func _analyzeSelfieInternal(_ image: UIImage) {
        estimateError = nil
        Task {
            do {
                let r = try await SkinToneEstimator.estimate(from: image)
                await MainActor.run {
                    self.estimate = r
                    self.selected = r.fitzpatrick   // tahmini otomatik seç
                    self.camPhase = .result
                    Telemetry.shared.custom("skinTone.estimated", props: [
                        "source": "profile_edit",
                        "fitzpatrick": r.fitzpatrick,
                        "ita": Int(r.ita),
                        "confidence": r.confidence,
                        "sample_count": r.sampleCount,
                    ])
                    Telemetry.shared.flush()
                }
                // Selfie + estimate backend'e kaydet (fire-and-forget)
                try? await UserService.shared.submitSkinToneEstimate(
                    image: image,
                    result: r,
                    source: "profile_edit"
                )
            } catch {
                await MainActor.run {
                    self.camPhase = .idle
                    let msg = (error as? LocalizedError)?.errorDescription ?? L("Analiz başarısız.")
                    self.estimateError = msg
                    Telemetry.shared.error("skinTone.failed", message: msg, props: ["source": "profile_edit"])
                    Telemetry.shared.flush()
                }
            }
        }
    }

    private func fitzCard(type: Int, title: String, subtitle: String, swatch: Color) -> some View {
        Button {
            Haptics.selection()
            selected = type
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(swatch)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Circle()
                                .strokeBorder(Theme.divider, lineWidth: 1)
                        )
                    if selected == type {
                        Circle()
                            .strokeBorder(Theme.onAccent, lineWidth: 2)
                            .frame(width: 44, height: 44)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(title))
                        .font(Theme.Typo.headline)
                        .foregroundStyle(selected == type ? Theme.onAccent : Theme.ink)
                    Text(LocalizedStringKey(subtitle))
                        .font(Theme.Typo.caption)
                        .foregroundStyle(selected == type ? Theme.onAccent.opacity(0.75) : Theme.inkSoft)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                ZStack {
                    if selected == type {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(Theme.onAccent)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.4).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(selected == type ? Theme.ink : Theme.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(selected == type ? Color.clear : Theme.divider, lineWidth: 1)
            )
            .shadow(color: selected == type ? Theme.ink.opacity(0.14) : .clear,
                    radius: 10, x: 0, y: 4)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: selected)
        }
        .buttonStyle(PressedScaleButtonStyle())
    }

    private func save() {
        guard let t = selected, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Haptics.light()

        var payload = ProfileUpdateRequest()
        payload.fitzpatrickType = t

        Task {
            do {
                try await UserService.shared.updateProfile(payload)
                await appState.refreshMe()
                Haptics.success()
                dismiss()
            } catch {
                Haptics.error()
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                isSaving = false
            }
        }
    }
}

#Preview {
    ProfileEditFitzpatrickView()
        .environment(AppState())
}
