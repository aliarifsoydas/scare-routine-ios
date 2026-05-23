//
//  SCare_RoutineApp.swift
//  SCare Routine
//
//  Created by aaStudio on 17.05.2026.
//

import SwiftUI
import SwiftData
import UIKit

/// APNs device token + remote notification delegate.
/// SwiftUI App lifecycle'a `@UIApplicationDelegateAdaptor` ile bağlanır.
final class SCareAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        return true
    }

    /// APNs token başarıyla alındı → backend'e kaydet.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = DeviceRegistrationService.shared.tokenString(from: deviceToken)
        Task { @MainActor in
            await DeviceRegistrationService.shared.register(token: tokenString)
        }
    }

    /// APNs register fail (ör. simulator, network, profile mismatch) — sessiz log.
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[APNs] register failed: \(error.localizedDescription)")
    }
}

@main
struct SCare_RoutineApp: App {
    @UIApplicationDelegateAdaptor(SCareAppDelegate.self) var appDelegate
    let modelContainer: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            self.modelContainer = try SCareSchema.makeContainer()
        } catch {
            fatalError("ModelContainer kurulamadı: \(error)")
        }
        // App launch event — Telemetry singleton init'i de tetikler
        Task { @MainActor in
            Telemetry.shared.custom("app.launch", props: [
                "session_id": Telemetry.shared.sessionID,
                "app_version": Telemetry.shared.appVersion,
                "os_version": Telemetry.shared.osVersion,
            ])
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Telemetry.shared.custom("app.foreground")
                // Foreground transition'da: queue poll + APNs token refresh
                Task {
                    await NotificationService.shared.syncPendingQueue()
                    await NotificationService.shared.reRegisterIfAuthorized()
                }
            case .background:
                Telemetry.shared.custom("app.background")
                Telemetry.shared.flush()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}

// MARK: - AppRoot (splash + content swap)

private struct AppRoot: View {
    @State private var showSplash = true
    @State private var splashStartedAt: Date = .now

    /// Minimum görünür süre — launch screen ile in-app splash arasındaki "double-splash flash"
    /// hissini engellemek için en az 600ms tut. Üstü açık (gerçek bootstrap > 600ms ise
    /// onun süresi kadar bekler).
    private let minSplashSeconds: Double = 0.6
    /// Üst limit — bootstrap çok uzun sürerse splash'ı 1.5s'de kapatıp ContentView'a geç.
    /// Sonrası ContentView'da skeleton/loader gösterilir.
    private let maxSplashSeconds: Double = 1.5

    var body: some View {
        ZStack {
            ContentView()
                .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashScreenView()
                    .transition(.opacity)
                    .task {
                        // Apple HIG: launch screen invisible olsun, in-app splash gerçek
                        // work'e bağlı. Burada AppState bootstrap'ı zaten paralel yapıyor,
                        // bizim splash sadece "minimum görünür" hissi sağlar.
                        let elapsed = Date.now.timeIntervalSince(splashStartedAt)
                        let remaining = max(0, minSplashSeconds - elapsed)
                        if remaining > 0 {
                            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                        }
                        // Üst limit guard: bootstrap takılırsa 1.5s'de kesinlikle geç
                        try? await Task.sleep(nanoseconds: 0)
                        withAnimation(.easeOut(duration: 0.25)) {
                            showSplash = false
                        }
                    }
                    .onAppear { splashStartedAt = .now }
            }
        }
        .onAppear {
            // Max splash guard — bootstrap takılırsa
            Task {
                try? await Task.sleep(nanoseconds: UInt64(maxSplashSeconds * 1_000_000_000))
                await MainActor.run {
                    if showSplash {
                        withAnimation(.easeOut(duration: 0.25)) { showSplash = false }
                    }
                }
            }
        }
    }
}

// MARK: - SplashScreenView (inline so synchronized folder doesn't lose it)

/// İlk açılış splash — beyaz ekran yerine brand peach + logo.
/// 1.2s sonra fade-out → ContentView. Sistem launch screen (LaunchBackground
/// colorset + Logo asset) instant render eder, bu in-app splash devralır.
private struct SplashScreenView: View {

    @State private var logoScale: CGFloat = 0.92
    @State private var logoOpacity: Double = 0
    @State private var nameOffset: CGFloat = 12
    @State private var nameOpacity: Double = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.canvas, Theme.surface, Theme.canvas],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Image("Logo")
                    .resizable()
                    .renderingMode(.original)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 132, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .shadow(color: Theme.ink.opacity(0.12), radius: 24, x: 0, y: 8)
                    .scaleEffect(pulse ? 1.02 : 1.0)
                    .opacity(logoOpacity)
                    .scaleEffect(logoScale)

                VStack(spacing: 4) {
                    Text("SCare Routine")
                        .font(.system(size: 24, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ink)

                    Text(L("Cilt bakım dünyan, tek yerde"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Theme.ink.opacity(0.55))
                }
                .offset(y: nameOffset)
                .opacity(nameOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                logoOpacity = 1
                logoScale = 1.0
            }
            withAnimation(.easeOut(duration: 0.65).delay(0.18)) {
                nameOffset = 0
                nameOpacity = 1
            }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
