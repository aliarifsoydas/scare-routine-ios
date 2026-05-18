import SwiftUI

/// Ana navigation: 4 tab + native iOS TabView.
/// Onboarding tamamlanmış kullanıcı için root view.
///
/// `selectedTab` binding'i sayesinde HomeView gibi alt ekranlar programmatic olarak
/// başka bir tab'a geçebilir (örn. profil kartından Profil tab'ına, "Tümü" linkinden
/// Arşiv tab'ına). Tab değerleri:
/// - 0: Anasayfa
/// - 1: Arşiv
/// - 2: Cilt
/// - 3: Profil
struct MainTabView: View {
    let user: AuthUser

    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(user: user, onNavigate: { tab in
                Haptics.light()
                selectedTab = tab
            })
                .tabItem {
                    Label("Anasayfa", systemImage: "house.fill")
                }
                .tag(0)

            ArchiveView()
                .tabItem {
                    Label("Arşiv", systemImage: "tray.full.fill")
                }
                .tag(1)

            SkinView()
                .tabItem {
                    Label("Cilt", systemImage: "leaf.fill")
                }
                .tag(2)

            ProfileView(user: user)
                .tabItem {
                    Label("Profil", systemImage: "person.crop.circle.fill")
                }
                .tag(3)
        }
        .tint(Theme.ink)
    }
}

#Preview {
    MainTabView(user: AuthUser(
        id: "preview",
        email: "preview@example.com",
        displayName: "Önizleme",
        locale: "tr",
        createdAt: nil,
        isNewUser: false
    ))
    .environment(AppState())
}
