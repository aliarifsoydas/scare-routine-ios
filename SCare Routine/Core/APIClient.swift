import Foundation
import OSLog

/// Backend ile konuşan async/await tabanlı network katmanı.
/// - Bearer token otomatik enjekte eder
/// - 401 alınca refresh-token akışını dener, başarısızsa logout
/// - Tüm JSON snake_case ↔ camelCase otomatik
///
/// `@MainActor` olması URLSession çağrılarını UI thread'i bloklamaz (URLSession async).
/// Modül genelinde default actor isolation MainActor olduğu için tip-erişimleri tutarlı.
@MainActor
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.aliarifsoydas.scareroutine", category: "APIClient")

    /// Refresh token akışı eş zamanlı tetiklenirse race olmasın diye tek bir task ile serileştir
    private var ongoingRefresh: Task<String, Error>?

    init(session: URLSession = .shared) {
        self.session = session

        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.dateEncodingStrategy = .secondsSince1970
        self.encoder = enc

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .secondsSince1970
        self.decoder = dec
    }

    // MARK: - Public

    func request<Response: Decodable>(
        _ endpoint: Endpoint,
        body: Encodable? = nil,
        as: Response.Type = Response.self
    ) async throws -> Response {
        let urlRequest = try makeRequest(endpoint: endpoint, body: body)
        return try await execute(urlRequest, endpoint: endpoint, retryOn401: true)
    }

    /// Response gerekmediği durumlar için (örn. DELETE)
    func requestVoid(_ endpoint: Endpoint, body: Encodable? = nil) async throws {
        let urlRequest = try makeRequest(endpoint: endpoint, body: body)
        let _: EmptyResponse = try await execute(urlRequest, endpoint: endpoint, retryOn401: true)
    }

    // MARK: - Internals

    private func makeRequest(endpoint: Endpoint, body: Encodable?) throws -> URLRequest {
        let url = AppConfig.baseURL
            .appendingPathComponent(AppConfig.apiVersion)
            .appendingPathComponent(endpoint.path.hasPrefix("/") ? String(endpoint.path.dropFirst()) : endpoint.path)

        guard let urlWithQuery = URL(string: url.absoluteString.replacingOccurrences(of: "%3F", with: "?")
                                                                .replacingOccurrences(of: "%26", with: "&"))
        else { throw APIError.invalidURL }

        var req = URLRequest(url: urlWithQuery)
        req.httpMethod = endpoint.method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Locale.current.identifier, forHTTPHeaderField: "Accept-Language")

        if endpoint.requiresAuth, let token = KeychainHelper.read(.accessToken) {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }

        return req
    }

    private func execute<Response: Decodable>(
        _ request: URLRequest,
        endpoint: Endpoint,
        retryOn401: Bool
    ) async throws -> Response {
        let (data, response) = try await performNetwork(request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch http.statusCode {
        case 200...299:
            if Response.self == EmptyResponse.self {
                return EmptyResponse() as! Response
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                // DEBUG: gerçek hata detayı + body'i logla — hangi field uyumsuz görelim
                let bodyPreview = String(data: data.prefix(1500), encoding: .utf8) ?? "<binary>"
                logger.error("Decode hatası [\(String(describing: Response.self))]: \(String(describing: error))")
                logger.error("Response body: \(bodyPreview, privacy: .public)")
                throw APIError.decodingFailed(error)
            }

        case 401:
            guard retryOn401, endpoint.requiresAuth else { throw APIError.unauthorized }
            // Refresh token akışı
            let newAccess = try await refreshAccessToken()
            var retried = request
            retried.setValue("Bearer \(newAccess)", forHTTPHeaderField: "Authorization")
            return try await execute(retried, endpoint: endpoint, retryOn401: false)

        case 403: throw APIError.forbidden
        case 404: throw APIError.notFound
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw APIError.rateLimited(retryAfter: retry)

        case 400...499, 500...599:
            if let env = try? decoder.decode(APIErrorEnvelope.self, from: data) {
                throw APIError.server(code: env.error.code, message: env.error.message, hint: env.error.hint)
            }
            throw APIError.invalidResponse

        default:
            throw APIError.invalidResponse
        }
    }

    private func performNetwork(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw APIError.networkOffline
        } catch {
            throw APIError.requestFailed(error)
        }
    }

    private func refreshAccessToken() async throws -> String {
        if let ongoing = ongoingRefresh {
            return try await ongoing.value
        }

        let task = Task<String, Error> { @MainActor in
            defer { self.ongoingRefresh = nil }

            guard let refresh = KeychainHelper.read(.refreshToken) else {
                throw APIError.unauthorized
            }

            let body = RefreshRequest(refreshToken: refresh)
            let req = try self.makeRequest(endpoint: .authRefresh, body: body)
            let resp: AuthResponse = try await self.execute(req, endpoint: .authRefresh, retryOn401: false)

            try KeychainHelper.save(resp.accessToken, for: .accessToken)
            try KeychainHelper.save(resp.refreshToken, for: .refreshToken)

            return resp.accessToken
        }

        ongoingRefresh = task
        return try await task.value
    }
}

// MARK: - Yardımcılar

struct EmptyResponse: Decodable {}

/// Encodable'ı type-erase eden helper (heterojen body göndermek için)
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ wrapped: Encodable) {
        self._encode = wrapped.encode
    }
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
