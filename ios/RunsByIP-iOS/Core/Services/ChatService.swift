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

    var currentUserId: String? {
        get async {
            (try? await currentUser().id.uuidString.lowercased())
        }
    }

    func fetchMessages() async throws {
        do {
            messages = try await supabase
                .from("messages")
                .select()
                .order("created_at", ascending: true)
                .execute()
                .value

            try await fetchReactions()
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
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
            let avatarUrl: String?
            let messageType: String
            let attachmentPath: String?

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case displayName = "display_name"
                case content
                case avatarUrl = "avatar_url"
                case messageType = "message_type"
                case attachmentPath = "attachment_path"
            }
        }

        let displayName = user.userMetadata["display_name"]?.stringValue ?? "Anonymous"
        let avatarUrl = user.userMetadata["avatar_url"]?.stringValue

        do {
            try await supabase
                .from("messages")
                .insert(NewMessage(
                    userId: user.id.uuidString.lowercased(),
                    displayName: displayName,
                    content: trimmedContent,
                    avatarUrl: avatarUrl,
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
        let currentDisplayName = user.userMetadata["display_name"]?.stringValue ?? "Anonymous"

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
                let displayName: String
                let emoji: String

                enum CodingKeys: String, CodingKey {
                    case messageId = "message_id"
                    case userId = "user_id"
                    case displayName = "display_name"
                    case emoji
                }
            }

            do {
                try await supabase
                    .from("message_reactions")
                    .insert(NewReaction(
                        messageId: messageId,
                        userId: user.id.uuidString,
                        displayName: currentDisplayName,
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

    func subscribeToMessages() {
        subscribeToMessageInserts()
        subscribeToReactionChanges()
        subscribeToTypingPresence()
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
                        userIds: Set(emojiRows.map(\.userId)),
                        displayNames: emojiRows.map(\.displayName)
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

    private func subscribeToMessageInserts() {
        messageChannel = supabase.realtimeV2.channel("messages-room")
        guard let messageChannel else { return }

        let insertions = messageChannel.postgresChange(InsertAction.self, table: "messages")

        Task { [weak self] in
            for await insert in insertions {
                guard let self else { return }
                if let message = try? insert.decodeRecord(as: ChatMessage.self, decoder: jsonDecoder),
                   !self.messages.contains(where: { $0.id == message.id }) {
                    self.messages.append(message)
                }
            }
        }

        Task {
            try? await messageChannel.subscribeWithError()
        }
    }

    private func subscribeToReactionChanges() {
        reactionChannel = supabase.realtimeV2.channel("message-reactions-room")
        guard let reactionChannel else { return }

        let insertions = reactionChannel.postgresChange(InsertAction.self, table: "message_reactions")
        let deletions = reactionChannel.postgresChange(DeleteAction.self, table: "message_reactions")

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

        Task {
            try? await reactionChannel.subscribeWithError()
        }
    }

    private func subscribeToTypingPresence() {
        typingChannel = supabase.realtimeV2.channel("chat-typing-room")
        guard let typingChannel else { return }

        let typingEvents = typingChannel.broadcastStream(event: "typing")

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

        Task {
            try? await typingChannel.subscribeWithError()
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
}
