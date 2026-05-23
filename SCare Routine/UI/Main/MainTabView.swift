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
    @Environment(LanguageManager.self) private var languageManager

    var body: some View {
        // Tab içerikleri için `.id(languageManager.current)`:
        // Dil değişince her tab'ın content tree'si yeniden inşa olur, böylece
        // `Text("literal")` cache'i temizlenir ve String(localized:) yeniden çalışır.
        // Tab selection state (selectedTab) korunur çünkü TabView dışında.
        TabView(selection: $selectedTab) {
            HomeView(user: user, onNavigate: { tab in
                Haptics.light()
                selectedTab = tab
            })
                .id(languageManager.current)
                .tabItem {
                    Label(L("Anasayfa"), systemImage: "house.fill")
                }
                .tag(0)

            ArchiveView()
                .id(languageManager.current)
                .tabItem {
                    Label(L("Arşiv"), systemImage: "tray.full.fill")
                }
                .tag(1)

            SkinView()
                .id(languageManager.current)
                .tabItem {
                    Label(L("Cilt"), systemImage: "leaf.fill")
                }
                .tag(2)

            ProfileView(user: user)
                .id(languageManager.current)
                .tabItem {
                    Label(L("Profil"), systemImage: "person.crop.circle.fill")
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
