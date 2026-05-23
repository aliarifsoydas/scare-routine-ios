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
    /// Quick Scan akışı — `AddProductFlowView(mode: .quickScan)` sheet'ini açar.
    /// Bu mod ürünü otomatik arşive eklemez; sadece fit-score önizleme paneli gösterir.
    @State private var showQuickScanSheet: Bool = false
    @State private var soonAlert: SoonAlert?
    /// RecentProductCard tap'inden açılan detay sheet'inin payload'u.
    @State private var selectedDetailItem: UserProductResponse?

    // Rutin kartları için state
    @State private var routines: [RoutineResponse] = []
    @State private var showCreateRoutineSheet: Bool = false
    @State private var navPath: NavigationPath = NavigationPath()
    @State private var aiSheetTarget: AIRecommendPreviewSheet.TimeSlot?
    @State private var creationSlotIntent: AIRecommendPreviewSheet.TimeSlot?

    /// "Yakında" alert payload — başlık + mesaj.
    private struct SoonAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// NavigationStack için route tipi. RoutineDetail için routineId taşır.
    /// `autoFocusAddStep` yeni oluşturulan rutinler için detail açıldığında
    /// adım ekleme sheet'ini otomatik açar.
    enum HomeRoute: Hashable {
        case routineList
        case routineDetail(id: String, autoFocusAddStep: Bool = false)
        case weeklyCalendar
    }

    // MARK: - Hesaplanan değerler

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return L("Günaydın")
        case 12..<18: return L("İyi günler")
        case 18..<22: return L("İyi akşamlar")
        default:      return L("İyi geceler")
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

    /// HeroCard ile aynı kriter: skin_type + birth_date varsa profil hazır sayılır.
    private var isProfileComplete: Bool {
        guard let p = profile else { return false }
        return p.skinType != nil && p.birthDate != nil
    }

    private var morningRoutine: RoutineResponse? {
        routines.first { isMorning($0) }
    }

    private var eveningRoutine: RoutineResponse? {
        routines.first { isEvening($0) }
    }

    private func isMorning(_ r: RoutineResponse) -> Bool {
        if let t = r.schedule?.time, let h = Int(t.split(separator: ":").first.map(String.init) ?? "") {
            return h < 14
        }
        let n = r.name.lowercased()
        return n.contains("sabah") || n.contains("morning")
    }

    private func isEvening(_ r: RoutineResponse) -> Bool {
        if let t = r.schedule?.time, let h = Int(t.split(separator: ":").first.map(String.init) ?? "") {
            return h >= 14
        }
        let n = r.name.lowercased()
        return n.contains("akşam") || n.contains("evening") || n.contains("gece")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navPath) {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        greetingHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        // Profil hazırsa hero card'ı gizle — kullanıcı tekrar görmek istemez.
                        // Sadece eksikse "Profilini tamamla" CTA olarak gösterilir.
                        if !isProfileComplete {
                            HomeProfileHeroCard(profile: profile) {
                                // MainTabView programmatic navigation — Profil tab'ına geçer.
                                // onNavigate yoksa (preview, eski caller) önceki soft fallback.
                                if let onNavigate {
                                    onNavigate(3)
                                } else {
                                    soonAlert = SoonAlert(
                                        title: L("Profilini görüntüle"),
                                        message: String(localized: "Alt menüden \"Profil\" sekmesine geçerek bilgilerini düzenleyebilirsin.")
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        // MARK: Bugün için (rutin kartları)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Text(L("Bugün için"))
                                    .font(Theme.Typo.headline)
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                if !routines.isEmpty {
                                    NavigationLink(value: HomeRoute.weeklyCalendar) {
                                        HStack(spacing: 3) {
                                            Image(systemName: "calendar")
                                                .font(.system(size: 11, weight: .semibold))
                                            Text(L("Haftalık"))
                                                .font(Theme.Typo.caption.weight(.semibold))
                                        }
                                        .foregroundStyle(Theme.ink)
                                    }
                                    NavigationLink(value: HomeRoute.routineList) {
                                        HStack(spacing: 2) {
                                            Text(L("Tümü"))
                                                .font(Theme.Typo.caption.weight(.semibold))
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 10, weight: .semibold))
                                        }
                                        .foregroundStyle(Theme.ink)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)

                            VStack(spacing: 10) {
                                routineSlotCard(
                                    icon: "sun.max.fill",
                                    title: L("Sabah rutini"),
                                    routine: morningRoutine
                                )
                                routineSlotCard(
                                    icon: "moon.stars.fill",
                                    title: L("Akşam rutini"),
                                    routine: eveningRoutine
                                )
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
                    await loadRoutines()
                }
            }
            .navigationBarHidden(true)
            .telemetryScreen("Home")
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .routineList:
                    RoutineListView()
                case .routineDetail(let id, let autoFocus):
                    if let r = routines.first(where: { $0.id == id }) {
                        RoutineDetailView(
                            routineId: id,
                            initialRoutine: r,
                            autoFocusAddStep: autoFocus,
                            onDeleted: { deletedId in
                                routines.removeAll { $0.id == deletedId }
                            }
                        )
                    }
                case .weeklyCalendar:
                    WeeklyCalendarView()
                }
            }
            .sheet(isPresented: $showCreateRoutineSheet) {
                CreateRoutineSheet(onCreated: { newRoutine in
                    routines.append(newRoutine)
                    routines.sort { $0.orderIndex < $1.orderIndex }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        navPath.append(HomeRoute.routineDetail(id: newRoutine.id, autoFocusAddStep: true))
                    }
                })
            }
            .sheet(item: $aiSheetTarget) { slot in
                AIRecommendPreviewSheet(
                    targetTime: slot,
                    onAccepted: { newRoutine in
                        routines.append(newRoutine)
                        routines.sort { $0.orderIndex < $1.orderIndex }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            navPath.append(HomeRoute.routineDetail(id: newRoutine.id))
                        }
                    }
                )
            }
            .confirmationDialog(
                L("Rutini nasıl oluşturmak istersin?"),
                isPresented: Binding(
                    get: { creationSlotIntent != nil },
                    set: { if !$0 { creationSlotIntent = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(L("✨ AI ile öner")) {
                    let slot = creationSlotIntent
                    creationSlotIntent = nil
                    aiSheetTarget = slot
                }
                Button(L("Manuel oluştur")) {
                    creationSlotIntent = nil
                    showCreateRoutineSheet = true
                }
                Button(L("Vazgeç"), role: .cancel) { creationSlotIntent = nil }
            } message: {
                Text(L("AI, arşivindeki ürünleri sıralayıp neden olduğunu açıklar. Manuelde sen kuruyorsun."))
            }
            .sheet(isPresented: $showAddProductSheet) {
                AddProductFlowView { newItem in
                    // Optimistic insert — gelen item'ı en başa al ve 5'ten fazla varsa kırp.
                    recentProducts.insert(newItem, at: 0)
                    if recentProducts.count > 5 {
                        recentProducts = Array(recentProducts.prefix(5))
                    }
                }
            }
            .sheet(isPresented: $showQuickScanSheet) {
                // Quick Scan modu: önizleme paneli arşive otomatik eklemez.
                // Kullanıcı panel içinden "Arşive ekle" derse onAdded callback'i tetiklenir
                // ve recent listesine eklenir; aksi halde recents değişmeden kalır.
                AddProductFlowView(mode: .quickScan) { newItem in
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
            .task {
                await loadRecents()
                await loadRoutines()
            }
        }
    }

    // MARK: - Rutin kart

    @ViewBuilder
    private func routineSlotCard(icon: String, title: String, routine: RoutineResponse?) -> some View {
        if let routine {
            NavigationLink(value: HomeRoute.routineDetail(id: routine.id)) {
                HomeRoutineCard(
                    icon: icon,
                    title: routine.name,
                    subtitle: routineSubtitle(for: routine),
                    actionLabel: L("Aç")
                )
            }
            .buttonStyle(PressedScaleButtonStyle())
        } else {
            Button {
                Haptics.light()
                creationSlotIntent = slotFor(title: title)
            } label: {
                HomeRoutineCard(
                    icon: icon,
                    title: title,
                    subtitle: L("AI senin ürünlerinle önersin"),
                    actionLabel: L("✨ Öner")
                )
            }
            .buttonStyle(PressedScaleButtonStyle())
        }
    }

    private func slotFor(title: String) -> AIRecommendPreviewSheet.TimeSlot {
        title.lowercased().contains("sabah") ? .morning : .evening
    }

    private func routineSubtitle(for r: RoutineResponse) -> String {
        var parts: [String] = []
        if let t = r.schedule?.time { parts.append(t) }
        if r.reminder { parts.append(L("Hatırlatma")) }
        return parts.isEmpty ? L("Detayları aç") : parts.joined(separator: " · ")
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
        // String → LocalizedStringKey: TR key catalog'da arandığında EN'e çevirilir.
        Text(LocalizedStringKey(title))
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
                    title: L("Yakında"),
                    message: String(localized: "Günlük cilt logu özelliği çok yakında — \"Cilt\" sekmesinden takibe başlayabilirsin.")
                )
            }
            HomeQuickActionTile(icon: "barcode.viewfinder", label: "Hızlı tara", isEnabled: true) {
                showQuickScanSheet = true
            }
        }
    }

    private var recentHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L("Son arşive eklenenler"))
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
                            title: L("Tüm ürünler"),
                            message: String(localized: "Alt menüden \"Arşiv\" sekmesine geçerek tüm ürünlerini görebilirsin.")
                        )
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(L("Tümü"))
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
                Text(L("Yükleniyor..."))
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
                Text(L("Arşivin boş"))
                    .font(Theme.Typo.headline)
                    .foregroundStyle(Theme.ink)
                Text(L("İlk ürününü ekleyerek başla"))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
            }

            Spacer(minLength: 8)

            Button {
                Haptics.light()
                showAddProductSheet = true
            } label: {
                Text(L("Ekle"))
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

    @MainActor
    private func loadRoutines() async {
        do {
            routines = try await RoutineService.shared.listRoutines()
                .sorted { $0.orderIndex < $1.orderIndex }
        } catch {
            // Sessiz fail — home boş kartlarla render eder.
            routines = []
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
