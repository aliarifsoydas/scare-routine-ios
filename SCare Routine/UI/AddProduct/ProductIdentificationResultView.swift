import SwiftUI

/// Quick Scan ve Add Product akışlarındaki "tanıma sonucu" sayfasının tek render kaynağı.
///
/// Mevcut `QuickScanResultPanel` (Quick Scan preview) ve `ProductReviewView` (Add Product)
/// host view'ları aynı bilgiyi (ürün + fit + pros/cons + conflicts + duplicate + inci)
/// farklı şekilde gösteriyordu. Bu view tek bir render layer'ı verir; host view'lar sadece
/// state management (loading/error/manual form) ve aksiyon (close/add/wrong-match) için kalır.
///
/// **Component reuse**: `FitScoreGauge`, `ProConsList`, `ConflictsCard`, `DuplicateWarningCard`,
/// `QuickEvaluationView` paylaşılan component'ler; bu view onları tüketir, kendisi yeniden
/// implement etmez.
///
/// **Backend kontrat**: `recognize`/`by-barcode`/`search` cevaplarının ortak tipi
/// `ProductRecognizeResponse` üzerinden besleniyor (Agent A "ProductIdentifyResponse" alias'ı
/// ileride DTO katmanında landing edecek; bu view tipini güncellemek tek satırlık değişiklik).
struct ProductIdentificationResultView: View {

    // MARK: - Mode

    /// Sayfanın hangi akışta render edildiğini belirler — primary CTA + INCI özetinin
    /// görünürlüğü mode'a göre değişir.
    enum Mode: Equatable {
        /// Quick Scan — kullanıcı markette ürün taradı, sadece "almalı mıyım?" cevabını
        /// görmek istiyor. Primary CTA "Tamam, kapat"; "Arşive ekle" opsiyonel ikincil.
        case preview
        /// Add Product — kullanıcı arşive eklemek için akışı başlattı. Primary CTA
        /// "Arşive ekle"; INCI özeti default açık.
        case reviewAndAdd
    }

    // MARK: - Inputs

    let mode: Mode

    /// Recognize cevabı (unified DTO). Confidence, product meta, INCI, source bilgisi
    /// burada. Quick Scan path'inde initial result olarak gelir; Add Product path'inde
    /// review screen'inin gösterdiği aynı response.
    let identifyResult: ProductRecognizeResponse

    /// AI quick evaluate sonucu (fit score + verdict + pros/cons + duplicate +
    /// conflicts). Opsiyonel — backend daha dönmediyse / hatadaysa nil olabilir;
    /// gauge ve evaluation bölümleri o zaman render edilmez.
    let evaluationResult: QuickEvaluateResponse?

    /// AI evaluate çağrısı sürüyor mu? `evaluationResult == nil && isEvaluating == true`
    /// durumunda inline loading hint gösterilir.
    let isEvaluating: Bool

    /// Local yakalama (henüz upload bitmemiş thumb). Hero foto fallback chain'inde
    /// network image'lardan sonra kullanılır.
    let capturedImage: UIImage?

    /// Parent'tan gelen public R2 photo URL'i — `identifyResult.product?.imageUrl`
    /// dönmediyse alternatif.
    let photoUrl: String?

    // MARK: - Callbacks

    /// Preview mode'da "Tamam, kapat" CTA → flow sheet'ini dismiss eder.
    var onClose: (() -> Void)? = nil

    /// Primary submit — review modunda "Arşive ekle", preview modunda opsiyonel ikincil.
    var onAddToArchive: (() -> Void)? = nil

    /// "Bu doğru ürün değil" — Agent D'nin `WrongMatchFooter` component'i bittiğinde
    /// bu callback'e bağlanır. Component yoksa footer render edilmez.
    var onWrongMatch: (() -> Void)? = nil

    /// Düşük confidence durumunda manuel girdiye yönlendirme — host view'ın
    /// confidence guard'ı tetikler, kullanıcıya gösterilen bir CTA değildir (bu view
    /// confidence guard'a sahip değil; sadece banner gösterir).
    var onManualEntry: (() -> Void)? = nil

    /// `true` → embedded mode: outer ScrollView, background, ve bottom action bar
    /// render edilmez; sadece content stack döner. `ProductReviewView` host'unun
    /// kendi ScrollView'ı + footerButtons'i olduğu için bu mode'u kullanır.
    var isEmbedded: Bool = false

    // MARK: - Body

    var body: some View {
        if isEmbedded {
            contentStack
        } else {
            ScrollView(.vertical) {
                contentStack
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                bottomActionBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .background(Theme.canvas.opacity(0.95))
            }
        }
    }

    /// İçerik dikey stack'i — embedded ve standalone mode tarafından paylaşılır.
    /// Sırası: header → verification banner → fit gauge → AI loading → duplicate →
    /// conflicts → pros/cons → INCI özet (reviewAndAdd) → wrong-match footer.
    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 16) {
            productHeader

            if shouldShowVerificationBanner {
                verificationBanner
            }

            if let eval = evaluationResult {
                fitScoreSection(eval)
            }

            if evaluationResult == nil && isEvaluating {
                aiLoadingHint
            }

            if let dupId = evaluationResult?.duplicateProductId,
               let dupName = evaluationResult?.duplicateProductName {
                DuplicateWarningCard(productId: dupId, productName: dupName)
            }

            if let conflicts = evaluationResult?.conflictsWith, !conflicts.isEmpty {
                ConflictsCard(conflicts: conflicts)
            }

            // NOT: pros/cons artık fitScoreSection içindeki QuickEvaluationView
            // tarafından gösteriliyor — burada ayrı ProConsList DUPLICATE oluyordu
            // ("Artılar/Eksiler" iki kez). Kaldırıldı.

            if mode == .reviewAndAdd, !identifyResult.inciList.isEmpty {
                inciSummarySection
            }

            // Wrong-match footer — kullanıcı recognition'ın yanlış olduğunu
            // söyleyebilir. attemptId yoksa (legacy attempt veya henüz konum-
            // landırılmamış ürün) callback bağlı olmaz; footer gizli kalır.
            if onWrongMatch != nil {
                WrongMatchFooter(onTap: { onWrongMatch?() })
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Sections

    /// Hero — ürün foto + brand + isim. Foto fallback chain'i:
    /// 1) `evaluationResult.product.photoUrl`
    /// 2) `identifyResult.product?.imageUrl`
    /// 3) parent'tan `photoUrl`
    /// 4) local `capturedImage`
    /// 5) placeholder ikon
    private var productHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let categoryLabel {
                Text(categoryLabel)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkMute)
            }
        }
    }

    @ViewBuilder
    private var heroPhoto: some View {
        if let evalUrl = evaluationResult?.product.photoUrl, !evalUrl.isEmpty,
           let url = URL(string: evalUrl) {
            AsyncRemoteImage(url: url, contentMode: .fit)
        } else if let recUrl = identifyResult.product?.imageUrl, !recUrl.isEmpty,
                  let url = URL(string: recUrl) {
            AsyncRemoteImage(url: url, contentMode: .fit)
        } else if let parentUrl = photoUrl, !parentUrl.isEmpty,
                  let url = URL(string: parentUrl) {
            AsyncRemoteImage(url: url, contentMode: .fit)
        } else if let img = capturedImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
        } else {
            ZStack {
                Theme.surfaceLow
                Image(systemName: "shippingbox")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Theme.inkMute)
            }
        }
    }

    private var brandText: String? {
        if let b = evaluationResult?.product.brand, !b.isEmpty { return b }
        return identifyResult.product?.brand
    }

    private var nameText: String {
        if let n = evaluationResult?.product.name, !n.isEmpty { return n }
        return identifyResult.product?.name ?? L("Bilinmeyen ürün")
    }

    private var categoryLabel: String? {
        identifyResult.product?.subcategory ?? identifyResult.product?.categoryId
    }

    /// Confidence "high" değilse banner göster — kullanıcı match'in kesinlikle
    /// doğru olmadığını bilsin. Quick Scan host view'ı low/awaitingConfirmation
    /// case'ini ayrı handle ediyor; bu view sadece "medium" ve aşağısı için soft
    /// hint sağlar.
    private var shouldShowVerificationBanner: Bool {
        let conf = identifyResult.confidence?.lowercased()
        return conf != "high" && (identifyResult.product != nil)
    }

    private var verificationBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.alert)
            Text(L("Bu ürünü doğru tanıdığımdan tam emin değilim"))
                .font(Theme.Typo.caption.weight(.medium))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(Theme.alert.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                        .strokeBorder(Theme.alert.opacity(0.30), lineWidth: 1)
                )
        )
    }

    /// Fit score + verdict bölümü — gauge + pros/cons + reasons'ı `QuickEvaluationView`
    /// kapsüller. Mode'a göre `.scanning` veya `.reviewing` context'i verir, böylece
    /// verdict copy doğru framing'i alır (almalı mıyım? vs. ekliyorum, dikkat?).
    private func fitScoreSection(_ eval: QuickEvaluateResponse) -> some View {
        QuickEvaluationView(result: eval, context: mode == .preview ? .scanning : .reviewing)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.surface)
            )
    }

    /// AI evaluate çağrısı sürerken kullanıcıya "boşa beklemiyor" hissi veren
    /// ince kart. `QuickScanResultPanel`'in rotating status label'ları yerine
    /// burada tek satırlık sade bir hint var — bu view loading state'ini host'a
    /// devrediyor, sadece inline pending hint gösteriyor.
    private var aiLoadingHint: some View {
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
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surfaceLow)
        )
    }

    /// INCI listesinin kompakt özeti — `reviewAndAdd` modunda kullanıcı detayı
    /// görmek ister. Disclosure component değil, ilk N kalemi inline gösteren
    /// kart — kullanıcı uzun listeyi ürün detay sayfasında görebilir.
    private var inciSummarySection: some View {
        let inci = identifyResult.inciList
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Text("\(L("İçindekiler özeti")) · \(inci.count)")
                    .font(Theme.Typo.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .textCase(.uppercase)
                Spacer()
            }
            Text(inci.joined(separator: ", "))
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface)
        )
    }

    // MARK: - Bottom CTA

    @ViewBuilder
    private var bottomActionBar: some View {
        switch mode {
        case .preview:
            VStack(spacing: 8) {
                Button {
                    Haptics.light()
                    onClose?()
                } label: {
                    Text(L("Tamam, kapat"))
                        .font(Theme.Typo.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radius)
                                .fill(Theme.ink)
                        )
                        .foregroundStyle(Theme.onAccent)
                }
                if onAddToArchive != nil {
                    Button {
                        Haptics.heavy()
                        onAddToArchive?()
                    } label: {
                        Text(L("Arşive ekle"))
                            .font(Theme.Typo.body.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.radius)
                                    .strokeBorder(Theme.ink, lineWidth: 1.2)
                            )
                            .foregroundStyle(Theme.ink)
                    }
                }
            }

        case .reviewAndAdd:
            Button {
                Haptics.heavy()
                onAddToArchive?()
            } label: {
                Text(L("Arşive ekle"))
                    .font(Theme.Typo.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius)
                            .fill(Theme.ink)
                    )
                    .foregroundStyle(Theme.onAccent)
            }
        }
    }
}

#Preview("Preview mode — great fit") {
    NavigationStack {
        ProductIdentificationResultView(
            mode: .preview,
            identifyResult: ProductRecognizeResponse(
                product: nil,
                ingredients: nil,
                confidence: "high",
                source: "obf"
            ),
            evaluationResult: QuickEvaluateResponse(
                product: .init(id: "p1", name: "Hydrating Cleanser", brand: "CeraVe", categoryId: nil, photoUrl: nil),
                fitScore: 86,
                verdict: .greatFit,
                pros: ["Nemlendirici", "Kokusuz"],
                cons: [],
                duplicateProductId: nil,
                duplicateProductName: nil,
                reasons: ["Kuru cilt için uygun aktifler"],
                via: .preCheck
            ),
            isEvaluating: false,
            capturedImage: nil,
            photoUrl: nil,
            onClose: {},
            onAddToArchive: {}
        )
    }
}

#Preview("Review mode — evaluating") {
    NavigationStack {
        ProductIdentificationResultView(
            mode: .reviewAndAdd,
            identifyResult: ProductRecognizeResponse(
                product: nil,
                ingredients: nil,
                confidence: "medium",
                source: "incidecoder"
            ),
            evaluationResult: nil,
            isEvaluating: true,
            capturedImage: nil,
            photoUrl: nil,
            onAddToArchive: {}
        )
    }
}
