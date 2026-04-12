import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let isCurrentUser: Bool
    let reactions: [MessageReaction]
    let currentUserId: String?
    let attachmentURL: URL?
    var onAvatarTap: (() -> Void)?
    var onReact: (String) -> Void

    @State private var showImagePreview = false

    private let quickReactions = ["🔥", "😂", "🙌", "👀", "🏀", "💯"]

    private var relativeTime: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: message.createdAt) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: message.createdAt)
        }() else { return "" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isCurrentUser {
                Spacer(minLength: 40)
                bubbleContent(alignment: .trailing)
                AvatarView(
                    name: message.displayName,
                    avatarUrl: message.avatarUrl,
                    size: 32
                )
            } else {
                Button(action: { onAvatarTap?() }) {
                    AvatarView(
                        name: message.displayName,
                        avatarUrl: message.avatarUrl,
                        size: 32
                    )
                }
                .buttonStyle(.plain)

                bubbleContent(alignment: .leading)
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal)
        .fullScreenCover(isPresented: $showImagePreview) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()

                if let attachmentURL {
                    AsyncImage(url: attachmentURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .ignoresSafeArea()
                        case .failure:
                            photoFallback
                                .padding(24)
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        @unknown default:
                            photoFallback
                                .padding(24)
                        }
                    }
                }

                Button {
                    showImagePreview = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.9))
                        .padding()
                }
            }
        }
    }

    @ViewBuilder
    private func bubbleContent(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            HStack(spacing: 6) {
                if !isCurrentUser {
                    Button(action: { onAvatarTap?() }) {
                        Text(message.displayName)
                            .font(.caption.bold())
                            .foregroundColor(.appAccentOrange)
                    }
                    .buttonStyle(.plain)
                }

                Text(relativeTime)
                    .font(.caption2)
                    .foregroundColor(.appTextTertiary)
            }

            VStack(alignment: .leading, spacing: 8) {
                if message.isPhotoMessage, let attachmentURL {
                    Button {
                        showImagePreview = true
                    } label: {
                        AsyncImage(url: attachmentURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 220, height: 220)
                                    .clipped()
                            case .failure:
                                photoFallback
                            case .empty:
                                ZStack {
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(Color.appSurface)
                                    ProgressView()
                                        .tint(.white)
                                }
                            @unknown default:
                                photoFallback
                            }
                        }
                        .frame(width: 220, height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "photo")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.black.opacity(0.45), in: Circle())
                                .padding(10)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if message.hasText {
                    Text(message.content)
                        .font(.body)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isCurrentUser ? Color.appAccentOrange : Color.appSurfaceElevated)
                        .cornerRadius(16, corners: isCurrentUser
                            ? [.topLeft, .topRight, .bottomLeft]
                            : [.topLeft, .topRight, .bottomRight])
                }
            }
            .contextMenu {
                ForEach(quickReactions, id: \.self) { emoji in
                    Button(emoji) {
                        onReact(emoji)
                    }
                }
            }

            ReactionBar(
                reactions: reactions,
                currentUserId: currentUserId,
                quickReactions: quickReactions,
                onReact: onReact
            )
        }
    }

    private var photoFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.appSurface)
            VStack(spacing: 8) {
                Image(systemName: "photo.fill")
                    .font(.title2)
                    .foregroundColor(.appAccentOrange)
                Text("Photo unavailable")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .frame(width: 220, height: 220)
    }
}

private struct ReactionBar: View {
    let reactions: [MessageReaction]
    let currentUserId: String?
    let quickReactions: [String]
    let onReact: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(reactions) { reaction in
                Button {
                    onReact(reaction.emoji)
                } label: {
                    HStack(spacing: 4) {
                        Text(reaction.emoji)
                        Text("\(reaction.count)")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        reaction.userIds.contains(currentUserId ?? "")
                        ? Color.appAccentOrange.opacity(0.22)
                        : Color.white.opacity(0.08)
                    )
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(reaction.userIds.contains(currentUserId ?? "") ? Color.appAccentOrange.opacity(0.65) : Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Menu {
                ForEach(quickReactions, id: \.self) { emoji in
                    Button(emoji) {
                        onReact(emoji)
                    }
                }
            } label: {
                Image(systemName: "face.smiling")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.75))
                    .padding(8)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
        }
    }
}

// MARK: - Rounded Corner Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    VStack(spacing: 12) {
        MessageBubbleView(
            message: ChatMessage(id: "1", userId: "a", displayName: "Isaac", content: "Who's pulling up Saturday?", avatarUrl: nil, messageType: "text", attachmentPath: nil, createdAt: "2026-03-23T10:00:00Z"),
            isCurrentUser: false,
            reactions: [MessageReaction(messageId: "1", emoji: "🔥", count: 3, userIds: ["x"], displayNames: ["J"])],
            currentUserId: "x",
            attachmentURL: nil,
            onAvatarTap: {},
            onReact: { _ in }
        )
        MessageBubbleView(
            message: ChatMessage(id: "2", userId: "b", displayName: "You", content: "I'm in! See you there", avatarUrl: nil, messageType: "photo", attachmentPath: "samples/1.jpg", createdAt: "2026-03-23T10:01:00Z"),
            isCurrentUser: true,
            reactions: [],
            currentUserId: "x",
            attachmentURL: nil,
            onAvatarTap: nil,
            onReact: { _ in }
        )
    }
    .padding(.vertical)
    .background(Color.appBackground)
}
