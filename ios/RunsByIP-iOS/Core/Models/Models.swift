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
    let status: String // "open", "completed", or "cancelled"
    let paymentsOpen: Bool
    let createdAt: String
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case id, date, time, location, status
        case priceCents = "price_cents"
        case minPlayers = "min_players"
        case maxPlayers = "max_players"
        case paymentsOpen = "payments_open"
        case createdAt = "created_at"
        case latitude, longitude
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try c.decode(String.self, forKey: .date)
        time = try c.decode(String.self, forKey: .time)
        location = try c.decode(String.self, forKey: .location)
        priceCents = try c.decode(Int.self, forKey: .priceCents)
        minPlayers = try c.decode(Int.self, forKey: .minPlayers)
        maxPlayers = try c.decode(Int.self, forKey: .maxPlayers)
        status = try c.decode(String.self, forKey: .status)
        paymentsOpen = try c.decode(Bool.self, forKey: .paymentsOpen)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        // Tolerant decode for the optional coords — migration 029 added
        // them, and rows decoded from views that don't surface those
        // columns simply default to nil.
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
    }

    // Memberwise init for previews / synthetic construction sites.
    // Swift only synthesizes this automatically when no explicit init
    // exists; once we added init(from:), we need to provide this too.
    init(
        id: String,
        date: String,
        time: String,
        location: String,
        priceCents: Int,
        minPlayers: Int,
        maxPlayers: Int,
        status: String,
        paymentsOpen: Bool,
        createdAt: String,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.time = time
        self.location = location
        self.priceCents = priceCents
        self.minPlayers = minPlayers
        self.maxPlayers = maxPlayers
        self.status = status
        self.paymentsOpen = paymentsOpen
        self.createdAt = createdAt
        self.latitude = latitude
        self.longitude = longitude
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

    var isGifMessage: Bool {
        normalizedMessageType == "gif" && attachmentPath?.isEmpty == false
    }

    var isVisualMessage: Bool { isPhotoMessage || isGifMessage }

    var hasText: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - MessageDeliveryState

enum MessageDeliveryState: Equatable {
    case sent
    case pending
    case failed(reason: String)
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
    /// Legacy rows may still have `status == "confirmed"` until the DB migration runs; treat as open.
    var effectiveStatus: String { status == "confirmed" ? "open" : status }

    var isCancelled: Bool { effectiveStatus == "cancelled" }
    var isCompleted: Bool { effectiveStatus == "completed" }
    var isOpen: Bool { effectiveStatus == "open" }

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

    /// "TONIGHT" / "TOMORROW" / "FRIDAY" / "MAR 14" depending on how
    /// far away the session is. Used by the home header for a more
    /// alive feel than just the raw date.
    var conversationalDayLabel: String {
        guard let parsed = parsedDate else { return formattedShortDate }
        let cal = Calendar.current
        let now = Date()
        let daysAway = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: parsed)).day ?? 0
        switch daysAway {
        case 0: return "TONIGHT"
        case 1: return "TOMORROW"
        case 2...6:
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            return f.string(from: parsed).uppercased()
        default:
            return formattedMonthDay
        }
    }

    var priceDisplay: String {
        priceCents.currencyDisplay
    }

    var refundDisplayAfterRunsFee: String {
        max(priceCents - 100, 0).currencyDisplay
    }

    // Apply the admin-configured iOS discount. Stripe rejects PaymentIntents
    // under 50 cents, so we mirror the edge function's floor — the displayed
    // price never drops below it.
    func effectivePriceCents(iosDiscountCents: Int) -> Int {
        guard iosDiscountCents > 0 else { return priceCents }
        let capped = min(iosDiscountCents, max(priceCents - 50, 0))
        return priceCents - capped
    }

    func effectivePriceDisplay(iosDiscountCents: Int) -> String {
        effectivePriceCents(iosDiscountCents: iosDiscountCents).currencyDisplay
    }
}

extension Int {
    var currencyDisplay: String {
        let amount = Decimal(self) / Decimal(100)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = self.isMultiple(of: 100) ? 0 : 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "USD \(amount)"
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

struct LeaderboardEntry: Identifiable, Equatable {
    let playerName: String
    let gameCount: Int
    var id: String { playerName }
}

// MARK: - Run vibe (post-game rating)

enum RunVibe: String, Codable, CaseIterable, Identifiable {
    case fire
    case mid
    case dud

    var id: String { rawValue }
    var emoji: String {
        switch self {
        case .fire: return "🔥"
        case .mid: return "😐"
        case .dud: return "💀"
        }
    }
    var label: String {
        switch self {
        case .fire: return "Fire"
        case .mid: return "Mid"
        case .dud: return "Dud"
        }
    }
}

struct RunVibeTally: Codable, Identifiable, Equatable {
    let vibe: String
    let votes: Int
    var id: String { vibe }
}

// MARK: - Session participant (RSVP joined to profile)

struct RSVPParticipant: Codable, Identifiable, Equatable {
    let userId: String?
    let name: String
    let email: String
    let avatarUrl: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case email
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
    }

    var id: String { email.lowercased() }
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
