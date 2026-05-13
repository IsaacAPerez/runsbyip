import Foundation
@preconcurrency import Supabase

// Reads ad-hoc app config from the app_settings table and keeps it in sync
// via realtime. RLS lets any authenticated user read; only admins can write.
@MainActor
final class AppConfigService: ObservableObject {
    @Published private(set) var iosDiscountCents: Int = 0
    @Published private(set) var chatSendLocked: Bool = false

    private var supabase: SupabaseClient { SupabaseService.shared.client }
    private var settingsChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?

    private struct SettingRow: Decodable {
        let key: String
        let value: AnyJSONValue
    }

    func refresh() async {
        do {
            let rows: [SettingRow] = try await supabase
                .from("app_settings")
                .select("key, value")
                .in("key", values: ["ios_discount_cents", "chat_send_locked"])
                .execute()
                .value

            for row in rows {
                apply(row)
            }
        } catch {
            // Leave the last-known values in place.
        }
    }

    private func apply(_ row: SettingRow) {
        switch row.key {
        case "ios_discount_cents":
            iosDiscountCents = max(row.value.intValue ?? 0, 0)
        case "chat_send_locked":
            chatSendLocked = row.value.boolValue ?? false
        default:
            break
        }
    }

    @discardableResult
    func setIOSDiscountCents(_ cents: Int) async throws -> Int {
        let clamped = max(cents, 0)
        struct Upsert: Encodable {
            let key: String
            let value: Int
            let updated_at: String
        }
        try await supabase
            .from("app_settings")
            .upsert(Upsert(
                key: "ios_discount_cents",
                value: clamped,
                updated_at: ISO8601DateFormatter().string(from: Date())
            ))
            .execute()
        iosDiscountCents = clamped
        return clamped
    }

    @discardableResult
    func setChatSendLocked(_ locked: Bool) async throws -> Bool {
        struct Upsert: Encodable {
            let key: String
            let value: Bool
            let updated_at: String
        }
        try await supabase
            .from("app_settings")
            .upsert(Upsert(
                key: "chat_send_locked",
                value: locked,
                updated_at: ISO8601DateFormatter().string(from: Date())
            ))
            .execute()
        chatSendLocked = locked
        return locked
    }

    // MARK: - Realtime

    func startRealtime() async {
        if settingsChannel != nil { return }

        let channel = supabase.realtimeV2.channel("app-settings-room")
        settingsChannel = channel

        let updates = channel.postgresChange(AnyAction.self, schema: "public", table: "app_settings")

        realtimeTask = Task { [weak self] in
            for await _ in updates {
                guard let self else { return }
                await self.refresh()
            }
        }

        do {
            try await channel.subscribeWithError()
        } catch {
            // Subscription failed — refresh() on scenePhase keeps us close enough.
        }
    }

    func stopRealtime() async {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let channel = settingsChannel {
            settingsChannel = nil
            await channel.unsubscribe()
        }
    }
}

// Minimal JSON value decoder so we can pull either a number, bool, or string
// from app_settings.value without committing to a per-key Decodable shape.
struct AnyJSONValue: Decodable {
    let intValue: Int?
    let boolValue: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            boolValue = b
            intValue = b ? 1 : 0
        } else if let i = try? container.decode(Int.self) {
            intValue = i
            boolValue = i != 0
        } else if let d = try? container.decode(Double.self) {
            intValue = Int(d)
            boolValue = d != 0
        } else if let s = try? container.decode(String.self) {
            intValue = Int(s)
            switch s.lowercased() {
            case "true": boolValue = true
            case "false": boolValue = false
            default: boolValue = nil
            }
        } else {
            intValue = nil
            boolValue = nil
        }
    }
}
