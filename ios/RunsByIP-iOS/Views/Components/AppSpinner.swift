import SwiftUI

/// Custom in-app loading spinner. Replaces every stock ProgressView so
/// loading state always feels on-brand: a rotating arc with an angular
/// gradient tail (premium "comet" look), defaulting to the app's accent
/// orange but tintable for use on colored buttons.
///
/// Four canonical sizes. The previous ad-hoc pattern of
/// `ProgressView().scaleEffect(0.8)` maps to `.sm`; default
/// `ProgressView()` maps to `.md`.
struct AppSpinner: View {
    enum Size {
        case xs, sm, md, lg

        var diameter: CGFloat {
            switch self {
            case .xs: return 14
            case .sm: return 18
            case .md: return 26
            case .lg: return 44
            }
        }

        var lineWidth: CGFloat { max(2, diameter * 0.14) }
    }

    var color: Color = .appAccentOrange
    var size: Size = .md

    @State private var rotation: Double = 0
    @State private var hasStarted: Bool = false

    var body: some View {
        Circle()
            // Trim leaves a small gap to make the rotation obvious; the
            // angular gradient fades the trailing edge into transparency
            // so it reads as a comet trail rather than a solid pac-man.
            .trim(from: 0.0, to: 0.78)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        color.opacity(0.0),
                        color.opacity(0.25),
                        color
                    ]),
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(280)
                ),
                style: StrokeStyle(lineWidth: size.lineWidth, lineCap: .round)
            )
            .frame(width: size.diameter, height: size.diameter)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                guard !hasStarted else { return }
                hasStarted = true
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
            .accessibilityLabel("Loading")
    }
}

#Preview {
    VStack(spacing: 24) {
        AppSpinner(size: .xs)
        AppSpinner(size: .sm)
        AppSpinner(size: .md)
        AppSpinner(size: .lg)
        AppSpinner(color: .white, size: .md)
    }
    .padding(40)
    .background(Color.appBackground)
}
