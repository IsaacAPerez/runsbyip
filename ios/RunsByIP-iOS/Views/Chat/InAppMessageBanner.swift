import SwiftUI

/// Top-anchored slide-in banner for a new chat message landing while the
/// user is somewhere else in the app. Pairs with the AppDelegate
/// suppression of system-banner pushes for `type=new_message` so the user
/// sees one consistent notification (this one), not two.
struct InAppMessageBanner: View {
    let message: ChatMessage
    let avatarUrl: String?
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

    private var preview: String {
        if message.isPhotoMessage {
            let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "📷 Photo" : "📷 \(text)"
        }
        return message.content
    }

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: message.displayName, avatarUrl: avatarUrl, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.displayName)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(preview)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.appSurfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 6)
        )
        .padding(.horizontal, 12)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Allow flicking up to dismiss; ignore downward drags.
                    dragOffset = min(value.translation.height, 0)
                }
                .onEnded { value in
                    if value.translation.height < -40 {
                        onDismiss()
                    } else {
                        withAnimation(.easeOut(duration: 0.15)) { dragOffset = 0 }
                    }
                }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
