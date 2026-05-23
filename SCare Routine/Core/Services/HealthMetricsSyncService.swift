import Foundation

/// HealthKit → Backend daily metrics sync orkestratörü.
///
/// **Sync stratejisi:**
/// 1. İlk açılış (`UserDefaults.scare.healthMetrics.lastSyncedAt` yoksa) → son 90 gün
/// 2. Sonraki foreground transition'larda → son 14 gün (overlap intentional, idempotent upsert)
/// 3. Min 30 dakika cooldown — battery koruması
///
/// Backend `(user_id, date, metric)` PK ile upsert, son yazan kazanır. iOS anchor cache
/// gerekmez çünkü full window re-fetch ucuz (90 gün × 1 metric = ~270 satır).
@MainActor
final class HealthMetricsSyncService {
    static let shared = HealthMetricsSyncService()
    private init() {}

    private let lastSyncKey = "scare.healthMetrics.lastSyncedAt"
    private let cooldownSeconds: TimeInterval = 30 * 60   // 30 dk

    /// Sleep daily history backend'e push. Cooldown'a takılırsa no-op.
    /// `force = true` ile cooldown bypass (manual trigger).
    func syncSleepHistory(force: Bool = false) async {
        guard HealthKitService.shared.isAvailable else { return }

        // Cooldown check
        if !force {
            let lastSync = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
            if let last = lastSync, Date().timeIntervalSince(last) < cooldownSeconds {
                return
            }
        }

        // İlk sync mü? Son sync varsa daha kısa window kullan.
        let isInitial = UserDefaults.standard.object(forKey: lastSyncKey) == nil
        let days = isInitial ? 90 : 14

        let dayToHours = await HealthKitService.shared.readDailySleepHours(days: days)
        guard !dayToHours.isEmpty else {
            print("[HealthMetrics] no sleep samples in last \(days) days")
            return
        }

        // Backend bulk payload
        let metrics = dayToHours.map { (date, hours) in
            HealthMetricBulkItem(date: date, metric: "sleep_hours", value: hours, source: "healthkit", hk_anchor: nil)
        }
        let payload = HealthMetricsBulkRequest(metrics: metrics)

        do {
            try await APIClient.shared.requestVoid(.postHealthMetricsBulk, body: payload)
            UserDefaults.standard.set(Date(), forKey: lastSyncKey)
            print("[HealthMetrics] synced \(metrics.count) sleep entries (\(days)d window, initial=\(isInitial))")
            Telemetry.shared.custom("healthkit.sleep_synced", props: [
                "count": metrics.count,
                "days": days,
                "initial": isInitial,
            ])
        } catch {
            print("[HealthMetrics] sync failed: \(error.localizedDescription)")
            Telemetry.shared.error("healthkit.sync_failed", message: error.localizedDescription, props: [:])
        }
    }
}

// MARK: - DTOs

private struct HealthMetricsBulkRequest: Encodable {
    let metrics: [HealthMetricBulkItem]
}

private struct HealthMetricBulkItem: Encodable {
    let date: String           // "YYYY-MM-DD"
    let metric: String         // "sleep_hours" | ...
    let value: Double
    let source: String?
    let hk_anchor: String?
}
