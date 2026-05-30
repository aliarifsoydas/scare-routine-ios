import SwiftUI

/// Ana navigation: 4 tab + native iOS TabView.
/// Onboarding tamamlanmış kullanıcı için root view.
///
/// AI Chat asistanına giriş: tab bar'ın üstünde sağa yaslı kompakt "✨ Asistan"
/// pill. iOS 26'da native `tabViewBottomAccessory` (Liquid Glass); iOS 17-25'te
/// floating overlay fallback. 4 tab'a dokunmaz.
///
/// Tab değerleri: 0 Anasayfa · 1 Arşiv · 2 Cilt · 3 Profil
struct MainTabView: View {
    let user: AuthUser

    @State private var selectedTab: Int = 0
    @State private var showChat = false
    @Environment(LanguageManager.self) private var languageManager

    var body: some View {
        assistantWrapped
            .fullScreenCover(isPresented: $showChat) {
                ChatView(locale: chatLocale)
            }
    }

    /// iOS 26: native bottom accessory (sağa yaslı). Eski sürüm: floating overlay.
    @ViewBuilder
    private var assistantWrapped: some View {
        if #available(iOS 26.0, *) {
            tabView.tabViewBottomAccessory {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    AssistantPill { openChat() }
                }
            }
        } else {
            tabView.overlay(alignment: .bottomTrailing) {
                AssistantPill { openChat() }
                    .padding(.trailing, 16)
                    .padding(.bottom, 70)
            }
        }
    }

    private var tabView: some View {
        // `.id(languageManager.current)`: dil değişince her tab content tree'si
        // yeniden inşa olur (String(localized:) cache temizlenir). Tab selection korunur.
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
                    Label(L("Ürünler"), systemImage: "tray.full.fill")
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

    private func openChat() {
        Haptics.light()
        showChat = true
    }

    private var chatLocale: String {
        languageManager.effectiveLocale.language.languageCode?.identifier ?? "tr"
    }
}

/// Sağa yaslı kompakt asistan pill — sohbeti açar.
private struct AssistantPill: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                Text(L("Asistan"))
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.ink))
            .overlay(Capsule().strokeBorder(Theme.onAccent.opacity(0.15), lineWidth: 1))
            .shadow(color: Theme.ink.opacity(0.20), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
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
