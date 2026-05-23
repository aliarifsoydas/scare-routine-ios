import Foundation
import UserNotifications
import UIKit

/// Local notification orkestratörü.
///
/// **Sorumluluk dağılımı:**
/// - Trigger mantığı (tier kuralları, saatler, koşullar) burada hardcoded.
/// - Mesaj metinleri backend'den (`notification_templates` tablosu) çekilir.
/// - Local notification scheduling `UNUserNotificationCenter` ile.
/// - Admin'in manuel push'ları queue'dan poll edilip local notification olarak sched edilir.
///
/// **Permission stratejisi:**
/// Sign-up + onboarding tamamlanınca (`PreparingPlanView` sonu) iste — "value first"
/// yaklaşımı: kullanıcı uygulamayı tanıdıktan sonra izin sor.
///
/// **Quiet hours:** 23:00 — 08:00 arası bildirim sched edilmez (Tier 2 sabah hariç).
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    /// UNUserNotificationCenter delegate'i — foreground'da iken bildirimlerin
    /// banner + ses ile gösterilmesini sağlar. iOS default'u foreground'da
    /// bildirimi gizlemek (test için çok kötü UX).
    private let delegate = NotificationCenterDelegate()

    private init() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    /// Template cache — locale bazlı. Boyut küçük (~15 entry), in-memory yeterli.
    private var templates: [String: NotificationTemplate] = [:]   // key: "tier0_day1_morning"
    private var loadedLocale: String?

    // MARK: - Permission

    /// İzin durumunu kontrol eder.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// İzin ister — "alert + badge + sound". Sonuç döner (true: granted).
    /// Onboarding sonunda PreparingPlanView'den çağırılır.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            Telemetry.shared.custom("notif.permission", props: ["granted": granted])
            // Granted → APNs remote notifications için register tetikle.
            // AppDelegate token'ı yakalayıp DeviceRegistrationService ile backend'e gönderecek.
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            print("[Notif] requestAuthorization error: \(error.localizedDescription)")
            return false
        }
    }

    /// Permission zaten verilmişse (yeni session veya yeniden açılışta) sessizce
    /// APNs register'a girişip token'ı tazele. App'in bootstrap'ında bir kez çağır.
    func reRegisterIfAuthorized() async {
        let status = await authorizationStatus()
        if status == .authorized || status == .provisional || status == .ephemeral {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - Template fetch

    /// Backend'den template'leri çeker, memory cache'e koyar.
    /// Locale değişirse (TR↔EN) reload yapılır.
    func loadTemplates(locale: String) async {
        if loadedLocale == locale, !templates.isEmpty { return }
        do {
            let resp: NotificationTemplatesResponse = try await APIClient.shared.request(
                .notificationTemplates(locale: locale)
            )
            self.templates = Dictionary(uniqueKeysWithValues: resp.templates.map { ($0.key, $0) })
            self.loadedLocale = resp.locale
            print("[Notif] loaded \(resp.templates.count) templates for locale=\(resp.locale)")
        } catch {
            print("[Notif] template fetch failed: \(error.localizedDescription) — using fallbacks")
        }
    }

    /// Template'i interpolate edip döner. Yoksa fallback metin.
    private func resolve(_ key: String, params: [String: String] = [:]) -> (title: String, body: String) {
        guard let t = templates[key] else {
            return ("SCare", "")   // sessiz fallback — title boş bırakma
        }
        var title = t.title
        var body = t.body
        for (k, v) in params {
            title = title.replacingOccurrences(of: "{\(k)}", with: v)
            body = body.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return (title, body)
    }

    // MARK: - Tier 0 — Aktivasyon (0 ürün)

    /// Onboarding bittiğinde + ürün eklenmemiş ise tetiklenir.
    /// Schedule:
    ///  - Day 1, 11:00 → tier0_day1_morning
    ///  - Day 1, 19:00 → tier0_day1_evening
    ///  - Day 2, 14:00 → tier0_day2_afternoon
    ///  - Day 4, 11:00 → tier0_day4_morning
    func scheduleTier0Activation() async {
        let center = UNUserNotificationCenter.current()
        let cal = Calendar.current
        let now = Date()

        struct Slot {
            let key: String
            let dayOffset: Int
            let hour: Int
            let minute: Int
        }
        let slots: [Slot] = [
            .init(key: "tier0_day1_morning",   dayOffset: 1, hour: 11, minute: 0),
            .init(key: "tier0_day1_evening",   dayOffset: 1, hour: 19, minute: 0),
            .init(key: "tier0_day2_afternoon", dayOffset: 2, hour: 14, minute: 0),
            .init(key: "tier0_day4_morning",   dayOffset: 4, hour: 11, minute: 0),
        ]

        for slot in slots {
            guard let targetDay = cal.date(byAdding: .day, value: slot.dayOffset, to: now) else { continue }
            var components = cal.dateComponents([.year, .month, .day], from: targetDay)
            components.hour = slot.hour
            components.minute = slot.minute
            guard let fireDate = cal.date(from: components), fireDate > now else { continue }

            let (title, body) = resolve(slot.key)
            if body.isEmpty { continue }   // template yok → skip

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["tier": "tier0", "key": slot.key]

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                repeats: false
            )
            let req = UNNotificationRequest(
                identifier: "tier0:\(slot.key)",
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(req)
            } catch {
                print("[Notif] Tier0 schedule failed for \(slot.key): \(error.localizedDescription)")
            }
        }
        Telemetry.shared.custom("notif.tier0.scheduled", props: ["count": slots.count])
    }

    /// Kullanıcı ilk ürünü ekleyince çağırılır — Tier 0 pending'lerini iptal et.
    func cancelTier0() {
        let center = UNUserNotificationCenter.current()
        let ids = ["tier0:tier0_day1_morning", "tier0:tier0_day1_evening",
                   "tier0:tier0_day2_afternoon", "tier0:tier0_day4_morning"]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        Telemetry.shared.custom("notif.tier0.cancelled", props: [:])
    }

    // MARK: - User-spesific queue (admin manuel push)

    /// Backend'deki pending mesajları çek + her birini local notification olarak sched +
    /// ack çağır. Bootstrap + scenePhase active'de tetiklenir.
    func syncPendingQueue() async {
        do {
            let resp: PendingNotificationsResponse = try await APIClient.shared.request(.pendingNotifications)
            guard !resp.notifications.isEmpty else { return }

            for notif in resp.notifications {
                let content = UNMutableNotificationContent()
                content.title = notif.title
                content.body = notif.body
                content.sound = .default
                content.userInfo = ["source": notif.source, "queue_id": notif.id]

                // scheduled_at <= now (backend filter'lı), hemen sched et — 1 sn delay
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let req = UNNotificationRequest(
                    identifier: "queue:\(notif.id)",
                    content: content,
                    trigger: trigger
                )

                // Sched — fail olsa bile ack'i atla, sched bağımsız
                do {
                    try await UNUserNotificationCenter.current().add(req)
                    print("[Notif] queue notif sched OK id=\(notif.id) title=\(notif.title)")
                } catch {
                    print("[Notif] queue notif sched FAIL id=\(notif.id): \(error.localizedDescription)")
                    Telemetry.shared.error(
                        "notif.queue.sched_failed",
                        message: error.localizedDescription,
                        props: ["queue_id": notif.id]
                    )
                }

                // Ack — sched ne olursa olsun mutlaka çağır.
                // Aksi takdirde backend'de pending kalır ve döngü tekrar eder.
                do {
                    try await APIClient.shared.requestVoid(.ackNotification(id: notif.id), body: EmptyBody())
                    print("[Notif] queue notif ack'd id=\(notif.id)")
                } catch {
                    print("[Notif] queue notif ack FAIL id=\(notif.id): \(error.localizedDescription)")
                }
            }
            Telemetry.shared.custom("notif.queue.synced", props: ["count": resp.notifications.count])
        } catch {
            print("[Notif] queue sync failed: \(error.localizedDescription)")
        }
    }
}

/// APIClient `requestVoid` body'siz call için (boş JSON `{}`).
private struct EmptyBody: Encodable {}

/// Foreground'da gelen bildirimleri banner + ses + badge ile göstermek için
/// gereken delegate. iOS default'u foreground'da göstermemek — test ve user
/// engagement için bunu zorunlu açıyoruz.
private final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }
}
