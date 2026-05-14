import Foundation

/// On-disk JSON cache for the most recent chat state. Lets cold-launches
/// paint immediately from disk while the network reconcile catches up.
/// We cap at the last 500 messages — older history is paged from the server.
actor ChatDiskCache {
    struct Snapshot: Codable {
        var messages: [ChatMessage]
        var reactions: [MessageReactionRecord]
        /// Newest createdAt we've persisted; used by reconcile to know what to fetch.
        var lastSeenCreatedAt: String?
    }

    static let messageRetention: Int = 500

    private let fileURL: URL
    private var inMemory: Snapshot?
    private var saveDebounceTask: Task<Void, Never>?

    init(userScope: String) {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("chat-cache", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // Per-user file so switching accounts doesn't leak chat history.
        self.fileURL = dir.appendingPathComponent("\(userScope).json")
    }

    func load() -> Snapshot {
        if let inMemory { return inMemory }
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            let empty = Snapshot(messages: [], reactions: [], lastSeenCreatedAt: nil)
            inMemory = empty
            return empty
        }
        inMemory = snap
        return snap
    }

    func save(messages: [ChatMessage], reactions: [MessageReactionRecord]) {
        let capped = Array(messages.suffix(Self.messageRetention))
        let keepIds = Set(capped.map(\.id))
        let trimmedReactions = reactions.filter { keepIds.contains($0.messageId) }
        let snap = Snapshot(
            messages: capped,
            reactions: trimmedReactions,
            lastSeenCreatedAt: capped.last?.createdAt
        )
        inMemory = snap
        scheduleWrite(snap)
    }

    func clear() {
        inMemory = Snapshot(messages: [], reactions: [], lastSeenCreatedAt: nil)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func scheduleWrite(_ snap: Snapshot) {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [fileURL] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            guard let data = try? JSONEncoder().encode(snap) else { return }
            try? data.write(to: fileURL, options: [.atomic])
        }
    }
}
