import Foundation
@preconcurrency import Supabase
import Realtime

/// Coordinates chat state across the app. Long-lived: created at launch,
/// retained through tab switches, torn down only on sign-out. Channels stay
/// alive while the user is anywhere in the app so typing presence + realtime
/// inserts work no matter which tab they're looking at.
@MainActor
final class ChatService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var reactionsByMessage: [String: [MessageReaction]] = [:]
    @Published var typingUsers: [ChatTypingUser] = []
    @Published private(set) var currentUserMuted: Bool = false
    @Published private(set) var hasMoreOlderMessages: Bool = false
    @Published private(set) var hasLoadedInitial: Bool = false
    @Published private(set) var deliveryStateById: [String: MessageDeliveryState] = [:]
    @Published private(set) var presenceUserIds: Set<String> = []

    static let pageSize: Int = 50
    /// Soft cap on in-memory rows. Older rows live on disk and are paged in
    /// when the user scrolls up. Trim happens after writes that push us over.
    static let inMemoryCap: Int = 300

    private let chatBucket = "chat-media"
    private let jsonDecoder = JSONDecoder()

    private var supabase: SupabaseClient { SupabaseService.shared.client }

    // MARK: - Realtime

    private var messageChannel: RealtimeChannelV2?
    private var reactionChannel: RealtimeChannelV2?
    private var typingChannel: RealtimeChannelV2?
    private var ownProfileChannel: RealtimeChannelV2?
    private var typingExpiryTask: Task<Void, Never>?
    private var typingExpirations: [String: Date] = [:]
    private var lastTypingEmittedState: Bool?
    private var lastTypingEmittedAt: Date?

    // MARK: - State

    private var reactionRecords: [MessageReactionRecord] = []
    private var avatarURLByUserId: [String: String] = [:]
    private var ownPendingMessageIds: Set<String> = []
    private var ownPendingReactionInsertIds: Set<String> = []
    private var ownPendingReactionDeleteIds: Set<String> = []
    private var isLoadingOlder: Bool = false
    private var isBootstrapped: Bool = false
    private var bootstrappedUserId: String?

    // MARK: - Backing services

    private var diskCache: ChatDiskCache?
    private var outboundQueue: ChatOutboundQueue?

    var currentUserId: String? {
        get async {
            (try? await currentUser().id.uuidString.lowercased())
        }
    }

    // MARK: - Bootstrap / shutdown

    /// Brings the service up for a signed-in user. Idempotent — calling
    /// repeatedly is a no-op while channels are healthy. Called from
    /// `MainTabView.task` so subscriptions span the user's whole session,
    /// not the chat tab's lifetime.
    func bootstrap() async {
        guard let uid = await currentUserId else { return }

        if isBootstrapped, bootstrappedUserId == uid {
            // Already up — reconcile to catch anything we missed and exit.
            await refetchSinceLastSeen()
            return
        }
        if isBootstrapped, bootstrappedUserId != uid {
            await shutdown()
        }

        let cache = ChatDiskCache(userScope: uid)
        diskCache = cache
        let client = supabase
        let queue = ChatOutboundQueue(
            userScope: uid,
            supabase: client,
            onSucceeded: { [weak self] tempId, serverId in
                await MainActor.run { [weak self] in
                    self?.outboundDidSucceed(tempId: tempId, serverId: serverId)
                }
            },
            onUpdated: { [weak self] item, isFinalFailure in
                await MainActor.run { [weak self] in
                    self?.outboundDidUpdate(item: item, isFinalFailure: isFinalFailure)
                }
            },
            onCancelled: { [weak self] tempId in
                await MainActor.run { [weak self] in
                    self?.outboundDidCancel(tempId: tempId)
                }
            }
        )
        outboundQueue = queue

        // Paint immediately from disk before the network fetch returns.
        let snap = await cache.load()
        if !snap.messages.isEmpty {
            messages = snap.messages
            reactionRecords = snap.reactions
            rebuildAvatarCache(from: messages)
            rebuildReactions()
            hasLoadedInitial = true
        }

        // Replay any pending sends that survived a relaunch.
        let pending = await queue.snapshot()
        for item in pending {
            let optimistic = ChatMessage(
                id: item.id,
                userId: item.userId,
                displayName: item.displayName,
                content: item.content,
                avatarUrl: avatarURLByUserId[item.userId.lowercased()],
                messageType: item.photoStoragePath == nil ? "text" : "photo",
                attachmentPath: item.photoStoragePath,
                createdAt: item.createdAt
            )
            if !messages.contains(where: { $0.id == item.id }) {
                messages.append(optimistic)
            }
            deliveryStateById[item.id] = item.attemptCount >= 5
                ? .failed(reason: item.lastError ?? "Failed to send")
                : .pending
        }
        await queue.scheduleDrain()

        // Realtime channels in parallel — each takes ~500ms-2s to confirm.
        async let realtime: () = subscribeAll()

        // Network reconcile in the background — UI is already painted from disk.
        Task { [weak self] in
            await self?.fetchMessages()
        }
        _ = await realtime

        isBootstrapped = true
        bootstrappedUserId = uid
    }

    /// Tears down realtime + clears in-memory state. Called on sign-out.
    func shutdown() async {
        typingExpiryTask?.cancel()
        typingExpiryTask = nil
        typingUsers = []
        typingExpirations = [:]
        presenceUserIds = []

        await messageChannel?.unsubscribe()
        await reactionChannel?.unsubscribe()
        await typingChannel?.unsubscribe()
        await ownProfileChannel?.unsubscribe()
        messageChannel = nil
        reactionChannel = nil
        typingChannel = nil
        ownProfileChannel = nil

        messages = []
        reactionRecords = []
        reactionsByMessage = [:]
        avatarURLByUserId = [:]
        deliveryStateById = [:]
        hasLoadedInitial = false
        hasMoreOlderMessages = false
        isBootstrapped = false
        bootstrappedUserId = nil

        outboundQueue = nil
        diskCache = nil
    }

    // MARK: - Fetch / reconcile

    func fetchMessages() async {
        do {
            let latest: [ChatMessage] = try await supabase
                .from("messages_with_profiles")
                .select()
                .order("created_at", ascending: false)
                .limit(Self.pageSize)
                .execute()
                .value

            let server = Array(latest.reversed())
            mergeRemoteMessages(server)
            // Only flip the "has more" gate based on the server result the
            // first time — if disk had older rows, we still have more to
            // page even when the server returned fewer than pageSize.
            hasMoreOlderMessages = latest.count == Self.pageSize || messages.count > server.count
            rebuildAvatarCache(from: messages)

            try await fetchReactions(forMessageIds: messages.map(\.id))
            hasLoadedInitial = true
            persistToDisk()
        } catch {
            // If disk had something, the UI is still painted — silent.
            if !hasLoadedInitial { hasLoadedInitial = true }
        }
    }

    @discardableResult
    func loadOlderMessages() async -> Int {
        guard !isLoadingOlder, hasMoreOlderMessages else { return 0 }
        guard let oldest = messages.first?.createdAt else { return 0 }

        isLoadingOlder = true
        defer { isLoadingOlder = false }

        do {
            let older: [ChatMessage] = try await supabase
                .from("messages_with_profiles")
                .select()
                .lt("created_at", value: oldest)
                .order("created_at", ascending: false)
                .limit(Self.pageSize)
                .execute()
                .value

            let prepend = Array(older.reversed())
            let existingIds = Set(messages.map(\.id))
            let deduped = prepend.filter { !existingIds.contains($0.id) }
            messages.insert(contentsOf: deduped, at: 0)
            hasMoreOlderMessages = older.count == Self.pageSize
            rebuildAvatarCache(from: messages)

            if !deduped.isEmpty {
                try? await fetchReactions(forMessageIds: deduped.map(\.id), merge: true)
            }
            persistToDisk()
            return deduped.count
        } catch {
            return 0
        }
    }

    /// Re-pull messages newer than our last-seen, plus refresh reactions for
    /// every message currently on screen — reaction insert/delete events can
    /// be missed during backgrounding and pure id-diff merge doesn't catch
    /// emoji churn.
    func refetchSinceLastSeen() async {
        do {
            let cutoff = messages.last?.createdAt
            let query = supabase.from("messages_with_profiles").select()
            let filtered = cutoff.map { query.gt("created_at", value: $0) } ?? query
            let newer: [ChatMessage] = try await filtered
                .order("created_at", ascending: true)
                .execute()
                .value

            mergeRemoteMessages(newer)
            rebuildAvatarCache(from: messages)

            try await fetchReactions(forMessageIds: messages.map(\.id))
            persistToDisk()
        } catch {
            // best-effort
        }
    }

    /// Union-merges server rows into the existing in-memory list. Server wins
    /// for overlapping ids (profile data on the row — display name, avatar —
    /// can change). Older disk rows stay in place; pending optimistic rows
    /// with local- ids stay because the server can't return them.
    private func mergeRemoteMessages(_ remote: [ChatMessage]) {
        var byId: [String: ChatMessage] = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        for m in remote { byId[m.id] = m }
        messages = byId.values.sorted { $0.createdAt < $1.createdAt }
        trimInMemoryIfNeeded()
    }

    private func trimInMemoryIfNeeded() {
        guard messages.count > Self.inMemoryCap else { return }
        let overflow = messages.count - Self.inMemoryCap
        messages.removeFirst(overflow)
        hasMoreOlderMessages = true
    }

    // MARK: - Avatars

    func effectiveAvatarURL(for message: ChatMessage, currentUserId: String?, currentUserProfileAvatar: String?) -> String? {
        if let u = message.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            return u
        }
        let uid = message.userId.lowercased()
        if let cached = avatarURLByUserId[uid] { return cached }
        if let cid = currentUserId?.lowercased(), cid == uid {
            let p = currentUserProfileAvatar?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !p.isEmpty { return p }
        }
        return nil
    }

    private func rebuildAvatarCache(from messages: [ChatMessage]) {
        var next: [String: String] = [:]
        for m in messages {
            let uid = m.userId.lowercased()
            if let u = m.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                next[uid] = u
            }
        }
        avatarURLByUserId = next
    }

    // MARK: - Send

    func sendMessage(content: String, photoData: Data? = nil) async throws {
        guard let queue = outboundQueue else { throw AppError.unauthorized }
        let user = try await currentUser()
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || photoData != nil else { return }

        let displayName = user.userMetadata["display_name"]?.stringValue ?? "Anonymous"
        let userIdString = user.id.uuidString.lowercased()

        let result: ChatOutboundQueue.EnqueueResult
        let messageType: String
        if let photoData {
            result = await queue.enqueuePhoto(
                userId: userIdString,
                displayName: displayName,
                content: trimmed,
                photoData: photoData
            )
            messageType = "photo"
        } else {
            result = await queue.enqueueText(
                userId: userIdString,
                displayName: displayName,
                content: trimmed
            )
            messageType = "text"
        }

        let optimistic = ChatMessage(
            id: result.id,
            userId: userIdString,
            displayName: displayName,
            content: trimmed,
            avatarUrl: avatarURLByUserId[userIdString],
            messageType: messageType,
            attachmentPath: nil,
            createdAt: result.createdAt
        )
        messages.append(optimistic)
        deliveryStateById[result.id] = .pending
        persistToDisk()
    }

    /// Queue callback: row landed on the server. Swap the temp row for one
    /// keyed by the server id so realtime echoes dedup against it.
    func outboundDidSucceed(tempId: String, serverId: String) {
        ownPendingMessageIds.insert(serverId)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.ownPendingMessageIds.remove(serverId)
        }

        // If the realtime echo beat us to the punch, the server row is
        // already present. Drop the temp row and let the echo stand.
        if let serverIdx = messages.firstIndex(where: { $0.id == serverId }) {
            // Mark sent.
            deliveryStateById[tempId] = nil
            messages.removeAll { $0.id == tempId }
            // Hydrate avatar if missing on the echo row.
            let echoRow = messages[serverIdx]
            if (echoRow.avatarUrl ?? "").isEmpty {
                Task { [weak self] in await self?.hydrateMessageFromView(id: serverId) }
            }
            persistToDisk()
            return
        }

        if let idx = messages.firstIndex(where: { $0.id == tempId }) {
            let prev = messages[idx]
            messages[idx] = ChatMessage(
                id: serverId,
                userId: prev.userId,
                displayName: prev.displayName,
                content: prev.content,
                avatarUrl: prev.avatarUrl,
                messageType: prev.messageType,
                attachmentPath: prev.attachmentPath,
                createdAt: prev.createdAt
            )
            deliveryStateById[tempId] = nil
            deliveryStateById[serverId] = .sent
        }
        persistToDisk()
    }

    /// Queue callback: send attempt failed. Either retrying or final failure.
    func outboundDidUpdate(item: ChatOutboundQueue.PendingItem, isFinalFailure: Bool) {
        if isFinalFailure {
            deliveryStateById[item.id] = .failed(reason: item.lastError ?? "Failed to send")
        } else {
            deliveryStateById[item.id] = .pending
        }
    }

    /// Queue callback: user (or app) cancelled a pending send.
    func outboundDidCancel(tempId: String) {
        messages.removeAll { $0.id == tempId }
        deliveryStateById[tempId] = nil
        persistToDisk()
    }

    func retryFailedMessage(id: String) {
        guard let queue = outboundQueue else { return }
        deliveryStateById[id] = .pending
        Task { await queue.retry(id: id) }
    }

    func cancelFailedMessage(id: String) {
        guard let queue = outboundQueue else { return }
        Task { await queue.cancel(id: id) }
    }

    func deliveryState(for messageId: String) -> MessageDeliveryState {
        deliveryStateById[messageId] ?? .sent
    }

    func publicURL(for attachmentPath: String?) -> URL? {
        guard let attachmentPath, !attachmentPath.isEmpty else { return nil }
        return try? supabase.storage.from(chatBucket).getPublicURL(path: attachmentPath)
    }

    // MARK: - Reactions

    func toggleReaction(messageId: String, emoji: String) async throws {
        let user = try await currentUser()
        let userIdString = user.id.uuidString.lowercased()

        if let existing = reactionRecords.first(where: {
            $0.messageId == messageId && $0.userId == userIdString && $0.emoji == emoji
        }) {
            // Optimistic remove.
            ownPendingReactionDeleteIds.insert(existing.id)
            reactionRecords.removeAll { $0.id == existing.id }
            rebuildReactions()

            do {
                try await supabase
                    .from("message_reactions")
                    .delete()
                    .eq("id", value: existing.id)
                    .execute()
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    self?.ownPendingReactionDeleteIds.remove(existing.id)
                }
            } catch {
                // Rollback.
                ownPendingReactionDeleteIds.remove(existing.id)
                if !reactionRecords.contains(where: { $0.id == existing.id }) {
                    reactionRecords.append(existing)
                    rebuildReactions()
                }
                throw AppError.networkError(error.localizedDescription)
            }
        } else {
            let tempId = "local-r-\(UUID().uuidString)"
            let now = ISO8601DateFormatter().string(from: Date())
            let optimistic = MessageReactionRecord(
                id: tempId,
                messageId: messageId,
                userId: userIdString,
                emoji: emoji,
                createdAt: now
            )
            reactionRecords.append(optimistic)
            rebuildReactions()

            struct NewReaction: Encodable {
                let messageId: String
                let userId: String
                let emoji: String

                enum CodingKeys: String, CodingKey {
                    case messageId = "message_id"
                    case userId = "user_id"
                    case emoji
                }
            }

            do {
                let inserted: MessageReactionRecord = try await supabase
                    .from("message_reactions")
                    .insert(NewReaction(
                        messageId: messageId,
                        userId: userIdString,
                        emoji: emoji
                    ))
                    .select()
                    .single()
                    .execute()
                    .value

                ownPendingReactionInsertIds.insert(inserted.id)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(10))
                    self?.ownPendingReactionInsertIds.remove(inserted.id)
                }
                if let idx = reactionRecords.firstIndex(where: { $0.id == tempId }) {
                    reactionRecords[idx] = inserted
                }
                rebuildReactions()
            } catch {
                reactionRecords.removeAll { $0.id == tempId }
                rebuildReactions()
                throw AppError.networkError(error.localizedDescription)
            }
        }
    }

    func isReactionSelected(messageId: String, emoji: String, currentUserId: String?) -> Bool {
        guard let currentUserId,
              let reaction = reactionsByMessage[messageId]?.first(where: { $0.emoji == emoji })
        else { return false }
        return reaction.userIds.contains(currentUserId)
    }

    private func fetchReactions(forMessageIds ids: [String]? = nil, merge: Bool = false) async throws {
        var query = supabase.from("message_reactions").select()
        if let ids, !ids.isEmpty {
            query = query.in("message_id", values: ids)
        }
        let rows: [MessageReactionRecord] = try await query
            .order("created_at", ascending: true)
            .execute()
            .value

        if merge {
            let existingIds = Set(reactionRecords.map(\.id))
            for row in rows where !existingIds.contains(row.id) {
                reactionRecords.append(row)
            }
        } else {
            // Preserve optimistic rows that the server hasn't echoed yet.
            let optimistic = reactionRecords.filter { $0.id.hasPrefix("local-r-") }
            reactionRecords = rows + optimistic
        }
        rebuildReactions()
    }

    private func rebuildReactions() {
        let groupedByMessage = Dictionary(grouping: reactionRecords, by: \.messageId)
        reactionsByMessage = groupedByMessage.mapValues { rows in
            Dictionary(grouping: rows, by: \.emoji)
                .map { emoji, emojiRows in
                    MessageReaction(
                        messageId: emojiRows.first?.messageId ?? "",
                        emoji: emoji,
                        count: emojiRows.count,
                        userIds: Set(emojiRows.map(\.userId))
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.count == rhs.count { return lhs.emoji < rhs.emoji }
                    return lhs.count > rhs.count
                }
        }
    }

    // MARK: - Typing (presence + broadcast belt-and-suspenders)

    func setTyping(isTyping: Bool) {
        // Throttle — receiver's typing window is 4s. Always emit immediately
        // on state flips so transitions feel instant.
        let now = Date()
        let stateChanged = lastTypingEmittedState != isTyping
        if !stateChanged,
           let last = lastTypingEmittedAt,
           now.timeIntervalSince(last) < 2.0 {
            return
        }
        lastTypingEmittedState = isTyping
        lastTypingEmittedAt = now

        Task {
            guard let user = try? await currentUser() else { return }
            let displayName = user.userMetadata["display_name"]?.stringValue ?? "Anonymous"
            let payload: [String: String] = [
                "user_id": user.id.uuidString,
                "display_name": displayName,
                "state": isTyping ? "typing" : "idle"
            ]
            try? await typingChannel?.broadcast(event: "typing", message: payload)
        }
    }

    // MARK: - Mute

    func toggleMute(userId: String, muted: Bool) async throws {
        try await supabase
            .from("profiles")
            .update(["is_muted": muted])
            .eq("id", value: userId)
            .execute()
    }

    func checkMuteStatus() async -> Bool? {
        guard let uid = await currentUserId else { return nil }
        do {
            let profile: UserProfile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: uid)
                .single()
                .execute()
                .value
            currentUserMuted = profile.isMuted
            return profile.isMuted
        } catch {
            return nil
        }
    }

    private func subscribeToOwnProfile() async {
        guard let uid = await currentUserId else { return }

        let channel = supabase.realtimeV2.channel("own-profile-\(uid)")
        ownProfileChannel = channel

        let updates = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "profiles",
            filter: "id=eq.\(uid)"
        )

        Task { [weak self] in
            for await update in updates {
                guard let self else { return }
                if let profile = try? update.decodeRecord(as: UserProfile.self, decoder: jsonDecoder) {
                    self.currentUserMuted = profile.isMuted
                }
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            print("[ChatService] own-profile channel subscribe failed: \(error)")
        }
    }

    func fetchAllUsers() async throws -> [UserProfile] {
        do {
            return try await supabase
                .from("profiles")
                .select()
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    func fetchProfile(userId: String) async throws -> UserProfile {
        do {
            return try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    private func currentUser() async throws -> Auth.User {
        do {
            return try await supabase.auth.session.user
        } catch {
            do {
                return try await supabase.auth.refreshSession().user
            } catch {
                throw AppError.unauthorized
            }
        }
    }

    // MARK: - Realtime subscriptions

    private func subscribeAll() async {
        async let m: () = subscribeToMessageInserts()
        async let r: () = subscribeToReactionChanges()
        async let t: () = subscribeToTypingPresence()
        async let p: () = subscribeToOwnProfile()
        _ = await (m, r, t, p)
    }

    private func subscribeToMessageInserts() async {
        let channel = supabase.realtimeV2.channel("messages-room")
        messageChannel = channel

        let insertions = channel.postgresChange(InsertAction.self, table: "messages")

        Task { [weak self] in
            for await insert in insertions {
                guard let self else { return }
                guard let raw = try? insert.decodeRecord(as: ChatMessage.self, decoder: jsonDecoder),
                      !self.messages.contains(where: { $0.id == raw.id }),
                      !self.ownPendingMessageIds.contains(raw.id) else { continue }

                self.messages.append(raw)
                self.persistToDisk()

                let cached = (avatarURLByUserId[raw.userId.lowercased()] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if cached.isEmpty {
                    Task { [weak self] in
                        await self?.hydrateMessageFromView(id: raw.id)
                    }
                }
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            print("[ChatService] messages channel subscribe failed: \(error)")
        }
    }

    private func hydrateMessageFromView(id: String) async {
        do {
            let enriched: ChatMessage = try await supabase
                .from("messages_with_profiles")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value

            if let idx = messages.firstIndex(where: { $0.id == id }) {
                messages[idx] = enriched
            }
            if let url = enriched.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
               !url.isEmpty {
                avatarURLByUserId[enriched.userId.lowercased()] = url
            }
            persistToDisk()
        } catch {
            // Falls back to initials in AvatarView.
        }
    }

    private func subscribeToReactionChanges() async {
        let channel = supabase.realtimeV2.channel("message-reactions-room")
        reactionChannel = channel

        let insertions = channel.postgresChange(InsertAction.self, table: "message_reactions")
        let deletions = channel.postgresChange(DeleteAction.self, table: "message_reactions")

        Task { [weak self] in
            for await insert in insertions {
                guard let self else { return }
                guard let inserted = try? insert.decodeRecord(as: MessageReactionRecord.self, decoder: jsonDecoder) else { continue }
                if self.ownPendingReactionInsertIds.contains(inserted.id) { continue }
                if !self.reactionRecords.contains(where: { $0.id == inserted.id }) {
                    self.reactionRecords.append(inserted)
                    self.rebuildReactions()
                    self.persistToDisk()
                }
            }
        }

        Task { [weak self] in
            for await delete in deletions {
                guard let self else { return }
                guard let deleted = try? delete.decodeOldRecord(as: MessageReactionRecord.self, decoder: jsonDecoder) else { continue }
                if self.ownPendingReactionDeleteIds.contains(deleted.id) { continue }
                self.reactionRecords.removeAll { $0.id == deleted.id }
                self.rebuildReactions()
                self.persistToDisk()
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            print("[ChatService] reactions channel subscribe failed: \(error)")
        }
    }

    private func subscribeToTypingPresence() async {
        let channel = supabase.realtimeV2.channel("chat-typing-room")
        typingChannel = channel

        let typingEvents = channel.broadcastStream(event: "typing")

        Task { [weak self] in
            for await event in typingEvents {
                guard let self else { return }
                guard let payload = event["payload"]?.objectValue,
                      let userId = payload["user_id"]?.stringValue,
                      let displayName = payload["display_name"]?.stringValue,
                      let state = payload["state"]?.stringValue
                else { continue }

                await self.handleTypingEvent(userId: userId, displayName: displayName, state: state)
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            print("[ChatService] typing channel subscribe failed: \(error)")
        }

        typingExpiryTask?.cancel()
        typingExpiryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.expireTypingUsersIfNeeded()
            }
        }
    }

    private func handleTypingEvent(userId: String, displayName: String, state: String) async {
        guard let currentUserId = try? await currentUser().id.uuidString, currentUserId != userId else { return }

        if state == "typing" {
            typingExpirations[userId] = Date().addingTimeInterval(4)
            if let index = typingUsers.firstIndex(where: { $0.id == userId }) {
                typingUsers[index] = ChatTypingUser(id: userId, displayName: displayName)
            } else {
                typingUsers.append(ChatTypingUser(id: userId, displayName: displayName))
            }
        } else {
            typingExpirations[userId] = nil
            typingUsers.removeAll { $0.id == userId }
        }
    }

    private func expireTypingUsersIfNeeded() async {
        let now = Date()
        let expiredIds = typingExpirations.compactMap { userId, expiry in
            expiry <= now ? userId : nil
        }

        guard !expiredIds.isEmpty else { return }
        expiredIds.forEach { typingExpirations[$0] = nil }
        typingUsers.removeAll { expiredIds.contains($0.id) }
    }

    // MARK: - Disk persistence

    private func persistToDisk() {
        guard let diskCache else { return }
        let sentMessages = messages.filter { (deliveryStateById[$0.id] ?? .sent) == .sent }
        let snapshot = sentMessages
        let reactions = reactionRecords.filter { !$0.id.hasPrefix("local-r-") }
        Task { await diskCache.save(messages: snapshot, reactions: reactions) }
    }

    // MARK: - Gallery

    private let galleryBucket = "gallery"

    func fetchGalleryPhotos() async throws -> [URL] {
        let files = try await supabase.storage.from(galleryBucket).list()
        return files.compactMap { file in
            guard !file.name.hasPrefix(".") else { return nil }
            return try? supabase.storage.from(galleryBucket).getPublicURL(path: file.name)
        }
    }

    func uploadGalleryPhoto(data: Data) async throws {
        let filename = "\(UUID().uuidString.lowercased()).jpg"
        try await supabase.storage.from(galleryBucket).upload(filename, data: data, options: .init(contentType: "image/jpeg"))
    }

    func deleteGalleryPhoto(path: String) async throws {
        try await supabase.storage.from(galleryBucket).remove(paths: [path])
    }
}
