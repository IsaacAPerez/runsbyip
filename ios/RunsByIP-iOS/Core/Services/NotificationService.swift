import Foundation
import UserNotifications
@preconcurrency import Supabase

@MainActor
final class NotificationService: ObservableObject {
    private var supabase: SupabaseClient { SupabaseService.shared.client }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            return granted
        } catch {
            return false
        }
    }

    func authorizationGranted() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    func registerDeviceToken(_ token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        Task {
            await saveTokenToSupabase(tokenString)
        }
    }

    func saveTokenToSupabase(_ token: String) async {
        guard let user = try? await supabase.auth.session.user else { return }

        struct TokenRecord: Encodable {
            let userId: String
            let token: String
            let platform: String

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case token, platform
            }
        }

        do {
            try await supabase
                .from("device_tokens")
                .upsert(TokenRecord(
                    userId: user.id.uuidString,
                    token: token,
                    platform: "ios"
                ))
                .execute()
        } catch {
            print("Failed to save device token: \(error.localizedDescription)")
        }
    }
}
