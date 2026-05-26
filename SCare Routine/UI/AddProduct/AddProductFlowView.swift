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
    /// Akışın çalışma modu.
    ///
    /// - `addToArchive`: klasik davranış. Review sonunda `ProductReviewView`
    ///   açılır, kullanıcı onaylayınca ürün otomatik olarak arşive eklenir.
    /// - `quickScan`: Quick Scan akışı. Review sonunda `QuickScanResultPanel`
    ///   açılır, ürün arşive otomatik EKLENMEZ; sadece fit-score önizlemesi
    ///   gösterilir. Kullanıcı isterse panel içinden arşive ekleyebilir.
    enum Mode {
        case addToArchive
        case quickScan
    }

    @Environment(\.dismiss) private var dismiss

    /// Akışın hangi modda çalışacağı. Varsayılan davranış değişmedi.
    var mode: Mode = .addToArchive

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

    // AutoCapture state — self-managed AVCaptureSession + scene stability
    @State private var autoCaptureState: AutoCaptureState = .searching
    @State private var instabilityRatio: CGFloat = 1.0
    @State private var autoCaptureResetTrigger: Int = 0
    @State private var autoCaptureSalientBox: CGRect?
    /// Son capture'ın Vision debug metadata'sı — recognize request'e eklenir (fine-tune).
    @State private var lastCaptureDebug: AutoCaptureDebug?

    // Galeri
    @State private var pickerItem: PhotosPickerItem?
    @State private var backPickerItem: PhotosPickerItem?

    // Front foto upload + OCR (recognize'a kadar geçici tutulur)
    @State private var frontPhotoKey: String?
    @State private var frontOcrBlocks: [String]?
    @State private var frontBrandHint: String?
    @State private var frontNameHint: String?

    // Speculative pipeline — front foto işlenirken kullanıcı arka çekerken
    // arka planda devam eden işler. Recognize hızlanır (~3-5s tasarruf).
    @State private var frontUploadTask: Task<ProductScanService.UploadedImage?, Never>?
    @State private var frontFpTask: Task<[Float]?, Never>?
    @State private var frontFpCleanTask: Task<(image: UIImage, vec: [Float])?, Never>?
    @State private var speculativeRecognizeTask: Task<ProductRecognizeResponse?, Never>?

    /// Barkod live scanner'da bulundu ama by-barcode lookup'ı miss verdi.
    /// Kullanıcı bu state'de fotoyu çekince barkodu da recognize'a yollarız.
    @State private var pendingBarcode: String?
    @State private var barcodeMissBanner: Bool = false

    // Arka etiket — opsiyonel; INCI panel için Vision multipass'a verir
    @State private var capturedBackImage: UIImage?
    @State private var backPhotoKey: String?
    @State private var backOcrBlocks: [String]?

    // Recognize sonucu
    @State private var recognized: ProductRecognizeResponse?
    @State private var uploadedPhotoUrl: String?

    /// Ön foto çekildi mi? Çekildiyse aynı .camera phase'inde "şimdi arkayı çek" UI'ı
    /// gösteririz; bu sayede `DataScannerViewController` unmount olmaz, camera warmup
    /// gecikmesi (~2-3s) yaşamayız.
    @State private var frontCaptured: Bool = false

    // (Eski scannerResetGen kaldırıldı — AutoCaptureCameraView için
    // autoCaptureResetTrigger kullanılır.)

    /// Front foto çekildiği anda 1.2s kısa bir overlay feedback göster ("Ön çekildi")
    /// → kullanıcı geçişi net fark eder.
    @State private var showFrontCapturedFlash: Bool = false

    // Error
    @State private var flowError: String?

    enum Phase: Equatable {
        case camera                 // Ön + arka tek phase — frontCaptured flag UI'ı değiştirir
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
                    if mode == .quickScan {
                        // Quick Scan akışı: recognize sonucu var → fit-score önizleme paneli.
                        // Bu panel arşive otomatik EKLEMEZ; kullanıcı isterse onAddToArchive
                        // ile mevcut addToArchive akışını tetikler.
                        QuickScanResultPanel(
                            productId: recognized?.product?.id ?? "",
                            initialResult: recognized,
                            capturedImage: capturedImage,
                            photoUrl: uploadedPhotoUrl,
                            onAddToArchive: {
                                // Kullanıcı yine de arşive eklemek istiyor → klasik review
                                // davranışını tetikle (current ProductReviewView path).
                                Task { await quickScanAddToArchive() }
                            },
                            onRescan: { resetToCamera() },
                            onDismiss: { dismiss() },
                            onManualEntry: {
                                // Düşük confidence → kullanıcı yanlış tanımayı reddedip
                                // manuel arama yapmak istedi. Quick Scan akışında ayrı bir
                                // manuel girdi ekranı yok; kullanıcıyı kameraya geri
                                // yollayıp orada "Manuel ekle" butonunu kullanmasını
                                // sağlıyoruz (tek doğru manuel akış noktası).
                                resetToCamera()
                            }
                        )
                    } else {
                        ProductReviewView(
                            recognized: recognized,
                            capturedImage: capturedImage,
                            photoUrl: uploadedPhotoUrl,
                            onSubmitted: { result in
                                if let attemptId = recognized?.attemptId {
                                    Task {
                                        await ProductScanService.shared.confirmRecognition(
                                            attemptId: attemptId, correct: true
                                        )
                                    }
                                }
                                phase = .success(productName: result.name ?? result.nickname ?? L("Ürün"))
                                onAdded?(result)
                                Task {
                                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                                    dismiss()
                                }
                            },
                            onRescan: { resetToCamera() }
                        )
                    }
                case .success(let name):
                    successPhase(name: name)
                }

                if showFrontCapturedFlash {
                    Color.white.opacity(0.85).ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: showFrontCapturedFlash)
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("İptal")) {
                        Haptics.light()
                        speculativeRecognizeTask?.cancel()
                        frontUploadTask?.cancel()
                        frontFpTask?.cancel()
                        frontFpCleanTask?.cancel()
                        dismiss()
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
            .alert(L("Hata"), isPresented: errorBinding) {
                Button(L("Tamam"), role: .cancel) { flowError = nil }
                Button(L("Tekrar dene")) { resetToCamera() }
            } message: {
                Text(flowError ?? L("Beklenmedik bir hata."))
            }
            .task {
                ProductScanService.shared.prewarmVisionModels()
                await checkPermissionOnAppear()
            }
        }
    }

    private var navTitle: String {
        switch phase {
        case .camera: return frontCaptured ? L("Arka etiket") : L("Ürün ekle")
        case .processing: return L("Tanınıyor")
        case .review: return L("Doğrula")
        case .success: return L("Eklendi")
        }
    }

    /// Tek satır durum mesajı — kameranın altında.
    private var currentCaption: String {
        if barcodeMissBanner, let bc = pendingBarcode {
            return String(format: L("Barkod %@ — fotoğrafla devam"), bc)
        }
        if frontCaptured { return L("Arka etiketi kareye al") }
        if detectedBarcode != nil { return L("Barkod yakalandı") }
        return L("Ürünü kareye sığdır")
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { flowError != nil },
            set: { if !$0 { flowError = nil } }
        )
    }

    // MARK: - Camera phase
    //
    // Sade: 1:1 kamera üstte, durum mesajı, primary "Çek" butonu, galeri ve manuel.

    @ViewBuilder
    private var cameraPhase: some View {
        VStack(spacing: 0) {
            // Front captured banner — ön çekildi proof + arkayı çek mesajı
            if frontCaptured, let img = capturedImage {
                HStack(spacing: 12) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Ön yüz çekildi"))
                            .font(Theme.Typo.caption.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(L("Şimdi arka etiketi çek"))
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.surface))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            // Kamera viewport — 1:1 aspect ratio, fit parent width
            scannerOrFallback
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .strokeBorder(Theme.divider, lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)

            // Caption — tek satır durum (kompakt)
            if permission == .authorized {
                HStack(spacing: 6) {
                    Circle()
                        .fill(barcodeMissBanner ? Theme.alert : Theme.inkSoft)
                        .frame(width: 5, height: 5)
                    Text(currentCaption)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(barcodeMissBanner ? Theme.alert : Theme.inkSoft)
                        .lineLimit(1)
                }
                .padding(.top, 12)
            }

            Spacer(minLength: 12)

            // Aksiyon barı
            VStack(spacing: 12) {
                if permission == .authorized {
                    PrimaryActionButton(
                        title: frontCaptured ? L("Arkayı çek") : L("Fotoğraf çek"),
                        systemImage: "camera.fill",
                        hapticStyle: .heavy
                    ) {
                        showFrontCapturedFlash = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeOut(duration: 0.15)) { showFrontCapturedFlash = false }
                        }
                        requestSnapshot = true
                    }
                }

                if frontCaptured {
                    PhotosPicker(selection: $backPickerItem, matching: .images, photoLibrary: .shared()) {
                        secondaryButtonLabel(text: L("Galeri'den seç"), system: "photo.on.rectangle")
                    }
                    .onChange(of: backPickerItem) { _, newValue in
                        guard let newValue else { return }
                        Task {
                            if let img = await newValue.loadUIImage() { await processBackImage(img) }
                            backPickerItem = nil
                        }
                    }
                    Button {
                        Haptics.light()
                        Task { await skipBackAndRecognize() }
                    } label: {
                        Text(L("Arkayı atla"))
                            .font(Theme.Typo.body.weight(.medium))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.vertical, 6)
                    }
                } else {
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        secondaryButtonLabel(text: L("Galeri'den seç"), system: "photo.on.rectangle")
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
                        recognized = ProductRecognizeResponse(
                            product: nil, ingredients: nil, confidence: "none", source: "none"
                        )
                        phase = .review
                    } label: {
                        Text(L("Manuel ekle"))
                            .font(Theme.Typo.body.weight(.medium))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.vertical, 6)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    /// Outlined secondary button label
    private func secondaryButtonLabel(text: String, system: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: system)
            Text(text).font(Theme.Typo.button)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(Theme.ink, lineWidth: 1.3)
        )
        .foregroundStyle(Theme.ink)
    }

    /// Kamera/permission fallback — parent 1:1 frame veriyor, biz sadece içerik döneriz.
    @ViewBuilder
    private var scannerOrFallback: some View {
        switch permission {
        case .authorized:
            AutoCaptureCameraView(
                detectedBarcode: $detectedBarcode,
                detectedText: $detectedText,
                mode: .auto,
                autoCaptureEnabled: false,  // Manuel çekim — auto-capture false-positive (kartvizit/klavye) yüzünden kapalı. Vision metadata yine toplanır.
                onCapturePhoto: { img, debug in
                    lastCaptureDebug = debug
                    if frontCaptured {
                        Task { await processBackImage(img) }
                    } else {
                        capturedImage = img
                        Task { await processCapturedImage(img) }
                    }
                },
                requestManualCapture: $requestSnapshot,
                resetTrigger: $autoCaptureResetTrigger,
                captureState: $autoCaptureState,
                instabilityRatio: $instabilityRatio,
                salientBox: $autoCaptureSalientBox
            )
            .onChange(of: detectedBarcode) { _, newValue in
                guard !frontCaptured, let bc = newValue, !bc.isEmpty else { return }
                Task { await processBarcode(bc) }
            }
        case .notDetermined:
            fallbackPanel(icon: "camera.metering.unknown",
                          text: L("Kamera izni gerekli")) {
                Button {
                    Haptics.light()
                    Task { permission = await CameraPermission.request() }
                } label: {
                    Text(L("İzin ver"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Theme.ink))
                }
            }
        case .denied, .restricted:
            fallbackPanel(icon: "lock.fill",
                          text: L("Kamera erişimi kapalı")) {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(L("Ayarlar"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Theme.ink))
                }
            }
        }
    }

    @ViewBuilder
    private func fallbackPanel<Action: View>(
        icon: String,
        text: String,
        @ViewBuilder action: () -> Action = { EmptyView() }
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.inkMute)
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .serif).italic())
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            action()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }

    // MARK: - Processing phase

    private var processingPhase: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.4)
                .tint(Theme.ink)
            Text(L("Ürün tanınıyor..."))
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
        if detectedBarcode != nil { return L("Barkod doğrulanıyor...") }
        if capturedImage != nil { return L("Etiket okunuyor ve katalog taranıyor...") }
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
                Text(L("Arşive eklendi"))
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

    /// Front foto yakalandığında:
    /// 1) Local Vision: barcode + OCR (block-level) çıkar — concurrent
    /// 2) Foto'yu upload (ön plan; arka da yüklenirse ek upload yapılır)
    /// 3) Barkod VARSA: direkt recognize (INCI barkod kaynaklı gelir, arkaya gerek yok)
    /// 4) Barkod YOKSA: state'i tut, frontCaptured=true → aynı .camera phase'inde "arkayı çek" UI'ı
    private func processCapturedImage(_ fullResImage: UIImage) async {
        // Strateji:
        // - OCR: FULL-RES (etiketteki küçük metin için)
        // - Vision FP + BG-removal: detached task içinde downscale + 1:1 center crop
        // - Upload + thumbnail: full downscaled (detached, main bloklamasın)
        // ÖNEMLİ: downscale/crop main'de YAPMA — UIImage decode ilk çağrıda 200-500ms blok.
        capturedImage = fullResImage  // thumbnail original'i kullansın, SwiftUI lazy decode
        // ÖNCE phase'i değiştir — kullanıcı arka kamera ekranına ANINDA geçsin.
        // Tüm OCR/FP/upload/recognize işleri detached background'da çalışır,
        // main thread serbest kalır (kamera reopen 3s donmasın).
        let resolvedPendingBarcode = pendingBarcode
        // .camera phase'de KAL — sadece frontCaptured flag'i set et.
        // Scanner unmount olmaz, AVCapture warmup gecikmesi yok.
        Haptics.success()
        frontCaptured = true
        // Flash zaten TAP'ta tetiklendi (kullanıcı 300-1000ms shutter wait'i hissetmesin).
        // Burada sadece state update.
        detectedBarcode = nil
        detectedText = nil
        // AutoCaptureCameraView reset — capture state'i .searching'e dönsün, yeni
        // back foto için tekrar auto-detect aktif olsun.
        autoCaptureResetTrigger += 1

        // Downscale (resize-only, ORİJİNAL RATIO korunur — cihazda 1:1 crop YOK).
        // Backend gerekirse kendi 1:1 crop'unu yapar. FP zaten .centerCrop option'ı
        // ile kendi crop'unu uyguluyor, ekstra cihaz-crop'u gereksizdi.
        let processedImageTask: Task<UIImage, Never> = Task.detached(priority: .userInitiated) {
            ProductScanService.shared.downscaleForProcessing(fullResImage)
        }

        // BG-removed image — downscaled (orijinal ratio) üzerinde. Foreground mask
        // crop gerektirmez.
        let bgRemovedTask: Task<UIImage?, Never> = Task.detached(priority: .userInitiated) {
            let down = await processedImageTask.value
            if #available(iOS 17.0, *) {
                return ProductScanService.shared.backgroundRemovedImage(from: down)
            }
            return nil
        }

        // OCR FULL-RES image üzerinde — küçük etiket metinleri okunabilsin.
        // Downscale OCR'ı bozuyordu ("BEYAZLATICI" → "NN DONỆNL PRI" gibi).
        let ocrTask: Task<(barcode: String?, blocks: [String]), Never> = Task.detached(priority: .userInitiated) {
            async let bc = ProductScanService.shared.detectBarcode(from: fullResImage)
            let blocks = await ProductScanService.shared.recognizeTextBlocks(from: fullResImage)
            let barcode = await bc
            return (barcode, blocks)
        }

        // VISION strict barcode scan — yalnızca product symbology (EAN/UPC) kabul eder.
        // Live AVCaptureMetadataOutput miss verdiyse veya kullanıcı barkodu kareye almadan
        // fotoyu çektiyse, foto üzerinde sessizce çalışır. detectBarcode'dan stricter:
        // QR/Code128 reject, payload numeric + 8-14 hane.
        let frontVisionBarcodeTask: Task<String?, Never> = Task.detached(priority: .userInitiated) {
            await BarcodeImageScanner.scan(image: fullResImage)
        }

        // SPECULATIVE PIPELINE — upload + FP + recognize arka planda detached.
        let uploadTask: Task<ProductScanService.UploadedImage?, Never> = Task.detached(priority: .userInitiated) {
            let down = await processedImageTask.value
            return (try? await ProductScanService.shared.uploadImage(down))
        }
        // FP downscaled (orijinal ratio) üzerinde — VNGenerateImageFeaturePrintRequest
        // zaten .centerCrop option'ı uyguluyor, ekstra cihaz-crop'u gereksiz.
        let fpTask: Task<[Float]?, Never> = Task.detached(priority: .userInitiated) {
            let down = await processedImageTask.value
            return await ProductScanService.shared.featurePrint(from: down)
        }
        let fpCleanTask: Task<(image: UIImage, vec: [Float])?, Never> = Task.detached(priority: .userInitiated) {
            // BG-removed paylaşıyor → backgroundRemovedImage 2. kez çağrılmaz
            guard let cleaned = await bgRemovedTask.value else { return nil }
            guard let vec = await ProductScanService.shared.featurePrint(from: cleaned) else { return nil }
            return (cleaned, vec)
        }

        // Speculative recognize: OCR + upload + FP bittiğinde recognize çağır.
        // brandHint/nameHint NULL — server-side LLM (Gemini Flash) raw OCR blocks'tan
        // extract eder, iOS regex'inden çok daha güvenilir.
        let specTask: Task<ProductRecognizeResponse?, Never> = Task.detached(priority: .userInitiated) {
            let ocrResult = await ocrTask.value
            let visionBarcode = await frontVisionBarcodeTask.value
            let uploaded = await uploadTask.value
            let fp = await fpTask.value
            let fpClean = await fpCleanTask.value?.vec
            // Barkod öncelik sırası:
            // 1) pendingBarcode (live AVCaptureMetadataOutput hit, by-barcode miss verdi)
            // 2) BarcodeImageScanner Vision strict scan (yalnız EAN/UPC, payload validated)
            // 3) ProductScanService.detectBarcode (loose — QR/Code128 dahil)
            let resolvedBarcode = resolvedPendingBarcode ?? visionBarcode ?? ocrResult.barcode
            print("[Vision Barcode] front=\(visionBarcode ?? "-") legacyOCR=\(ocrResult.barcode ?? "-") pending=\(resolvedPendingBarcode ?? "-") → resolved=\(resolvedBarcode ?? "-")")
            let ocrText = ocrResult.blocks.isEmpty ? nil : ocrResult.blocks.joined(separator: "\n")
            // Hiçbir sinyal yoksa speculative atla
            if resolvedBarcode == nil && ocrText == nil && fp == nil {
                return nil
            }
            if let bc = resolvedBarcode {
                print("[Recognize] speculative front with barcode=\(bc)")
            }
            do {
                return try await ProductScanService.shared.recognize(
                    barcode: resolvedBarcode,
                    ocrText: ocrText,
                    ocrBlocks: ocrResult.blocks.isEmpty ? nil : ocrResult.blocks,
                    brandHint: nil,
                    nameHint: nil,
                    photoUrl: uploaded?.publicUrl,
                    photoKey: uploaded?.key,
                    photoKeyBack: nil,
                    photoKeyClean: nil,
                    ocrBlocksBack: nil,
                    featurePrint: fp,
                    featurePrintClean: fpClean
                )
            } catch {
                return nil
            }
        }

        // @State'e set et — back foto akışında await edilecek
        frontUploadTask = uploadTask
        frontFpTask = fpTask
        frontFpCleanTask = fpCleanTask
        speculativeRecognizeTask = specTask

        // OCR bitince blocks'u UI state'e yansıt
        Task {
            let ocrResult = await ocrTask.value
            frontOcrBlocks = ocrResult.blocks.isEmpty ? nil : ocrResult.blocks
        }
    }

    /// İki foto da hazır olduğunda (veya kullanıcı arkayı atladığında) recognize'ı çağırır.
    private func recognizeNow(
        barcode: String?,
        ocrText: String?,
        ocrBlocks: [String]?,
        brandHint: String?,
        nameHint: String?,
        photoUrl: String?,
        photoKey: String?,
        photoKeyBack: String? = nil,
        ocrBlocksBack: [String]? = nil
    ) async {
        phase = .processing
        // FP + BG-removed FP — DETACHED (MainActor inherit etmesin, ana thread bloklamasın).
        // Önce speculative pipeline'dan cache'lenmiş task'ları KULLAN; yoksa yeniden hesapla.
        var pendingCleanImage: UIImage? = nil
        var featurePrint: [Float]? = nil
        var featurePrintClean: [Float]? = nil
        if let img = capturedImage {
            // Speculative cache hit'i tercih et (zaten hesaplanmış)
            if let cachedFpTask = frontFpTask {
                featurePrint = await cachedFpTask.value
            } else {
                featurePrint = await Task.detached(priority: .userInitiated) {
                    await ProductScanService.shared.featurePrint(from: img)
                }.value
            }
            if let cachedCleanTask = frontFpCleanTask {
                if let cached = await cachedCleanTask.value {
                    featurePrintClean = cached.vec
                    pendingCleanImage = cached.image
                }
            } else if #available(iOS 17.0, *) {
                let cleaned = await Task.detached(priority: .userInitiated) {
                    await ProductScanService.shared.featurePrintBackgroundRemoved(from: img)
                }.value
                if let cleaned = cleaned {
                    featurePrintClean = cleaned.vec
                    pendingCleanImage = cleaned.image
                }
            }
        }
        do {
            let resp = try await ProductScanService.shared.recognize(
                barcode: barcode,
                ocrText: ocrText,
                ocrBlocks: ocrBlocks,
                brandHint: brandHint,
                nameHint: nameHint,
                photoUrl: photoUrl,
                photoKey: photoKey,
                photoKeyBack: photoKeyBack,
                // photoKeyClean detached upload — recognize bekletmez, key sonra bağlanır.
                photoKeyClean: nil,
                ocrBlocksBack: ocrBlocksBack,
                featurePrint: featurePrint,
                featurePrintClean: featurePrintClean,
                captureDebug: lastCaptureDebug
            )
            recognized = resp
            phase = .review

            // Recognize sonrası: BG-removed image'ı arka planda upload + attempt'a bağla.
            // Recognize 1s'de bittiği için kullanıcı bunu beklemiyor.
            if let cleanImg = pendingCleanImage, let attemptId = resp.attemptId {
                Task.detached(priority: .background) {
                    if let uploaded = try? await ProductScanService.shared.uploadImage(cleanImg, kind: "product_photo_clean") {
                        await ProductScanService.shared.attachCleanPhoto(attemptId: attemptId, photoKey: uploaded.key)
                    }
                }
            }
        } catch {
            recognized = ProductRecognizeResponse(
                product: nil, ingredients: nil, confidence: "none", source: "none"
            )
            phase = .review
        }
    }

    /// Arka etiket fotoğrafı geldiğinde:
    /// 1) Speculative front-recognize result hazırsa kontrol et
    /// 2) High confidence → kabul et (back data detail screen'da kullanılır)
    /// 3) Medium/low/none → tam recognize (front+back data ile)
    private func processBackImage(_ fullResImage: UIImage) async {
        // Strateji: OCR FULL-RES (INCI etiketi küçük metin), upload DOWNSCALED.
        let image = ProductScanService.shared.downscaleForProcessing(fullResImage)
        capturedBackImage = image
        phase = .processing

        // OCR full-res image üzerinde — INCI içerik listesindeki küçük metin için kritik.
        let backOcrTask: Task<(barcode: String?, blocks: [String]), Never> = Task.detached(priority: .userInitiated) {
            async let bc = ProductScanService.shared.detectBarcode(from: fullResImage)
            async let bl = ProductScanService.shared.recognizeTextBlocks(from: fullResImage)
            return await (bc, bl)
        }
        // Vision strict barcode scan (arka foto) — back foto'da barkod daha sık görülür.
        let backVisionBarcodeTask: Task<String?, Never> = Task.detached(priority: .userInitiated) {
            await BarcodeImageScanner.scan(image: fullResImage)
        }
        let backUploadTask: Task<ProductScanService.UploadedImage?, Never> = Task.detached(priority: .userInitiated) {
            (try? await ProductScanService.shared.uploadImage(image))
        }

        let (barcode, blocks) = await backOcrTask.value
        let backVisionBarcode = await backVisionBarcodeTask.value
        backOcrBlocks = blocks.isEmpty ? nil : blocks
        print("[Vision Barcode] back=\(backVisionBarcode ?? "-") legacyOCR=\(barcode ?? "-")")

        // YENİ AKIŞ — duplicate row önlemek için:
        // 1) Speculative recognize'ı CANCEL ETME, BEKLE → tek attempt_id ile devam et
        // 2) Back foto upload edilince attach-back endpoint'i çağır (yeni recognize call YOK)
        // 3) Back'te barkod yakalanırsa (önceden barkod yoksa) sadece foto attach edilir;
        //    barkod-merkezli flow'u atla — front match'i zaten kullanıcının görüp onaylayacağı şey
        //
        // Eski davranış: backOCR + frontOCR + back foto ile YENİDEN /recognize çağrılıyordu.
        // Bu (a) duplicate recognition_attempts row üretiyordu, (b) re-rank logic
        // front'un doğru match'ini override edebiliyordu (jaccard threshold çok gevşek).
        //
        // Yeni davranış: front match korunur, back foto sadece evidence için kaydedilir.
        // Kullanıcı yanlış buluyorsa confirm modal'dan reject edip manuel düzeltebilir.

        let specResult = await speculativeRecognizeTask?.value
        speculativeRecognizeTask = nil

        guard let result = specResult else {
            // Speculative recognize fail oldu → fallback: tam recognize call.
            // Barkod öncelik: pendingBarcode (live hit) > Vision strict (front/back) > loose OCR detect.
            let uploaded = await backUploadTask.value
            let frontUploaded = await frontUploadTask?.value
            let finalBarcode = pendingBarcode ?? backVisionBarcode ?? barcode
            if let bc = finalBarcode {
                print("[Recognize] fallback back-path barcode=\(bc)")
            }
            await recognizeNow(
                barcode: finalBarcode,
                ocrText: nil,
                ocrBlocks: frontOcrBlocks,
                brandHint: nil,
                nameHint: nil,
                photoUrl: frontUploaded?.publicUrl ?? uploadedPhotoUrl,
                photoKey: frontUploaded?.key ?? frontPhotoKey,
                photoKeyBack: uploaded?.key,
                ocrBlocksBack: blocks.isEmpty ? nil : blocks
            )
            return
        }

        // Speculative başarılı → front match'i göster, back foto'yu attach et
        recognized = result
        phase = .review

        // Back foto upload bitti ise mevcut attempt'a bağla (yeni row YOK)
        let uploaded = await backUploadTask.value
        if let attemptId = result.attemptId, let backKey = uploaded?.key {
            Task.detached(priority: .background) {
                await ProductScanService.shared.attachBackPhoto(attemptId: attemptId, photoKey: backKey)
            }
        }

        // Clean (BG-removed) image attach — speculative pipeline'dan gelir
        if let attemptId = result.attemptId, let cleanTask = frontFpCleanTask {
            Task.detached(priority: .background) {
                if let cleaned = await cleanTask.value,
                   let uploadedClean = try? await ProductScanService.shared.uploadImage(cleaned.image, kind: "product_photo_clean") {
                    await ProductScanService.shared.attachCleanPhoto(attemptId: attemptId, photoKey: uploadedClean.key)
                }
            }
        }
    }

    /// Kullanıcı "arkayı atla" derse: speculative recognize hazırsa direkt kullan.
    /// Recognize duplicate çağrısı YOK — front upload + recognize zaten paralel başlamıştı.
    private func skipBackAndRecognize() async {
        phase = .processing
        if let specTask = speculativeRecognizeTask, let result = await specTask.value {
            recognized = result
            phase = .review
            // Cleaned image attach (back foto YOK çünkü skip ettik)
            if let attemptId = result.attemptId, let cleanTask = frontFpCleanTask {
                Task.detached(priority: .background) {
                    if let cleanImg = await cleanTask.value?.image {
                        if let cleaned = try? await ProductScanService.shared.uploadImage(cleanImg, kind: "product_photo_clean") {
                            await ProductScanService.shared.attachCleanPhoto(attemptId: attemptId, photoKey: cleaned.key)
                        }
                    }
                }
            }
            return
        }
        // Speculative başlatılmamış (fallback) — manuel recognize
        await recognizeNow(
            barcode: pendingBarcode,
            ocrText: frontOcrBlocks?.joined(separator: "\n"),
            ocrBlocks: frontOcrBlocks,
            brandHint: nil,
            nameHint: nil,
            photoUrl: uploadedPhotoUrl,
            photoKey: frontPhotoKey
        )
    }

    /// Live barcode bulundu — by-barcode lookup → bulunduysa direkt review.
    /// Bulamadıysa kullanıcıya fotoyu çekmesini söyle (kamera'da kal); barkod
    /// daha sonra `processCapturedImage` ile birlikte recognize'a iletilir.
    private func processBarcode(_ barcode: String) async {
        // Aynı barcode tekrarsa atlat
        if case .processing = phase { return }
        if case .review = phase { return }
        if pendingBarcode == barcode { return }       // aynı barkodu defalarca tetikleme

        phase = .processing
        do {
            let (p, ings) = try await ProductScanService.shared.lookupByBarcode(barcode)
            if let p = p {
                recognized = ProductRecognizeResponse(
                    product: p,
                    ingredients: ings,
                    confidence: "high",
                    source: "obf"
                )
                phase = .review
                return
            }
            // Katalogda yok — kullanıcıdan foto isteyelim. Barkod state'i pending
            // tutulur; foto çekilince recognize body'sine eklenir.
            Haptics.warning()
            pendingBarcode = barcode
            barcodeMissBanner = true
            phase = .camera
        } catch {
            Haptics.warning()
            pendingBarcode = barcode
            barcodeMissBanner = true
            phase = .camera
        }
    }

    /// Quick Scan modunda kullanıcı "yine de arşive ekle" derse: mevcut recognize
    /// sonucundan minimal `UserProductCreateRequest` üret ve `addToArchive` çağır.
    /// Sonuç ile success animasyonu + dismiss tetiklenir.
    private func quickScanAddToArchive() async {
        guard let result = recognized else { return }
        let productId = result.product?.id
        let payload = UserProductCreateRequest(
            productId: productId,
            nickname: nil,
            photoUrl: uploadedPhotoUrl ?? result.product?.imageUrl,
            openedAt: nil,
            rating: nil,
            notes: nil,
            addedVia: "scan",
            manualBrand: nil,
            manualName: nil,
            manualCategory: nil
        )
        do {
            let created = try await ProductScanService.shared.addToArchive(payload)
            if let attemptId = result.attemptId {
                Task {
                    await ProductScanService.shared.confirmRecognition(
                        attemptId: attemptId, correct: true
                    )
                }
            }
            phase = .success(productName: created.name ?? created.nickname ?? L("Ürün"))
            onAdded?(created)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
        } catch {
            flowError = error.localizedDescription
        }
    }

    private func resetToCamera() {
        Haptics.light()
        detectedBarcode = nil
        detectedText = nil
        capturedImage = nil
        recognized = nil
        uploadedPhotoUrl = nil
        frontPhotoKey = nil
        frontOcrBlocks = nil
        frontBrandHint = nil
        frontNameHint = nil
        capturedBackImage = nil
        backPhotoKey = nil
        backOcrBlocks = nil
        backPickerItem = nil
        pendingBarcode = nil
        barcodeMissBanner = false
        flowError = nil
        frontCaptured = false
        // CANCEL detached tasks — orphan upload/compute/HTTP önle
        speculativeRecognizeTask?.cancel()
        frontUploadTask?.cancel()
        frontFpTask?.cancel()
        frontFpCleanTask?.cancel()
        speculativeRecognizeTask = nil
        frontUploadTask = nil
        frontFpTask = nil
        frontFpCleanTask = nil
        autoCaptureResetTrigger += 1
        phase = .camera
    }
}

#Preview {
    AddProductFlowView()
}

