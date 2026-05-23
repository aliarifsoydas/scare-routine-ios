import Foundation

/// Backend'in `GET /v1/notifications/templates` cevabı.
///
/// Templates remote config — metinleri admin dashboard'undan edit edebilir, iOS
/// build push gerekmez. iOS Tier mantığı + saat hesabını kendi yapar, sadece
/// `key + locale` ile mesaj metnini buradan çeker.
struct NotificationTemplatesResponse: Decodable {
    let locale: String
    let templates: [NotificationTemplate]
}

struct NotificationTemplate: Decodable, Identifiable {
    let key: String
    let locale: String
    let title: String
    let body: String

    var id: String { "\(locale):\(key)" }
}

/// Backend'in `GET /v1/me/notifications/pending` cevabı.
///
/// Admin'in kullanıcıya manuel gönderdiği (veya AI engine'in tetiklediği) mesajlar
/// queue'lanmış halde. iOS bootstrap + foreground'da poll edip her birini local
/// notification olarak sched eder, sonra `/ack` ile sent mark eder.
struct PendingNotificationsResponse: Decodable {
    let notifications: [UserNotification]
}

struct UserNotification: Decodable, Identifiable {
    let id: Int
    let title: String
    let body: String
    /// Unix timestamp — backend `scheduled_at` → APIClient
    /// `.convertFromSnakeCase` ile `scheduledAt` olarak gelir.
    let scheduledAt: Int
    /// "admin_manual" | "ai_engine" | "system"
    let source: String
    let createdAt: Int
}
