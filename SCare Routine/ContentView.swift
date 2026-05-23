//
//  ContentView.swift
//  SCare Routine
//
//  Created by aaStudio on 17.05.2026.
//

import SwiftUI

/// Root view — AppState.phase'e göre uygun ekrana yönlendirir.
struct ContentView: View {
    @State private var appState = AppState()
    @State private var languageManager = LanguageManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch appState.phase {
            case .launching:
                LaunchView()
            case .onboarding:
                SignInScreenView()
            case .authenticated(let user):
                if appState.needsOnboarding {
                    OnboardingHostView()
                } else {
                    MainTabView(user: user)
                }
            }
        }
        .environment(appState)
        .environment(languageManager)
        .environment(\.locale, languageManager.effectiveLocale)
        // NOT: .id(languageManager.current) ile view tree rebuild edilirse
        // tab/navigation state sıfırlanıyor (Settings → ana sayfaya atıyor).
        // Restart-required pattern uygulandığı için anlık SwiftUI refresh'e
        // gerek yok; user app'i kapatıp açınca yeni dil ile boot olur.
        .tint(Theme.accent)
        .task {
            await appState.bootstrap()
            // İlk açılışta HealthKit'ten:
            //  1) daily sleep history backend'e push (90 gün init)
            //  2) son 7 günün ortalamasını profile.lifestyle'a yansıt
            await appState.syncHealthKitHistory()
            await appState.syncHealthKitSleepToProfile()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Her foreground transition'da delta sync
            // (Apple Watch sleep tracking güncel veriyi yansıt)
            if newPhase == .active {
                Task {
                    await appState.syncHealthKitHistory()
                    await appState.syncHealthKitSleepToProfile()
                }
            }
        }
    }
}

// MARK: - Launch (yükleme)

private struct LaunchView: View {
    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            VStack(spacing: 20) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                ProgressView()
                    .tint(Theme.inkSoft)
            }
        }
    }
}

// MARK: - Sign in ekranı (henüz auth olmamış kullanıcı)

private struct SignInScreenView: View {
    @Environment(AppState.self) private var appState
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(spacing: 10) {
                    Text(verbatim: "SCare Routine")
                        .font(Theme.Typo.title)
                        .foregroundStyle(Theme.ink)
                    Text(L("Kozmetik arşivin ve akıllı rutin asistanın"))
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                SignInWithAppleView(
                    locale: appState.locale,
                    onSuccess: { user in appState.signIn(user) },
                    onError: { err in errorMessage = err.errorDescription }
                )
                .padding(.horizontal, 28)

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.alert)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Text(L("Devam ederek Gizlilik Politikası ve Kullanım Şartları'nı kabul etmiş olursun."))
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.inkMute)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Authenticated placeholder (ana ekran tasarımı sonra)

private struct MainPlaceholderView: View {
    let user: AuthUser
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                VStack(spacing: 18) {
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Theme.ink)

                    Text(L("Profilin hazır"))
                        .font(Theme.Typo.title)
                        .foregroundStyle(Theme.ink)

                    Text(user.displayName ?? user.email ?? user.id)
                        .font(Theme.Typo.body)
                        .foregroundStyle(Theme.inkSoft)

                    Spacer()

                    Text(L("Ana ekran tasarımı geliyor"))
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.inkMute)

                    Button(L("Çıkış yap")) {
                        Task { await appState.signOut() }
                    }
                    .font(Theme.Typo.body)
                    .foregroundStyle(Theme.alert)
                    .padding(.bottom, 24)
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
    }
}
