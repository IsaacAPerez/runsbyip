import SwiftUI
import UIKit
import ImageIO

/// Renders an animated GIF in a SwiftUI view. SwiftUI's AsyncImage shows
/// only the first frame of a GIF; we drop down to ImageIO + a per-frame
/// timer wired to CADisplayLink so the bubble actually animates. Frames
/// are decoded once and held in memory — gallery-scale GIFs (10-100
/// frames each, a handful visible at once) fit comfortably.
struct AnimatedGifView: View {
    let url: URL?
    let data: Data?
    var contentMode: UIView.ContentMode = .scaleAspectFill

    init(url: URL, contentMode: UIView.ContentMode = .scaleAspectFill) {
        self.url = url
        self.data = nil
        self.contentMode = contentMode
    }

    init(data: Data, contentMode: UIView.ContentMode = .scaleAspectFill) {
        self.url = nil
        self.data = data
        self.contentMode = contentMode
    }

    var body: some View {
        AnimatedGifRepresentable(url: url, data: data, contentMode: contentMode)
    }
}

// MARK: - UIViewRepresentable

private struct AnimatedGifRepresentable: UIViewRepresentable {
    let url: URL?
    let data: Data?
    let contentMode: UIView.ContentMode

    func makeUIView(context: Context) -> AnimatedGifUIView {
        let view = AnimatedGifUIView()
        view.contentMode = contentMode
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ uiView: AnimatedGifUIView, context: Context) {
        uiView.contentMode = contentMode
        if let data {
            uiView.setData(data)
        } else if let url {
            uiView.setURL(url)
        }
    }
}

// MARK: - Animated UIView (ImageIO-backed)

final class AnimatedGifUIView: UIView {
    private var imageView = UIImageView()
    private var displayLink: CADisplayLink?
    private var frames: [UIImage] = []
    private var frameDurations: [TimeInterval] = []
    private var totalDuration: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private var lastTickAt: CFTimeInterval = 0
    private var loadingTask: Task<Void, Never>?
    private var currentURL: URL?
    private var currentDataHash: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(imageView)
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var contentMode: UIView.ContentMode {
        didSet { imageView.contentMode = contentMode }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stop()
        } else if !frames.isEmpty {
            start()
        }
    }

    func setURL(_ url: URL) {
        // Skip if the URL hasn't changed — UIViewRepresentable.updateUIView
        // fires on every render, so guarding here keeps us from cancelling
        // and restarting the decode on every parent layout pass.
        guard currentURL != url else { return }
        currentURL = url
        currentDataHash = nil
        loadingTask?.cancel()
        frames = []
        imageView.image = nil

        loadingTask = Task { [weak self] in
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = .returnCacheDataElseLoad
                let (data, _) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.applyData(data) }
            } catch {
                // Fall back to nothing — bubble will look empty.
            }
        }
    }

    func setData(_ data: Data) {
        let hash = data.hashValue
        guard currentDataHash != hash else { return }
        currentDataHash = hash
        currentURL = nil
        loadingTask?.cancel()
        applyData(data)
    }

    private func applyData(_ data: Data) {
        let (decodedFrames, durations) = Self.decodeGIF(data: data)
        if decodedFrames.isEmpty {
            // Not actually animatable — fall back to a static UIImage.
            imageView.image = UIImage(data: data)
            stop()
            return
        }
        frames = decodedFrames
        frameDurations = durations
        totalDuration = durations.reduce(0, +)
        elapsed = 0
        imageView.image = frames.first
        if window != nil { start() }
    }

    private func start() {
        stop()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTickAt = CACurrentMediaTime()
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard totalDuration > 0 else { return }
        let now = CACurrentMediaTime()
        let delta = now - lastTickAt
        lastTickAt = now
        elapsed = (elapsed + delta).truncatingRemainder(dividingBy: totalDuration)

        var cursor: TimeInterval = 0
        for (i, dur) in frameDurations.enumerated() {
            cursor += dur
            if elapsed < cursor {
                if imageView.image !== frames[i] { imageView.image = frames[i] }
                return
            }
        }
    }

    /// Decodes every frame of a GIF using ImageIO. The per-frame delay
    /// honors `kCGImagePropertyGIFUnclampedDelayTime` when present (the
    /// real value); falls back to `kCGImagePropertyGIFDelayTime` (which
    /// most browsers clamp to >= 0.02s); and finally to a safe 0.1s
    /// default if neither is set.
    private static func decodeGIF(data: Data) -> (frames: [UIImage], durations: [TimeInterval]) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return ([], [])
        }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return ([], []) }

        var images: [UIImage] = []
        var durations: [TimeInterval] = []
        images.reserveCapacity(count)
        durations.reserveCapacity(count)

        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(UIImage(cgImage: cg))
            durations.append(frameDelay(at: i, in: source))
        }
        return (images, durations)
    }

    private static func frameDelay(at index: Int, in source: CGImageSource) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let gif = props[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        else { return 0.1 }
        if let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime as String] as? TimeInterval, unclamped > 0 {
            return unclamped
        }
        if let clamped = gif[kCGImagePropertyGIFDelayTime as String] as? TimeInterval, clamped > 0 {
            return clamped
        }
        return 0.1
    }
}
