import Foundation

/// AI rutin önerisi servisi.
///
/// Backend `/v1/ai/recommend-routine` çağırır. Önerilen rutini döner;
/// kullanıcı onaylarsa caller `RoutineService.createRoutine` ile kaydeder.
@MainActor
final class AIRecommendService {
    static let shared = AIRecommendService()

    private let api = APIClient.shared

    private init() {}

    /// Önerilen rutini al. `focus` opsiyonel — kullanıcı "leke için" gibi
    /// belirli bir endişeyi vurgulamak isterse geçirilir.
    func recommendRoutine(
        targetTime: String,
        language: String? = nil,
        focus: String? = nil
    ) async throws -> AIRecommendRoutineResponse {
        let body = AIRecommendRoutineRequest(
            targetTime: targetTime,
            language: language,
            focus: focus?.isEmpty == true ? nil : focus
        )
        return try await api.request(.aiRecommendRoutine, body: body)
    }

    /// Haftalık planı al. `focus` opsiyonel — "refresh" geçirilirse backend
    /// cache'i bypass eder ve yeni bir plan üretir. LLM çağrısı uzun sürebilir,
    /// caller tarafında 30-45s timeout beklenir.
    func recommendWeeklyPlan(
        locale: String,
        focus: String? = nil
    ) async throws -> WeeklyPlanResponse {
        let body = AIRecommendWeeklyPlanRequest(
            locale: locale,
            focus: focus?.isEmpty == true ? nil : focus
        )
        return try await api.request(.aiRecommendWeeklyPlan, body: body)
    }
}
