import Foundation
import UIKit

/// Cilt günlüğü servisi.
///
/// Backend endpoint'leri:
/// - `POST /v1/me/skin-logs`
/// - `GET  /v1/me/skin-logs?from=&to=`
/// - `GET  /v1/me/skin-trends?metric=&days=`
///
/// Selfie upload `ProductScanService.uploadImage`'le aynı R2 presigned URL akışını
/// kullanır; backend `/v1/uploads/sign` `kind: "selfie"` parametresini destekliyor.
/// `kind` parametresi tutarlılık için burada `uploadSelfie` helper'ında bağlanır.
@MainActor
final class SkinLogService {
    static let shared = SkinLogService()
    private init() {}

    private let api = APIClient.shared

    // MARK: - CRUD

    /// Yeni cilt logu oluşturur. Backend `{ item: SkinLogResponse }` döner;
    /// item alanını unwrap edip caller'a SkinLogResponse veririz.
    func create(_ payload: SkinLogCreateRequest) async throws -> SkinLogResponse {
        let resp: CreateSkinLogResponse = try await api.request(.postSkinLog, body: payload)
        return resp.item
    }

    /// Date aralığında log listesi. `from`/`to` "YYYY-MM-DD" formatında inclusive.
    func list(from: String, to: String) async throws -> [SkinLogResponse] {
        let resp: ListSkinLogsResponse = try await api.request(.listSkinLogs(from: from, to: to))
        return resp.items
    }

    /// Metric: "hydration" | "redness" | "oiliness" | "breakouts" | "overall".
    /// Days: son N gün (örn. 30).
    func trends(metric: String, days: Int) async throws -> SkinTrendsResponse {
        try await api.request(.skinTrends(metric: metric, days: days))
    }

    // MARK: - Upload

    /// Selfie'yi R2'ye yükler. Backend `kind: "selfie"` için ayrı bir bucket prefix
    /// kullanır + post-process pipeline'ı tetiklenir (metrics_only modda gözlem
    /// çıkarıldıktan sonra foto silinir).
    ///
    /// ProductScanService.uploadImage `kind: "product_photo"` ile sabitlenmiş, bu
    /// nedenle selfie için ayrı bir helper yazıyoruz. Aynı `/v1/uploads/sign`
    /// endpoint'ini kullanır.
    func uploadSelfie(_ image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw ScanError.imageEncodingFailed
        }

        let signReq = UploadSignRequest(kind: "selfie", contentType: "image/jpeg", ext: "jpg")
        let sign: UploadSignResponse = try await api.request(.signUpload, body: signReq)

        guard let url = URL(string: sign.uploadUrl) else {
            throw ScanError.uploadFailed("invalid_presigned_url")
        }

        var attempt = 0
        var lastError: Error?
        while attempt < 3 {
            do {
                try await putData(data, to: url, contentType: "image/jpeg")
                return sign.publicUrl
            } catch {
                lastError = error
                attempt += 1
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 400_000_000)
                }
            }
        }
        throw ScanError.uploadFailed(lastError?.localizedDescription ?? "unknown")
    }

    private func putData(_ data: Data, to url: URL, contentType: String) async throws {
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        let session = URLSession(configuration: cfg)
        let (_, response) = try await session.upload(for: req, from: data)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ScanError.uploadFailed("status_\(code)")
        }
    }
}
