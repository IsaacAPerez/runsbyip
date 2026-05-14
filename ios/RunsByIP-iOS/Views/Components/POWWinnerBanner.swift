import SwiftUI

/// Full-width celebratory banner shown the moment a POW poll closes. Two
/// variants: "You won" for the current user when their display name
/// matches winner_name, and a "Player of the Week is X" announcement
/// for everyone else.
struct POWWinnerBanner: View {
    let winnerName: String
    let voteCount: Int
    let isCurrentUser: Bool
    let onDismiss: () -> Void

    @State private var sparkle: Bool = false

    private var title: String {
        isCurrentUser ? "🏆 You're the Player of the Week!" : "🏆 Player of the Week"
    }

    private var subtitle: String {
        let voteWord = voteCount == 1 ? "vote" : "votes"
        return isCurrentUser
            ? "\(voteCount) \(voteWord). Take a bow."
            : "\(winnerName) won with \(voteCount) \(voteWord)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Sparkle clusters that pulse for vibe; pure SwiftUI, no
            // particle system — works on every device tier.
            ZStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.appAccentOrange)
                    .scaleEffect(sparkle ? 1.15 : 0.85)
                    .opacity(sparkle ? 1.0 : 0.5)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy).width(.condensed))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.7))
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [Color.appAccentOrange.opacity(0.95), Color.appAccentOrange.opacity(0.55)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.appAccentOrange.opacity(0.4), radius: 14, x: 0, y: 6)
        .padding(.horizontal, 12)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                sparkle.toggle()
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
