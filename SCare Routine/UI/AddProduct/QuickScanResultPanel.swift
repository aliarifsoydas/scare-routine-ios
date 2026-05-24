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

    /// NDJSON streaming opt-in. Backend hazır olunca true yap, `evaluate()`
    /// `URLSession.bytes(for:)` üzerinden chunk-by-chunk consume eder.
    /// Şimdilik daima single-shot JSON fetch.
    var useStreaming: Bool = false

    private enum Phase {
        case loading
        case loaded(QuickEvaluateResponse)
        case error(String)
    }

    @State private var phase: Phase = .loading
    @State private var statusIndex: Int = 0
    @State private var statusTimer: Timer?
    /// Loaded sonrası staggered reveal'ı tetikleyen sayaç — her result için
    /// yeni bir değer alır, animation `.value:` parametresine geçer.
    @State private var revealToken: Int = 0

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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                Divider().opacity(0.5)

                switch phase {
                case .loading:
                    loadingSection
                        .transition(.opacity)
                case .loaded(let result):
                    loadedSection(result)
                case .error(let msg):
                    errorSection(msg)
                        .transition(.opacity)
                }
            }
            .padding(20)
            .animation(.easeInOut(duration: 0.25), value: isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(L("Hızlı Tarama"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .task {
            await evaluate()
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

    /// Loaded state — staggered reveal:
    /// gauge (0s) → verdict (0.2s) → duplicate (0.4s) → pros/cons (0.6s) → reasons (0.8s).
    /// QuickEvaluationView'ın iç bileşimi olduğu gibi kullanılır; reveal animasyonu
    /// bu panele özel (review akışı yoksa staggered animation göstermez).
    private func loadedSection(_ result: QuickEvaluateResponse) -> some View {
        QuickEvaluationView(result: result, context: .scanning)
            .modifier(StaggeredReveal(token: revealToken))
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
            Button {
                Haptics.heavy()
                onAddToArchive()
            } label: {
                Text(L("Arşive ekle"))
                    .font(Theme.Typo.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.ink))
                    .foregroundStyle(Theme.onAccent)
            }
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
                phase = .loaded(result)
                // Reveal token'ı arttır → StaggeredReveal animation'ını tetikle.
                // Animation duration'ı reveal modifier kendi içinde stagger ediyor;
                // burada sadece geçişi başlat.
                withAnimation(.easeOut(duration: 0.35)) {
                    revealToken &+= 1
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
