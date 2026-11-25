import SwiftUI
import UIKit
import ImageIO

/// A cached fallback is not proof that a higher-priority candidate failed.
/// Keep ordered selection separate from transport so cache warmth cannot
/// silently change a team's authoritative artwork.
@MainActor
enum FottyImageSelectionPolicy {
    struct Selection<Value> {
        let requestURLs: [URL]
        let selectedURL: URL
        let value: Value

        func value(for currentURLs: [URL]) -> Value? {
            requestURLs == currentURLs ? value : nil
        }
    }

    static func preferredCached<Value>(urls: [URL], cache: (URL) -> Value?) -> Value? {
        urls.first.flatMap(cache)
    }

    static func load<Value>(urls: [URL], cache: (URL) -> Value?,
                            fetch: (URL) async -> Value?) async -> Selection<Value>? {
        var attempted = Set<URL>()
        for url in urls where attempted.insert(url).inserted {
            guard !Task.isCancelled else { return nil }
            if let cached = cache(url) {
                return Selection(requestURLs: urls, selectedURL: url, value: cached)
            }
            let fetched = await fetch(url)
            guard !Task.isCancelled else { return nil }
            if let fetched {
                return Selection(requestURLs: urls, selectedURL: url, value: fetched)
            }
        }
        return nil
    }
}

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let urls: [URL]
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var loadedImage: FottyImageSelectionPolicy.Selection<UIImage>?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.urls = url.map { [$0] } ?? []
        self.content = content
        self.placeholder = placeholder
    }

    init(
        urls: [URL],
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.urls = urls
        self.content = content
        self.placeholder = placeholder
    }

    private var cachedImage: UIImage? {
        FottyImageSelectionPolicy.preferredCached(urls: urls) { FottyImageCache.shared.image(for: $0) }
    }

    var body: some View {
        Group {
            if let image = loadedImage?.value(for: urls) ?? cachedImage {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: urls) {
            let requestURLs = urls
            if loadedImage?.value(for: requestURLs) != nil { return }
            let selected = await FottyImageSelectionPolicy.load(urls: requestURLs,
                cache: { FottyImageCache.shared.image(for: $0) },
                fetch: { await FottyImagePipeline.shared.image(for: $0) })
            guard !Task.isCancelled else { return }
            loadedImage = selected
        }
    }
}
