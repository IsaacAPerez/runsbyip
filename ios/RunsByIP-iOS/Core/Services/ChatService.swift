import Foundation
@preconcurrency import Supabase
import Realtime

@MainActor
final class ChatService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var reactionsByMessage: [String: [MessageReaction]] = [:]
    @Published var typingUsers: [ChatTypingUser] = []
    @Published private(set) var currentUserMuted: Bool = false
    @Published private(set) var hasMoreOlderMessages: Bool = false

    static let pageSize: Int = 50
    private var isLoadingOlder: Bool = false

    private let chatBucket = "chat-media"
    private let jsonDecoder = JSONDecoder()

    private var supabase: SupabaseClient { SupabaseService.shared.client }
    private var messageChannel: RealtimeChannelV2?
    private var reactionChannel: RealtimeChannelV2?
    private var typingChannel: RealtimeChannelV2?
    private var ownProfileChannel: RealtimeChannelV2?
    private var typingExpiryTask: Task<Void, Never>?
    private var typingExpirations: [String: Date] = [:]
    private var lastTypingEmittedState: Bool?
    private var lastTypingEmittedAt: Date?
    private var reactionRecords: [MessageReactionRecord] = []
    /// Populated from `messages_with_profiles`; realtime inserts only include `messages` columns (no avatar).
    private var avatarURLByUserId: [String: String] = [:]

    var currentUserId: String? {
        get async {
            (try? await currentUser().id.uuidString.lowercased())
        }
    }

    func fetchMessages() async throws {
        do {
            // Load the most recent page only. Older rows are paged in on
            // demand by loadOlderMessages() when the user scrolls to the top.
            // Without this cap the cold-start query scaled linearly with
            // the room's lifetime history.
            let latest: [ChatMessage] = try await supabase
                .from("messages_with_profiles")
                .select()
                .order("created_at", ascending: false)
                .limit(Self.pageSize)
                .execute()
                .value

            messages = latest.reversed()
            hasMoreOlderMessages = latest.count == Self.pageSize
            rebuildAvatarCache(from: messages)

            // Fetch reactions only for the messages we have on screen.
            // Older pages bring their own reactions when loaded.
            try await fetchReactions(forMessageIds: messages.map(\.id))
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    /// Pages in the next batch of older messages above the current head.
    /// Returns the number of new rows prepended; 0 means we hit the top.
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

            let prepend = older.reversed()
            let existingIds = Set(messages.map(\.id))
            let deduped = prepend.filter { !existingIds.contains($0.id) }
            messages.insert(contentsOf: deduped, at: 0)
            hasMoreOlderMessages = older.count == Self.pageSize
            rebuildAvatarCache(from: messages)

            if !deduped.isEmpty {
                try? await fetchReactions(forMessageIds: deduped.map(\.id), merge: true)
            }
            return deduped.count
        } catch {
            return 0
        }
    }

    /// Reconciles local state with the server after a possible realtime gap
    /// (e.g., the app was backgrounded or the channel briefly dropped).
    /// Fetches any messages newer than the last one we've seen and merges
    /// without disturbing existing rows. Reactions are re-pulled wholesale
    /// since they're cheap and INSERT/DELETE deltas are easy to miss.
    func refetchSinceLastSeen() async {
        do {
            let cutoff = messages.last?.createdAt
            let query = supabase.from("messages_with_profiles").select()
            let filtered = cutoff.map { query.gt("created_at", value: $0) } ?? query
            let newer: [ChatMessage] = try await filtered
                .order("created_at", ascending: true)
                .execute()
                .value

            var seenIds = Set(messages.map(\.id))
            for msg in newer where !seenIds.contains(msg.id) {
                messages.append(msg)
                seenIds.insert(msg.id)
            }
            rebuildAvatarCache(from: messages)

            try await fetchReactions(forMessageIds: messages.map(\.id))
        } catch {
            // Silent: foreground reconciliation is best-effort. Realtime
            // will continue to deliver new messages on the next insert.
        }
    }

    /// Avatar for UI: prefer row from view, then cache from last fetch, then current user's loaded profile (realtime rows omit `avatar_url`).
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

    func sendMessage(content: String, photoData: Data? = nil) async throws {
        let user = try await currentUser()
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Lowercased to match the storage RLS check `auth.uid()::text =
        // (storage.foldername(name))[1]` — auth.uid() emits a lowercase
        // UUID and Swift's uuidString is uppercase, so the upload was
        // rejected with a row-policy violation until normalized.
        let attachmentPath = try await uploadPhotoIfNeeded(photoData, userId: user.id.uuidString.lowercased())
        let messageType = attachmentPath == nil ? "text" : "photo"

        guard !trimmedContent.isEmpty || attachmentPath != nil else { return }

        struct NewMessage: Encodable {
            let userId: String
            let displayName: String
            let content: String
            let messageType: String
            let attachmentPath: String?

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case displayName = "display_name"
                case content
                case messageType = "message_type"
                case attachmentPath = "attachment_path"
            }
        }

        let displayName = user.userMetadata["display_name"]?.stringValue ?? "Anonymous"
        let userIdString = user.id.uuidString.lowercased()

        // Optimistic append: show the user's own message immediately so it
        // doesn't depend on the realtime echo (which can be delayed or, per
        // load testing, dropped ~5% of the time). After the server insert
        // returns, swap the temp id for the real one so the realtime echo's
        // dedup hits and we don't end up with two rows.
        let tempId = "local-\(UUID().uuidString)"
        let nowIso = ISO8601DateFormatter().string(from: Date())
        let optimistic = ChatMessage(
            id: tempId,
            userId: userIdString,
            displayName: displayName,
            content: trimmedContent,
            avatarUrl: avatarURLByUserId[userIdString],
            messageType: messageType,
            attachmentPath: attachmentPath,
            createdAt: nowIso
        )
        messages.append(optimistic)

        struct InsertedRow: Decodable {
            let id: String
        }

        do {
            let inserted: InsertedRow = try await supabase
                .from("messages")
                .insert(NewMessage(
                    userId: userIdString,
                    displayName: displayName,
                    content: trimmedContent,
                    messageType: messageType,
                    attachmentPath: attachmentPath
                ))
                .select("id")
                .single()
                .execute()
                .value

            if let idx = messages.firstIndex(where: { $0.id == tempId }) {
                let prev = messages[idx]
                messages[idx] = ChatMessage(
                    id: inserted.id,
                    userId: prev.userId,
                    displayName: prev.displayName,
                    content: prev.content,
                    avatarUrl: prev.avatarUrl,
                    messageType: prev.messageType,
                    attachmentPath: prev.attachmentPath,
                    createdAt: prev.createdAt
                )
            }
        } catch {
            // Roll back the optimistic row so the user sees the failure.
            messages.removeAll { $0.id == tempId }
            throw AppError.networkError(error.localizedDescription)
        }
    }

    func publicURL(for attachmentPath: String?) -> URL? {
        guard let attachmentPath, !attachmentPath.isEmpty else { return nil }
        return try? supabase.storage.from(chatBucket).getPublicURL(path: attachmentPath)
    }

    func toggleReaction(messageId: String, emoji: String) async throws {
        let user = try await currentUser()
        // Postgres canonicalizes UUIDs to lowercase; Swift's uuidString is
        // uppercase. Mismatch made the local "does this reaction exist?"
        // lookup miss, so a second tap re-INSERTed and the unique index
        // (message_id, user_id, emoji) bounced it as a duplicate.
        let userIdString = user.id.uuidString.lowercased()

        if let existing = reactionRecords.first(where: {
            $0.messageId == messageId && $0.userId == userIdString && $0.emoji == emoji
        }) {
            do {
                try await supabase
                    .from("message_reactions")
                    .delete()
                    .eq("id", value: existing.id)
                    .execute()
            } catch {
                throw AppError.networkError(error.localizedDescription)
            }
        } else {
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
                try await supabase
                    .from("message_reactions")
                    .insert(NewReaction(
                        messageId: messageId,
                        userId: userIdString,
                        emoji: emoji
                    ))
                    .execute()
            } catch {
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

    /// Sets up all three realtime channels and awaits each channel's initial
    /// subscription. Broadcasting (used for the typing indicator) only works
    /// once the channel is subscribed — firing-and-forgetting the subscribe
    /// lost early keystrokes. Subscribes run in parallel: each channel takes
    /// ~500ms-2s to confirm, so doing them concurrently cuts cold-start time
    /// roughly 3x.
    func subscribeToMessages() async {
        async let messages: () = subscribeToMessageInserts()
        async let reactions: () = subscribeToReactionChanges()
        async let typing: () = subscribeToTypingPresence()
        async let ownProfile: () = subscribeToOwnProfile()
        _ = await (messages, reactions, typing, ownProfile)
    }

    func setTyping(isTyping: Bool) {
        // Throttle: receiver's typing window is 4s, so re-emitting "typing"
        // every ~2s is enough to keep the indicator alive without flooding
        // the channel on every keystroke. Always emit immediately when the
        // state flips so transitions (idle→typing, typing→idle) feel instant.
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

    func unsubscribe() async {
        // Await teardown so a quick navigate-away + return doesn't race a new
        // subscribe against the previous channel still being torn down. That
        // race leaked channels and could double-deliver inserts/reactions.
        typingExpiryTask?.cancel()
        typingExpiryTask = nil
        typingUsers = []
        typingExpirations = [:]

        await messageChannel?.unsubscribe()
        await reactionChannel?.unsubscribe()
        await typingChannel?.unsubscribe()
        await ownProfileChannel?.unsubscribe()
        messageChannel = nil
        reactionChannel = nil
        typingChannel = nil
        ownProfileChannel = nil
    }

    // MARK: - Mute

    func toggleMute(userId: String, muted: Bool) async throws {
        try await supabase
            .from("profiles")
            .update(["is_muted": muted])
            .eq("id", value: userId)
            .execute()
    }

    /// Returns the user's mute state, or `nil` on error so callers can
    /// preserve the last-known value rather than flipping a muted user to
    /// un-muted on a transient fetch failure. (The DB/RLS still blocks the
    /// send either way, but the UX shouldn't lie.)
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

        // Filter to just our row so admin mute toggles on this user land
        // here immediately. profiles is in the realtime publication and
        // SELECT RLS is open, so the row is broadcast to the row owner.
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

    private func uploadPhotoIfNeeded(_ photoData: Data?, userId: String) async throws -> String? {
        guard let photoData else { return nil }

        let filePath = "\(userId)/\(UUID().uuidString).jpg"

        do {
            _ = try await supabase.storage
                .from(chatBucket)
                .upload(filePath, data: photoData, options: FileOptions(contentType: "image/jpeg", upsert: false))
            return filePath
        } catch {
            throw AppError.networkError("Photo upload failed: \(error.localizedDescription)")
        }
    }

    /// Loads reactions, optionally scoped to a set of message ids. When
    /// `merge` is true the new rows are unioned with the existing ones
    /// (used when paging in older messages); otherwise they replace.
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
            reactionRecords = rows
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
                    if lhs.count == rhs.count {
                        return lhs.emoji < rhs.emoji
                    }
                    return lhs.count > rhs.count
                }
        }
    }

    private func subscribeToMessageInserts() async {
        let channel = supabase.realtimeV2.channel("messages-room")
        messageChannel = channel

        let insertions = channel.postgresChange(InsertAction.self, table: "messages")

        Task { [weak self] in
            for await insert in insertions {
                guard let self else { return }
                guard let raw = try? insert.decodeRecord(as: ChatMessage.self, decoder: jsonDecoder),
                      !self.messages.contains(where: { $0.id == raw.id }) else { continue }

                // Append the raw row immediately so the bubble appears without delay.
                self.messages.append(raw)

                // Realtime INSERT events don't include avatar_url (it's on the
                // profiles table). Only re-fetch through messages_with_profiles
                // when we don't already have this user's avatar cached —
                // otherwise effectiveAvatarURL falls back to the cache and the
                // single-row hydrate query is wasted work. Saves an N×N query
                // storm during chat bursts at game-night scale.
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

    /// Realtime INSERT events on `messages` don't carry avatar_url (it was
    /// moved to the profiles table in migration 003). Re-query the single
    /// row through `messages_with_profiles` to get the joined profile data,
    /// then swap the enriched version into the messages array.
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
        } catch {
            // Keep the raw row — AvatarView falls back to initials.
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
                if !self.reactionRecords.contains(where: { $0.id == inserted.id }) {
                    self.reactionRecords.append(inserted)
                    self.rebuildReactions()
                }
            }
        }

        Task { [weak self] in
            for await delete in deletions {
                guard let self else { return }
                guard let deleted = try? delete.decodeOldRecord(as: MessageReactionRecord.self, decoder: jsonDecoder) else { continue }
                self.reactionRecords.removeAll { $0.id == deleted.id }
                self.rebuildReactions()
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
                // broadcastStream yields the full broadcast envelope; the
                // message we sent lives under the "payload" key.
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
