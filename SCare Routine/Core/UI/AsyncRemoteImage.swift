import SwiftUI

/// Tema renkleriyle hizalı yükleme/hata placeholder'lı async görsel.
/// `AsyncImage` ile aynı API, sadece sürekli aynı boş-durum stiline sahip.
struct AsyncRemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                switch phase {
                case .empty:
                    placeholder(loading: true)
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                case .failure:
                    placeholder(loading: false)
                @unknown default:
                    placeholder(loading: false)
                }
            }
        } else {
            placeholder(loading: false)
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
