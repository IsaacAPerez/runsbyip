import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var powService: POWService

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showRSVP = false
    @State private var showAllRuns = false
    @State private var leaderboard: [LeaderboardEntry] = []

    private var currentSession: GameSession? {
        sessionService.currentSession
    }

    private var confirmedCount: Int {
        guard let session = currentSession else { return 0 }
        return max(0, min(session.maxPlayers, sessionService.currentSessionRSVPCount))
    }

    private var isCurrentSessionFull: Bool {
        guard let session = currentSession else { return false }
        return session.isFull(using: confirmedCount)
    }

    private var firstName: String {
        let fallback = authService.currentProfile?.displayName
            ?? authService.currentUser?.userMetadata["display_name"]?.stringValue
            ?? "Player"

        return fallback
            .split(separator: " ")
            .first
            .map(String.init)
            ?? fallback
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground
                    .ignoresSafeArea()

                if isLoading {
                    LoadingView(message: "Loading home...")
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            HomeHeader(
                                firstName: firstName,
                                hasUpcomingSession: currentSession != nil,
                                onBrowseRuns: { showAllRuns = true }
                            )

                            // Countdown Card
                            if let session = currentSession {
                                CountdownCard(session: session)
                            } else {
                                EmptyCountdownCard()
                            }

                            // Next Run Details Card
                            if let session = currentSession {
                                NextRunCard(
                                    session: session,
                                    confirmedCount: confirmedCount,
                                    onRSVP: {
                                        guard !session.isFull(using: confirmedCount) else { return }
                                        showRSVP = true
                                    }
                                )

                                HomeStatusStrip(
                                    session: session,
                                    confirmedCount: confirmedCount
                                )
                            }

                            // Player of the Week
                            POWCard()

                            // Extra content when no session
                            if currentSession == nil {
                                if !leaderboard.isEmpty {
                                    MostConsistentCard(entries: leaderboard)
                                }

                                NBAScoresCard()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                    }
                }

                if let errorMessage {
                    VStack {
                        Spacer()
                        ToastView(message: errorMessage, type: .error)
                            .padding(.bottom, 20)
                    }
                }
            }
            .sheet(isPresented: $showRSVP) {
                if let session = currentSession {
                    RSVPView(session: session)
                }
            }
            .navigationDestination(isPresented: $showAllRuns) {
                SessionsListView()
            }
            .task {
                await loadData()
                sessionService.subscribeToCurrentSession()
            }
            .refreshable {
                await loadData()
                sessionService.subscribeToCurrentSession()
            }
            .onDisappear {
                sessionService.unsubscribe()
            }
        }
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        do {
            try await sessionService.fetchCurrentSession()
            try await powService.fetchCurrentPoll()
            if currentSession == nil {
                leaderboard = try await sessionService.fetchLeaderboard()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct HomeHeader: View {
    let firstName: String
    let hasUpcomingSession: Bool
    let onBrowseRuns: () -> Void

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date()).uppercased()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(dateLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundColor(.appTextSecondary)

                Text(hasUpcomingSession ? "Next run, \(firstName)." : "Stay ready, \(firstName).")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(hasUpcomingSession ? "Everything important is below." : "No clutter, just the essentials.")
                    .font(.subheadline)
                    .foregroundColor(.appTextSecondary)
            }

            Spacer(minLength: 0)

            Button(action: onBrowseRuns) {
                Image(systemName: "calendar")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.appSurfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Browse runs")
        }
    }
}

private struct NextRunCard: View {
    let session: GameSession
    let confirmedCount: Int
    let onRSVP: () -> Void

    private var spotsLeft: Int {
        max(session.maxPlayers - confirmedCount, 0)
    }

    private var locationLine: String {
        session.location
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT RUN")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.6)
                        .foregroundColor(.appTextSecondary)

                    Text(session.formattedDate)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                BadgeView.forStatus(session.status)
            }

            VStack(alignment: .leading, spacing: 12) {
                DetailRow(systemImage: "clock.fill", title: session.time)
                DetailRow(systemImage: "mappin.and.ellipse", title: locationLine)
                DetailRow(systemImage: "creditcard.fill", title: session.priceDisplay)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Spots")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Text("\(confirmedCount)/\(session.maxPlayers)")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.appBorder)
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.appAccentOrange)
                            .frame(
                                width: geo.size.width * CGFloat(min(confirmedCount, session.maxPlayers)) / CGFloat(max(session.maxPlayers, 1)),
                                height: 6
                            )
                    }
                }
                .frame(height: 6)

                Text(spotsLeft == 0 ? "Run is full" : "\(spotsLeft) spots left")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            Button(action: onRSVP) {
                Text(spotsLeft == 0 ? "RUN IS FULL" : (session.paymentsOpen ? "RSVP & PAY \(session.priceDisplay)" : "LOCK IN"))
                    .font(.system(size: 15, weight: .black))
                    .tracking(1.2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(spotsLeft == 0 ? Color.appSurfaceElevated : Color.appAccentOrange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(spotsLeft == 0)
            .opacity(spotsLeft == 0 ? 0.55 : 1)
        }
        .padding(22)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        )
    }
}

private struct HomeStatusStrip: View {
    let session: GameSession
    let confirmedCount: Int

    private var spotsLeft: Int {
        max(session.maxPlayers - confirmedCount, 0)
    }

    var body: some View {
        HStack(spacing: 12) {
            StatusPill(title: "STATUS", value: session.status.capitalized)
            StatusPill(title: "LEFT", value: "\(spotsLeft)")
            StatusPill(title: "PRICE", value: session.priceDisplay)
        }
    }
}

private struct StatusPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.1)
                .foregroundColor(.appTextSecondary)

            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.appSurfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}


private struct DetailRow: View {
    let systemImage: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundColor(.appAccentOrange)
                .frame(width: 20)

            Text(title)
                .font(.subheadline)
                .foregroundColor(.white)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Most Consistent Card

private struct MostConsistentCard: View {
    let entries: [LeaderboardEntry]

    private let medals = ["🥇", "🥈", "🥉"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(.appAccentOrange)
                    .font(.system(size: 16))

                Text("MOST CONSISTENT")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(.appTextSecondary)

                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 12) {
                        if index < 3 {
                            Text(medals[index])
                                .font(.system(size: 18))
                                .frame(width: 28)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.appTextTertiary)
                                .frame(width: 28)
                        }

                        Text(entry.playerName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        Text("\(entry.gameCount)")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundColor(.appAccentOrange)

                        Text(entry.gameCount == 1 ? "game" : "games")
                            .font(.system(size: 12))
                            .foregroundColor(.appTextTertiary)
                    }
                    .padding(.vertical, 10)

                    if index < entries.count - 1 {
                        Divider().background(Color.appBorder)
                    }
                }
            }
        }
        .padding(22)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        )
    }
}

// MARK: - NBA Scores Card

private struct NBAScoresCard: View {
    var body: some View {
        Button {
            if let url = URL(string: "https://www.espn.com/nba/scoreboard") {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "basketball.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.appAccentOrange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("NBA TODAY")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundColor(.appTextSecondary)

                    Text("Check today's scores & highlights")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appTextTertiary)
            }
            .padding(18)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthService())
        .environmentObject(SessionService())
        .environmentObject(NavigationCoordinator())
        .environmentObject(POWService())
}
