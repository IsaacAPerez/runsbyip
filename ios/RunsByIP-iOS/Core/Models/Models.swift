import Foundation

// MARK: - GameSession

struct GameSession: Codable, Identifiable {
    let id: String
    let date: String
    let time: String
    let location: String
    let priceCents: Int
    let minPlayers: Int
    let maxPlayers: Int
    let status: String // "open", "confirmed", or "cancelled"
    let paymentsOpen: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, date, time, location, status
        case priceCents = "price_cents"
        case minPlayers = "min_players"
        case maxPlayers = "max_players"
        case paymentsOpen = "payments_open"
        case createdAt = "created_at"
    }
}

// MARK: - RSVP

struct RSVP: Codable, Identifiable {
    let id: String
    let sessionId: String
    let playerName: String
    let playerEmail: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case playerName = "player_name"
        case playerEmail = "player_email"
        case createdAt = "created_at"
    }
}

// MARK: - ChatMessage

struct ChatMessage: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let displayName: String
    let content: String
    let avatarUrl: String?
    let messageType: String?
    let attachmentPath: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, content
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case messageType = "message_type"
        case attachmentPath = "attachment_path"
        case createdAt = "created_at"
    }

    init(
        id: String,
        userId: String,
        displayName: String,
        content: String,
        avatarUrl: String? = nil,
        messageType: String? = nil,
        attachmentPath: String? = nil,
        createdAt: String
    ) {
        self.id = id
        self.userId = userId
        self.displayName = displayName
        self.content = content
        self.avatarUrl = avatarUrl
        self.messageType = messageType
        self.attachmentPath = attachmentPath
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        userId = try c.decode(String.self, forKey: .userId)
        // View can omit profile row; API may send null — keep decoding resilient.
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        messageType = try c.decodeIfPresent(String.self, forKey: .messageType)
        attachmentPath = try c.decodeIfPresent(String.self, forKey: .attachmentPath)
        createdAt = try c.decode(String.self, forKey: .createdAt)
    }

    var normalizedMessageType: String {
        messageType?.lowercased() ?? "text"
    }

    var isPhotoMessage: Bool {
        normalizedMessageType == "photo" && attachmentPath?.isEmpty == false
    }

    var hasText: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - MessageReaction

struct MessageReactionRecord: Codable, Identifiable, Equatable {
    let id: String
    let messageId: String
    let userId: String
    let emoji: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, emoji
        case messageId = "message_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

struct MessageReaction: Identifiable, Equatable {
    let messageId: String
    let emoji: String
    let count: Int
    let userIds: Set<String>

    var id: String { "\(messageId)-\(emoji)" }
}

// MARK: - Typing Presence

struct ChatTypingUser: Identifiable, Equatable {
    let id: String
    let displayName: String
}

// MARK: - UserProfile

struct UserProfile: Codable, Identifiable {
    let id: String
    let email: String?
    let displayName: String?
    let bio: String?
    let avatarUrl: String?
    let role: String
    let createdAt: String?
    let isMuted: Bool

    enum CodingKeys: String, CodingKey {
        case id, email, role, bio
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case isMuted = "is_muted"
    }

    init(id: String, email: String?, displayName: String?, bio: String?, avatarUrl: String?, role: String, createdAt: String?, isMuted: Bool = false) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.role = role
        self.createdAt = createdAt
        self.isMuted = isMuted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        role = try container.decode(String.self, forKey: .role)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
    }
}

// MARK: - DeviceToken

struct DeviceToken: Codable, Identifiable {
    let id: String
    let userId: String
    let token: String
    let platform: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, token, platform
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

// MARK: - GameSession Helpers

extension GameSession {
    var isCancelled: Bool { status == "cancelled" }
    var isOpen: Bool { status == "open" }

    func isFull(using confirmedCount: Int) -> Bool {
        confirmedCount >= maxPlayers
    }

    func spotsRemaining(using confirmedCount: Int) -> Int {
        max(maxPlayers - confirmedCount, 0)
    }

    var parsedDate: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }

    var sessionDateTime: Date? {
        // Normalize time string: "10:00PM" → "10:00 PM"
        let normalizedTime = time.replacingOccurrences(
            of: #"(\d)(AM|PM)"#,
            with: "$1 $2",
            options: .regularExpression
        )
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: "\(date) \(normalizedTime)")
    }

    var formattedDate: String {
        guard let parsed = parsedDate else { return date }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: parsed)
    }

    var formattedShortDate: String {
        guard let parsed = parsedDate else { return date }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: parsed)
    }

    var formattedWeekday: String {
        guard let parsed = parsedDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: parsed).uppercased()
    }

    var formattedMonthDay: String {
        guard let parsed = parsedDate else { return date }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: parsed).uppercased()
    }

    var priceDisplay: String {
        "$\(priceCents / 100)"
    }
}

// MARK: - POW Poll

struct POWPoll: Codable, Identifiable {
    let id: String
    let sessionId: String
    let opensAt: String
    let closesAt: String
    let status: String // "open", "closed", "archived"
    let winnerName: String?
    let winnerVotes: Int?

    enum CodingKeys: String, CodingKey {
        case id, status
        case sessionId = "session_id"
        case opensAt = "opens_at"
        case closesAt = "closes_at"
        case winnerName = "winner_name"
        case winnerVotes = "winner_votes"
    }

    var isOpen: Bool { status == "open" }
    var isClosed: Bool { status == "closed" }

    var closesAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: closesAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: closesAt)
    }

    var closesInText: String {
        guard let closesDate = closesAtDate else { return "" }
        let remaining = closesDate.timeIntervalSince(Date())
        guard remaining > 0 else { return "Voting ended" }
        let days = Int(remaining) / 86400
        let hours = (Int(remaining) % 86400) / 3600
        if days > 0 { return "Vote closes in \(days)d \(hours)h" }
        if hours > 0 { return "Vote closes in \(hours)h" }
        let minutes = (Int(remaining) % 3600) / 60
        return "Vote closes in \(minutes)m"
    }
}

// MARK: - POW Vote

struct POWVote: Codable, Identifiable {
    let id: String
    let pollId: String
    let voterName: String
    let voterEmail: String
    let votedForName: String

    enum CodingKeys: String, CodingKey {
        case id
        case pollId = "poll_id"
        case voterName = "voter_name"
        case voterEmail = "voter_email"
        case votedForName = "voted_for_name"
    }
}

// MARK: - POW Vote Tally

struct POWVoteTally: Codable, Identifiable {
    let votedForName: String
    let voteCount: Int
    let voters: String?

    var id: String { votedForName }

    var voterList: [String] {
        guard let voters = voters, !voters.isEmpty else { return [] }
        return voters.components(separatedBy: ", ")
    }

    enum CodingKeys: String, CodingKey {
        case votedForName = "voted_for_name"
        case voteCount = "vote_count"
        case voters
    }
}

// MARK: - Leaderboard

struct LeaderboardEntry: Identifiable {
    let playerName: String
    let gameCount: Int
    var id: String { playerName }
}

// MARK: - AppError

enum AppError: LocalizedError {
    case networkError(String)
    case authError(String)
    case paymentError(String)
    case notFound
    case unauthorized
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .networkError(let message): return "Network error: \(message)"
        case .authError(let message): return "Auth error: \(message)"
        case .paymentError(let message): return "Payment error: \(message)"
        case .notFound: return "Resource not found"
        case .unauthorized: return "Unauthorized"
        case .unknown(let error): return error.localizedDescription
        }
    }
}
