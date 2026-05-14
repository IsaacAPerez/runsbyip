import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let isCurrentUser: Bool
    let reactions: [MessageReaction]
    let currentUserId: String?
    let attachmentURL: URL?
    /// When set, overrides `message.avatarUrl` (realtime inserts only include `messages` columns).
    var avatarDisplayURL: String? = nil
    var onAvatarTap: (() -> Void)?
    var onReact: (String) -> Void
    /// When `false`, reactions and quick-emoji UI are disabled (chat write gate).
    var reactionsAllowed: Bool = true
    var deliveryState: MessageDeliveryState = .sent
    var onRetry: (() -> Void)?
    var onCancelFailed: (() -> Void)?

    @State private var showImagePreview = false

    private let quickReactions: [String] = Array(EmojiCatalog.popular.prefix(6))

    private var resolvedAvatarURL: String? {
        if let u = avatarDisplayURL?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty { return u }
        if let u = message.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty { return u }
        return nil
    }

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
                    avatarUrl: resolvedAvatarURL,
                    size: 32
                )
            } else {
                Button(action: { onAvatarTap?() }) {
                    AvatarView(
                        name: message.displayName,
                        avatarUrl: resolvedAvatarURL,
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
            ZStack {
                Color.black
                    .ignoresSafeArea()
                    .onTapGesture { showImagePreview = false }

                if let attachmentURL {
                    if message.isGifMessage {
                        AnimatedGifView(url: attachmentURL, contentMode: .scaleAspectFit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea()
                    } else {
                        CachedAsyncImage(
                            url: attachmentURL,
                            contentMode: .fit,
                            failure: { photoFallback.padding(24) },
                            loading: { AppSpinner(color: .white, size: .sm) }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    showImagePreview = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.9))
                        .padding()
                }
            }
            .statusBarHidden()
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
                if message.isGifMessage, let attachmentURL {
                    Button {
                        showImagePreview = true
                    } label: {
                        AnimatedGifView(url: attachmentURL, contentMode: .scaleAspectFill)
                            .frame(width: 220, height: 220)
                            .background(Color.appSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Text("GIF")
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                                    .padding(10)
                            }
                    }
                    .buttonStyle(.plain)
                } else if message.isPhotoMessage, let attachmentURL {
                    Button {
                        showImagePreview = true
                    } label: {
                        CachedAsyncImage(
                            url: attachmentURL,
                            contentMode: .fill,
                            failure: { photoFallback },
                            loading: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(Color.appSurface)
                                    AppSpinner(color: .white, size: .md)
                                }
                            }
                        )
                        .frame(width: 220, height: 220)
                        .clipped()
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
                        .foregroundColor(isCurrentUser ? .appBackground : .white)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isCurrentUser ? Color.appAccentOrange : Color.appSurfaceElevated)
                        .cornerRadius(16, corners: isCurrentUser
                            ? [.topLeft, .topRight, .bottomLeft]
                            : [.topLeft, .topRight, .bottomRight])
                        .opacity(isPendingForUser ? 0.65 : 1.0)
                }
            }
            .modifier(ReactionContextMenuModifier(
                reactionsAllowed: reactionsAllowed && isDeliverySent,
                quickReactions: quickReactions,
                messageText: message.content,
                onReact: onReact
            ))

            if isCurrentUser, case .failed(let reason) = deliveryState {
                FailedSendRow(reason: reason, onRetry: onRetry, onCancel: onCancelFailed)
            } else if isPendingForUser {
                HStack(spacing: 4) {
                    AppSpinner(color: .appTextSecondary, size: .xs)
                    Text("Sending…")
                        .font(.caption2)
                        .foregroundColor(.appTextSecondary)
                }
            }

            ReactionBar(
                reactions: reactions,
                currentUserId: currentUserId,
                quickReactions: quickReactions,
                reactionsAllowed: reactionsAllowed && isDeliverySent,
                onReact: onReact
            )
        }
    }

    private var isDeliverySent: Bool {
        if case .sent = deliveryState { return true }
        return false
    }

    private var isPendingForUser: Bool {
        guard isCurrentUser else { return false }
        if case .pending = deliveryState { return true }
        return false
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

private struct FailedSendRow: View {
    let reason: String
    let onRetry: (() -> Void)?
    let onCancel: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.appError)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't send")
                    .font(.caption.bold())
                    .foregroundColor(.appError)
                Text(reason)
                    .font(.caption2)
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            if let onRetry {
                Button("Retry", action: onRetry)
                    .font(.caption.bold())
                    .foregroundColor(.appAccentOrange)
            }
            if let onCancel {
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundColor(.appTextSecondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.appError.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ReactionContextMenuModifier: ViewModifier {
    let reactionsAllowed: Bool
    let quickReactions: [String]
    let messageText: String
    let onReact: (String) -> Void

    func body(content: Content) -> some View {
        content.contextMenu {
            if reactionsAllowed {
                ForEach(quickReactions, id: \.self) { emoji in
                    Button(emoji) { onReact(emoji) }
                }
            }
            if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    UIPasteboard.general.string = messageText
                    Haptics.success()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }
}

private struct ReactionBar: View {
    let reactions: [MessageReaction]
    let currentUserId: String?
    let quickReactions: [String]
    let reactionsAllowed: Bool
    let onReact: (String) -> Void

    @State private var showPicker = false

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
                .disabled(!reactionsAllowed)
                .opacity(reactionsAllowed ? 1 : 0.45)
            }

            Button {
                showPicker = true
            } label: {
                Image(systemName: "face.smiling")
                    .font(.caption.bold())
                    .foregroundColor(.white.opacity(0.75))
                    .padding(8)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!reactionsAllowed)
            .opacity(reactionsAllowed ? 1 : 0.45)
            .sheet(isPresented: $showPicker) {
                EmojiPickerView { emoji in
                    onReact(emoji)
                }
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
            reactions: [MessageReaction(messageId: "1", emoji: "🔥", count: 3, userIds: ["x"])],
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
