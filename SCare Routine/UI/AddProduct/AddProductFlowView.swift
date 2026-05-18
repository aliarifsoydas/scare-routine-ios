import SwiftUI
import PhotosUI
import AVFoundation

/// Ürün ekleme akışının ana sheet'i.
///
/// Fazlar:
/// 1. `.camera`     — VisionKit live tarama (barcode/text) veya galeri seçimi
/// 2. `.processing` — Backend recognize + upload
/// 3. `.review`     — Kullanıcı doğruluyor / düzenliyor (ProductReviewView)
/// 4. `.success`    — Animasyonlu onay, 1.5sn sonra dismiss
struct AddProductFlowView: View {
    @Environment(\.dismiss) private var dismiss

    /// Akış başarıyla biterse parent'a eklenmiş ürünü iletir
    var onAdded: ((UserProductResponse) -> Void)? = nil

    // MARK: - State

    @State private var phase: Phase = .camera

    // Kamera state
    @State private var detectedBarcode: String?
    @State private var detectedText: String?
    @State private var capturedImage: UIImage?
    @State private var requestSnapshot: Bool = false
    @State private var permission: CameraPermission = .notDetermined

    // Galeri
    @State private var pickerItem: PhotosPickerItem?

    // Recognize sonucu
    @State private var recognized: ProductRecognizeResponse?
    @State private var uploadedPhotoUrl: String?

    // Error
    @State private var flowError: String?

    enum Phase: Equatable {
        case camera
        case processing
        case review
        case success(productName: String)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                switch phase {
                case .camera:
                    cameraPhase
                case .processing:
                    processingPhase
                case .review:
                    ProductReviewView(
                        recognized: recognized,
                        capturedImage: capturedImage,
                        photoUrl: uploadedPhotoUrl,
                        onSubmitted: { result in
                            phase = .success(productName: result.name ?? result.nickname ?? "Ürün")
                            onAdded?(result)
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                dismiss()
                            }
                        },
                        onRescan: { resetToCamera() }
                    )
                case .success(let name):
                    successPhase(name: name)
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("İptal") {
                        Haptics.light()
                        dismiss()
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
            .alert("Hata", isPresented: errorBinding) {
                Button("Tamam", role: .cancel) { flowError = nil }
                Button("Tekrar dene") { resetToCamera() }
            } message: {
                Text(flowError ?? "Beklenmedik bir hata.")
            }
            .task { await checkPermissionOnAppear() }
        }
    }

    private var navTitle: String {
        switch phase {
        case .camera: return "Ürün ekle"
        case .processing: return "Tanınıyor..."
        case .review: return "Doğrula"
        case .success: return "Eklendi"
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { flowError != nil },
            set: { if !$0 { flowError = nil } }
        )
    }

    // MARK: - Camera phase

    @ViewBuilder
    private var cameraPhase: some View {
        VStack(spacing: 0) {
            // Scanner / fallback
            scannerOrFallback
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .strokeBorder(Theme.divider, lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

            // Bilgi şeridi
            if CameraScannerView.isSupported, permission == .authorized {
                liveStatusBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            Spacer(minLength: 16)

            // Aksiyon barı
            VStack(spacing: 12) {
                if CameraScannerView.isSupported, permission == .authorized {
                    PrimaryActionButton(
                        title: "Fotoğraf çek ve tanı",
                        systemImage: "camera.fill",
                        hapticStyle: .heavy
                    ) {
                        requestSnapshot = true
                    }
                }

                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle")
                        Text("Galeri'den seç")
                            .font(Theme.Typo.button)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius)
                            .strokeBorder(Theme.ink, lineWidth: 1.5)
                    )
                    .foregroundStyle(Theme.ink)
                }
                .onChange(of: pickerItem) { _, newValue in
                    guard let newValue else { return }
                    Task {
                        if let img = await newValue.loadUIImage() {
                            capturedImage = img
                            await processCapturedImage(img)
                        }
                        pickerItem = nil
                    }
                }

                Button {
                    Haptics.light()
                    capturedImage = nil
                    detectedBarcode = nil
                    detectedText = nil
                    // Boş manuel akış — direkt review (manual mode)
                    recognized = ProductRecognizeResponse(
                        product: nil, ingredients: nil, confidence: "none", source: "none"
                    )
                    phase = .review
                } label: {
                    Text("Tarama olmadan manuel ekle")
                        .font(Theme.Typo.body.weight(.medium))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private var scannerOrFallback: some View {
        switch permission {
        case .authorized:
            if CameraScannerView.isSupported {
                CameraScannerView(
                    detectedBarcode: $detectedBarcode,
                    detectedText: $detectedText,
                    mode: .auto,
                    onCapturePhoto: { img in
                        capturedImage = img
                        Task { await processCapturedImage(img) }
                    },
                    requestSnapshot: $requestSnapshot
                )
                .frame(height: 360)
                .onChange(of: detectedBarcode) { _, newValue in
                    guard let bc = newValue, !bc.isEmpty else { return }
                    Task { await processBarcode(bc) }
                }
            } else {
                fallbackPanel(text: "Bu cihazda canlı tarama desteklenmiyor.\nGaleri'den fotoğraf seçebilirsin.")
            }
        case .notDetermined:
            fallbackPanel(text: "Kamera izni gerekli.\n'İzin ver' diyerek devam edebilirsin.") {
                PrimaryActionButton(title: "İzin ver", systemImage: "camera") {
                    Task {
                        permission = await CameraPermission.request()
                    }
                }
            }
        case .denied, .restricted:
            fallbackPanel(text: "Kamera erişimi reddedildi.\nAyarlar'dan açabilirsin.") {
                PrimaryActionButton(title: "Ayarları aç", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fallbackPanel<Action: View>(text: String, @ViewBuilder action: () -> Action = { EmptyView() }) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.inkMute)
            Text(text)
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
            action()
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .background(Theme.surface)
    }

    private var liveStatusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "viewfinder")
                .foregroundStyle(Theme.inkSoft)
            if let bc = detectedBarcode {
                Text("Barkod: \(bc)")
                    .font(Theme.Typo.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            } else if let txt = detectedText {
                Text("Metin yakalandı: \(txt.split(separator: "\n").first.map(String.init) ?? "")")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
            } else {
                Text("Barkod veya etikete doğrult")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.surface)
        )
    }

    // MARK: - Processing phase

    private var processingPhase: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
                .tint(Theme.ink)
            Text("Ürün tanınıyor...")
                .font(Theme.Typo.headline)
                .foregroundStyle(Theme.ink)
            Text(processingSubtitle)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
    }

    private var processingSubtitle: String {
        if detectedBarcode != nil { return "Barkod doğrulanıyor..." }
        if capturedImage != nil { return "Etiket okunuyor ve katalog taranıyor..." }
        return ""
    }

    // MARK: - Success phase

    private func successPhase(name: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.ink)
                    .frame(width: 96, height: 96)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
            }
            .transition(.scale.combined(with: .opacity))

            VStack(spacing: 4) {
                Text("Arşive eklendi")
                    .font(Theme.Typo.title)
                    .foregroundStyle(Theme.ink)
                Text(name)
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
    }

    // MARK: - Pipeline

    private func checkPermissionOnAppear() async {
        permission = CameraPermission.current
        if permission == .notDetermined {
            permission = await CameraPermission.request()
        }
    }

    /// Galeri fotoğrafı geldiğinde:
    /// 1) Local Vision: barcode + OCR (block-level) çıkar
    /// 2) Upload → publicUrl
    /// 3) Recognize çağrısı (ocrBlocks + ocrText + hint + photoUrl)
    private func processCapturedImage(_ image: UIImage) async {
        phase = .processing

        // 1) Local Vision (concurrent)
        async let localBarcode = ProductScanService.shared.detectBarcode(from: image)
        async let localBlocks = ProductScanService.shared.recognizeTextBlocks(from: image)
        let (bc, blocks) = await (localBarcode, localBlocks)
        let ocr = blocks.isEmpty ? nil : blocks.joined(separator: "\n")

        var photoUrl: String? = nil
        do {
            photoUrl = try await ProductScanService.shared.uploadImage(image)
            uploadedPhotoUrl = photoUrl
        } catch {
            // Upload başarısız olsa bile recognize'i hint'lerle deneyelim
            photoUrl = nil
        }

        let (brandHint, nameHint) = ProductScanService.extractBrandAndName(from: ocr ?? "")

        // Hiçbir sinyal yoksa user'a "manuel" akışı açarak yumuşak fallback
        if bc == nil && ocr == nil && photoUrl == nil {
            recognized = ProductRecognizeResponse(
                product: nil, ingredients: nil, confidence: "none", source: "none"
            )
            phase = .review
            return
        }

        do {
            let resp = try await ProductScanService.shared.recognize(
                barcode: bc,
                ocrText: ocr,
                ocrBlocks: blocks.isEmpty ? nil : blocks,
                brandHint: brandHint,
                nameHint: nameHint,
                photoUrl: photoUrl
            )
            recognized = resp
            phase = .review
        } catch {
            // Recognize fail → yumuşak fallback: manuel akışı aç
            recognized = ProductRecognizeResponse(
                product: nil, ingredients: nil, confidence: "none", source: "none"
            )
            phase = .review
        }
    }

    /// Live barcode bulundu — by-barcode lookup → bulunduysa direkt review,
    /// bulamadıysa recognize cascade'ine düş.
    private func processBarcode(_ barcode: String) async {
        // Aynı barcode tekrarsa atlat
        if case .processing = phase { return }
        if case .review = phase { return }

        phase = .processing
        do {
            if let p = try await ProductScanService.shared.lookupByBarcode(barcode) {
                recognized = ProductRecognizeResponse(
                    product: p, ingredients: nil, confidence: "high", source: "obf"
                )
                phase = .review
                return
            }
            // Lookup boşsa: recognize'e düş
            let resp = try await ProductScanService.shared.recognize(barcode: barcode)
            recognized = resp
            phase = .review
        } catch {
            recognized = ProductRecognizeResponse(
                product: nil, ingredients: nil, confidence: "none", source: "none"
            )
            phase = .review
        }
    }

    private func resetToCamera() {
        Haptics.light()
        detectedBarcode = nil
        detectedText = nil
        capturedImage = nil
        recognized = nil
        uploadedPhotoUrl = nil
        flowError = nil
        phase = .camera
    }
}

#Preview {
    AddProductFlowView()
}
