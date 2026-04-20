import SwiftUI

/// Branded splash shown while auth state resolves at app startup.
/// Mirrors the onboarding welcome page treatment so the transition feels seamless.
struct SplashView: View {
    @State private var iconPulse = false
    @State private var dotsAnimate = false

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.space24) {
                Spacer()

                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .white.opacity(0.25), radius: 24, y: 10)
                    .scaleEffect(iconPulse ? 1.04 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                        value: iconPulse
                    )

                VStack(spacing: 10) {
                    Text("RunsByIP")
                        .font(.system(size: 38, weight: .black).width(.condensed))
                        .foregroundColor(.appTextPrimary)

                    Text("Weekly pickup basketball in LA")
                        .font(.appBody)
                        .foregroundColor(.appTextSecondary)
                }

                Spacer()

                LoadingDots(animate: dotsAnimate)
                    .padding(.bottom, AppSpacing.space32)
            }
            .padding(.horizontal, AppSpacing.space32)
        }
        .onAppear {
            iconPulse = true
            dotsAnimate = true
        }
    }
}

/// Three-dot wave loader — each dot scales + fades with a staggered delay.
private struct LoadingDots: View {
    let animate: Bool

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.appTextPrimary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animate ? 1.0 : 0.5)
                    .opacity(animate ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(0.15 * Double(index)),
                        value: animate
                    )
            }
        }
    }
}

#Preview {
    SplashView()
}
