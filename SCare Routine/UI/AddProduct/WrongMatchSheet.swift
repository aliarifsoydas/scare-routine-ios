import SwiftUI

/// "Bu yanlış ürün" düzeltme sheet'i — kullanıcı recognition pipeline'ının yanlış
/// tahmin verdiği durumlarda, gerçekten taradığı ürünü manuel arar ve düzeltir.
///
/// **Akış**:
/// 1. Kullanıcı `WrongMatchFooter`'a tıkladı → bu sheet açılır.
/// 2. SearchBar ile katalog arar (`ProductScanService.shared.search(query:)`)
/// 3. Sonuçtan birini seçer → `confirmRecognition(attemptId, correct: false, correctedProductId: ...)`
/// 4. Veya "Hiçbiri uymuyor" → `confirmRecognition(attemptId, correct: false, correctedProductId: nil)`
/// 5. Veya "Listede yok — manuel ekle" → opsiyonel manuel-entry callback tetiklenir
///
/// **Veri toplama**: Bu sheet'in confirm sinyali fine-tune dataset için kritik. Kullanıcı
/// pas geçerse footer hiç görünmemiş gibi davranır; aksiyon alırsa backend yanlış match'in
/// gerçek ürününü öğrenir.
///
/// **Defensive**: Boş arama, hata durumu, hiç sonuç vs. defensive handle edilir; sheet'i
/// blocking yapmaz — kullanıcı her zaman "İptal" ile çıkabilir.
struct WrongMatchSheet: View {

    // MARK: - Inputs

    /// Hangi recognition attempt'i için düzeltme veriliyor.
    let attemptId: String

    /// Sheet kapanırken caller'a haber ver — başarı (correctedProductId varsa) veya
    /// kullanıcı sadece kapattıysa nil.
    ///
    /// **Caller responsibility**: parent bu callback ile (a) UI'ı refresh edebilir
    /// (örn. yeni ürüne navigate), (b) toast/banner gösterebilir, veya (c) hiçbir şey
    /// yapmayabilir. Bu sheet sadece sinyali geçer.
    var onCorrected: ((RecognizedProduct?) -> Void)? = nil

    /// "Listede yok — manuel ekle" CTA → manuel ekleme flow'unu tetikle.
    /// Parent vermezse bu satır gizlenir.
    var onManualEntryRequested: (() -> Void)? = nil

    // MARK: - State

    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var results: [RecognizedProduct] = []
    @State private var isSearching: Bool = false
    @State private var selectedCorrection: RecognizedProduct?
    @State private var isSubmitting: Bool = false
    @State private var submitError: String?
    /// Debounce token — kullanıcı yazarken her keypress'te query atmamak için
    /// `searchText` değişiminden 350ms sonra arama tetiklenir. Yeni keypress
    /// gelirse eski task'ı iptal et.
    @State private var searchTask: Task<Void, Never>?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                searchField
                resultsList
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle(L("Doğru ürünü seç"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("İptal")) {
                        Haptics.light()
                        dismiss()
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
            .safeAreaInset(edge: .bottom) {
                footerActions
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .background(Theme.canvas.opacity(0.95))
            }
        }
    }

    // MARK: - Sections

    /// Açıklayıcı subtitle — kullanıcı niye düzeltiyor olduğunu anlasın, motive et.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Tanıdığım ürün yanlışsa, hangisini taradığını söyle — modeli geliştirmemize yardım edersin."))
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// Custom search bar — `searchable` modifier yerine kompakt inline TextField.
    /// Sheet içinde `searchable` üst navigation'a iter, modal'da görünüm garip.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Theme.inkSoft)
            TextField(L("Ürün ara..."), text: $searchText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    triggerSearch(immediate: true)
                }
                .onChange(of: searchText) { _, _ in
                    triggerSearch(immediate: false)
                }
            if isSearching {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.inkSoft)
            } else if !searchText.isEmpty {
                Button {
                    Haptics.light()
                    searchText = ""
                    results = []
                    selectedCorrection = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkMute)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(Theme.surface)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    /// Arama sonuçları listesi + boş state'ler. Submit error de buraya gömülü.
    @ViewBuilder
    private var resultsList: some View {
        if let err = submitError {
            errorBanner(err)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }

        if results.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(results) { product in
                        resultRow(product)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
    }

    /// Tek satır arama sonucu — tap → seç (tekrar tap → deselect).
    /// Sağda checkmark ikonu seçili durum gösterir.
    private func resultRow(_ product: RecognizedProduct) -> some View {
        let isSelected = product.id == selectedCorrection?.id
        return Button {
            Haptics.selection()
            selectedCorrection = isSelected ? nil : product
        } label: {
            HStack(spacing: 12) {
                AsyncRemoteImage(url: resolveImageURL(product.imageUrl))
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    if let brand = product.brand, !brand.isEmpty {
                        Text(brand.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                    }
                    Text(product.name ?? L("Bilinmeyen ürün"))
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Theme.ink : Theme.inkMute)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(isSelected ? Theme.surfaceLow : Theme.surface)
            )
        }
        .buttonStyle(.plain)
    }

    /// Boş state — kullanıcı arama yapmadıysa hint, yaptıysa "sonuç yok" mesajı.
    @ViewBuilder
    private var emptyState: some View {
        let hasQuery = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(spacing: 10) {
            Spacer(minLength: 24)
            Image(systemName: hasQuery && !isSearching ? "magnifyingglass" : "doc.text.magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.inkMute)
            Text(hasQuery && !isSearching
                 ? L("Sonuç bulunamadı")
                 : L("Ürün ara..."))
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Submit hatası inline banner — sheet'i kapatmaz, kullanıcı tekrar dener.
    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.alert)
            Text(msg)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.alert)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                .fill(Theme.alert.opacity(0.10))
        )
    }

    /// Footer aksiyonları:
    /// - Primary: "Bu doğru" (selectedCorrection varsa enabled)
    /// - Secondary: "Hiçbiri uymuyor" (her zaman görünür)
    /// - Tertiary: "Listede yok — manuel ekle" (parent callback verirse)
    private var footerActions: some View {
        VStack(spacing: 8) {
            PrimaryActionButton(
                title: L("Bu doğru"),
                systemImage: "checkmark",
                isEnabled: selectedCorrection != nil && !isSubmitting,
                isLoading: isSubmitting,
                hapticStyle: .heavy
            ) {
                Task { await submitCorrection() }
            }

            Button {
                Haptics.light()
                Task { await submitNoneMatch() }
            } label: {
                Text(L("Hiçbiri uymuyor"))
                    .font(Theme.Typo.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius)
                            .strokeBorder(Theme.divider, lineWidth: 1)
                    )
                    .foregroundStyle(Theme.inkSoft)
            }
            .disabled(isSubmitting)

            if onManualEntryRequested != nil {
                Button {
                    Haptics.light()
                    // Sheet'i kapat ve parent'a manuel ekleme isteği bildir.
                    // "Hiçbiri uymuyor"dan farklı: bu hiç confirm SİGNAL'i göndermez,
                    // sadece manuel akışı tetikler. Backend için bu nötr (yanlış demedi).
                    dismiss()
                    onManualEntryRequested?()
                } label: {
                    Text(L("Listede yok — manuel ekle"))
                        .font(Theme.Typo.caption)
                        .underline()
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(.top, 2)
                .disabled(isSubmitting)
            }
        }
    }

    // MARK: - Logic

    /// Debounce'lı arama tetikleyici. `immediate=true` → debounce'ı atla (submit veya
    /// keyboard return). Yoksa 350ms bekle, başka keypress gelirse iptal et.
    private func triggerSearch(immediate: Bool) {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            // Boş query — sonuç ve seçim temizle, loading bitir.
            results = []
            selectedCorrection = nil
            isSearching = false
            return
        }
        searchTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            if Task.isCancelled { return }
            await performSearch(query)
        }
    }

    @MainActor
    private func performSearch(_ query: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            let resp = try await ProductScanService.shared.search(query: query)
            if Task.isCancelled { return }
            results = resp.products
            // Eski seçim listede yoksa temizle.
            if let sel = selectedCorrection, !results.contains(where: { $0.id == sel.id }) {
                selectedCorrection = nil
            }
        } catch is CancellationError {
            return
        } catch {
            // Network/decode hatası — empty results göster ama silent log. Kullanıcı
            // tekrar dene yazsın; sheet bloklayıcı hata göstermek istemiyoruz.
            results = []
            #if DEBUG
            print("[WrongMatchSheet] search failed: \(error)")
            #endif
        }
    }

    /// Kullanıcı bir ürün seçti → backend'e "correct: false, correctedProductId: X" yolla.
    @MainActor
    private func submitCorrection() async {
        guard let selected = selectedCorrection else { return }
        submitError = nil
        isSubmitting = true
        defer { isSubmitting = false }

        // confirmRecognition fire-and-forget değil; başarı durumunda dismiss + callback.
        await ProductScanService.shared.confirmRecognition(
            attemptId: attemptId,
            correct: false,
            correctedProductId: selected.id
        )
        // ProductScanService.confirmRecognition error swallow ediyor (.warning log).
        // Bu yüzden buraya gelirsek başarı varsayıyoruz. Future: backend hatasını
        // yüzeye çıkarmak için ProductScanService imzasını değiştir (yasaklı şu an).
        Haptics.success()
        onCorrected?(selected)
        dismiss()
    }

    /// "Hiçbiri uymuyor" — kullanıcı recognition'ı yanlış dedi ama doğru ürünü de bilmiyor.
    /// Backend `correctedProductId: nil` ile sinyali alır; fine-tune dataset için yine
    /// değerli (negatif örnek).
    @MainActor
    private func submitNoneMatch() async {
        submitError = nil
        isSubmitting = true
        defer { isSubmitting = false }
        await ProductScanService.shared.confirmRecognition(
            attemptId: attemptId,
            correct: false,
            correctedProductId: nil
        )
        Haptics.success()
        onCorrected?(nil)
        dismiss()
    }

    /// Backend `image_url` field'i bazen relative ("/v1/images/...") bazen absolute döner.
    /// Relative ise AppConfig.baseURL ile birleştir.
    private func resolveImageURL(_ raw: String?) -> URL? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        if let abs = URL(string: raw), abs.scheme != nil { return abs }
        return URL(string: raw, relativeTo: AppConfig.baseURL)?.absoluteURL
    }
}

#Preview {
    WrongMatchSheet(
        attemptId: "attempt_demo_123",
        onCorrected: { _ in },
        onManualEntryRequested: {}
    )
}
