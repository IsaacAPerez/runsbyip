import SwiftUI
import PhotosUI

struct ChatView: View {
    @EnvironmentObject var chatService: ChatService
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var appConfig: AppConfigService
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @StateObject private var chatWriteGate = ChatWriteGate()
    @Environment(\.scenePhase) private var scenePhase

    @State private var isTogglingChatLock = false

    @State private var messageText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var currentUserId: String?
    @State private var tappedProfile: ChatMessage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoPreview: UIImage?
    @State private var selectedPhotoData: Data?
    /// Set when the picked image is a GIF — preserves the original
    /// animated bytes so we send it as `message_type = 'gif'` instead
    /// of compressing to a static JPEG.
    @State private var selectedGifData: Data?
    @State private var typingResetTask: Task<Void, Never>?
    @State private var showMembers = false
    /// Ids of message cells currently on screen. Used to compute "pinned near
    /// bottom" without requiring the very last cell to be visible — being one
    /// or two rows up from the floor still counts.
    @State private var visibleMessageIds: Set<String> = []
    @State private var isLoadingOlder: Bool = false
    @State private var didInitialScroll: Bool = false
    /// True while we're driving a scroll programmatically (cold-launch
    /// settle, tab-tap-to-bottom, keyboard-pin, new-message auto-pin).
    /// The top "Load older…" sentinel only paginates when this is FALSE —
    /// i.e., the user actually dragged their way to the top. Starts true
    /// so the initial top-down LazyVStack layout can't trigger pagination
    /// before settleInitialScroll runs.
    @State private var isProgrammaticScrolling: Bool = true
    /// In-flight task fired by a chat-tab tap. Cancelled when a new tap
    /// arrives so two quick taps don't queue duplicate scrolls.
    @State private var tabScrollTask: Task<Void, Never>?
    @State private var unreadIncomingCount: Int = 0
    /// How many of the trailing rows count as "pinned near bottom". Set
    /// generously — being one or two screens up from the floor should
    /// still auto-scroll on a new message. Reading actual history (where
    /// the bottom 8 rows aren't on screen) is where the new-message pill
    /// kicks in.
    private static let pinnedBottomLookback: Int = 8

    private var isMuted: Bool { chatService.currentUserMuted }

    @State private var gatePassphrase = ""
    @State private var gateError: String?

    private var canUseChatWrites: Bool {
        !ChatWriteGateConfig.isEnabled || chatWriteGate.isUnlocked
    }

    /// "1 online (you)" when nobody else is in chat, "N online" when
    /// others are. Always includes self in the count.
    private var onlineLabel: String {
        let others = chatService.presenceUserIds.count
        if others == 0 {
            return "1 online (you)"
        }
        return "\(others + 1) online"
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
                                    if chatService.hasMoreOlderMessages {
                                        // Top sentinel: when the user has
                                        // scrolled (with their finger) up to
                                        // the very top of what's loaded, page
                                        // in the next older batch. Programmatic
                                        // scrolls (initial settle, tab-tap-to-
                                        // bottom, keyboard pin, etc.) set
                                        // isProgrammaticScrolling so this
                                        // .onAppear is a no-op during them.
                                        HStack {
                                            Spacer()
                                            if isLoadingOlder {
                                                AppSpinner(color: .appTextSecondary, size: .md)
                                            } else {
                                                Text("Loading older…")
                                                    .font(.caption)
                                                    .foregroundColor(.appTextSecondary)
                                            }
                                            Spacer()
                                        }
                                        .padding(.vertical, 8)
                                        .onAppear {
                                            guard !isProgrammaticScrolling else { return }
                                            loadOlderMessages(proxy: proxy)
                                        }
                                    }

                                    ForEach(Array(chatService.messages.enumerated()), id: \.element.id) { index, message in
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
                                            reactionsAllowed: canUseChatWrites,
                                            deliveryState: chatService.deliveryState(for: message.id),
                                            onRetry: { chatService.retryFailedMessage(id: message.id) },
                                            onCancelFailed: { chatService.cancelFailedMessage(id: message.id) }
                                        )
                                        .id(message.id)
                                        .onAppear {
                                            visibleMessageIds.insert(message.id)
                                        }
                                        .onDisappear {
                                            visibleMessageIds.remove(message.id)
                                        }
                                    }
                                }
                                .padding(.vertical, 14)
                            }
                            .scrollDismissesKeyboard(.interactively)
                            .onChange(of: chatService.messages.count) { oldCount, newCount in
                                // First time messages populate, stagger a few
                                // scrolls — LazyVStack hasn't laid out the
                                // bottom cells yet on the first pass, and
                                // photo bubbles can shift things further as
                                // their AsyncImage placeholder swaps in.
                                if !didInitialScroll, newCount > 0 {
                                    didInitialScroll = true
                                    settleInitialScroll(proxy: proxy)
                                    return
                                }
                                guard newCount > oldCount else { return }

                                // Auto-scroll when the user was looking at
                                // the tail of the chat (any of the last 3
                                // bubbles visible). Also always scroll when
                                // the new last row is ours — sending should
                                // always pull the view to the bottom.
                                let msgs = chatService.messages
                                let wasNearBottom = msgs.dropLast()
                                    .suffix(Self.pinnedBottomLookback)
                                    .contains { visibleMessageIds.contains($0.id) }
                                let newLastIsOurs = msgs.last?.userId == currentUserId
                                if wasNearBottom || newLastIsOurs {
                                    scrollToBottom(proxy: proxy)
                                    unreadIncomingCount = 0
                                } else {
                                    // Reading history — surface the new-message
                                    // pill instead of hijacking scroll.
                                    unreadIncomingCount += (newCount - oldCount)
                                }
                            }
                            .onAppear {
                                if !didInitialScroll, !chatService.messages.isEmpty {
                                    didInitialScroll = true
                                    settleInitialScroll(proxy: proxy)
                                }
                            }
                            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                                // Pin to the latest message when the keyboard
                                // comes up so the composer never covers it.
                                let msgs = chatService.messages
                                let nearBottom = msgs
                                    .suffix(Self.pinnedBottomLookback)
                                    .contains { visibleMessageIds.contains($0.id) }
                                if nearBottom {
                                    scrollToBottom(proxy: proxy)
                                }
                            }
                            .onChange(of: visibleMessageIds) { _, _ in
                                // Clear the new-message pill once the user
                                // has scrolled back into the live tail.
                                guard unreadIncomingCount > 0 else { return }
                                let msgs = chatService.messages
                                let nearBottom = msgs
                                    .suffix(Self.pinnedBottomLookback)
                                    .contains { visibleMessageIds.contains($0.id) }
                                if nearBottom {
                                    unreadIncomingCount = 0
                                }
                            }
                            .onChange(of: navigationCoordinator.scrollChatToBottomToken) { _, _ in
                                // Tap chat tab → jump to newest. Mark the
                                // scroll as programmatic so the top sentinel
                                // can't paginate during the animation
                                // (otherwise its re-layout-driven .onAppear
                                // would yank the viewport back to the top).
                                tabScrollTask?.cancel()
                                tabScrollTask = Task { @MainActor in
                                    isProgrammaticScrolling = true
                                    try? await Task.sleep(for: .milliseconds(120))
                                    if Task.isCancelled { return }
                                    scrollToBottom(proxy: proxy)
                                    unreadIncomingCount = 0
                                    try? await Task.sleep(for: .milliseconds(700))
                                    if Task.isCancelled { return }
                                    isProgrammaticScrolling = false
                                }
                            }
                            .overlay(alignment: .bottom) {
                                if unreadIncomingCount > 0 {
                                    NewMessagesPill(count: unreadIncomingCount) {
                                        scrollToBottom(proxy: proxy)
                                        unreadIncomingCount = 0
                                    }
                                    .padding(.bottom, 12)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                            .animation(.easeOut(duration: 0.2), value: unreadIncomingCount)
                        }
                    }

                    VStack(spacing: 10) {
                        // Typing indicator sits above every bottom panel so
                        // it's visible to muted users, users staring at the
                        // chat-lock banner, and the gate panel — anywhere
                        // realtime typing broadcasts land.
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
                        } else if appConfig.chatSendLocked && !authService.isAdmin {
                            HStack(spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .foregroundColor(.appTextSecondary)
                                Text("Chat is locked by an admin")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.appTextSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        } else if canUseChatWrites {
                            if let selectedPhotoPreview {
                                HStack(spacing: 12) {
                                    Image(uiImage: selectedPhotoPreview)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(selectedGifData != nil ? "GIF ready" : "Photo ready")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.white)
                                        Text(selectedGifData != nil
                                            ? "Animated. Send to share."
                                            : "Photos and GIFs supported.")
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
            // Note: we don't use the shared .condensedNavTitle modifier
            // here because it claims the principal toolbar slot for a
            // plain title — and we want a title + live online count.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Chat")
                            .font(.system(size: 17, weight: .semibold).width(.condensed))
                            .foregroundColor(.white)
                        // presenceUserIds excludes the current user, so the
                        // displayed count is "everyone else in chat right now"
                        // + 1 for self. Always render once chat has loaded so
                        // the user can confirm presence is live even when
                        // they're alone in the room ("1 online" = you).
                        if chatService.hasLoadedInitial {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text(onlineLabel)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.appTextSecondary)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        if authService.isAdmin {
                            Button {
                                toggleGlobalChatLock()
                            } label: {
                                if isTogglingChatLock {
                                    AppSpinner(size: .sm)
                                } else {
                                    Image(systemName: appConfig.chatSendLocked ? "lock.fill" : "lock.open.fill")
                                        .foregroundColor(appConfig.chatSendLocked ? .appError : .appAccentOrange)
                                }
                            }
                            .disabled(isTogglingChatLock)
                            .accessibilityLabel(appConfig.chatSendLocked ? "Unlock chat for everyone" : "Lock chat for everyone")
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
                // Channels stay subscribed across tab switches — only the
                // composer's typing-reset task is local to this view.
                typingResetTask?.cancel()
                chatService.setTyping(isTyping: false)
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
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedPhotoData != nil
            || selectedGifData != nil
    }

    private func loadChat() async {
        // bootstrap() is idempotent — it paints from disk immediately on the
        // first call, kicks off realtime subscriptions for the whole session,
        // and on subsequent calls just reconciles since-last-seen. The
        // singleton-at-MainTabView ensures channels stay alive while the user
        // navigates between tabs.
        async let userIdTask = chatService.currentUserId
        async let muteTask = chatService.checkMuteStatus()

        if !chatService.hasLoadedInitial {
            await chatService.bootstrap()
        } else {
            await chatService.refetchSinceLastSeen()
        }

        currentUserId = await userIdTask
        _ = await muteTask
        isLoading = false
    }

    private func settleInitialScroll(proxy: ScrollViewProxy) {
        // Fire multiple non-animated scrolls so we catch the moment the
        // LazyVStack finishes laying out the bottom cells and the photo
        // bubbles have rendered through their AsyncImage placeholder. A
        // single .onAppear scroll fires before the last cell exists and
        // strands the user near the top.
        isProgrammaticScrolling = true
        if let lastId = chatService.messages.last?.id {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
        let stops = [50, 200, 500, 900]
        for delayMS in stops {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(delayMS))
                if let lastId = chatService.messages.last?.id {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
                if delayMS == stops.last {
                    isProgrammaticScrolling = false
                }
            }
        }
    }

    private func loadOlderMessages(proxy: ScrollViewProxy) {
        guard !isLoadingOlder, chatService.hasMoreOlderMessages else { return }
        let anchorId = chatService.messages.first?.id
        isLoadingOlder = true
        Task {
            let added = await chatService.loadOlderMessages()
            isLoadingOlder = false
            // Pin the viewport to the previously-topmost message so the
            // newly prepended rows don't visually shove the user down.
            if added > 0, let anchorId {
                await MainActor.run {
                    proxy.scrollTo(anchorId, anchor: .top)
                }
            }
        }
    }

    private func toggleGlobalChatLock() {
        guard authService.isAdmin else { return }
        let next = !appConfig.chatSendLocked
        isTogglingChatLock = true
        Task {
            do {
                _ = try await appConfig.setChatSendLocked(next)
            } catch {
                errorMessage = "Couldn't update chat lock: \(error.localizedDescription)"
            }
            isTogglingChatLock = false
        }
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
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Couldn't load that photo. Try another one."
                return
            }

            // GIFs go through unmodified — JPEG compression would strip
            // the animation and we'd send a still frame. The preview's
            // UIImage shows the first frame (UIImage doesn't animate
            // directly, but the bubble will when sent).
            if isGifData(data) {
                let preview = UIImage(data: data)
                await MainActor.run {
                    selectedGifData = data
                    selectedPhotoData = nil
                    selectedPhotoPreview = preview
                }
                return
            }

            guard let optimizedData = UIImage(data: data)?.jpegData(compressionQuality: 0.82),
                  let preview = UIImage(data: optimizedData)
            else {
                errorMessage = "Couldn't load that photo. Try another one."
                return
            }

            await MainActor.run {
                selectedPhotoData = optimizedData
                selectedGifData = nil
                selectedPhotoPreview = preview
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sniff the first 6 bytes for the GIF magic header (`GIF87a` /
    /// `GIF89a`). Cheaper than asking PhotosPicker for UTType and avoids
    /// PHPicker quirks where some library items don't expose their UTI.
    private func isGifData(_ data: Data) -> Bool {
        guard data.count >= 6 else { return false }
        let header = data.prefix(6)
        return header == Data([0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
               header == Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
    }

    private func clearSelectedPhoto() {
        selectedPhotoItem = nil
        selectedPhotoPreview = nil
        selectedPhotoData = nil
        selectedGifData = nil
    }

    private func sendMessage() {
        guard canUseChatWrites else { return }
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let photoData = selectedPhotoData
        let gifData = selectedGifData
        guard !content.isEmpty || photoData != nil || gifData != nil else { return }

        Haptics.impact(.light)
        messageText = ""
        clearSelectedPhoto()
        typingResetTask?.cancel()
        chatService.setTyping(isTyping: false)

        Task {
            do {
                try await chatService.sendMessage(content: content, photoData: photoData, gifData: gifData)
            } catch AppError.unauthorized {
                errorMessage = "Sign in to send messages."
            } catch {
                errorMessage = error.localizedDescription
                await MainActor.run {
                    messageText = content
                    if let gifData {
                        selectedGifData = gifData
                        selectedPhotoPreview = UIImage(data: gifData)
                    } else if let photoData, let preview = UIImage(data: photoData) {
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
        Haptics.selection()
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
                        AppSpinner(color: .black, size: .md)
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

private struct NewMessagesPill: View {
    let count: Int
    let onTap: () -> Void

    private var label: String {
        count == 1 ? "1 new message" : "\(count) new messages"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down")
                    .font(.caption.bold())
                Text(label)
                    .font(.caption.bold())
            }
            .foregroundColor(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.appAccentOrange, in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
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
                            MemberRow(
                                user: user,
                                isOnline: chatService.presenceUserIds.contains(user.id.lowercased()),
                                isAdmin: isAdmin
                            ) {
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
    var isOnline: Bool = false
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
            .overlay(alignment: .bottomTrailing) {
                if isOnline {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.appSurface, lineWidth: 2))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(user.displayName ?? "Player")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    if isOnline {
                        Text("ONLINE")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(1)
                            .foregroundColor(.green)
                    }

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
