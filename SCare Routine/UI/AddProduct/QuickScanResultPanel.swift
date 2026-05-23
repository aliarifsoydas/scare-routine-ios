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

    private enum Phase {
        case loading
        case loaded(QuickEvaluateResponse)
        case error(String)
    }

    @State private var phase: Phase = .loading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                Divider().opacity(0.5)

                switch phase {
                case .loading:
                    loadingSection
                case .loaded(let result):
                    loadedSection(result)
                case .error(let msg):
                    errorSection(msg)
                }
            }
            .padding(20)
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

    private var loadingSection: some View {
        HStack(spacing: 12) {
            ProgressView().tint(Theme.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Senin için değerlendiriliyor"))
                    .font(Theme.Typo.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Text(L("Cilt profilin ve arşivin karşılaştırılıyor"))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
    }

    /// Loaded state — UI body extracted into `QuickEvaluationView` so the same
    /// fit-score/verdict/pros/cons layout can be reused inline in `ProductReviewView`.
    private func loadedSection(_ result: QuickEvaluateResponse) -> some View {
        QuickEvaluationView(result: result, context: .scanning)
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

    /// Backend `quickEvaluate(productId:)` çağrısı.
    /// `productId` boşsa hemen error state'ine düşer — recognize match'i kaçırmış demek.
    private func evaluate() async {
        phase = .loading
        guard !productId.isEmpty else {
            phase = .error(L("Ürün eşleştirilemedi"))
            return
        }
        do {
            let result = try await ProductScanService.shared.quickEvaluate(productId: productId)
            phase = .loaded(result)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .error(message)
        }
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
