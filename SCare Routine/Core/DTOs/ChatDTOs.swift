import Foundation

// AI Chat → Rutin DTO'ları. Backend snake_case → APIClient camelCase'e çevirir.
// Backend: src/routes/chat.ts + src/pipelines/chat-turn.ts

// MARK: - Session

struct ChatSessionDTO: Decodable, Identifiable, Hashable {
    let id: String
    let status: String              // active | committed | abandoned
    let title: String?
    let committedRoutineId: String?
    let locale: String
    let createdAt: Date?
    let updatedAt: Date?
}

// MARK: - Draft (RecommendationResult karşılığı)

struct ChatDraftDTO: Decodable, Hashable {
    let steps: [ChatDraftStepDTO]
    let routineNotes: String
    let suitabilityScore: Int
    let missingCategories: [String]
    let warnings: [String]

    static let empty = ChatDraftDTO(steps: [], routineNotes: "", suitabilityScore: 0, missingCategories: [], warnings: [])
}

struct ChatDraftStepDTO: Decodable, Identifiable, Hashable {
    let userProductId: String
    let orderIndex: Int
    let instruction: String?
    let rationale: String
    let addresses: [String]
    let daysActive: [Int]?
    let frequencyLabel: String?

    var id: String { "\(userProductId)-\(orderIndex)" }
}

// MARK: - Message

struct ChatMessageDTO: Decodable, Identifiable, Hashable {
    let id: String
    let role: String                // user | assistant | system
    let content: String?
    let hasPhoto: Bool
    let meta: ChatMessageMeta?
    let createdAt: Date?
}

struct ChatMessageMeta: Decodable, Hashable {
    let event: String?              // product_added | skin_observation | report
    let userProductId: String?
    let photoKind: String?          // product | skin
    let flagged: Bool?
}

// MARK: - Responses

/// POST /sessions ve POST /messages → aynı turn şekli.
struct ChatTurnResponse: Decodable {
    let session: ChatSessionDTO
    let reply: String
    let draft: ChatDraftDTO
    let readyToCommit: Bool
    let missingInfo: [String]
}

struct ChatSessionDetailResponse: Decodable {
    let session: ChatSessionDTO
    let draft: ChatDraftDTO?
    let messages: [ChatMessageDTO]
}

struct ChatSessionListResponse: Decodable {
    let sessions: [ChatSessionDTO]
}

struct ChatEventResponse: Decodable {
    let ok: Bool
    let userProductId: String?
    let label: String?
}

/// Commit yanıtı — defensive: yalnızca onay için gereken alanlar.
/// (App rutinleri ayrıca /me/routines'den tazeler.)
struct ChatCommitResponse: Decodable {
    let routine: ChatCommittedRoutine
    let mode: String
}

struct ChatCommittedRoutine: Decodable {
    let id: String
    let name: String?
}

// MARK: - Requests

struct ChatStartRequest: Encodable {
    let message: String?
    let locale: String?
}

struct ChatMessageRequest: Encodable {
    let content: String?
    let photoKey: String?
    let photoKind: String?          // product | skin
    let category: String?           // face | scalp | body
}

struct ChatProductEventRequest: Encodable {
    let type: String                // "product_added"
    let userProductId: String
}

struct ChatCommitRequest: Encodable {
    let mode: String                // new | merge
    let targetRoutineId: String?
    let name: String?
    let timeSlot: String?           // morning | evening
    let schedule: RoutineSchedulePayload?
    let emoji: String?
}

struct ChatReportRequest: Encodable {
    let messageId: String?
    let reason: String
}
