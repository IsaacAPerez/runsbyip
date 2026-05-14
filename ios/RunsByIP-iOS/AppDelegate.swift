import UIKit
import UserNotifications
import OSLog

@MainActor
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // Set by RunsByIPApp on launch so the delegate can forward notification taps.
    weak var notificationService: NotificationService?
    weak var navigationCoordinator: NavigationCoordinator?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: - Remote Notification Registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        notificationService?.registerDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Logger(subsystem: "com.isaacperez.runsbyip", category: "push").error("Failed to register for remote notifications: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // For chat messages while the app is foregrounded, suppress the
        // system banner — ChatService delivers the message live via
        // realtime and we render our own in-app banner so the user
        // doesn't get a duplicate system notification on top of seeing
        // the bubble appear. Non-chat pushes (session reminders, etc.)
        // still get the standard treatment.
        let type = notification.request.content.userInfo["type"] as? String
        if type == "new_message" {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Extract only Sendable string values to cross isolation boundary safely
        var payload: [String: String] = [:]
        for (key, value) in response.notification.request.content.userInfo {
            if let k = key as? String, let v = value as? String {
                payload[k] = v
            }
        }
        Task { @MainActor in
            navigationCoordinator?.handleNotificationTap(payload: payload)
        }
        completionHandler()
    }
}
