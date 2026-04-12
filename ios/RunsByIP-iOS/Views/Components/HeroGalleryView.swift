import SwiftUI
import UIKit

struct HeroGalleryView: View {
    let urls: [URL]

    var body: some View {
        ZStack {
            Color.appBackground

            if !urls.isEmpty {
                ScrollingStripView(urls: urls, speed: 30)
            }

            // Gradient overlay
            LinearGradient(
                colors: [
                    Color.appBackground,
                    Color.appBackground.opacity(0.85),
                    Color.appBackground.opacity(0.4),
                    Color.appBackground.opacity(0.2)
                ],
                startPoint: .bottom,
                endPoint: .top
            )

            // Side fades
            HStack {
                LinearGradient(
                    colors: [Color.appBackground, Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 40)

                Spacer()

                LinearGradient(
                    colors: [Color.clear, Color.appBackground],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 40)
            }
        }
        .frame(height: 340)
        .clipped()
    }
}

// MARK: - UIKit-backed scrolling strip (no SwiftUI state churn)

private struct ScrollingStripView: UIViewRepresentable {
    let urls: [URL]
    let speed: CGFloat

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        container.backgroundColor = .clear

        let strip = UIView()
        strip.tag = 100
        container.addSubview(strip)

        // Load images asynchronously
        Task { @MainActor in
            var imageViews: [UIImageView] = []

            for url in urls + urls { // double for seamless loop
                let iv = UIImageView()
                iv.contentMode = .scaleAspectFill
                iv.clipsToBounds = true
                iv.backgroundColor = UIColor(Color.appSurface)
                strip.addSubview(iv)
                imageViews.append(iv)

                // Load image
                Task {
                    if let (data, _) = try? await URLSession.shared.data(from: url),
                       let image = UIImage(data: data) {
                        iv.image = image
                    }
                }
            }

            context.coordinator.imageViews = imageViews
            context.coordinator.strip = strip
            context.coordinator.container = container
            context.coordinator.layoutAndAnimate()
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(urlCount: urls.count, speed: speed)
    }

    class Coordinator {
        let urlCount: Int
        let speed: CGFloat
        var imageViews: [UIImageView] = []
        weak var strip: UIView?
        weak var container: UIView?
        private var displayLink: CADisplayLink?

        init(urlCount: Int, speed: CGFloat) {
            self.urlCount = urlCount
            self.speed = speed
        }

        func layoutAndAnimate() {
            guard let strip, let container else { return }

            let containerWidth = container.bounds.width > 0 ? container.bounds.width : UIScreen.main.bounds.width
            let imageWidth = max(containerWidth * 0.75, 250)
            let height: CGFloat = 340

            for (i, iv) in imageViews.enumerated() {
                iv.frame = CGRect(x: CGFloat(i) * imageWidth, y: 0, width: imageWidth, height: height)
            }

            let totalWidth = CGFloat(urlCount) * imageWidth
            strip.frame = CGRect(x: 0, y: 0, width: totalWidth * 2, height: height)

            // Start display link
            displayLink?.invalidate()
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        @objc private func tick(_ link: CADisplayLink) {
            guard let strip else { return }
            let containerWidth = strip.superview?.bounds.width ?? UIScreen.main.bounds.width
            let imageWidth = max(containerWidth * 0.75, 250)
            let singleStripWidth = CGFloat(urlCount) * imageWidth

            var x = strip.frame.origin.x - speed * CGFloat(link.duration)
            if x <= -singleStripWidth {
                x += singleStripWidth
            }
            strip.frame.origin.x = x
        }

        deinit {
            displayLink?.invalidate()
        }
    }
}
