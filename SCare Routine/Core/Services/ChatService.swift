import Foundation

/// AI Chat → Rutin servis katmanı. APIClient üzerinden /v1/ai/chat/... çağrıları.
@MainActor
final class ChatService {
    static let shared = ChatService()
    private let api = APIClient.shared
    private init() {}

    /// Yeni oturum (+opsiyonel ilk mesaj → açılış turn'ü).
    func startSession(message: String?, locale: String?) async throws -> ChatTurnResponse {
        try await api.request(.createChatSession, body: ChatStartRequest(message: message, locale: locale))
    }

    /// Kullanıcının oturum listesi (özet).
    func listSessions() async throws -> [ChatSessionDTO] {
        let resp: ChatSessionListResponse = try await api.request(.listChatSessions)
        return resp.sessions
    }

    /// Tek oturumun transcript'i + güncel taslağı.
    func getSession(id: String) async throws -> ChatSessionDetailResponse {
        try await api.request(.getChatSession(id: id))
    }

    /// Kullanıcı mesajı (+opsiyonel foto) → turn.
    func sendMessage(
        id: String,
        content: String?,
        photoKey: String? = nil,
        photoKind: String? = nil,
        category: String? = nil
    ) async throws -> ChatTurnResponse {
        try await api.request(
            .postChatMessage(id: id),
            body: ChatMessageRequest(content: content, photoKey: photoKey, photoKind: photoKind, category: category)
        )
    }

    /// Recognize+confirm sonrası: arşive eklenen ürünü sohbete bildir (iOS-orchestrated).
    @discardableResult
    func addProductEvent(id: String, userProductId: String) async throws -> ChatEventResponse {
        try await api.request(
            .chatProductEvent(id: id),
            body: ChatProductEventRequest(type: "product_added", userProductId: userProductId)
        )
    }

    /// Taslağı rutine yaz. mode: "new" | "merge".
    func commit(
        id: String,
        mode: String,
        targetRoutineId: String? = nil,
        name: String? = nil,
        timeSlot: String? = nil,
        schedule: RoutineSchedulePayload? = nil,
        emoji: String? = nil
    ) async throws -> ChatCommitResponse {
        try await api.request(
            .commitChat(id: id),
            body: ChatCommitRequest(
                mode: mode, targetRoutineId: targetRoutineId, name: name,
                timeSlot: timeSlot, schedule: schedule, emoji: emoji
            )
        )
    }

    /// İçerik şikayeti (Apple 4.7.1).
    func report(id: String, messageId: String?, reason: String) async throws {
        try await api.requestVoid(.reportChat(id: id), body: ChatReportRequest(messageId: messageId, reason: reason))
    }

    /// Oturumu sil (mesajlar + chat-özel fotolar temizlenir).
    func deleteSession(id: String) async throws {
        try await api.requestVoid(.deleteChatSession(id: id))
    }
}
