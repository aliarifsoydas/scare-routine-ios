import SwiftUI

/// Quick Scan result panel — kullanıcı markette ürün taradıktan sonra
/// AI değerlendirmesi: fit_score / verdict / pros / cons / duplicate warning.
///
/// Faz:
/// - `.loading`               — `quickEvaluate` çağrısı süresince
/// - `.loaded(response)`      — sonuç gösterimi (gauge + verdict + pros/cons + duplicate)
/// - `.error(message)`        — backend hata, "Tekrar dene" CTA ile
///
/// Backend cevabını ön belleğe alır; aynı panel içinde tekrarlayan render'da yeniden
/// fetch yapmaz. `productId` boş gelirse direkt hata state'i gösterir
/// (recognize match kaçırmış demektir).
///
/// Parent (`AddProductFlowView` Quick Scan mode) sadece state geçişlerini ve
/// arşive ekle/tekrar tara/kapat callback'lerini yönetir. Endpoint çağrısı bu
/// panelin sorumluluğudur.
///
/// **UX**: yanıt geldikten sonra içerik staggered olarak fade-in olur (Spotify
/// daylist tarzı) — gauge, verdict, duplicate, pros/cons, reasons sırasıyla
/// belirir. Beklerken rotation eden status label'lar gösterilir (1.5s).
///
/// **Streaming**: `useStreaming=true` olduğunda backend NDJSON akışı tüketilir
/// (chunk-by-chunk reveal). Şimdilik default `false` — backend hazır değil.
struct QuickScanResultPanel: View {
    /// Recognize'dan gelen katalog ürün ID'si. Boş ise hata gösterilir.
    let productId: String

    /// Recognize step'inden geçirilen sonuç — fotoğraf + brand/name'i `quickEvaluate`
    /// dönmeden önce hemen gösterebilmek için. Optional çünkü manuel ekleme yolunda nil.
    let initialResult: ProductRecognizeResponse?

    /// Local olarak yakalanmış görsel (henüz upload edilmemiş thumb).
    /// `initialResult.product?.imageUrl` yoksa fallback olarak hero'da kullanılır.
    let capturedImage: UIImage?

    /// Upload edilmiş public foto URL'i (R2/CloudFront).
    /// `initialResult.product?.imageUrl` ile bir alternatif — biri varsa hero gösterilir.
    let photoUrl: String?

    /// Kullanıcı "arşive ekle" derse parent flow tetiklenir.
    let onAddToArchive: () -> Void

    /// "Tekrar tara" — parent .camera phase'ine sıfırlar.
    let onRescan: () -> Void

    /// Paneli ve flow sheet'ini kapatır.
    let onDismiss: () -> Void

    /// Düşük confidence durumunda kullanıcının "manuel ara" diyerek manuel ekleme
    /// flow'una geçmesini sağlar. Parent vermezse `onRescan`'a düşer (tekrar tara).
    var onManualEntry: (() -> Void)? = nil

    /// NDJSON streaming opt-in. Backend hazır olunca true yap, `evaluate()`
    /// `URLSession.bytes(for:)` üzerinden chunk-by-chunk consume eder.
    /// Şimdilik daima single-shot JSON fetch.
    var useStreaming: Bool = false

    private enum Phase {
        case loading
        case loaded(QuickEvaluateResponse)
        case error(String)
        /// Recognition confidence düşük → kullanıcı önce ürünün doğru olup olmadığını
        /// onaylasın. `quickEvaluate` çağrılmaz; kullanıcı `Bu doğru ürün` derse
        /// confidence guard aşılır, normal `.loading → .loaded` akışına geçilir.
        case awaitingConfirmation
    }

    /// Recognition confidence threshold sonucu — `evaluate()` başlamadan önce
    /// `actionFor(confidence:)` ile karar verilir.
    ///
    /// - `proceedSilent`: high confidence — analiz hemen çalışsın.
    /// - `proceedWithBanner`: medium — analiz çalışsın, üstte "doğru tanıdığımdan
    ///   tam emin değilim" banner göster.
    /// - `requireConfirm`: low (veya unknown) — `quickEvaluate` BAŞLATMA, kullanıcı
    ///   önce ürünün doğru olup olmadığını onaylasın.
    private enum ConfidenceAction {
        case proceedSilent
        case proceedWithBanner
        case requireConfirm
    }

    @State private var phase: Phase = .loading
    @State private var statusIndex: Int = 0
    @State private var statusTimer: Timer?
    // NOT: `revealToken` (staggered reveal) ve `showLowConfidenceBanner` artık
    // gerek yok — loaded UI'ı `ProductIdentificationResultView` render ediyor,
    // verification banner'ı kendi içinde confidence'a göre gösteriyor.

    /// Wrong-match düzeltme sheet'i — kullanıcı "bu yanlış ürün" footer'ına bastı.
    /// `initialResult.attemptId` yoksa footer hiç render edilmez; bu state ancak
    /// attemptId varken `true` olabilir.
    @State private var showWrongMatchSheet: Bool = false
    /// Wrong-match düzeltme başarıyla gönderildiyse footer'ı tekrar göstermemek
    /// için flag — kullanıcı aynı taramada birden fazla düzeltme yollamasın.
    @State private var wrongMatchSubmitted: Bool = false

    /// Spotify-daylist tarzı dönen status label'ları — LLM beklerken kullanıcının
    /// boşa beklediği hissini azaltır. Pre-check (~500ms) cevabı bu rotation'ı
    /// görmeden geçer; LLM (~3-5s) en az 2 label gösterir.
    private let statuses: [String] = [
        L("Profilini kontrol ediyor..."),
        L("Arşivinle eşleştiriyor..."),
        L("Aktif maddeleri değerlendiriyor..."),
        L("Cilt uyumunu hesaplıyor..."),
    ]

    var body: some View {
        // `.loaded` phase'i tek render kaynağına (ProductIdentificationResultView)
        // devrederiz; loading / error / awaitingConfirmation hâlâ host'a ait
        // çünkü Quick Scan'a özel UX (confidence guard, status rotation, retry).
        Group {
            switch phase {
            case .loaded(let result):
                ProductIdentificationResultView(
                    mode: .preview,
                    identifyResult: initialResult ?? ProductRecognizeResponse(
                        product: nil,
                        ingredients: nil,
                        confidence: initialResult?.confidence ?? "high",
                        source: initialResult?.source
                    ),
                    evaluationResult: result,
                    isEvaluating: false,
                    capturedImage: capturedImage,
                    photoUrl: photoUrl,
                    onClose: { onDismiss() },
                    onAddToArchive: { onAddToArchive() },
                    onWrongMatch: wrongMatchCallback,
                    onManualEntry: onManualEntry
                )
            default:
                hostedPhases
            }
        }
        .navigationTitle(L("Hızlı Tarama"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await startWithConfidenceGuard()
        }
        .sheet(isPresented: $showWrongMatchSheet) {
            if let attemptId = initialResult?.attemptId, !attemptId.isEmpty {
                WrongMatchSheet(
                    attemptId: attemptId,
                    onCorrected: { _ in
                        // Düzeltme gönderildi — footer'ı bir daha gösterme. Toast/
                        // navigate kararı parent flow'a ait; bu panel sadece sinyali
                        // submit etti.
                        wrongMatchSubmitted = true
                    },
                    onManualEntryRequested: onManualEntry
                )
            }
        }
    }

    /// `onWrongMatch` callback'i — sadece `attemptId` varken footer görünür ve
    /// callback bağlı olur. `wrongMatchSubmitted=true` durumunda da nil dönüp
    /// footer'ı gizleriz (kullanıcı zaten düzeltme yolladı).
    private var wrongMatchCallback: (() -> Void)? {
        guard let attemptId = initialResult?.attemptId, !attemptId.isEmpty else {
            return nil
        }
        guard !wrongMatchSubmitted else { return nil }
        return { showWrongMatchSheet = true }
    }

    /// Loaded olmayan tüm phase'ler (loading / error / awaitingConfirmation) —
    /// eski host UI'ı korur. Hero + retry/footer Quick Scan'a özgü.
    private var hostedPhases: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                Divider().opacity(0.5)

                switch phase {
                case .loading:
                    loadingSection
                        .transition(.opacity)
                case .error(let msg):
                    errorSection(msg)
                        .transition(.opacity)
                case .awaitingConfirmation:
                    awaitingConfirmationSection
                        .transition(.opacity)
                case .loaded:
                    EmptyView()  // delegated above
                }
            }
            .padding(20)
            .animation(.easeInOut(duration: 0.25), value: isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            footer
        }
    }

    // MARK: - Sections

    /// Ürün fotoğrafı + brand + isim — quickEvaluate dönmeden önce de doluyor.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            heroPhoto
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(Theme.surfaceLow)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

            if let brand = brandText, !brand.isEmpty {
                Text(brand.uppercased())
                    .font(Theme.Typo.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
            }
            Text(nameText)
                .font(Theme.Typo.headline)
                .foregroundStyle(Theme.ink)
        }
    }

    /// Foto öncelik sırası:
    /// 1) loaded sonucundaki `product.photoUrl`
    /// 2) recognize result `product.imageUrl`
    /// 3) parent'tan gelen `photoUrl` (upload bitmiş ama recognize image_url'i null)
    /// 4) local `capturedImage` (henüz upload bitmedi)
    /// 5) placeholder ikon
    @ViewBuilder
    private var heroPhoto: some View {
        if case .loaded(let r) = phase,
           let urlStr = r.product.photoUrl, !urlStr.isEmpty,
           let url = URL(string: urlStr) {
            AsyncRemoteImage(url: url, contentMode: .fit)
        } else if let urlStr = initialResult?.product?.imageUrl, !urlStr.isEmpty,
                  let url = URL(string: urlStr) {
            AsyncRemoteImage(url: url, contentMode: .fit)
        } else if let urlStr = photoUrl, !urlStr.isEmpty, let url = URL(string: urlStr) {
            AsyncRemoteImage(url: url, contentMode: .fit)
        } else if let img = capturedImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
        } else {
            placeholderIcon
        }
    }

    private var placeholderIcon: some View {
        ZStack {
            Theme.surfaceLow
            Image(systemName: "shippingbox")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Theme.inkMute)
        }
    }

    /// Hero'da gösterilecek brand: loaded olduğunda response.product.brand öncelikli;
    /// yoksa recognize'dan gelen brand.
    private var brandText: String? {
        if case .loaded(let r) = phase, let b = r.product.brand, !b.isEmpty {
            return b
        }
        return initialResult?.product?.brand
    }

    /// Hero'da gösterilecek isim: loaded → response.product.name; yoksa recognize name.
    private var nameText: String {
        if case .loaded(let r) = phase {
            return r.product.name
        }
        return initialResult?.product?.name ?? L("Bilinmeyen ürün")
    }

    /// Rotating-status loading row. Status label `id(statusIndex)` ile crossfade eder.
    private var loadingSection: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Theme.ink)
            Text(statuses[statusIndex])
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.inkSoft)
                .id(statusIndex)
                .transition(.opacity)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
        .onAppear { startStatusRotation() }
        .onDisappear { stopStatusRotation() }
    }

    /// 1.5s'de bir status label index'ini döndür — `withAnimation` crossfade tetikler.
    private func startStatusRotation() {
        stopStatusRotation()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
                    statusIndex = (statusIndex + 1) % statuses.count
                }
            }
        }
    }

    private func stopStatusRotation() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    // NOTE: `loadedSection` / `lowConfidenceBanner` artık dead — loaded UI'ı
    // `ProductIdentificationResultView` render ediyor; medium confidence banner
    // de orada `verificationBanner` adıyla yaşıyor. Bu view sadece host fazlarını
    // (loading / error / awaitingConfirmation) tutar.

    /// Düşük confidence durumunda analiz çalışmaz — kullanıcı önce ürünün doğru
    /// olup olmadığını onaylasın diye 3 seçenekli overlay gösterilir:
    /// "Bu doğru ürün" (analizi başlat) / "Manuel ara" / "Tekrar fotoğraf çek".
    private var awaitingConfirmationSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.alert)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Bu ürünü tanımakta zorlandım"))
                        .font(Theme.Typo.headline)
                        .foregroundStyle(Theme.ink)
                    Text(L("Devam etmeden önce, gösterdiğim ürünün doğru olduğunu onayla."))
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                Button {
                    Haptics.selection()
                    Task { await userConfirmedProduct() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                        Text(L("Bu doğru ürün"))
                    }
                    .font(Theme.Typo.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.ink))
                    .foregroundStyle(Theme.onAccent)
                }
                Button {
                    Haptics.light()
                    if let onManualEntry { onManualEntry() } else { onRescan() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        Text(L("Manuel ara"))
                    }
                    .font(Theme.Typo.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall)
                            .strokeBorder(Theme.ink, lineWidth: 1.2)
                    )
                    .foregroundStyle(Theme.ink)
                }
                Button {
                    Haptics.light()
                    onRescan()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text(L("Tekrar fotoğraf çek"))
                    }
                    .font(Theme.Typo.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall)
                            .strokeBorder(Theme.divider, lineWidth: 1)
                    )
                    .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private func errorSection(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.alert)
            Text(L("Değerlendirme yapılamadı"))
                .font(Theme.Typo.headline)
                .foregroundStyle(Theme.ink)
            Text(msg)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button {
                Haptics.light()
                Task { await evaluate() }
            } label: {
                Text(L("Tekrar dene"))
                    .font(Theme.Typo.body.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.ink))
                    .foregroundStyle(Theme.onAccent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            // `.awaitingConfirmation` durumunda kullanıcı henüz ürünü onaylamamış,
            // doğrudan arşive ekleme yanlış ürün eklenmesi riskine yol açar →
            // butonu disable et (overlay tarafındaki "Bu doğru ürün" CTA yönlendirir).
            Button {
                Haptics.heavy()
                onAddToArchive()
            } label: {
                Text(L("Arşive ekle"))
                    .font(Theme.Typo.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius)
                            .fill(isAwaitingConfirmation ? Theme.surfaceLow : Theme.ink)
                    )
                    .foregroundStyle(isAwaitingConfirmation ? Theme.inkMute : Theme.onAccent)
            }
            .disabled(isAwaitingConfirmation)
            HStack(spacing: 10) {
                Button {
                    Haptics.light()
                    onRescan()
                } label: {
                    Text(L("Tekrar tara"))
                        .font(Theme.Typo.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radius)
                                .strokeBorder(Theme.divider, lineWidth: 1)
                        )
                        .foregroundStyle(Theme.ink)
                }
                Button {
                    Haptics.light()
                    onDismiss()
                } label: {
                    Text(L("Kapat"))
                        .font(Theme.Typo.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radius)
                                .strokeBorder(Theme.divider, lineWidth: 1)
                        )
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .padding(.top, 14)
        .background(Theme.canvas)
    }

    // MARK: - Logic

    /// `isLoading` türetilmiş bool — `animation(_:value:)` Bool karşılaştırması için.
    /// Enum'lar `Equatable` olmadığı için doğrudan `value: phase` çalışmıyor.
    private var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    /// Footer "Arşive ekle" butonunun disabled olup olmayacağı.
    /// Confidence guard kullanıcıyı bekletiyorken arşive ekleme akışını engelle.
    private var isAwaitingConfirmation: Bool {
        if case .awaitingConfirmation = phase { return true }
        return false
    }

    /// Backend `quickEvaluate(productId:)` çağrısı.
    /// `productId` boşsa hemen error state'ine düşer — recognize match'i kaçırmış demek.
    ///
    /// `via == .preCheck` (~500ms) ile `via == .llm` (~3-5s) ayrımını UI yapmaz;
    /// her iki durumda da loading section status rotation gösterir, response gelince
    /// staggered reveal başlar. Pre-check çok hızlı dönerse status rotation belki
    /// hiç görünmez — sorun değil, kullanıcı verdict'i hemen alır.
    ///
    /// `useStreaming=true` olduğunda backend NDJSON chunk'ları gönderir; ileride
    /// burada `URLSession.bytes(for:)` ile her chunk geldiğinde partial UI update
    /// edilir. Şimdilik flag false olduğu için tek-shot.
    private func evaluate() async {
        await MainActor.run {
            phase = .loading
            statusIndex = 0
        }
        guard !productId.isEmpty else {
            await MainActor.run {
                phase = .error(L("Ürün eşleştirilemedi"))
            }
            return
        }
        do {
            let result: QuickEvaluateResponse
            if useStreaming {
                // Placeholder: backend NDJSON hazır olunca burada
                // `for try await line in URLSession.bytes(for:).lines` ile her chunk'ı
                // tüketip phase'i incremental update edeceğiz.
                result = try await ProductScanService.shared.quickEvaluate(productId: productId)
            } else {
                result = try await ProductScanService.shared.quickEvaluate(productId: productId)
            }
            await MainActor.run {
                stopStatusRotation()
                withAnimation(.easeOut(duration: 0.35)) {
                    phase = .loaded(result)
                }
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await MainActor.run {
                stopStatusRotation()
                phase = .error(message)
            }
        }
    }

    // MARK: - Confidence guard
    //
    // `.task { await evaluate() }` doğrudan analiz başlatıyordu — bu yanlış match
    // durumunda kullanıcıya yanlış ürün için yanlış analiz gösteriyordu. Bu yüzden
    // recognize confidence'a göre 3 farklı UX seçiyoruz:
    //
    // - **high**: analiz hemen çalışır, banner yok (proceedSilent)
    // - **medium**: analiz çalışır + üstte sarı "tam emin değilim" banner (proceedWithBanner)
    // - **low / unknown**: analiz BAŞLAMAZ, kullanıcı önce ürünü onaylasın (requireConfirm)

    /// Backend recognize cevabındaki confidence string'inden UI aksiyonunu seçer.
    /// Tanımsız değerler defensive olarak `.requireConfirm`'e düşer — yanlış match
    /// için yanlış analiz göstermemek üstün önceliklidir.
    private func actionFor(confidence: String?) -> ConfidenceAction {
        switch confidence {
        case "high":   return .proceedSilent
        case "medium": return .proceedWithBanner
        default:       return .requireConfirm  // "low", "none", nil, bilinmeyen
        }
    }

    /// `.task` modifier'ından çağrılır. Confidence guard'a göre ya direkt
    /// `evaluate()` başlatır, ya `awaitingConfirmation` phase'ine düşer.
    /// Medium confidence banner'ı `ProductIdentificationResultView` kendi içinde
    /// gösteriyor (verificationBanner) — burada `proceedWithBanner` ile
    /// `proceedSilent` aynı davranır.
    private func startWithConfidenceGuard() async {
        let action = actionFor(confidence: initialResult?.confidence)
        switch action {
        case .proceedSilent, .proceedWithBanner:
            await evaluate()
        case .requireConfirm:
            await MainActor.run { phase = .awaitingConfirmation }
        }
    }

    /// Kullanıcı confirm overlay'inde "Bu doğru ürün" derse: confidence'ı override
    /// edip normal `evaluate()` akışına gir.
    private func userConfirmedProduct() async {
        await evaluate()
    }
}

// MARK: - Staggered reveal

/// Loaded içeriği aşağıdan yumuşakça sıralı olarak fade-in eder.
/// Şu anda `QuickEvaluationView`'ı bir bütün olarak reveal eder; iç bileşenleri
/// ayrı ayrı staggered reveal etmek için `QuickEvaluationView`'ı parçalamak
/// gerekiyor — Quick Scan ve Product Review paylaştığı için riskli.
/// Bu yüzden panel-level reveal: 0.4s'lik tek opacity+move geçişi yeterli
/// "ses çıkararak geliyor" hissi veriyor.
///
/// Daha agresif stagger (her satır ayrı) istiyorsak `QuickEvaluationView` içine
/// `revealStep` parametresi eklemeli — gelecek iterasyon.
private struct StaggeredReveal: ViewModifier {
    let token: Int

    func body(content: Content) -> some View {
        content
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                )
            )
            .id(token)
    }
}

#Preview {
    NavigationStack {
        QuickScanResultPanel(
            productId: "prod_demo_123",
            initialResult: nil,
            capturedImage: nil,
            photoUrl: nil,
            onAddToArchive: {},
            onRescan: {},
            onDismiss: {}
        )
        .navigationTitle("Hızlı Tarama")
        .navigationBarTitleDisplayMode(.inline)
    }
}
