import SwiftUI

// MARK: - Screen environment

/// `.telemetryScreen("Onboarding.SkinType")` ile bir view'a screen prefix tanımla.
/// Bu prefix child view'lardaki `.track("...")` modifier'larında otomatik prepend edilir.
/// Modifier ayrıca onAppear'da `Telemetry.screen(name)` çağırır.

private struct TelemetryScreenKey: EnvironmentKey {
    static let defaultValue: String = "app"
}

extension EnvironmentValues {
    var telemetryScreen: String {
        get { self[TelemetryScreenKey.self] }
        set { self[TelemetryScreenKey.self] = newValue }
    }
}

struct TelemetryScreenModifier: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        content
            .environment(\.telemetryScreen, name)
            .onAppear {
                Telemetry.shared.screen(name)
            }
    }
}

extension View {
    /// Bu view'a screen prefix bağla. Child'lardaki `.track("...")` modifier'ları
    /// "{name}.{localName}" formatında tap log'lar.
    ///
    /// Onappear'da ayrıca screen event log'lar.
    func telemetryScreen(_ name: String) -> some View {
        modifier(TelemetryScreenModifier(name: name))
    }
}

// MARK: - Tap tracking

/// `.track("submit")` modifier bir view'a tap tracking ekler.
/// Env'den screen prefix alır, log: "Onboarding.SkinType.submit"
///
/// SimultaneousGesture kullanır — Button kendi action'ını çalışmaya devam ettirir,
/// tracking onunla paralel.
struct TrackTapModifier: ViewModifier {
    let localName: String
    let props: [String: Any]?
    @Environment(\.telemetryScreen) var screen

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onEnded {
                let fullName = screen == "app" ? localName : "\(screen).\(localName)"
                Telemetry.shared.tap(fullName, props: props)
            }
        )
    }
}

extension View {
    /// Bu view'ın tap'i için telemetry. Screen prefix otomatik (varsa) ile birleşir.
    /// Örnek: parent `.telemetryScreen("Profile")` + child `.track("save")` → "Profile.save"
    func track(_ localName: String, props: [String: Any]? = nil) -> some View {
        modifier(TrackTapModifier(localName: localName, props: props))
    }
}
