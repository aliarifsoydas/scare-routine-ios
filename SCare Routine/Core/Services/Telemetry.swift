import Foundation
import UIKit

/// iOS app-side telemetry — screen, tap, timing, error event'leri toplayıp
/// backend `/v1/telemetry/events` endpoint'ine batch'le push eder.
///
/// Davranış:
///  - In-memory buffer, 20 event veya 30s'de bir flush
///  - App background'a geçince hemen flush
///  - Network fail = silently swallow, event kaybolur (telemetry kritik değil)
///  - Auth optional: JWT varsa header'a koyar, yoksa anonymous
///
/// Kullanım:
///  Telemetry.shared.screen("Onboarding.SkinType")
///  Telemetry.shared.tap("submit_button", props: ["screen": "FinalPlan"])
///  let token = Telemetry.shared.startTiming("recognize.total")
///  ...later...
///  Telemetry.shared.endTiming(token)
@MainActor
final class Telemetry {
    static let shared = Telemetry()

    // Session — app açılışında yeni UUID
    let sessionID: String = UUID().uuidString
    let appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let osVersion: String = UIDevice.current.systemVersion
    let deviceModel: String = UIDevice.current.model

    private var buffer: [[String: Any]] = []
    private var flushTimer: Timer?
    private let bufferLimit = 20
    private let flushInterval: TimeInterval = 30
    private var timings: [UUID: (name: String, startedAt: Date)] = [:]
    private var isFlushing = false

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in Telemetry.shared.flushNow() }
        }
        scheduleTimer()
    }

    // MARK: - Public API

    func screen(_ name: String, props: [String: Any]? = nil) {
        enqueue(type: "screen", name: name, props: props, durationMs: nil)
    }

    func tap(_ name: String, props: [String: Any]? = nil) {
        enqueue(type: "tap", name: name, props: props, durationMs: nil)
    }

    func timing(_ name: String, ms: Int, props: [String: Any]? = nil) {
        enqueue(type: "timing", name: name, props: props, durationMs: ms)
    }

    func error(_ name: String, message: String, props: [String: Any]? = nil) {
        var merged: [String: Any] = props ?? [:]
        merged["message"] = message
        enqueue(type: "error", name: name, props: merged, durationMs: nil)
    }

    func custom(_ name: String, props: [String: Any]? = nil) {
        enqueue(type: "custom", name: name, props: props, durationMs: nil)
    }

    @discardableResult
    func startTiming(_ name: String) -> UUID {
        let token = UUID()
        timings[token] = (name, Date())
        return token
    }

    func endTiming(_ token: UUID, props: [String: Any]? = nil) {
        guard let entry = timings.removeValue(forKey: token) else { return }
        let ms = Int(Date().timeIntervalSince(entry.startedAt) * 1000)
        timing(entry.name, ms: ms, props: props)
    }

    /// Buffer'daki tüm event'leri hemen gönder. Kritik akışlarda (submit, recognize done)
    /// kullanıcı yarıda kapatırsa veri kaybını engeller.
    func flush() {
        flushNow()
    }

    // MARK: - Internals

    private func enqueue(type: String, name: String, props: [String: Any]?, durationMs: Int?) {
        var e: [String: Any] = ["type": type, "name": name]
        if let p = props, !p.isEmpty { e["props"] = p }
        if let dur = durationMs { e["duration_ms"] = dur }
        buffer.append(e)
        if buffer.count >= bufferLimit {
            flushNow()
        }
    }

    private func scheduleTimer() {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { _ in
            Task { @MainActor in Telemetry.shared.flushNow() }
        }
    }

    private func flushNow() {
        guard !isFlushing, !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll()
        isFlushing = true
        let sessionID = self.sessionID
        let appVersion = self.appVersion
        let osVersion = self.osVersion
        let deviceModel = self.deviceModel
        Task {
            await Telemetry.sendBatch(
                events: batch,
                sessionID: sessionID,
                appVersion: appVersion,
                osVersion: osVersion,
                deviceModel: deviceModel
            )
            await MainActor.run { Telemetry.shared.isFlushing = false }
        }
    }

    /// Static — `self` capture problem'i Swift 6 strict concurrency'de fail eder,
    /// statik fonksiyon değer'leri parametre olarak alır, isolation'dan bağımsız çalışır.
    private static func sendBatch(
        events: [[String: Any]],
        sessionID: String,
        appVersion: String,
        osVersion: String,
        deviceModel: String
    ) async {
        let body: [String: Any] = [
            "session_id": sessionID,
            "app_version": appVersion,
            "os_version": osVersion,
            "device_model": deviceModel,
            "events": events,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        let url = AppConfig.baseURL.appendingPathComponent("v1/telemetry/events")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = KeychainHelper.read(.accessToken) {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = data
        req.timeoutInterval = 6
        _ = try? await URLSession.shared.data(for: req)
    }
}
