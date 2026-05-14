import SwiftUI
import UIKit

/// Image-cache singleton shared across chat bubbles. NSCache is thread-safe
/// and bounded — entries get evicted under memory pressure. Keyed by URL.
final class ChatImageCache: @unchecked Sendable {
    static let shared = ChatImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    private init() { cache.countLimit = 200 }

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

/// AsyncImage replacement that retries transient failures and caches the
/// decoded UIImage in memory. The stock AsyncImage gives up after one
/// failed request, which is the chat bubble's `Photo unavailable`
/// permanent state — the underlying storage URL is usually fine, the
/// request just hit a transient TCP/CDN hiccup. Three attempts with
/// exponential backoff covers virtually all of those cases.
struct CachedAsyncImage<Failure: View, Loading: View>: View {
    let url: URL
    let contentMode: ContentMode
    let failure: () -> Failure
    let loading: () -> Loading

    @State private var image: UIImage?
    @State private var state: LoadState = .loading

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed
    }

    init(
        url: URL,
        contentMode: ContentMode = .fill,
        @ViewBuilder failure: @escaping () -> Failure,
        @ViewBuilder loading: @escaping () -> Loading
    ) {
        self.url = url
        self.contentMode = contentMode
        self.failure = failure
        self.loading = loading
    }

    var body: some View {
        Group {
            if let image, state == .loaded {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if state == .failed {
                Button(action: retry) {
                    failure()
                }
                .buttonStyle(.plain)
            } else {
                loading()
            }
        }
        .task(id: url) {
            await load(attempt: 0)
        }
    }

    private func load(attempt: Int) async {
        if let cached = ChatImageCache.shared.image(for: url) {
            image = cached
            state = .loaded
            return
        }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 12
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard let decoded = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            ChatImageCache.shared.store(decoded, for: url)
            image = decoded
            state = .loaded
        } catch {
            if Task.isCancelled { return }
            if attempt < CachedAsyncImageBackoff.seconds.count {
                let wait = CachedAsyncImageBackoff.seconds[attempt]
                try? await Task.sleep(for: .seconds(Double(wait)))
                if Task.isCancelled { return }
                await load(attempt: attempt + 1)
            } else {
                state = .failed
            }
        }
    }

    private func retry() {
        state = .loading
        Task { await load(attempt: 0) }
    }
}

private enum CachedAsyncImageBackoff {
    static let seconds: [UInt64] = [1, 3, 8]
}
