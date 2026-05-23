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
                safetyBadgesSection
                activesSection
                concernsSection
                usageSection
                warningsSection
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
                    .accessibilityLabel(L("Kapat"))
                }
            }
            .confirmationDialog(
                L("Bu ürünü arşivinden silmek istiyor musun?"),
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(L("Sil"), role: .destructive) {
                    Task { await performDelete() }
                }
                Button(L("Vazgeç"), role: .cancel) {}
            } message: {
                Text(L("Bu işlem geri alınamaz."))
            }
            .alert(
                L("İşlem başarısız"),
                isPresented: Binding(
                    get: { mutationError != nil },
                    set: { if !$0 { mutationError = nil } }
                ),
                presenting: mutationError
            ) { _ in
                Button(L("Tamam"), role: .cancel) { mutationError = nil }
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
                // Hero — .fit modunda göster ki dikey çekilmiş ürün etiket fotoları
                // (Cosmed Atopia, Siveno gibi şişe/kutu fotorafları) yarım çıkmasın.
                // Theme.surfaceLow arka plan + center align dikey foto için doğal.
                AsyncRemoteImage(url: photoURL, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .background(Theme.surfaceLow)
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

                    // Verification badge — crowdsource doğrulama durumu
                    if let badge = verificationBadge {
                        HStack(spacing: 6) {
                            Image(systemName: badge.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(badge.tint)
                            Text(badge.label)
                                .font(Theme.Typo.caption.weight(.medium))
                                .foregroundStyle(Theme.ink)
                            if let version = fullDetail?.formulaVersion, version > 1 {
                                Text(String(format: L("• Formül v%lld"), version))
                                    .font(Theme.Typo.caption)
                                    .foregroundStyle(Theme.inkSoft)
                            }
                            if let region = fullDetail?.region, !region.isEmpty {
                                Text("• \(region)")
                                    .font(Theme.Typo.caption)
                                    .foregroundStyle(Theme.inkSoft)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(badge.tint.opacity(0.12)))
                        .padding(.top, 4)
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

    /// Pregnancy / vegan / fragrance-free / sulfate-free / silicone-free / alcohol-free
    /// flag'leri — INCI-derived deterministik enrichment'tan gelir. Sadece bilinen
    /// (nil olmayan) bayrakları gösteririz, kullanıcı net "var/yok" görsün.
    @ViewBuilder
    private var safetyBadgesSection: some View {
        let badges = safetyBadges
        if !badges.isEmpty {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(badges, id: \.label) { b in
                        HStack(spacing: 6) {
                            Image(systemName: b.systemImage)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(b.tint)
                            Text(b.label)
                                .font(Theme.Typo.caption.weight(.medium))
                                .foregroundStyle(Theme.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(b.tint.opacity(0.12))
                        )
                    }
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                .listRowBackground(Color.clear)
            } header: {
                Text(L("Güvenlik ve içerik"))
            }
        }
    }

    /// AI-extracted aktif maddeler — Niacinamide, Retinol, Salicylic Acid gibi.
    /// Varsa yüzde + rol etiketiyle gösteriliyor.
    @ViewBuilder
    private var activesSection: some View {
        if let actives = fullDetail?.keyActives, !actives.isEmpty {
            Section {
                ForEach(actives, id: \.name) { active in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(active.name)
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if let role = active.role, !role.isEmpty {
                                Text(role.capitalized)
                                    .font(Theme.Typo.caption)
                                    .foregroundStyle(Theme.inkSoft)
                            }
                        }
                        Spacer(minLength: 8)
                        if let pct = active.percent {
                            Text("%\(String(format: "%g", pct))")
                                .font(Theme.Typo.caption.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Theme.success.opacity(0.18)))
                        }
                    }
                }
            } header: {
                HStack {
                    Text(L("Aktif maddeler"))
                    Spacer()
                    Text("\(actives.count)").foregroundStyle(Theme.inkSoft)
                }
            }
            .listRowBackground(Theme.surface.opacity(0.6))
        }
    }

    /// Cilt tipi uygunluğu + ürünün adreslediği sorunlar.
    @ViewBuilder
    private var concernsSection: some View {
        let suitable = fullDetail?.suitableSkinTypes ?? []
        let unsuitable = fullDetail?.unsuitableSkinTypes ?? []
        let concerns = fullDetail?.concernsAddressed ?? []
        let allergens = fullDetail?.allergensFlags ?? []

        if !suitable.isEmpty || !unsuitable.isEmpty || !concerns.isEmpty || !allergens.isEmpty {
            Section {
                if !suitable.isEmpty {
                    LabeledContent(L("Uygun cilt")) {
                        Text(suitable.map { $0.capitalized }.joined(separator: ", "))
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if !unsuitable.isEmpty {
                    LabeledContent(L("Kaçınılması gereken")) {
                        Text(unsuitable.map { $0.capitalized }.joined(separator: ", "))
                            .foregroundStyle(Theme.alert)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if !concerns.isEmpty {
                    LabeledContent(L("Adreslediği")) {
                        Text(concerns.map { $0.capitalized }.joined(separator: ", "))
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if let ph = fullDetail?.ph {
                    LabeledContent("pH", value: String(format: "%.1f", ph))
                }
                if !allergens.isEmpty {
                    DisclosureGroup {
                        ForEach(allergens, id: \.self) { a in
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.alert)
                                Text(a.capitalized)
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                    } label: {
                        HStack {
                            Text(L("EU 26 alerjen"))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(allergens.count)").foregroundStyle(Theme.alert)
                        }
                    }
                    .tint(Theme.inkSoft)
                }
            } header: {
                Text(L("Cilt uyumu"))
            }
            .listRowBackground(Theme.surface.opacity(0.6))
        }
    }

    /// Kullanım talimatı — ürün etiketinden veya marka resmi sayfasından okunmuş.
    /// Salt kaynaklı veri, kaynaksız AI generation yapmıyoruz.
    @ViewBuilder
    private var usageSection: some View {
        if let txt = fullDetail?.usageDirections, !txt.isEmpty {
            Section {
                Text(txt)
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            } header: {
                Label(L("Nasıl kullanılır"), systemImage: "hand.tap")
            }
            .listRowBackground(Theme.surface.opacity(0.6))
        }
    }

    @ViewBuilder
    private var warningsSection: some View {
        let warn = fullDetail?.warnings ?? ""
        let storage = fullDetail?.storageInstructions ?? ""
        let target = fullDetail?.targetAudience ?? ""
        let manu = fullDetail?.manufacturer ?? ""
        if !warn.isEmpty || !storage.isEmpty || !target.isEmpty || !manu.isEmpty {
            Section {
                if !warn.isEmpty {
                    LabeledContent(L("Uyarılar")) {
                        Text(warn)
                            .foregroundStyle(Theme.alert)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !storage.isEmpty {
                    LabeledContent(L("Saklama")) {
                        Text(storage)
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !target.isEmpty {
                    LabeledContent(L("Hedef"), value: target)
                }
                if !manu.isEmpty {
                    LabeledContent(L("Üretici")) {
                        Text(manu)
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text(L("Uyarılar & saklama"))
            }
            .listRowBackground(Theme.surface.opacity(0.6))
        }
    }

    private var detailsSection: some View {
        Section {
            if let vol = formattedVolume {
                LabeledContent(L("Hacim"), value: vol)
            }
            if let pao = fullDetail?.paoMonths, pao > 0 {
                LabeledContent(L("PAO"), value: String(format: L("%lld ay"), pao))
            }
            if let cat = fullDetail?.category, !cat.isEmpty {
                LabeledContent(L("Kategori"), value: cat)
            }
            if let created = localItem.createdAt {
                LabeledContent(L("Eklendi"), value: Self.shortDate(created))
            }
            if fullDetail?.verified == true {
                LabeledContent(L("Doğrulanma")) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.success)
                        Text(L("Doğrulanmış"))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        } header: {
            Text(L("Detaylar"))
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
                        Text(L("Yükleniyor…"))
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
                            Text(L("Bileşenler"))
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
                            Text(L("Öne çıkanlar"))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(claims.count)")
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .tint(Theme.inkSoft)
                }
            } header: {
                Text(L("İçindekiler (INCI)"))
            }
            .listRowBackground(Theme.surface.opacity(0.6))
        }
    }

    private var preferencesSection: some View {
        Section {
            Toggle(isOn: $isFavorite) {
                Label(L("Favori"), systemImage: "star.fill")
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.ink)
            .onChange(of: isFavorite) { _, newValue in
                guard !suppressFavoriteSync else { return }
                Task { await syncFavorite(newValue) }
            }

            Toggle(isOn: $isArchived) {
                Label(L("Arşivde sakla"), systemImage: "tray.full.fill")
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.ink)
            .onChange(of: isArchived) { _, newValue in
                guard !suppressArchivedSync else { return }
                Task { await syncArchived(newValue) }
            }
        } header: {
            Text(L("Tercihler"))
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
                    Label(L("Arşivden sil"), systemImage: "trash")
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
            loadError = (error as? LocalizedError)?.errorDescription ?? L("Detaylar yüklenemedi.")
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
            mutationError = (error as? LocalizedError)?.errorDescription ?? L("Favori güncellenemedi.")
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
            mutationError = (error as? LocalizedError)?.errorDescription ?? L("Arşiv durumu güncellenemedi.")
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
            mutationError = (error as? LocalizedError)?.errorDescription ?? L("Silme başarısız.")
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
        return L("Adsız ürün")
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

    private struct SafetyBadge {
        let label: String
        let systemImage: String
        let tint: Color
    }

    private struct VerificationBadge {
        let label: String
        let systemImage: String
        let tint: Color
    }

    /// Crowdsource doğrulama badge'i (hero section'da görünür).
    /// 1 tarama = "Tek tarama" (gri), 2-4 = "Doğrulanıyor" (sarı),
    /// 5+ = "Doğrulanmış" (yeşil). INCI typo sayısı yüksekse "ham veri" uyarısı.
    private var verificationBadge: VerificationBadge? {
        guard let d = fullDetail else { return nil }
        guard let count = d.verifiedCount else { return nil }
        if count >= 5 {
            return .init(
                label: String(format: L("Doğrulanmış • %lld tarama"), count),
                systemImage: "checkmark.seal.fill",
                tint: Theme.success
            )
        }
        if count >= 2 {
            return .init(
                label: String(format: L("Doğrulanıyor • %lld tarama"), count),
                systemImage: "checkmark.circle",
                tint: Theme.accent
            )
        }
        return .init(
            label: L("Tek tarama"),
            systemImage: "person.fill",
            tint: Theme.inkSoft
        )
    }

    /// fullDetail'den safety bayraklarını UI grid'i için derler.
    /// pregnancy_safe / vegan / cruelty_free / fragrance/sulfate/silicone/alcohol-free.
    /// nil bayraklar gösterilmez, sadece kesin pozitif/negatif olanlar görünür.
    private var safetyBadges: [SafetyBadge] {
        guard let d = fullDetail else { return [] }
        var out: [SafetyBadge] = []
        if let v = d.pregnancySafe {
            out.append(.init(
                label: v ? L("Hamilelikte güvenli") : L("Hamilelikte dikkat"),
                systemImage: v ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                tint: v ? Theme.success : Theme.alert
            ))
        }
        if let v = d.vegan {
            out.append(.init(
                label: v ? L("Vegan") : L("Hayvansal içerik"),
                systemImage: v ? "leaf.fill" : "pawprint.fill",
                tint: v ? Theme.success : Theme.inkSoft
            ))
        }
        if d.crueltyFree == true {
            out.append(.init(label: L("Cruelty-free"), systemImage: "hand.raised.fill", tint: Theme.success))
        }
        if let v = d.fragranceFree, v {
            out.append(.init(label: L("Parfümsüz"), systemImage: "nose", tint: Theme.success))
        }
        if let v = d.sulfateFree, v {
            out.append(.init(label: L("Sülfatsız"), systemImage: "drop.fill", tint: Theme.success))
        }
        if let v = d.siliconeFree, v {
            out.append(.init(label: L("Silikonsuz"), systemImage: "circle.dotted", tint: Theme.success))
        }
        if let v = d.alcoholFree, v {
            out.append(.init(label: L("Alkolsüz"), systemImage: "drop", tint: Theme.success))
        }
        return out
    }

    private static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = LanguageManager.shared.effectiveLocale
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
