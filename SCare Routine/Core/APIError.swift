import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case requestFailed(Error)
    case invalidResponse
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(retryAfter: Int?)
    case server(code: String, message: String, hint: String?)
    case decodingFailed(Error)
    case networkOffline

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Geçersiz adres."
        case .requestFailed(let err): return "İstek başarısız: \(err.localizedDescription)"
        case .invalidResponse: return "Sunucudan beklenmedik yanıt."
        case .unauthorized: return "Oturumun süresi doldu. Lütfen tekrar giriş yap."
        case .forbidden: return "Bu işlem için yetkin yok."
        case .notFound: return "İstenen kayıt bulunamadı."
        case .rateLimited(let retry):
            if let retry { return "Çok fazla istek. \(retry) saniye sonra tekrar dene." }
            return "Çok fazla istek. Birazdan tekrar dene."
        case .server(_, let msg, let hint):
            if let hint { return "\(msg) (\(hint))" }
            return msg
        case .decodingFailed: return "Yanıt çözümlenemedi."
        case .networkOffline: return "İnternet bağlantın yok gibi görünüyor."
        }
    }
}

/// Backend'in döndüğü standart hata zarfı: { "error": { "code", "message", "hint?" } }
struct APIErrorEnvelope: Decodable {
    let error: APIErrorBody

    struct APIErrorBody: Decodable {
        let code: String
        let message: String
        let hint: String?
    }
}
