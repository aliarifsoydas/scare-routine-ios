import SwiftUI

/// Anasayfa — kişiselleştirilmiş selamlama + profil özet + rutin kartları + hızlı eylemler + son arşiv.
///
/// Onboarding'in OnboardingStepContainer disiplini ile aynı kompozisyon:
/// - 20pt horizontal padding her bölümde
/// - 20pt section spacing
/// - Theme dışı renk yok
/// - Pull-to-refresh ile son arşiv tazelenir
///
/// State kaynakları:
/// - `appState.currentUser?.displayName` → selamlama
/// - `appState.currentProfile?.skinType / birthDate / fitzpatrickType` → profil hero kartı
/// - `appState.locale` → tarih formatında (TR ↔︎ EN)
/// - `task` ile `ProductScanService.listMyProducts()` → son 5 ürün
struct HomeView: View {
    let user: AuthUser

    /// MainTabView'dan gelen programmatic tab navigation callback'i.
    /// `0` Home, `1` Arşiv, `2` Cilt, `3` Profil.
    var onNavigate: ((Int) -> Void)? = nil

    @Environment(AppState.self) private var appState

    @State private var recentProducts: [UserProductResponse] = []
    @State private var isLoadingRecents: Bool = true
    @State private var showAddProductSheet: Bool = false
    @State private var soonAlert: SoonAlert?
    /// RecentProductCard tap'inden açılan detay sheet'inin payload'u.
    @State private var selectedDetailItem: UserProductResponse?

    /// "Yakında" alert payload — başlık + mesaj.
    private struct SoonAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    // MARK: - Hesaplanan değerler

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return "Günaydın"
        case 12..<18: return "İyi günler"
        case 18..<22: return "İyi akşamlar"
        default:      return "İyi geceler"
        }
    }

    private var greetingSymbol: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return "sun.horizon.fill"
        case 12..<18: return "sun.max.fill"
        case 18..<22: return "sun.dust.fill"
        default:      return "moon.stars.fill"
        }
    }

    private var firstName: String? {
        let raw = appState.currentUser?.displayName ?? user.displayName
        guard let name = raw, !name.isEmpty else { return nil }
        return name.split(separator: " ").first.map(String.init)
    }

    private var todayDateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: appState.locale == "en" ? "en_US" : "tr_TR")
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: .now).capitalizedFirstLetter
    }

    private var profile: ProfileData? { appState.currentProfile }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        greetingHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        HomeProfileHeroCard(profile: profile) {
                            // MainTabView programmatic navigation — Profil tab'ına geçer.
                            // onNavigate yoksa (preview, eski caller) önceki soft fallback.
                            if let onNavigate {
                                onNavigate(3)
                            } else {
                                soonAlert = SoonAlert(
                                    title: "Profilini görüntüle",
                                    message: "Alt menüden \"Profil\" sekmesine geçerek bilgilerini düzenleyebilirsin."
                                )
                            }
                        }
                        .padding(.horizontal, 20)

                        // MARK: Bugün için (rutin kartları)
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Bugün için")
                            VStack(spacing: 10) {
                                HomeRoutineCard(
                                    icon: "sun.max.fill",
                                    title: "Sabah rutini",
                                    subtitle: "Henüz oluşturmadın",
                                    actionLabel: "Oluştur"
                                ) {
                                    soonAlert = SoonAlert(
                                        title: "Yakında",
                                        message: "Sabah rutini özelliği çok yakında geliyor. Cilt tipine göre özelleştirilmiş adımlar burada olacak."
                                    )
                                }
                                HomeRoutineCard(
                                    icon: "moon.stars.fill",
                                    title: "Akşam rutini",
                                    subtitle: "Henüz oluşturmadın",
                                    actionLabel: "Oluştur"
                                ) {
                                    soonAlert = SoonAlert(
                                        title: "Yakında",
                                        message: "Akşam rutini özelliği çok yakında geliyor. Cilt tipine göre özelleştirilmiş adımlar burada olacak."
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        // MARK: Hızlı eylemler
                        VStack(alignment: .leading, spacing: 12) {
                            sectionHeader("Hızlı eylemler")
                            quickActionsGrid
                                .padding(.horizontal, 20)
                        }

                        // MARK: Son arşiv
                        VStack(alignment: .leading, spacing: 12) {
                            recentHeader
                            recentRow
                        }

                        Spacer(minLength: 48)
                    }
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await loadRecents()
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showAddProductSheet) {
                AddProductFlowView { newItem in
                    // Optimistic insert — gelen item'ı en başa al ve 5'ten fazla varsa kırp.
                    recentProducts.insert(newItem, at: 0)
                    if recentProducts.count > 5 {
                        recentProducts = Array(recentProducts.prefix(5))
                    }
                }
            }
            .sheet(item: $selectedDetailItem) { item in
                ProductDetailView(
                    item: item,
                    onUpdated: { updated in
                        // Local cache'i optimistic patch'le (favori, arşiv durumu vs.)
                        if let idx = recentProducts.firstIndex(where: { $0.id == updated.id }) {
                            recentProducts[idx] = updated
                        }
                    },
                    onDeleted: { id in
                        recentProducts.removeAll { $0.id == id }
                    }
                )
            }
            .alert(item: $soonAlert) { item in
                Alert(
                    title: Text(item.title),
                    message: Text(item.message),
                    dismissButton: .default(Text("Tamam")) { Haptics.light() }
                )
            }
            .task { await loadRecents() }
        }
    }

    // MARK: - Bileşenler

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(greeting + (firstName.map { ", \($0)" } ?? ""))
                    .font(Theme.Typo.title)
                    .foregroundStyle(Theme.ink)
                Image(systemName: greetingSymbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.inkSoft)
                    .symbolRenderingMode(.hierarchical)
            }
            Text(todayDateString)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typo.headline)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 20)
    }

    private var quickActionsGrid: some View {
        let cols = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
        return LazyVGrid(columns: cols, spacing: 10) {
            HomeQuickActionTile(icon: "camera.viewfinder", label: "Ürün ekle", isEnabled: true) {
                showAddProductSheet = true
            }
            HomeQuickActionTile(icon: "list.bullet.clipboard", label: "Cilt logu", isEnabled: false) {
                soonAlert = SoonAlert(
                    title: "Yakında",
                    message: "Günlük cilt logu özelliği çok yakında — \"Cilt\" sekmesinden takibe başlayabilirsin."
                )
            }
            HomeQuickActionTile(icon: "sparkles", label: "AI öneri", isEnabled: false) {
                soonAlert = SoonAlert(
                    title: "Yakında",
                    message: "AI cilt önerileri için profil verilerini analiz eden öneri motorumuz hazırlanıyor."
                )
            }
        }
    }

    private var recentHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Son arşive eklenenler")
                .font(Theme.Typo.headline)
                .foregroundStyle(Theme.ink)
            Spacer()
            if !recentProducts.isEmpty {
                // Programmatic Arşiv tab'ına geçiş — MainTabView'ın selectedTab binding'ini kullanır.
                Button {
                    Haptics.light()
                    if let onNavigate {
                        onNavigate(1)
                    } else {
                        soonAlert = SoonAlert(
                            title: "Tüm ürünler",
                            message: "Alt menüden \"Arşiv\" sekmesine geçerek tüm ürünlerini görebilirsin."
                        )
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("Tümü")
                            .font(Theme.Typo.caption.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var recentRow: some View {
        if isLoadingRecents {
            HStack {
                ProgressView().tint(Theme.ink)
                Text("Yükleniyor...")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity, minHeight: 124)
            .padding(.horizontal, 20)
        } else if recentProducts.isEmpty {
            emptyRecentState
                .padding(.horizontal, 20)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(recentProducts) { product in
                        RecentProductCard(item: product) {
                            // Detay sheet aç — ProductDetailView, item'ı taşır
                            selectedDetailItem = product
                        }
                    }
                    RecentAddCard {
                        showAddProductSheet = true
                    }
                }
                .padding(.horizontal, 20)
            }
            // Yan kayan içerikte 5pt vertical nefes — kartların altında kesilmesin
            .padding(.vertical, 2)
        }
    }

    private var emptyRecentState: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: 48, height: 48)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Arşivin boş")
                    .font(Theme.Typo.headline)
                    .foregroundStyle(Theme.ink)
                Text("İlk ürününü ekleyerek başla")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
            }

            Spacer(minLength: 8)

            Button {
                Haptics.light()
                showAddProductSheet = true
            } label: {
                Text("Ekle")
                    .font(Theme.Typo.caption.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Theme.ink)
                    )
            }
            .buttonStyle(PressedScaleButtonStyle())
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
    }

    // MARK: - Veri

    @MainActor
    private func loadRecents() async {
        // Pull-to-refresh sırasında spinner'ı tekrar tetikleme — sadece ilk yüklemede.
        if recentProducts.isEmpty { isLoadingRecents = true }
        defer { isLoadingRecents = false }

        do {
            let all = try await ProductScanService.shared.listMyProducts()
            // Backend createdAt sıralı dönmüyor olabilir — defensive olarak yeni → eski sırala.
            // createdAt nil'leri en sona at.
            let sorted = all.sorted { a, b in
                switch (a.createdAt, b.createdAt) {
                case (let x?, let y?): return x > y
                case (.some, .none):   return true
                case (.none, .some):   return false
                case (.none, .none):   return false
                }
            }
            recentProducts = Array(sorted.prefix(5))
        } catch {
            // Sessizce başarısız — anasayfada error gösterme; kullanıcı yine de
            // diğer bölümleri kullanabilsin. Arşiv sekmesi gerçek error gösterir.
            recentProducts = []
        }
    }
}

// MARK: - Helper

private extension String {
    /// "cuma, 18 mayıs" → "Cuma, 18 mayıs"
    var capitalizedFirstLetter: String {
        guard let first = self.first else { return self }
        return first.uppercased() + self.dropFirst()
    }
}

#Preview {
    HomeView(user: AuthUser(
        id: "preview",
        email: "preview@example.com",
        displayName: "Ali Arif Soydaş",
        locale: "tr",
        createdAt: nil,
        isNewUser: false
    ))
    .environment(AppState())
}
