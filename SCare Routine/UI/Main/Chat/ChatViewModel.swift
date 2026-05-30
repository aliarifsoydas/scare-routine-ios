import Foundation
import Observation

/// AI Chat ekranının state'i. Oturum + mesajlar + canlı taslak.
/// Mesajlar lokal olarak tutulur (turn response reply döner); foto/ürün event'leri
/// lokal system baloncuğu olarak eklenir.
@MainActor
@Observable
final class ChatViewModel {
    var session: ChatSessionDTO?
    var messages: [ChatMessageDTO] = []
    var draft: ChatDraftDTO = .empty
    var readyToCommit = false
    var missingInfo: [String] = []

    var input: String = ""
    var isSending = false
    var isStarting = false
    var errorMessage: String?
    var committedRoutineId: String?

    private let service = ChatService.shared
    private let locale: String

    /// Yeni oturum için locale, mevcut oturum için nil sessionId ile başla.
    init(locale: String, existingSessionId: String? = nil) {
        self.locale = locale
        self.existingSessionId = existingSessionId
    }

    private let existingSessionId: String?
    var hasDraft: Bool { !draft.steps.isEmpty }

    // MARK: - Lifecycle

    func bootstrap() async {
        if let id = existingSessionId {
            await loadExisting(id: id)
        } else {
            await startNew()
        }
    }

    private func startNew() async {
        guard session == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let turn = try await service.startSession(message: nil, locale: locale)
            session = turn.session
            apply(turn: turn, appendReply: true)
        } catch {
            errorMessage = friendly(error)
        }
    }

    private func loadExisting(id: String) async {
        isStarting = true
        defer { isStarting = false }
        do {
            let detail = try await service.getSession(id: id)
            session = detail.session
            messages = detail.messages
            draft = detail.draft ?? .empty
            committedRoutineId = detail.session.committedRoutineId
        } catch {
            errorMessage = friendly(error)
        }
    }

    // MARK: - Send

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let session, !isSending else { return }
        input = ""
        appendUser(content: text)
        isSending = true
        defer { isSending = false }
        do {
            let turn = try await service.sendMessage(id: session.id, content: text)
            apply(turn: turn, appendReply: true)
        } catch {
            errorMessage = friendly(error)
        }
    }

    // MARK: - Product / skin events (iOS-5 tarafından çağrılır)

    func onProductAdded(userProductId: String, label: String) async {
        guard let session else { return }
        do {
            _ = try await service.addProductEvent(id: session.id, userProductId: userProductId)
            appendSystem(content: String(format: L("\"%@\" arşivine eklendi."), label))
        } catch {
            errorMessage = friendly(error)
        }
    }

    // MARK: - Commit

    /// Merge için mevcut rutinler (commit sheet picker'ı).
    var existingRoutines: [RoutineResponse] = []

    func loadRoutines() async {
        existingRoutines = (try? await RoutineService.shared.listRoutines()) ?? []
    }

    /// timeSlot: "morning" | "evening" → schedule.time/emoji türetilir (AIRecommend ile aynı).
    func commit(mode: String, targetRoutineId: String?, name: String?, timeSlot: String) async -> Bool {
        guard let session else { return false }
        let isEvening = timeSlot == "evening"
        var schedule = RoutineSchedulePayload()
        schedule.time = isEvening ? "21:00" : "08:00"
        schedule.tz = TimeZone.current.identifier
        schedule.frequency = "daily"
        let emoji = isEvening ? "🌙" : "☀️"
        do {
            let resp = try await service.commit(
                id: session.id, mode: mode, targetRoutineId: targetRoutineId,
                name: name, timeSlot: timeSlot, schedule: schedule, emoji: emoji
            )
            committedRoutineId = resp.routine.id
            return true
        } catch {
            errorMessage = friendly(error)
            return false
        }
    }

    // MARK: - Report

    func report(messageId: String?, reason: String) async {
        guard let session else { return }
        try? await service.report(id: session.id, messageId: messageId, reason: reason)
    }

    // MARK: - Helpers

    private func apply(turn: ChatTurnResponse, appendReply: Bool) {
        draft = turn.draft
        readyToCommit = turn.readyToCommit
        missingInfo = turn.missingInfo
        committedRoutineId = turn.session.committedRoutineId
        if appendReply, !turn.reply.isEmpty {
            appendAssistant(content: turn.reply)
        }
    }

    private func appendUser(content: String) {
        messages.append(ChatMessageDTO(id: UUID().uuidString, role: "user", content: content, hasPhoto: false, meta: nil, createdAt: Date()))
    }
    private func appendAssistant(content: String) {
        messages.append(ChatMessageDTO(id: UUID().uuidString, role: "assistant", content: content, hasPhoto: false, meta: nil, createdAt: Date()))
    }
    private func appendSystem(content: String) {
        messages.append(ChatMessageDTO(id: UUID().uuidString, role: "system", content: content, hasPhoto: false, meta: nil, createdAt: Date()))
    }

    private func friendly(_ error: Error) -> String {
        if case let APIError.server(_, message, _) = error { return message }
        return L("Bir şeyler ters gitti, tekrar dener misin?")
    }
}
