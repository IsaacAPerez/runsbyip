import Foundation

enum Tab: Hashable {
    case home
    case chat
    case profile
    case admin
}

@MainActor
final class NavigationCoordinator: ObservableObject {
    @Published var selectedTab: Tab = .home

    func handleNotificationTap(payload: [String: String]) {
        guard let type = payload["type"] else { return }

        switch type {
        case "new_message":
            selectedTab = .chat
        case "session_reminder", "spot_available":
            selectedTab = .home
        default:
            break
        }
    }

    func handleDeepLink(url: URL) {
        guard url.scheme == "runsbyip" else { return }

        switch url.host {
        case "chat":
            selectedTab = .chat
        case "session", "home":
            selectedTab = .home
        case "profile":
            selectedTab = .profile
        default:
            break
        }
    }
}
