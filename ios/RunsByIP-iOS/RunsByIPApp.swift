import SwiftUI
import StripePayments
import UserNotifications

@main
struct RunsByIPApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var authService = AuthService()
    @StateObject private var sessionService = SessionService()
    @StateObject private var chatService = ChatService()
    @StateObject private var paymentService = PaymentService()
    @StateObject private var notificationService = NotificationService()
    @StateObject private var appRouter = AppRouter()
    @StateObject private var navigationCoordinator = NavigationCoordinator()
    @StateObject private var powService = POWService()

    init() {
        STPAPIClient.shared.publishableKey = StripeConfig.publishableKey
        UIApplication.shared.registerForRemoteNotifications()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                .environmentObject(sessionService)
                .environmentObject(chatService)
                .environmentObject(paymentService)
                .environmentObject(notificationService)
                .environmentObject(appRouter)
                .environmentObject(navigationCoordinator)
                .environmentObject(powService)
                .onAppear {
                    appRouter.observe(authService: authService)
                    appDelegate.notificationService = notificationService
                    appDelegate.navigationCoordinator = navigationCoordinator
                    UNUserNotificationCenter.current().setBadgeCount(0)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    UNUserNotificationCenter.current().setBadgeCount(0)
                }
                .onOpenURL { url in
                    if StripeAPI.handleURLCallback(with: url) {
                        return
                    }

                    if url.scheme == "runsbyip" && url.host == "auth" {
                        Task {
                            try? await authService.handleOAuthCallback(url: url)
                        }
                    } else {
                        navigationCoordinator.handleDeepLink(url: url)
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var appRouter: AppRouter
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var notificationService: NotificationService
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    var body: some View {
        Group {
            switch appRouter.authState {
            case .loading:
                LoadingView()
            case .unauthenticated:
                LoginView()
            case .authenticated:
                if hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView {
                        hasCompletedOnboarding = true
                    }
                    .environmentObject(authService)
                    .environmentObject(notificationService)
                }
            }
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var notificationService: NotificationService
    @EnvironmentObject var authService: AuthService

    private var isAdmin: Bool {
        authService.currentProfile?.email == "iperez2435@gmail.com"
    }

    var body: some View {
        TabView(selection: $navigationCoordinator.selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "figure.basketball")
                }
                .tag(Tab.home)

            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(Tab.chat)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(Tab.profile)

            if isAdmin {
                AdminDashboardView()
                    .tabItem {
                        Label("Admin", systemImage: "gearshape.fill")
                    }
                    .tag(Tab.admin)
            }
        }
        .tint(Color.appAccentOrange)
        .preferredColorScheme(.dark)
        .task {
            await authService.loadProfile()
            // Request push notification permission on first authenticated launch
            let status = await notificationService.authorizationStatus()
            if status == .notDetermined {
                let granted = await notificationService.requestPermission()
                if granted {
                    await MainActor.run {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
        }
    }
}
