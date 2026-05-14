import Foundation
@preconcurrency import Supabase

/// Persistent outbound queue for chat messages. Each text send is durable
/// across app restarts; photo sends stay in-memory since their binary payload
/// is expensive to persist and re-uploading a photo on cold launch is rarely
/// what the user wants. Failed sends surface in the UI with a retry tap.
actor ChatOutboundQueue {
    struct PendingItem: Codable, Identifiable, Equatable {
        let id: String
        let userId: String
        let displayName: String
        let content: String
        let createdAt: String
        var photoStoragePath: String?
        /// "text", "photo", or "gif". Drives the storage upload's MIME +
        /// extension and the `messages.message_type` value.
        var messageType: String
        var attemptCount: Int
        var lastError: String?

        var isPhoto: Bool { photoStoragePath != nil && messageType == "photo" }
        var isGif: Bool { photoStoragePath != nil && messageType == "gif" }

        init(
            id: String,
            userId: String,
            displayName: String,
            content: String,
            createdAt: String,
            photoStoragePath: String?,
            messageType: String,
            attemptCount: Int,
            lastError: String?
        ) {
            self.id = id
            self.userId = userId
            self.displayName = displayName
            self.content = content
            self.createdAt = createdAt
            self.photoStoragePath = photoStoragePath
            self.messageType = messageType
            self.attemptCount = attemptCount
            self.lastError = lastError
        }

        // Decode with a fallback so queue files written before this field
        // existed still load — old text-only sends stay text-only, old
        // photo sends keep being treated as photos.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            userId = try c.decode(String.self, forKey: .userId)
            displayName = try c.decode(String.self, forKey: .displayName)
            content = try c.decode(String.self, forKey: .content)
            createdAt = try c.decode(String.self, forKey: .createdAt)
            photoStoragePath = try c.decodeIfPresent(String.self, forKey: .photoStoragePath)
            attemptCount = try c.decode(Int.self, forKey: .attemptCount)
            lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
            messageType = try c.decodeIfPresent(String.self, forKey: .messageType)
                ?? (photoStoragePath != nil ? "photo" : "text")
        }
    }

    struct EnqueueResult {
        let id: String
        let createdAt: String
    }

    typealias OnSucceeded = @Sendable (_ tempId: String, _ serverId: String) async -> Void
    typealias OnUpdated = @Sendable (_ item: PendingItem, _ isFinalFailure: Bool) async -> Void
    typealias OnCancelled = @Sendable (_ tempId: String) async -> Void

    // MARK: - Persistence

    private let storageURL: URL
    private var persisted: [PendingItem] = []
    /// Photo payloads live in memory only — see file-level note.
    private var pendingPhotoData: [String: Data] = [:]

    // MARK: - Dependencies

    private let supabase: SupabaseClient
    private let onSucceeded: OnSucceeded
    private let onUpdated: OnUpdated
    private let onCancelled: OnCancelled

    // MARK: - Worker

    private var drainTask: Task<Void, Never>?
    private var isDraining: Bool = false

    private static let maxAttempts: Int = 5
    private static let backoffSeconds: [UInt64] = [1, 3, 10, 30]

    init(
        userScope: String,
        supabase: SupabaseClient,
        onSucceeded: @escaping OnSucceeded,
        onUpdated: @escaping OnUpdated,
        onCancelled: @escaping OnCancelled
    ) {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("chat-outbound", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = dir.appendingPathComponent("\(userScope).json")
        self.persisted = Self.loadFromDisk(url: storageURL)
        self.supabase = supabase
        self.onSucceeded = onSucceeded
        self.onUpdated = onUpdated
        self.onCancelled = onCancelled
    }

    func snapshot() -> [PendingItem] { persisted }

    // MARK: - Enqueue

    func enqueueText(userId: String, displayName: String, content: String) -> EnqueueResult {
        let id = "local-\(UUID().uuidString)"
        let createdAt = ISO8601DateFormatter().string(from: Date())
        let item = PendingItem(
            id: id,
            userId: userId,
            displayName: displayName,
            content: content,
            createdAt: createdAt,
            photoStoragePath: nil,
            messageType: "text",
            attemptCount: 0,
            lastError: nil
        )
        persisted.append(item)
        saveToDisk()
        scheduleDrain()
        return EnqueueResult(id: id, createdAt: createdAt)
    }

    func enqueuePhoto(userId: String, displayName: String, content: String, photoData: Data) -> EnqueueResult {
        return enqueueBinary(
            userId: userId,
            displayName: displayName,
            content: content,
            data: photoData,
            messageType: "photo"
        )
    }

    func enqueueGif(userId: String, displayName: String, content: String, gifData: Data) -> EnqueueResult {
        return enqueueBinary(
            userId: userId,
            displayName: displayName,
            content: content,
            data: gifData,
            messageType: "gif"
        )
    }

    private func enqueueBinary(userId: String, displayName: String, content: String, data: Data, messageType: String) -> EnqueueResult {
        let id = "local-\(UUID().uuidString)"
        let createdAt = ISO8601DateFormatter().string(from: Date())
        pendingPhotoData[id] = data
        let item = PendingItem(
            id: id,
            userId: userId,
            displayName: displayName,
            content: content,
            createdAt: createdAt,
            photoStoragePath: nil,
            messageType: messageType,
            attemptCount: 0,
            lastError: nil
        )
        persisted.append(item)
        saveToDisk()
        scheduleDrain()
        return EnqueueResult(id: id, createdAt: createdAt)
    }

    func retry(id: String) {
        guard let idx = persisted.firstIndex(where: { $0.id == id }) else { return }
        persisted[idx].attemptCount = 0
        persisted[idx].lastError = nil
        saveToDisk()
        scheduleDrain()
    }

    func cancel(id: String) async {
        persisted.removeAll { $0.id == id }
        pendingPhotoData[id] = nil
        saveToDisk()
        await onCancelled(id)
    }

    // MARK: - Drain

    func scheduleDrain() {
        guard !isDraining else { return }
        drainTask?.cancel()
        drainTask = Task { [weak self] in
            await self?.drainLoop()
        }
    }

    private func drainLoop() async {
        isDraining = true
        defer { isDraining = false }

        while let nextId = persisted.first(where: { $0.attemptCount < Self.maxAttempts })?.id {
            guard !Task.isCancelled else { return }
            guard let idx = persisted.firstIndex(where: { $0.id == nextId }) else { break }
            var item = persisted[idx]

            do {
                let serverId = try await performSend(item: &item)
                persisted.removeAll { $0.id == item.id }
                pendingPhotoData[item.id] = nil
                saveToDisk()
                await onSucceeded(item.id, serverId)
            } catch {
                item.attemptCount += 1
                item.lastError = error.localizedDescription
                persisted[idx] = item
                saveToDisk()

                if item.attemptCount >= Self.maxAttempts {
                    await onUpdated(item, true)
                    continue
                }
                await onUpdated(item, false)
                let waitIdx = min(Int(item.attemptCount) - 1, Self.backoffSeconds.count - 1)
                try? await Task.sleep(for: .seconds(Double(Self.backoffSeconds[max(waitIdx, 0)])))
            }
        }
    }

    // MARK: - Network

    private struct NewMessage: Encodable {
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

    private struct InsertedRow: Decodable { let id: String }

    private func performSend(item: inout PendingItem) async throws -> String {
        if pendingPhotoData[item.id] != nil, item.photoStoragePath == nil {
            let path = try await uploadBinary(for: item)
            item.photoStoragePath = path
            if let idx = persisted.firstIndex(where: { $0.id == item.id }) {
                persisted[idx].photoStoragePath = path
                saveToDisk()
            }
        }

        let inserted: InsertedRow = try await supabase
            .from("messages")
            .insert(NewMessage(
                userId: item.userId,
                displayName: item.displayName,
                content: item.content,
                messageType: item.messageType,
                attachmentPath: item.photoStoragePath
            ))
            .select("id")
            .single()
            .execute()
            .value
        return inserted.id
    }

    private func uploadBinary(for item: PendingItem) async throws -> String {
        guard let data = pendingPhotoData[item.id] else {
            throw AppError.networkError("Attachment data missing for pending send")
        }
        let (ext, mime) = mimeAndExtension(for: item.messageType)
        let path = "\(item.userId)/\(UUID().uuidString).\(ext)"
        _ = try await supabase.storage
            .from("chat-media")
            .upload(path, data: data, options: FileOptions(contentType: mime, upsert: false))
        return path
    }

    private func mimeAndExtension(for messageType: String) -> (ext: String, mime: String) {
        switch messageType {
        case "gif": return ("gif", "image/gif")
        default: return ("jpg", "image/jpeg")
        }
    }

    // MARK: - Disk

    private static func loadFromDisk(url: URL) -> [PendingItem] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([PendingItem].self, from: data) else {
            return []
        }
        return items
    }

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }
}
