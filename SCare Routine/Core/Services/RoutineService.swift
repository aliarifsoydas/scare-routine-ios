import Foundation

/// Backend routine endpoint'leri:
///   GET    /v1/me/routines
///   GET    /v1/me/routines/:id
///   POST   /v1/me/routines
///   PATCH  /v1/me/routines/:id
///   DELETE /v1/me/routines/:id
///   PUT    /v1/me/routines/:id/steps   (steps re-set)
///   POST   /v1/me/logs                  (RoutineLog)
@MainActor
final class RoutineService {
    static let shared = RoutineService()

    private let api = APIClient.shared

    private init() {}

    // MARK: - List

    /// Aktif + arşivlenmemiş tüm rutinler. orderIndex'e göre sıralı.
    func listRoutines() async throws -> [RoutineResponse] {
        let resp: ListRoutinesResponse = try await api.request(.listRoutines)
        return resp.routines
    }

    /// Tek rutin + adımları.
    func getRoutine(id: String) async throws -> (routine: RoutineResponse, steps: [RoutineStepResponse]) {
        let resp: RoutineDetailResponse = try await api.request(.routineDetail(id: id))
        return (resp.routine, resp.steps ?? [])
    }

    // MARK: - Create

    /// Yeni rutin + adımlar. Backend response { routine, steps }.
    func createRoutine(_ payload: RoutineCreateRequest) async throws -> (routine: RoutineResponse, steps: [RoutineStepResponse]) {
        let resp: CreateRoutineResponse = try await api.request(.createRoutine, body: payload)
        return (resp.routine, resp.steps ?? [])
    }

    // MARK: - Update meta (name/schedule/reminder/color/emoji)

    func updateRoutine(id: String, _ payload: RoutineUpdateRequest) async throws {
        let _: EmptyResponse = try await api.request(.updateRoutine(id: id), body: payload)
    }

    func deleteRoutine(id: String) async throws {
        let _: EmptyResponse = try await api.request(.deleteRoutine(id: id))
    }

    // MARK: - Set steps (re-order / replace)

    /// PUT body: [{ user_product_id, instruction, duration_seconds, is_optional }]
    func setSteps(routineId: String, steps: [RoutineStepPayload]) async throws -> [RoutineStepResponse] {
        struct StepsBody: Encodable {
            let steps: [RoutineStepPayload]
        }
        struct StepsResponse: Decodable {
            let steps: [RoutineStepResponse]
        }
        let resp: StepsResponse = try await api.request(.setRoutineSteps(id: routineId), body: StepsBody(steps: steps))
        return resp.steps
    }

    // MARK: - Log (complete)

    /// Bugünün rutinini tamamla. completedStepIds = tamamlanan step id'leri.
    /// Backend completion_pct'ı otomatik hesaplar.
    func logRoutine(_ payload: RoutineLogPayload) async throws -> RoutineLogResponse {
        struct LogResponse: Decodable { let log: RoutineLogResponse }
        let resp: LogResponse = try await api.request(.postLog, body: payload)
        return resp.log
    }
}

// EmptyResponse APIClient.swift'te zaten tanımlı — burada redeclare etmiyoruz.
