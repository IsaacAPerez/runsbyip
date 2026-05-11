import SwiftUI
import PhotosUI

struct ChatView: View {
    @EnvironmentObject var chatService: ChatService
    @EnvironmentObject var authService: AuthService
    @StateObject private var chatWriteGate = ChatWriteGate()
    @Environment(\.scenePhase) private var scenePhase

    @State private var messageText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var currentUserId: String?
    @State private var tappedProfile: ChatMessage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoPreview: UIImage?
    @State private var selectedPhotoData: Data?
    @State private var typingResetTask: Task<Void, Never>?
    @State private var showMembers = false
    @State private var isMuted = false

    @State private var gatePassphrase = ""
    @State private var gateError: String?

    private var canUseChatWrites: Bool {
        !ChatWriteGateConfig.isEnabled || chatWriteGate.isUnlocked
    }

    private var typingIndicatorText: String? {
        let names = chatService.typingUsers.map(\.displayName)
        guard !names.isEmpty else { return nil }
        if names.count == 1 {
            return "\(names[0]) is typing…"
        }
        if names.count == 2 {
            return "\(names[0]) and \(names[1]) are typing…"
        }
        return "Several hoopers are typing…"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    if isLoading {
                        LoadingView(message: "Loading chat...")
                    } else if chatService.messages.isEmpty {
                        Spacer()
                        EmptyStateView(
                            icon: "💬",
                            title: "No Messages Yet",
                            subtitle: "Say hey or drop a run photo. Dead chat is bad for morale."
                        )
                        Spacer()
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 16) {
                                    ForEach(chatService.messages) { message in
                                        MessageBubbleView(
                                            message: message,
                                            isCurrentUser: message.userId == currentUserId,
                                            reactions: chatService.reactionsByMessage[message.id] ?? [],
                                            currentUserId: currentUserId,
                                            attachmentURL: chatService.publicURL(for: message.attachmentPath),
                                            avatarDisplayURL: chatService.effectiveAvatarURL(
                                                for: message,
                                                currentUserId: currentUserId,
                                                currentUserProfileAvatar: authService.currentProfile?.avatarUrl
                                            ),
                                            onAvatarTap: {
                                                if message.userId != currentUserId {
                                                    tappedProfile = message
                                                }
                                            },
                                            onReact: { emoji in
                                                react(to: message.id, emoji: emoji)
                                            },
                                            reactionsAllowed: canUseChatWrites
                                        )
                                        .id(message.id)
                                    }
                                }
                                .padding(.vertical, 14)
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .onChange(of: chatService.messages.count) { _, _ in
                                scrollToBottom(proxy: proxy)
                            }
                            .onAppear {
                                scrollToBottom(proxy: proxy, animated: false)
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        if isMuted {
                            HStack(spacing: 8) {
                                Image(systemName: "speaker.slash.fill")
                                    .foregroundColor(.appTextSecondary)
                                Text("You've been muted")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.appTextSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        } else if canUseChatWrites {
                            if let typingIndicatorText {
                                HStack(spacing: 8) {
                                    TypingDotsView()
                                    Text(typingIndicatorText)
                                        .font(.caption)
                                        .foregroundColor(.appTextSecondary)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            if let selectedPhotoPreview {
                                HStack(spacing: 12) {
                                    Image(uiImage: selectedPhotoPreview)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Photo ready")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.white)
                                        Text("Attachments are photo-only for now.")
                                            .font(.caption)
                                            .foregroundColor(.appTextSecondary)
                                    }

                                    Spacer()

                                    Button {
                                        clearSelectedPhoto()
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.title3)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                }
                                .padding(12)
                                .background(Color.appSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .padding(.horizontal)
                            }

                            HStack(alignment: .bottom, spacing: 12) {
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                                    Image(systemName: selectedPhotoPreview == nil ? "photo.on.rectangle.angled" : "photo.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(selectedPhotoPreview == nil ? .white.opacity(0.72) : .appAccentOrange)
                                        .frame(width: 42, height: 42)
                                        .background(Color.appSurface, in: Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color.appBorder, lineWidth: 1)
                                        )
                                }

                                TextField(selectedPhotoPreview == nil ? "Message..." : "Add a caption...", text: $messageText, axis: .vertical)
                                    .lineLimit(1...4)
                                    .padding(12)
                                    .background(Color.appSurface)
                                    .foregroundColor(.white)
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.appBorder, lineWidth: 1)
                                    )
                                    .onChange(of: messageText) { _, newValue in
                                        handleComposerChange(newValue)
                                    }

                                Button {
                                    sendMessage()
                                } label: {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 34))
                                        .foregroundColor(canSendMessage ? .appAccentOrange : .appTextSecondary)
                                }
                                .disabled(!canSendMessage)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                        } else {
                            ChatWriteGatePanel(
                                chatWriteGate: chatWriteGate,
                                passphrase: $gatePassphrase,
                                errorMessage: $gateError,
                                onUnlocked: {
                                    gatePassphrase = ""
                                    gateError = nil
                                }
                            )
                        }
                    }
                    .background(Color.appBackground)
                }
            }
            .condensedNavTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        if ChatWriteGateConfig.isEnabled, chatWriteGate.isUnlocked {
                            Button {
                                typingResetTask?.cancel()
                                chatService.setTyping(isTyping: false)
                                chatWriteGate.lock()
                                gateError = nil
                            } label: {
                                Image(systemName: "lock.open.fill")
                                    .foregroundColor(.appAccentOrange)
                            }
                            .accessibilityLabel("Lock chat sending")
                        }
                        Button {
                            showMembers = true
                        } label: {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(.appAccentOrange)
                        }
                    }
                }
            }
            .sheet(isPresented: $showMembers) {
                MembersListView()
                    .environmentObject(chatService)
                    .environmentObject(authService)
            }
            .onChange(of: chatWriteGate.isUnlocked) { _, unlocked in
                if !unlocked {
                    typingResetTask?.cancel()
                    chatService.setTyping(isTyping: false)
                    clearSelectedPhoto()
                    messageText = ""
                }
            }
            .task {
                await loadChat()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Realtime postgres changes don't replay missed events, so
                // anything sent while we were backgrounded never reaches the
                // local channel. Reconcile from the server on foreground.
                guard newPhase == .active, !isLoading else { return }
                Task { await chatService.refetchSinceLastSeen() }
            }
            .onDisappear {
                typingResetTask?.cancel()
                chatService.setTyping(isTyping: false)
                Task { await chatService.unsubscribe() }
            }
            .onChange(of: selectedPhotoItem) { _, newValue in
                Task {
                    await loadSelectedPhoto(newValue)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
                Button("OK") { errorMessage = nil }
            }, message: {
                Text(errorMessage ?? "")
            })
            .sheet(item: $tappedProfile) { message in
                UserPublicProfileView(
                    userId: message.userId,
                    displayName: message.displayName,
                    avatarUrl: message.avatarUrl
                )
                .environmentObject(chatService)
            }
        }
    }

    private var canSendMessage: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedPhotoData != nil
    }

    private func loadChat() async {
        // Render as soon as the fetch + auth lookups resolve. Realtime
        // subscribes run detached: the Supabase tenant cold-starts (replication
        // slot, publication validation, WAL stream) on first connect after
        // inactivity, which can take seconds or hang outright. Gating the
        // spinner on that produced infinite "Loading chat..." in the sim.
        // The insert handler dedupes by id, so any messages that land while
        // subscribes are still warming up are caught by refetchSinceLastSeen
        // on the next foregrounding.
        async let userIdTask = chatService.currentUserId
        async let muteTask = chatService.checkMuteStatus()
        Task { await chatService.subscribeToMessages() }

        do {
            try await chatService.fetchMessages()
        } catch {
            errorMessage = error.localizedDescription
        }

        currentUserId = await userIdTask
        if let muted = await muteTask { isMuted = muted }
        isLoading = false
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        guard let lastId = chatService.messages.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else {
            clearSelectedPhoto()
            return
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let optimizedData = UIImage(data: data)?.jpegData(compressionQuality: 0.82),
                  let preview = UIImage(data: optimizedData)
            else {
                errorMessage = "Couldn't load that photo. Try another one."
                return
            }

            await MainActor.run {
                selectedPhotoData = optimizedData
                selectedPhotoPreview = preview
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearSelectedPhoto() {
        selectedPhotoItem = nil
        selectedPhotoPreview = nil
        selectedPhotoData = nil
    }

    private func sendMessage() {
        guard canUseChatWrites else { return }
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let photoData = selectedPhotoData
        guard !content.isEmpty || photoData != nil else { return }

        messageText = ""
        clearSelectedPhoto()
        typingResetTask?.cancel()
        chatService.setTyping(isTyping: false)

        Task {
            do {
                try await chatService.sendMessage(content: content, photoData: photoData)
            } catch AppError.unauthorized {
                errorMessage = "Sign in to send messages."
            } catch {
                errorMessage = error.localizedDescription
                await MainActor.run {
                    messageText = content
                    if let photoData, let preview = UIImage(data: photoData) {
                        selectedPhotoData = photoData
                        selectedPhotoPreview = preview
                    }
                }
            }
        }
    }

    private func react(to messageId: String, emoji: String) {
        guard canUseChatWrites else {
            errorMessage = "Unlock chat below to react."
            return
        }
        Task {
            do {
                try await chatService.toggleReaction(messageId: messageId, emoji: emoji)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleComposerChange(_ newValue: String) {
        guard canUseChatWrites else { return }
        guard currentUserId != nil else { return }
        let hasContent = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedPhotoData != nil
        chatService.setTyping(isTyping: hasContent)

        typingResetTask?.cancel()
        guard hasContent else { return }

        typingResetTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                chatService.setTyping(isTyping: false)
            }
        }
    }
}

private struct ChatWriteGatePanel: View {
    @ObservedObject var chatWriteGate: ChatWriteGate
    @Binding var passphrase: String
    @Binding var errorMessage: String?
    var onUnlocked: () -> Void

    @FocusState private var fieldFocused: Bool
    @State private var isVerifying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chat is protected")
                .font(.subheadline.bold())
                .foregroundColor(.white)

            Text("Enter the group passphrase to send messages, show typing, and add reactions.")
                .font(.caption)
                .foregroundColor(.appTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if chatWriteGate.isInLockout {
                Text("Too many attempts. Try again in \(chatWriteGate.lockoutRemainingSeconds)s.")
                    .font(.caption)
                    .foregroundColor(.appError)
            } else if let err = chatWriteGate.lastVerificationError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.appError)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.appError)
            }

            SecureField("Passphrase", text: $passphrase)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)
                .padding(12)
                .background(Color.appSurfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                )
                .focused($fieldFocused)
                .disabled(isVerifying)

            Button {
                tryUnlock()
            } label: {
                Group {
                    if isVerifying {
                        ProgressView()
                            .tint(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    } else {
                        Text("Unlock chat")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .background(Color.appAccentOrange)
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius, style: .continuous))
            }
            .disabled(
                passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || chatWriteGate.isInLockout
                    || isVerifying
            )
            .opacity(chatWriteGate.isInLockout ? 0.5 : 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.appBackground)
        .onAppear { fieldFocused = true }
    }

    private func tryUnlock() {
        errorMessage = nil
        isVerifying = true
        Task { @MainActor in
            let ok = await chatWriteGate.submitPassphrase(passphrase)
            isVerifying = false
            if ok {
                onUnlocked()
            } else if chatWriteGate.lastVerificationError != nil {
                passphrase = ""
            } else if !chatWriteGate.isInLockout {
                errorMessage = "Incorrect passphrase"
                passphrase = ""
            }
        }
    }
}

private struct TypingDotsView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.appAccentOrange.opacity(0.85))
                    .frame(width: 6, height: 6)
                    .offset(y: animate ? -2 : 2)
                    .animation(
                        .easeInOut(duration: 0.45)
                        .repeatForever()
                        .delay(Double(index) * 0.12),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

// MARK: - Members List View

struct MembersListView: View {
    @EnvironmentObject var chatService: ChatService
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) var dismiss

    @State private var users: [UserProfile] = []
    @State private var isLoading = true
    @State private var selectedUser: UserProfile?

    private var isAdmin: Bool { authService.isAdmin }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if isLoading {
                    LoadingView(message: "Loading members...")
                } else if users.isEmpty {
                    EmptyStateView(
                        icon: "👥",
                        title: "No Members",
                        subtitle: "Members will appear here once they join."
                    )
                } else {
                    List(users) { user in
                        Button {
                            selectedUser = user
                        } label: {
                            MemberRow(user: user, isAdmin: isAdmin) {
                                toggleMute(user: user)
                            }
                        }
                        .listRowBackground(Color.appSurface)
                        .listRowSeparatorTint(Color.appBorder)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .condensedNavTitle("Members")
                        .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.appAccentOrange)
                }
            }
            .sheet(item: $selectedUser) { user in
                UserPublicProfileView(
                    userId: user.id,
                    displayName: user.displayName ?? "Player",
                    avatarUrl: user.avatarUrl
                )
                .environmentObject(chatService)
            }
            .task {
                do {
                    users = try await chatService.fetchAllUsers()
                } catch {
                    // Degrade gracefully
                }
                isLoading = false
            }
        }
    }

    private func toggleMute(user: UserProfile) {
        let newMuted = !user.isMuted
        Task {
            try? await chatService.toggleMute(userId: user.id, muted: newMuted)
            if let idx = users.firstIndex(where: { $0.id == user.id }) {
                users = try await chatService.fetchAllUsers()
            }
        }
    }
}

// MARK: - Member Row

private struct MemberRow: View {
    let user: UserProfile
    var isAdmin: Bool = false
    var onToggleMute: (() -> Void)?

    private var joinDate: String {
        guard let createdAt = user.createdAt else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: createdAt) else { return "" }
        let display = DateFormatter()
        display.dateFormat = "MMM yyyy"
        return "Joined \(display.string(from: date))"
    }

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(
                name: user.displayName ?? "?",
                avatarUrl: user.avatarUrl,
                size: 44
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(user.displayName ?? "Player")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    if user.isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.8))
                    }
                }

                if !joinDate.isEmpty {
                    Text(joinDate)
                        .font(.system(size: 13))
                        .foregroundColor(.appTextSecondary)
                }
            }

            Spacer()

            if isAdmin && user.role != "admin" {
                Button {
                    onToggleMute?()
                } label: {
                    Image(systemName: user.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 16))
                        .foregroundColor(user.isMuted ? .red : .appTextSecondary)
                        .frame(width: 36, height: 36)
                        .background(user.isMuted ? Color.red.opacity(0.15) : Color.appSurface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.appTextTertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ChatView()
        .environmentObject(ChatService())
        .environmentObject(AuthService())
}
