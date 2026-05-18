import SwiftUI

/// Arşivdeki bir ürünün detay sheet'i — native iOS Form pattern.
///
/// Açılış: hem `HomeView`'daki `RecentProductCard` hem `ArchiveView`'deki `ProductCard`
/// tap'inden `.sheet(item:)` ile sunulur — `UserProductResponse` arşiv kaydını taşır.
///
/// Akış:
/// 1. Sheet açılır, üstte arşivdeki yerel bilgilerle render başlar (hızlı görünüm)
/// 2. `.task` içinde `getProductDetail(productId:)` çağrısı ile katalog detayı +
///    INCI listesi çekilir (productId varsa)
/// 3. Tercihler section'ındaki native Toggle'lar (favori/arşivde sakla) PATCH tetikler;
///    optimistic — fail durumunda state geri alınır.
/// 4. Destructive "Arşivden sil" satırı confirmation dialog açar.
struct ProductDetailView: View {
    let item: UserProductResponse

    /// Toggle sonrası parent'a haber ver — güncel local snapshot'ı geçer.
    var onUpdated: ((UserProductResponse) -> Void)? = nil

    /// Silme başarılıysa parent listeden item'ı kaldırır.
    var onDeleted: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var fullDetail: RecognizedProduct? = nil
    @State private var ingredients: [RecognizedIngredient] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?

    /// Local mutable kopya — UI optimistic patch yapar, server PATCH success
    /// olduğunda parent'a bunu döner.
    @State private var localItem: UserProductResponse

    /// Native Toggle'ların doğrudan bağlandığı state. `onChange` ile backend'e gönderilir;
    /// fail durumunda guard flag yardımıyla state silently rollback edilir.
    @State private var isFavorite: Bool
    @State private var isArchived: Bool

    /// Toggle değişimini programatik rollback sırasında tekrar tetiklenmemesi için flag.
    @State private var suppressFavoriteSync: Bool = false
    @State private var suppressArchivedSync: Bool = false

    @State private var mutationError: String?
    @State private var showDeleteConfirm: Bool = false

    init(
        item: UserProductResponse,
        onUpdated: ((UserProductResponse) -> Void)? = nil,
        onDeleted: ((String) -> Void)? = nil
    ) {
        self.item = item
        self.onUpdated = onUpdated
        self.onDeleted = onDeleted
        self._localItem = State(initialValue: item)
        self._isFavorite = State(initialValue: item.isFavorite)
        self._isArchived = State(initialValue: item.isArchived)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                heroSection
                detailsSection
                ingredientsSection
                preferencesSection
                deleteSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle(displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Haptics.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(Theme.inkSoft)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel("Kapat")
                }
            }
            .confirmationDialog(
                "Bu ürünü arşivinden silmek istiyor musun?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Sil", role: .destructive) {
                    Task { await performDelete() }
                }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Bu işlem geri alınamaz.")
            }
            .alert(
                "İşlem başarısız",
                isPresented: Binding(
                    get: { mutationError != nil },
                    set: { if !$0 { mutationError = nil } }
                ),
                presenting: mutationError
            ) { _ in
                Button("Tamam", role: .cancel) { mutationError = nil }
            } message: { msg in
                Text(msg)
            }
            .task { await loadDetail() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    /// Hero görsel + brand/name/category — Form içinde header'sız bir Section olarak
    /// otururken, listSectionRowBackground kaldırılarak temiz bir hero görünümü verilir.
    private var heroSection: some View {
        Section {
            VStack(spacing: 14) {
                AsyncRemoteImage(url: photoURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .strokeBorder(Theme.divider, lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    if let brand = displayBrand, !brand.isEmpty {
                        Text(brand.uppercased())
                            .font(Theme.Typo.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                    }

                    Text(displayName)
                        .font(Theme.Typo.title)
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let sub = subtitleText {
                        Text(sub)
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 12, trailing: 4))
            .listRowSeparator(.hidden)
        }
    }

    private var detailsSection: some View {
        Section {
            if let vol = formattedVolume {
                LabeledContent("Hacim", value: vol)
            }
            if let pao = fullDetail?.paoMonths, pao > 0 {
                LabeledContent("PAO", value: "\(pao) ay")
            }
            if let cat = fullDetail?.category, !cat.isEmpty {
                LabeledContent("Kategori", value: cat)
            }
            if let created = localItem.createdAt {
                LabeledContent("Eklendi", value: Self.shortDate(created))
            }
            if fullDetail?.verified == true {
                LabeledContent("Doğrulanma") {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.success)
                        Text("Doğrulanmış")
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        } header: {
            Text("Detaylar")
        } footer: {
            if let err = loadError {
                Text(err)
                    .foregroundStyle(Theme.alert)
            }
        }
        .listRowBackground(Theme.surface.opacity(0.6))
    }

    @ViewBuilder
    private var ingredientsSection: some View {
        let hasContent = !ingredients.isEmpty || isLoading

        if hasContent {
            Section {
                if isLoading && ingredients.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().tint(Theme.inkSoft)
                        Text("Yükleniyor…")
                            .foregroundStyle(Theme.inkSoft)
                    }
                } else if !ingredients.isEmpty {
                    DisclosureGroup {
                        ForEach(sortedIngredients, id: \.id) { ing in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(ing.orderIndex + 1).")
                                    .font(Theme.Typo.caption.weight(.semibold))
                                    .foregroundStyle(Theme.inkMute)
                                    .frame(width: 30, alignment: .leading)
                                Text(ing.inciName)
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } label: {
                        HStack {
                            Text("Bileşenler")
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(ingredients.count)")
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .tint(Theme.inkSoft)
                }

                if let claims = fullDetail?.claims, !claims.isEmpty {
                    DisclosureGroup {
                        ForEach(claims, id: \.self) { claim in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.success)
                                Text(claim)
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } label: {
                        HStack {
                            Text("Öne çıkanlar")
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(claims.count)")
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .tint(Theme.inkSoft)
                }
            } header: {
                Text("İçindekiler (INCI)")
            }
            .listRowBackground(Theme.surface.opacity(0.6))
        }
    }

    private var preferencesSection: some View {
        Section {
            Toggle(isOn: $isFavorite) {
                Label("Favori", systemImage: "star.fill")
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.ink)
            .onChange(of: isFavorite) { _, newValue in
                guard !suppressFavoriteSync else { return }
                Task { await syncFavorite(newValue) }
            }

            Toggle(isOn: $isArchived) {
                Label("Arşivde sakla", systemImage: "tray.full.fill")
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.ink)
            .onChange(of: isArchived) { _, newValue in
                guard !suppressArchivedSync else { return }
                Task { await syncArchived(newValue) }
            }
        } header: {
            Text("Tercihler")
        }
        .listRowBackground(Theme.surface.opacity(0.6))
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                Haptics.warning()
                showDeleteConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Label("Arşivden sil", systemImage: "trash")
                    Spacer()
                }
            }
        }
        .listRowBackground(Theme.surface.opacity(0.6))
    }

    // MARK: - Data fetch

    @MainActor
    private func loadDetail() async {
        guard let pid = item.productId, !pid.isEmpty else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let detail = try await ProductScanService.shared.getProductDetail(productId: pid)
            self.fullDetail = detail.product
            self.ingredients = detail.ingredients
        } catch APIError.notFound {
            // Katalogdan kaldırılmış olabilir — sessiz devam.
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? "Detaylar yüklenemedi."
        }
    }

    // MARK: - Toggle sync (optimistic + rollback)

    @MainActor
    private func syncFavorite(_ newValue: Bool) async {
        do {
            try await ProductScanService.shared.updateMyProduct(
                localItem.id,
                payload: UserProductUpdateRequest(isFavorite: newValue)
            )
            Haptics.success()
            if let patched = patched(localItem, isFavorite: newValue, isArchived: nil) {
                localItem = patched
                onUpdated?(patched)
            }
        } catch {
            Haptics.error()
            mutationError = (error as? LocalizedError)?.errorDescription ?? "Favori güncellenemedi."
            suppressFavoriteSync = true
            isFavorite = !newValue
            suppressFavoriteSync = false
        }
    }

    @MainActor
    private func syncArchived(_ newValue: Bool) async {
        do {
            try await ProductScanService.shared.updateMyProduct(
                localItem.id,
                payload: UserProductUpdateRequest(isArchived: newValue)
            )
            Haptics.success()
            if let patched = patched(localItem, isFavorite: nil, isArchived: newValue) {
                localItem = patched
                onUpdated?(patched)
            }
        } catch {
            Haptics.error()
            mutationError = (error as? LocalizedError)?.errorDescription ?? "Arşiv durumu güncellenemedi."
            suppressArchivedSync = true
            isArchived = !newValue
            suppressArchivedSync = false
        }
    }

    @MainActor
    private func performDelete() async {
        do {
            try await ProductScanService.shared.deleteMyProduct(localItem.id)
            Haptics.success()
            onDeleted?(localItem.id)
            try? await Task.sleep(nanoseconds: 200_000_000)
            dismiss()
        } catch {
            Haptics.error()
            mutationError = (error as? LocalizedError)?.errorDescription ?? "Silme başarısız."
        }
    }

    // MARK: - Derived

    private var photoURL: URL? {
        if let s = localItem.photoUrl, let u = URL(string: s) { return u }
        if let s = fullDetail?.imageUrl, let u = URL(string: s) { return u }
        return nil
    }

    private var displayBrand: String? {
        if let b = localItem.brand, !b.isEmpty { return b }
        if let b = fullDetail?.brand, !b.isEmpty { return b }
        return nil
    }

    private var displayName: String {
        if let n = localItem.name, !n.isEmpty { return n }
        if let n = fullDetail?.name, !n.isEmpty { return n }
        if let nick = localItem.nickname, !nick.isEmpty { return nick }
        return "Adsız ürün"
    }

    private var subtitleText: String? {
        var parts: [String] = []
        if let cat = fullDetail?.category, !cat.isEmpty { parts.append(cat) }
        if let sub = fullDetail?.subcategory, !sub.isEmpty { parts.append(sub) }
        if let nick = localItem.nickname, !nick.isEmpty { parts.append(nick) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private var sortedIngredients: [RecognizedIngredient] {
        ingredients.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var formattedVolume: String? {
        guard let vol = fullDetail?.volumeMl, vol > 0 else { return nil }
        if vol.rounded() == vol { return "\(Int(vol)) ml" }
        return String(format: "%.1f ml", vol)
    }

    private static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: date)
    }

    /// `UserProductResponse` Decodable-only init'e sahip — alanları kopyalamak için
    /// JSON roundtrip yapıyoruz. APIClient'ın `convertFromSnakeCase` stratejisini taklit eder.
    private func patched(_ source: UserProductResponse, isFavorite: Bool?, isArchived: Bool?) -> UserProductResponse? {
        var dict: [String: Any] = [
            "id": source.id,
            "is_favorite": isFavorite ?? source.isFavorite,
            "is_archived": isArchived ?? source.isArchived
        ]
        if let v = source.productId { dict["product_id"] = v }
        if let v = source.brand { dict["brand"] = v }
        if let v = source.name { dict["name"] = v }
        if let v = source.nickname { dict["nickname"] = v }
        if let v = source.photoUrl { dict["photo_url"] = v }
        if let v = source.addedVia { dict["added_via"] = v }
        if let v = source.createdAt { dict["created_at"] = v.timeIntervalSince1970 }

        guard
            let data = try? JSONSerialization.data(withJSONObject: dict),
            let decoded = try? Self.makeDecoder().decode(UserProductResponse.self, from: data)
        else { return nil }
        return decoded
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}
