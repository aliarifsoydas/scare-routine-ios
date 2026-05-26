import SwiftUI

/// Anasayfa — "Bugün" odaklı haftalık plan + arşiv özetleri.
///
/// Onboarding'in OnboardingStepContainer disiplini ile aynı kompozisyon:
/// - 20pt horizontal padding her bölümde
/// - 20pt section spacing
/// - Theme dışı renk yok
/// - Pull-to-refresh ile son arşiv + weekly plan tazelenir
///
/// State kaynakları:
/// - `appState.currentUser?.displayName` → selamlama
/// - `appState.currentProfile?.skinType / birthDate / fitzpatrickType` → profil hero kartı
/// - `appState.locale` → tarih + AI weekly plan request
/// - `task(id:)` ile `AIRecommendService.recommendWeeklyPlan(locale:)` → bugünün adımları
/// - `task` ile `ProductScanService.listMyProducts()` → son 5 ürün + step thumbnail eşlemesi
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

    /// Kullanıcının **kabul ettiği** persistent plan — backend'den GET ile gelir veya
    /// UserDefaults mirror'ından instant okunur. AI yeniden çağrılmaz.
    @State private var storedPlan: StoredWeeklyPlan?
    /// AI suggest sonucu — kullanıcı henüz "kabul et" demedi. AcceptPlanSheet'in payload'u.
    @State private var pendingSuggestion: WeeklyPlanResponse?
    @State private var showAcceptSheet: Bool = false
    /// `loadStoredOrSuggest` çağrılırken `true`'ya alınır; mirror anında doluyorsa
    /// hemen `false`'a düşer → loading flash yaşanmaz.
    @State private var isLoadingPlan: Bool = false
    @State private var planError: String?

    /// Geriye dönük "var olan UI bloklarına geçirilecek WeeklyPlanResponse" — storedPlan
    /// içindeki planı veya pendingSuggestion'ı tek ucundan döndürür. Today/Strip/Hero
    /// blokları bunu okur.
    private var weeklyPlan: WeeklyPlanResponse? {
        storedPlan?.plan
    }

    @State private var navPath: NavigationPath = NavigationPath()

    // Spotify daylist-style rotating loading hint — sade 3 status, agresif değil.
    @State private var loadingStatusIndex: Int = 0
    @State private var loadingTimer: Timer?

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
        f.dateFormat = "d MMMM"
        return f.string(from: .now).capitalizedFirstLetter
    }

    private var profile: ProfileData? { appState.currentProfile }

    /// HeroCard ile aynı kriter: skin_type + birth_date varsa profil hazır sayılır.
    private var isProfileComplete: Bool {
        guard let p = profile else { return false }
        return p.skinType != nil && p.birthDate != nil
    }

    /// Spotify daylist tarzı 2-3 status — agresif değil, kullanıcıya AI'ın
    /// arka planda neyi düşündüğünü hissettirir.
    private var loadingStatuses: [String] {
        [
            L("Bugünün ritüali derleniyor..."),
            L("Aktif madde rotasyonu hesaplanıyor..."),
            L("Adımlar sıralanıyor..."),
        ]
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navPath) {
            // GEO-LOCKED OVERFLOW FIX: .frame(maxWidth: .infinity) yetmediği
            // anlaşıldı — bazı child intrinsic width'leri (RecentProductCard,
            // nested ScrollView, vs.) hâlâ parent'ı şişirebiliyor. Son çare:
            // GeometryReader ile ekran width'ini explicit ölç + VStack'e
            // .frame(width: geo.size.width) ile HARD-LOCK et. Bu, content
            // extent'ini ekran genişliği ile kilitler — hiçbir child bypass
            // edemez. CSS "overflow-x: hidden" + "width: 100vw"in birleşik
            // SwiftUI eşdeğeri.
            GeometryReader { screenGeo in
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 20) {
                        greetingHeader
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        // MARK: Bugün hero — greeting'in hemen altı
                        todayHeroContainer
                            .padding(.horizontal, 20)

                        // MARK: Bugünkü adımlar (sabah/akşam segmented card)
                        if let plan = weeklyPlan, let day = todayPlanDay(in: plan) {
                            TodayPlanCard(
                                day: day,
                                userProducts: recentProducts,
                                locale: appState.locale
                            )
                            .padding(.horizontal, 20)
                            .onAppear {
                                Telemetry.shared.custom("home.today_plan.shown", props: [
                                    "rest": day.restDay,
                                    "morning": day.morningSteps.count,
                                    "evening": day.eveningSteps.count,
                                ])
                            }
                        }

                        // MARK: Haftalık plan mini-strip
                        weeklyStripSection
                            .padding(.horizontal, 20)

                        // Profil hazırsa hero card'ı gizle — kullanıcı tekrar görmek istemez.
                        // Sadece eksikse "Profilini tamamla" CTA olarak gösterilir.
                        if !isProfileComplete {
                            HomeProfileHeroCard(profile: profile) {
                                // MainTabView programmatic navigation — Profil tab'ına geçer.
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

                        // Rutin listesi link — küçük secondary CTA olarak alt köşede kalır.
                        routineListLink
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        Spacer(minLength: 48)
                    }
                    // GEO-LOCKED: VStack'i screen width'e tam olarak kilitle.
                    // .frame(maxWidth: .infinity) bazen yetmiyor (intrinsic width
                    // hesabı SwiftUI'da edge case'lerde parent'ı bypass eder).
                    // GeometryReader'dan gelen explicit width ile content extent'i
                    // ekran piksel boyutuna eşitlenir → yatay overflow imkansız.
                    .frame(width: screenGeo.size.width, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await loadRecents()
                    // Pull-to-refresh: backend stored plan'i tekrar oku. Plan yoksa
                    // suggest + accept sheet açılır. Mevcut planı VOID etmez — kullanıcı
                    // sheet içinden "Kabul et" derse UPSERT ile replace edilir.
                    await refreshWeeklyPlan()
                }
            }
            .navigationBarHidden(true)
            .telemetryScreen("Home")
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .routineList:
                    RoutineListView()
                case .routineDetail(let id, let autoFocus):
                    // Rutin listesi kendi navigation'ını çözüyor; HomeView artık
                    // routines state'ini cache'lemiyor — initialRoutine yok, sadece id.
                    RoutineDetailView(
                        routineId: id,
                        initialRoutine: nil,
                        autoFocusAddStep: autoFocus,
                        onDeleted: { _ in }
                    )
                case .weeklyCalendar:
                    WeeklyCalendarView()
                }
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
            }
            // Locale değişirse stored plan'i yeniden çek; backend GET locale değiştiyse
            // farklı dil ile dönmüş plan da olabilir.
            .task(id: appState.locale) {
                await loadStoredOrSuggest()
            }
            .sheet(isPresented: $showAcceptSheet) {
                // Sheet kapanırsa ve hâlâ pending suggestion ile kabul edilmediyse
                // pendingSuggestion'ı temizle — bir sonraki açılışta tekrar AI çağrılmasın
                // (storedPlan oluşmadıysa bile kullanıcı manuel "Yenile" demeli).
                pendingSuggestion = nil
            } content: {
                if let suggestion = pendingSuggestion {
                    AcceptPlanSheet(
                        initialPlan: suggestion,
                        isFirstPlan: storedPlan == nil,
                        locale: appState.locale,
                        onAccepted: { stored in
                            storedPlan = stored
                            pendingSuggestion = nil
                            planError = nil
                        }
                    )
                }
            }
            }  // GeometryReader screenGeo close — overflow hard-lock
        }
    }

    // MARK: - Refresh (pull-to-refresh + retry)

    @MainActor
    private func refreshWeeklyPlan() async {
        // Stored plan varsa: yenisini suggest et + sheet aç. User isterse kabul eder.
        // Stored plan yoksa: loadStoredOrSuggest aynı path'i kullanır.
        if storedPlan != nil {
            await suggestAndPresentAcceptSheet()
        } else {
            await loadStoredOrSuggest()
        }
    }

    // MARK: - Today hero container (loading / ready / error sarmalayıcı)

    @ViewBuilder
    private var todayHeroContainer: some View {
        if let plan = weeklyPlan, let day = todayPlanDay(in: plan) {
            TodayHeroSection(
                day: day,
                todayDateString: todayDateString,
                dayDisplayName: dayNameLocalized(day.dayOfWeek)
            )
            .onAppear {
                Telemetry.shared.custom("home.today_hero.shown", props: [
                    "rest": day.restDay,
                ])
            }
        } else if isLoadingPlan {
            todayLoadingSkeleton
        } else {
            todayEmptyState
        }
    }

    @ViewBuilder
    private var todayLoadingSkeleton: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(L("Bugün"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.ink))
                Text(todayDateString)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Theme.ink)
                    .scaleEffect(0.85)
                Text(loadingStatuses[loadingStatusIndex])
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.inkSoft)
                    .transition(.opacity)
                    .id(loadingStatusIndex)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
        .onAppear { startLoadingTimer() }
        .onDisappear { stopLoadingTimer() }
    }

    @ViewBuilder
    private var todayEmptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "leaf")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.inkSoft)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Bugün için henüz plan yok"))
                    .font(Theme.Typo.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(L("Arşivine ürün ekleyince AI bugünün rutinini hazırlar."))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(Theme.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
    }

    // MARK: - Weekly strip section

    @ViewBuilder
    private var weeklyStripSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Haftalık plan"))
                    .font(Theme.Typo.caption.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.inkSoft)
                Spacer()
                NavigationLink(value: HomeRoute.weeklyCalendar) {
                    HStack(spacing: 2) {
                        Text(L("Tüm hafta"))
                            .font(Theme.Typo.caption.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Theme.ink)
                }
                .track("weekly_strip.all_week")
            }

            NavigationLink(value: HomeRoute.weeklyCalendar) {
                HomeWeeklyStrip(
                    days: weeklyPlan?.days ?? [],
                    todayWeekday: WeekdayFormat.todayWeekday(),
                    locale: appState.locale
                )
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .fill(Theme.surface.opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .strokeBorder(Theme.divider.opacity(0.6), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .track("weekly_strip.tap")
        }
    }

    // MARK: - Routine list küçük link

    @ViewBuilder
    private var routineListLink: some View {
        NavigationLink(value: HomeRoute.routineList) {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 11, weight: .semibold))
                Text(L("Tüm rutinlerim"))
                    .font(Theme.Typo.caption.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Theme.inkSoft)
        }
        .track("routine_list.tap")
    }

    // MARK: - Bileşenler

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(greeting + (firstName.map { ", \($0)" } ?? ""))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Image(systemName: greetingSymbol)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.inkSoft)
                    .symbolRenderingMode(.hierarchical)
            }
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
            // Yatay scroll'u ekrandan dışarı taşmasın — content'i ekran boyutuna clip.
            // ScrollView default'ta content extent kadar yer kaplar, parent vertical
            // ScrollView genişliğine literal overflow yapar → tüm sayfa sağa-sola sallanır.
            // .clipped() bu davranışı keser (CSS overflow-x: hidden karşılığı).
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .clipped()
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

    // MARK: - Today plan helpers

    /// ISO weekday (1=Mon..7=Sun) → response.days içinde eşleşen gün.
    private func todayPlanDay(in plan: WeeklyPlanResponse) -> WeeklyPlanDay? {
        let today = WeekdayFormat.todayWeekday()
        return plan.days.first(where: { $0.dayOfWeek == today })
    }

    /// Response.day.dayName'i öncelikle kullan, yoksa locale'a göre fallback ile
    /// gün adını döndür. Backend "Pazartesi"/"Monday" gibi tam ad göndermeyebilir;
    /// boş geldiği için lokal fallback şart.
    private func dayNameLocalized(_ day: Int) -> String {
        if let plan = weeklyPlan,
           let info = plan.days.first(where: { $0.dayOfWeek == day }),
           !info.dayName.isEmpty {
            return info.dayName
        }
        let trNames = ["", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]
        let enNames = ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        let table = appState.locale == "en" ? enNames : trNames
        guard (1...7).contains(day) else { return "" }
        return table[day]
    }

    // MARK: - Loading status timer

    private func startLoadingTimer() {
        stopLoadingTimer()
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
                    loadingStatusIndex = (loadingStatusIndex + 1) % loadingStatuses.count
                }
            }
        }
    }

    private func stopLoadingTimer() {
        loadingTimer?.invalidate()
        loadingTimer = nil
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
            // recentProducts hem strip'te hem TodayPlanCard'da step-thumbnail eşlemesinde
            // kullanılıyor — ham listenin tamamı değil, ilk 5 + thumbnail için
            // listMyProducts ham listeyi tut. UI side recents zaten prefix(5)'i alıyor.
            // step thumbnail için ham liste şart → ayrı state cost'u var, ama küçük JSON.
            recentProducts = sorted
        } catch {
            // Sessizce başarısız — anasayfada error gösterme; kullanıcı yine de
            // diğer bölümleri kullanabilsin. Arşiv sekmesi gerçek error gösterir.
            recentProducts = []
        }
    }

    /// Yeni akış: önce backend'den kullanıcının kabul ettiği planı dene; varsa instant
    /// göster (AI çağrılmaz → loading flash yok). Yoksa AI suggest et ve AcceptPlanSheet'i aç.
    @MainActor
    private func loadStoredOrSuggest() async {
        // 1. Optimistic: UserDefaults mirror'ından oku → 0ms render.
        if storedPlan == nil, let cached = UserWeeklyPlanService.shared.loadCachedMirror() {
            storedPlan = cached
            isLoadingPlan = false
        } else if storedPlan == nil {
            // Mirror yok → loading skeleton göster, AI/network bitene kadar
            isLoadingPlan = true
        }

        // 2. Backend GET — authoritative, mirror'ı update eder.
        do {
            if let fresh = try await UserWeeklyPlanService.shared.getCurrent() {
                storedPlan = fresh
                planError = nil
                isLoadingPlan = false
                stopLoadingTimer()
                return
            }
            // 3. Backend 404 → kullanıcı henüz plan kabul etmemiş.
            //    Mirror da yokken loading state'i göster; AI suggest et + sheet aç.
            //    Eğer mirror vardı ama backend 404 dedi → mirror sahibi olmayan bir
            //    kullanıcı (logout/login) olabilir; storedPlan'i de temizle.
            storedPlan = nil
            await suggestAndPresentAcceptSheet()
        } catch {
            // Network fail: mirror varsa onu göster, AI suggest yapma — kullanıcı
            // hâlâ planını görsün.
            planError = error.localizedDescription
            Telemetry.shared.error("home.stored_plan.failed", message: error.localizedDescription)
            isLoadingPlan = false
            stopLoadingTimer()
        }
    }

    /// AI'dan yeni suggestion al ve AcceptPlanSheet'i aç. "İlk plan" akışında ve
    /// "Yenile" CTA'sında ortak kullanılır.
    @MainActor
    private func suggestAndPresentAcceptSheet() async {
        isLoadingPlan = true
        defer { isLoadingPlan = false }
        do {
            let suggested = try await AIRecommendService.shared.recommendWeeklyPlan(
                locale: appState.locale,
                focus: "refresh"
            )
            pendingSuggestion = suggested
            showAcceptSheet = true
            stopLoadingTimer()
        } catch {
            planError = error.localizedDescription
            Telemetry.shared.error("home.weekly_plan.failed", message: error.localizedDescription)
            stopLoadingTimer()
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
