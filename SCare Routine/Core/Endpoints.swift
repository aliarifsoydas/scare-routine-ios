import Foundation

/// Backend route'ları — agent'ın yazdığı `/v1/...` path'leriyle eşleşir.
enum Endpoint {
    // Auth
    case authApple
    case authRefresh
    case authLogout
    case deleteAccount

    // Profil & Consent
    case me
    case updateProfile
    case getConsents
    case postConsent
    case exportData

    // Ürün katalog
    case recognizeProduct
    case quickEvaluateProduct
    case confirmRecognitionAttempt(id: String)
    case attachCleanPhoto(id: String)
    case attachBackPhoto(id: String)
    case productByBarcode(String)
    case searchProducts(query: String, topMatch: Bool = false)
    case productDetail(id: String)
    case verifyProduct(id: String)

    // Kullanıcı arşivi
    case listMyProducts
    case addMyProduct
    case updateMyProduct(id: String)
    case deleteMyProduct(id: String)

    // Upload
    case signUpload

    // Rutinler
    case listRoutines
    case routineDetail(id: String)
    case createRoutine
    case updateRoutine(id: String)
    case deleteRoutine(id: String)
    case setRoutineSteps(id: String)

    // Loglar & Takvim
    case listLogs(from: String, to: String)
    case postLog
    case calendarWeek(week: String)         // YYYY-WW
    case weeklySummaries(last: Int)

    // Cilt
    case postSkinLog
    case listSkinLogs(from: String, to: String)
    case skinTrends(metric: String, days: Int)
    case postSkinToneEstimate

    // Notifications
    case notificationTemplates(locale: String)
    case pendingNotifications
    case ackNotification(id: Int)
    case registerDevice

    // Health metrics
    case postHealthMetricsBulk

    // Cycle
    case listCycles
    case createCycle
    case updateCycle(id: String)
    case cyclePhase(date: String)

    // AI
    case aiRoutineReview
    case aiProductExplain
    case aiSkinMeta
    case aiRecommendRoutine
    case aiRecommendWeeklyPlan
    case aiUsage

    // User-accepted weekly plan (persistent — "kabul ettim, kalsın")
    case meWeeklyPlanGet
    case meWeeklyPlanAccept
    case meWeeklyPlanDiscard

    // Sistem
    case health
    case categories

    var path: String {
        switch self {
        case .authApple: return "/auth/apple"
        case .authRefresh: return "/auth/refresh"
        case .authLogout: return "/auth/logout"
        case .deleteAccount: return "/auth/account"

        case .me: return "/me"
        case .updateProfile: return "/me/profile"
        case .getConsents: return "/me/consent"
        case .postConsent: return "/me/consent"
        case .exportData: return "/me/export"

        case .recognizeProduct: return "/products/recognize"
        case .quickEvaluateProduct: return "/products/quick-evaluate"
        case .confirmRecognitionAttempt(let id): return "/products/recognition/\(id)/confirm"
        case .attachCleanPhoto(let id): return "/products/recognition/\(id)/attach-clean"
        case .attachBackPhoto(let id): return "/products/recognition/\(id)/attach-back"
        case .productByBarcode(let bc): return "/products/by-barcode/\(bc)"
        case .searchProducts(let q, let topMatch):
            let qs = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let tm = topMatch ? "&top_match=true" : ""
            return "/products/search?q=\(qs)\(tm)"
        case .productDetail(let id): return "/products/\(id)"
        case .verifyProduct(let id): return "/products/\(id)/verify"

        case .listMyProducts: return "/me/products"
        case .addMyProduct: return "/me/products"
        case .updateMyProduct(let id): return "/me/products/\(id)"
        case .deleteMyProduct(let id): return "/me/products/\(id)"

        case .signUpload: return "/uploads/sign"

        case .listRoutines: return "/me/routines"
        case .routineDetail(let id): return "/me/routines/\(id)"
        case .createRoutine: return "/me/routines"
        case .updateRoutine(let id): return "/me/routines/\(id)"
        case .deleteRoutine(let id): return "/me/routines/\(id)"
        case .setRoutineSteps(let id): return "/me/routines/\(id)/steps"

        case .listLogs(let from, let to): return "/me/logs?from=\(from)&to=\(to)"
        case .postLog: return "/me/logs"
        case .calendarWeek(let w): return "/me/calendar?week=\(w)"
        case .weeklySummaries(let n): return "/me/summaries/weekly?last=\(n)"

        case .postSkinLog: return "/me/skin-logs"
        case .listSkinLogs(let from, let to): return "/me/skin-logs?from=\(from)&to=\(to)"
        case .skinTrends(let m, let d): return "/me/skin-logs/trends?metric=\(m)&days=\(d)"
        case .postSkinToneEstimate: return "/me/skin-tone-estimate"

        case .notificationTemplates(let locale): return "/notifications/templates?locale=\(locale)"
        case .pendingNotifications: return "/me/notifications/pending"
        case .ackNotification(let id): return "/me/notifications/\(id)/ack"
        case .registerDevice: return "/me/devices/register"
        case .postHealthMetricsBulk: return "/me/health-metrics/bulk"

        case .listCycles: return "/me/cycles"
        case .createCycle: return "/me/cycles"
        case .updateCycle(let id): return "/me/cycles/\(id)"
        case .cyclePhase(let date): return "/me/cycle-phase?date=\(date)"

        case .aiRoutineReview: return "/ai/routine-review"
        case .aiProductExplain: return "/ai/product-explain"
        case .aiSkinMeta: return "/ai/skin-meta"
        case .aiRecommendRoutine: return "/ai/recommend-routine"
        case .aiRecommendWeeklyPlan: return "/ai/recommend-weekly-plan"
        case .aiUsage: return "/ai/usage"

        case .meWeeklyPlanGet, .meWeeklyPlanAccept, .meWeeklyPlanDiscard: return "/me/weekly-plan"

        case .health: return "/health"
        case .categories: return "/categories"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .authApple, .authRefresh, .authLogout,
             .postConsent, .recognizeProduct, .quickEvaluateProduct,
             .confirmRecognitionAttempt,
             .attachCleanPhoto, .attachBackPhoto,
             .verifyProduct,
             .addMyProduct, .signUpload, .createRoutine,
             .postLog, .postSkinLog, .postSkinToneEstimate, .createCycle,
             .ackNotification, .registerDevice, .postHealthMetricsBulk,
             .aiRoutineReview, .aiProductExplain, .aiSkinMeta, .aiRecommendRoutine, .aiRecommendWeeklyPlan,
             .meWeeklyPlanAccept:
            return .post

        case .updateProfile, .setRoutineSteps:
            return .put

        case .updateMyProduct, .updateRoutine, .updateCycle:
            return .patch

        case .deleteAccount, .deleteMyProduct, .deleteRoutine, .meWeeklyPlanDiscard:
            return .delete

        default:
            return .get
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .authApple, .authRefresh, .health: return false
        default: return true
        }
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}
