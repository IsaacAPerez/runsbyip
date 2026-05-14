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
    @StateObject private var appConfig = AppConfigService()

    init() {
        STPAPIClient.shared.publishableKey = StripeConfig.publishableKey
        UIApplication.shared.registerForRemoteNotifications()
        configureAppearance()
    }

    private func configureAppearance() {
        let condensed = UIFont.systemFont(ofSize: 17, weight: .regular, width: .condensed)

        // Navigation bar
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(Color(hex: "000000"))
        navAppearance.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold, width: .condensed),
            .foregroundColor: UIColor.white
        ]
        navAppearance.largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 34, weight: .bold, width: .condensed),
            .foregroundColor: UIColor.white
        ]
        UINavigationBar.appearance().prefersLargeTitles = false
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance

        // Tab bar
        let tabFont = UIFont.systemFont(ofSize: 10, weight: .medium, width: .condensed)
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(Color(hex: "000000"))

        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.titleTextAttributes = [.font: tabFont, .foregroundColor: UIColor(Color(hex: "666666"))]
        itemAppearance.selected.titleTextAttributes = [.font: tabFont, .foregroundColor: UIColor.white]
        tabAppearance.stackedLayoutAppearance = itemAppearance
        tabAppearance.inlineLayoutAppearance = itemAppearance
        tabAppearance.compactInlineLayoutAppearance = itemAppearance

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .fontWidth(.condensed)
                .environmentObject(authService)
                .environmentObject(sessionService)
                .environmentObject(chatService)
                .environmentObject(paymentService)
                .environmentObject(notificationService)
                .environmentObject(appRouter)
                .environmentObject(navigationCoordinator)
                .environmentObject(powService)
                .environmentObject(appConfig)
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
                SplashView()
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
    @EnvironmentObject var appConfig: AppConfigService
    @EnvironmentObject var chatService: ChatService
    @EnvironmentObject var powService: POWService
    @Environment(\.scenePhase) private var scenePhase

    private var isAdmin: Bool {
        authService.isAdmin
    }

    /// Wrap the selection binding so we can detect *every* selection of
    /// the chat tab — including re-taps when it's already selected.
    /// SwiftUI's onChange doesn't fire for re-selection (the value
    /// doesn't change), but the binding's setter still runs.
    private var tabSelectionBinding: Binding<Tab> {
        Binding(
            get: { navigationCoordinator.selectedTab },
            set: { newTab in
                if newTab == .chat {
                    navigationCoordinator.requestScrollChatToBottom()
                }
                navigationCoordinator.selectedTab = newTab
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelectionBinding) {
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
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                // POW winner takes priority — biggest moment, always shows.
                if let win = powService.winnerAnnouncement {
                    POWWinnerBanner(
                        winnerName: win.winnerName ?? "",
                        voteCount: win.winnerVotes ?? 0,
                        isCurrentUser: (authService.currentProfile?.displayName ?? "") == (win.winnerName ?? ""),
                        onDismiss: { powService.winnerAnnouncement = nil }
                    )
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: win.id)
                }

                // In-app message banner — only when the user isn't already on
                // chat. Auto-dismisses after a short window; tap jumps to chat.
                if let incoming = chatService.incomingMessageNotification,
                   navigationCoordinator.selectedTab != .chat {
                    InAppMessageBanner(
                        message: incoming,
                        avatarUrl: chatService.effectiveAvatarURL(
                            for: incoming,
                            currentUserId: nil,
                            currentUserProfileAvatar: nil
                        ),
                        onTap: {
                            navigationCoordinator.selectedTab = .chat
                            chatService.incomingMessageNotification = nil
                        },
                        onDismiss: {
                            chatService.incomingMessageNotification = nil
                        }
                    )
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: incoming.id)
                }
            }
            .padding(.top, 4)
        }
        .onChange(of: powService.winnerAnnouncement?.id) { _, newId in
            guard newId != nil else { return }
            // Auto-dismiss the celebration after 8 seconds — long enough
            // to read + sparkle, short enough not to overstay welcome.
            let isMe = (authService.currentProfile?.displayName ?? "")
                == (powService.winnerAnnouncement?.winnerName ?? "")
            if isMe { Haptics.success() }
            Task { @MainActor in
                let dismissedId = newId
                try? await Task.sleep(for: .seconds(8))
                if powService.winnerAnnouncement?.id == dismissedId {
                    powService.winnerAnnouncement = nil
                }
            }
        }
        .onChange(of: chatService.incomingMessageNotification?.id) { _, newId in
            guard newId != nil else { return }
            // Auto-dismiss after 4 seconds unless replaced by a newer one.
            Task { @MainActor in
                let dismissedId = newId
                try? await Task.sleep(for: .seconds(4))
                if chatService.incomingMessageNotification?.id == dismissedId {
                    chatService.incomingMessageNotification = nil
                }
            }
        }
        .onChange(of: navigationCoordinator.selectedTab) { _, newTab in
            // If the user jumps to chat manually, clear any pending banner.
            if newTab == .chat {
                chatService.incomingMessageNotification = nil
            }
        }
        .task(id: authService.currentUser?.id) {
            // Sign-out path: tear chat down so realtime channels close and
            // disk cache + outbound queue rebind on next sign-in.
            if authService.currentUser == nil {
                await chatService.shutdown()
                await powService.unsubscribeFromPollUpdates()
                return
            }

            if authService.currentProfile == nil {
                await authService.loadProfile()
            }

            // Bring chat up for this user (idempotent — paints from disk
            // immediately, starts realtime, replays any pending sends).
            // We do this here rather than from ChatView so channels stay
            // alive across tab switches and typing presence remains active.
            await chatService.bootstrap()

            // Subscribe to POW poll updates so the winner celebration
            // banner can fire the moment a poll closes.
            await powService.subscribeToPollUpdates()

            // Fetch admin-tunable config (iOS RSVP discount, chat lock)
            // once the user is signed in — RLS on app_settings requires an
            // authenticated session for reads. Then subscribe to realtime so
            // an admin toggling the chat lock from another device flips the
            // UI here without a foreground bounce.
            await appConfig.refresh()
            await appConfig.startRealtime()

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
        .onChange(of: scenePhase) { _, newPhase in
            // Re-pull the discount when the app returns to the foreground so
            // admin edits land without a relaunch.
            if newPhase == .active, authService.currentUser != nil {
                Task { await appConfig.refresh() }
            }
        }
    }
}
