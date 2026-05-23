import SwiftUI

/// Kullanıcının kozmetik ürün arşivi.
/// Boşken davetkar empty state; ürünler varsa 2-sütun LazyVGrid.
/// Sağ üst "+" → AddProductFlowView (kamera + tanıma + ekleme).
struct ArchiveView: View {
    @State private var searchQuery = ""
    @State private var products: [UserProductResponse] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showAddSheet = false
    /// Grid'den seçilen ürün — ProductDetailView sheet'inin payload'u.
    @State private var selectedItem: UserProductResponse?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var filtered: [UserProductResponse] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return products }
        return products.filter { p in
            (p.name?.lowercased().contains(q) ?? false)
            || (p.brand?.lowercased().contains(q) ?? false)
            || (p.nickname?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                if isLoading {
                    loadingState
                } else if let err = loadError, products.isEmpty {
                    errorState(err)
                } else if products.isEmpty {
                    emptyState
                } else {
                    productGrid
                }
            }
            .navigationTitle(L("Arşiv"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .accessibilityLabel(L("Ürün ekle"))
                }
            }
            .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .automatic), prompt: L("Ürün ara"))
            .sheet(isPresented: $showAddSheet) {
                AddProductFlowView { newItem in
                    // Optimistic ekleme — başa al
                    products.insert(newItem, at: 0)
                }
            }
            .sheet(item: $selectedItem) { item in
                ProductDetailView(
                    item: item,
                    onUpdated: { updated in
                        if let idx = products.firstIndex(where: { $0.id == updated.id }) {
                            products[idx] = updated
                        }
                    },
                    onDeleted: { id in
                        products.removeAll { $0.id == id }
                    }
                )
            }
            .task { await load() }
            .refreshable { await load(showSpinner: false) }
        }
    }

    // MARK: - Yüklenme / hata

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Theme.ink)
            Text(L("Arşiv yükleniyor..."))
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.alert)
            Text(message)
                .font(Theme.Typo.body)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Haptics.light()
                Task { await load() }
            } label: {
                Text(L("Tekrar dene"))
                    .font(Theme.Typo.button)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.ink, lineWidth: 1.5)
                    )
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Theme.inkMute)

            VStack(spacing: 8) {
                Text(L("Arşivin boş"))
                    .font(Theme.Typo.headline)
                    .foregroundStyle(Theme.ink)
                Text(L("Kullandığın kozmetikleri fotoğraflayarak\narşivine ekleyebilirsin."))
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
            }

            Button {
                Haptics.light()
                showAddSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.viewfinder")
                    Text(L("İlk ürünü ekle"))
                        .font(Theme.Typo.button)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .fill(Theme.ink)
                )
                .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.plain)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Grid

    private var productGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(filtered) { p in
                    Button {
                        Haptics.light()
                        selectedItem = p
                    } label: {
                        ProductCard(item: p)
                    }
                    .buttonStyle(PressedScaleButtonStyle())
                    .accessibilityLabel(p.name ?? p.nickname ?? L("Ürün"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)

            if !filtered.isEmpty {
                Text(String(format: L("%d ürün"), filtered.count))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkMute)
                    .padding(.bottom, 16)
            }
        }
        .scrollIndicators(.hidden)
        .overlay {
            if !searchQuery.isEmpty && filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Theme.inkMute)
                    Text(L("Eşleşen ürün yok"))
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
    }

    // MARK: - Veri

    @MainActor
    private func load(showSpinner: Bool = true) async {
        if showSpinner { isLoading = true }
        loadError = nil
        defer { isLoading = false }

        do {
            products = try await ProductScanService.shared.listMyProducts()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
