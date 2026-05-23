import SwiftUI
import UIKit

/// Process-level image cache (NSCache) + URLCache disk backing.
///
/// Önceden her AsyncRemoteImage view'ı kendi state'inde tutuyordu — arşiv'e
/// her girişte tüm thumbnails sıfırdan fetch ediliyordu. Bu cache URL bazlı
/// process-yaşam-süresi boyunca tutar; arşive ikinci girişte aynı image hit.
///
/// İki katmanlı:
/// 1. NSCache (in-memory, decode edilmiş UIImage) — sıcak yol, en hızlısı.
/// 2. URLCache.shared (memory+disk, raw bytes) — NSCache evict olsa veya
///    uygulama yeniden açılsa bile diskten okuyup decode edebilelim diye.
enum RemoteImageCache {
    private static let cache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.countLimit = 500           // ~500 thumb in-memory (daha tolerant)
        c.totalCostLimit = 128 * 1024 * 1024  // 128 MB
        return c
    }()

    /// Tek seferlik URLCache yapılandırması; uygulama boyunca byte cache'i.
    private static let _bootstrap: Void = {
        // 64 MB memory, 256 MB disk — thumbnails için generös ama makul.
        let memoryCapacity = 64 * 1024 * 1024
        let diskCapacity = 256 * 1024 * 1024
        URLCache.shared = URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            diskPath: "SCareRemoteImageCache"
        )
    }()

    static func bootstrap() { _ = _bootstrap }

    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    static func set(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    /// URLCache'ten (memory+disk) cached response varsa decode edip döner.
    /// Network'e gitmez. Senkron'dur.
    static func cachedImageFromURLCache(for request: URLRequest) -> UIImage? {
        guard let cached = URLCache.shared.cachedResponse(for: request),
              let img = UIImage(data: cached.data) else { return nil }
        return img
    }
}

/// Tema renkleriyle hizalı yükleme/hata placeholder'lı async görsel.
///
/// Worker'daki `/v1/uploads/object/*` route'u **auth'lu** (selfie/ürün foto private kalsın
/// diye). `AsyncImage(url:)` Authorization header geçirmediği için 401 alır; bu yüzden
/// manuel URLSession ile Bearer token ekleyen bir loader kullanıyoruz.
struct AsyncRemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var loadedFor: URL?
    @State private var failed: Bool = false

    init(url: URL?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
        // Bootstrap URLCache (idempotent).
        RemoteImageCache.bootstrap()
        // SENKRON cache check — View init'inde. Bu sayede ilk frame'de
        // ProgressView değil doğrudan image render edilir, flash yok.
        if let url, let cached = RemoteImageCache.image(for: url) {
            _image = State(initialValue: cached)
            _loadedFor = State(initialValue: url)
            _failed = State(initialValue: false)
        } else if let url {
            // NSCache miss → URLCache (disk) hit dene; hala senkron.
            let req = Self.makeRequest(for: url)
            if let cached = RemoteImageCache.cachedImageFromURLCache(for: req) {
                RemoteImageCache.set(cached, for: url)
                _image = State(initialValue: cached)
                _loadedFor = State(initialValue: url)
                _failed = State(initialValue: false)
            } else {
                _image = State(initialValue: nil)
                _loadedFor = State(initialValue: nil)
                _failed = State(initialValue: false)
            }
        } else {
            _image = State(initialValue: nil)
            _loadedFor = State(initialValue: nil)
            _failed = State(initialValue: false)
        }
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if failed || url == nil {
                placeholder(loading: false)
                    .transition(.opacity)
            } else {
                placeholder(loading: true)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: image != nil)
        .task(id: url) {
            await load(url)
        }
    }

    private static func makeRequest(for url: URL) -> URLRequest {
        var req = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 30
        )
        if url.absoluteString.contains("/v1/uploads/object/"),
           let token = KeychainHelper.read(.accessToken) {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    @MainActor
    private func load(_ url: URL?) async {
        guard let url else {
            image = nil
            failed = false
            loadedFor = nil
            return
        }
        // Aynı URL için zaten yüklenmiş → noop. View recreation sonrası init
        // zaten cache'ten doldurduğu için bu erken çıkış ekstra net fetch'i önler.
        if loadedFor == url, image != nil { return }

        // 1) NSCache hit — anlık (no network)
        if let cached = RemoteImageCache.image(for: url) {
            image = cached
            loadedFor = url
            failed = false
            return
        }

        // 2) URLCache (disk) hit — senkron decode, no network
        let req = Self.makeRequest(for: url)
        if let cached = RemoteImageCache.cachedImageFromURLCache(for: req) {
            RemoteImageCache.set(cached, for: url)
            image = cached
            loadedFor = url
            failed = false
            return
        }

        // 3) Network fetch
        failed = false
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let img = UIImage(data: data) else {
                failed = true
                return
            }
            RemoteImageCache.set(img, for: url)
            image = img
            loadedFor = url
        } catch {
            failed = true
        }
    }

    @ViewBuilder
    private func placeholder(loading: Bool) -> some View {
        ZStack {
            Theme.surfaceLow
            if loading {
                ProgressView()
                    .tint(Theme.inkMute)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Theme.inkMute)
            }
        }
    }
}
