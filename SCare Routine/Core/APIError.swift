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
        case .invalidURL: return L("Geçersiz adres.")
        case .requestFailed(let err):
            let fmt = L("İstek başarısız: %@")
            return String(format: fmt, err.localizedDescription)
        case .invalidResponse: return L("Sunucudan beklenmedik yanıt.")
        case .unauthorized: return L("Oturumun süresi doldu. Lütfen tekrar giriş yap.")
        case .forbidden: return L("Bu işlem için yetkin yok.")
        case .notFound: return L("İstenen kayıt bulunamadı.")
        case .rateLimited(let retry):
            if let retry {
                let fmt = L("Çok fazla istek. %lld saniye sonra tekrar dene.")
                return String(format: fmt, retry)
            }
            return L("Çok fazla istek. Birazdan tekrar dene.")
        case .server(_, let msg, let hint):
            if let hint { return "\(msg) (\(hint))" }
            return msg
        case .decodingFailed: return L("Yanıt çözümlenemedi.")
        case .networkOffline: return L("İnternet bağlantın yok gibi görünüyor.")
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
