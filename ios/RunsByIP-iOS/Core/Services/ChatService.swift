import Foundation
@preconcurrency import Supabase
import Realtime

@MainActor
final class ChatService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var reactionsByMessage: [String: [MessageReaction]] = [:]
    @Published var typingUsers: [ChatTypingUser] = []

    private let chatBucket = "chat-media"
    private let jsonDecoder = JSONDecoder()

    private var supabase: SupabaseClient { SupabaseService.shared.client }
    private var messageChannel: RealtimeChannelV2?
    private var reactionChannel: RealtimeChannelV2?
    private var typingChannel: RealtimeChannelV2?
    private var typingExpiryTask: Task<Void, Never>?
    private var typingExpirations: [String: Date] = [:]
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
            messages = try await supabase
                .from("messages_with_profiles")
                .select()
                .order("created_at", ascending: true)
                .execute()
                .value
            rebuildAvatarCache(from: messages)

            try await fetchReactions()
        } catch {
            throw AppError.networkError(error.localizedDescription)
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
        let attachmentPath = try await uploadPhotoIfNeeded(photoData, userId: user.id.uuidString)
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

        do {
            try await supabase
                .from("messages")
                .insert(NewMessage(
                    userId: user.id.uuidString.lowercased(),
                    displayName: displayName,
                    content: trimmedContent,
                    messageType: messageType,
                    attachmentPath: attachmentPath
                ))
                .execute()
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    func publicURL(for attachmentPath: String?) -> URL? {
        guard let attachmentPath, !attachmentPath.isEmpty else { return nil }
        return try? supabase.storage.from(chatBucket).getPublicURL(path: attachmentPath)
    }

    func toggleReaction(messageId: String, emoji: String) async throws {
        let user = try await currentUser()

        if let existing = reactionRecords.first(where: {
            $0.messageId == messageId && $0.userId == user.id.uuidString && $0.emoji == emoji
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
                        userId: user.id.uuidString,
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
    /// lost early keystrokes.
    func subscribeToMessages() async {
        await subscribeToMessageInserts()
        await subscribeToReactionChanges()
        await subscribeToTypingPresence()
    }

    func setTyping(isTyping: Bool) {
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

    func unsubscribe() {
        typingExpiryTask?.cancel()
        typingExpiryTask = nil
        typingUsers = []
        typingExpirations = [:]

        Task {
            await messageChannel?.unsubscribe()
            await reactionChannel?.unsubscribe()
            await typingChannel?.unsubscribe()
            messageChannel = nil
            reactionChannel = nil
            typingChannel = nil
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

    func checkMuteStatus() async -> Bool {
        guard let uid = await currentUserId else { return false }
        do {
            let profile: UserProfile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: uid)
                .single()
                .execute()
                .value
            return profile.isMuted
        } catch {
            return false
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

    private func fetchReactions() async throws {
        reactionRecords = try await supabase
            .from("message_reactions")
            .select()
            .order("created_at", ascending: true)
            .execute()
            .value

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

                // Then re-fetch through `messages_with_profiles` to pick up
                // the sender's current avatar_url + display_name — realtime
                // only ships `messages` columns, and avatar_url lives on the
                // profiles table.
                Task { [weak self] in
                    await self?.hydrateMessageFromView(id: raw.id)
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
            for await payload in typingEvents {
                guard let self else { return }
                guard let userId = payload["user_id"]?.stringValue,
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
