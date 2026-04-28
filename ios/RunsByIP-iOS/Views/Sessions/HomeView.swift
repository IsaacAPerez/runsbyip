import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var chatService: ChatService
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var powService: POWService

    @State private var isLoading = true
    @State private var hasLoadedOnce = false
    @State private var errorMessage: String?
    @State private var showRSVP = false
    @State private var showAllRuns = false
    @State private var leaderboard: [LeaderboardEntry] = []
    @State private var galleryURLs: [URL] = []
    @State private var sessionForRSVP: GameSession?

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
            ZStack(alignment: .top) {
                Color.appBackground
                    .ignoresSafeArea()

                // Hero gallery pinned behind scroll content
                if !galleryURLs.isEmpty {
                    HeroGalleryView(urls: galleryURLs)
                        .ignoresSafeArea(edges: .top)
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header overlay on top of hero
                        HomeHeader(
                            firstName: firstName,
                            hasUpcomingSession: currentSession != nil,
                            onBrowseRuns: { showAllRuns = true }
                        )
                        .padding(.top, 280)

                        if let session = currentSession {
                            NextRunCard(
                                session: session,
                                confirmedCount: confirmedCount,
                                onRSVP: {
                                    guard !session.isFull(using: confirmedCount) else { return }
                                    sessionForRSVP = session
                                    showRSVP = true
                                }
                            )
                        } else if isLoading && !hasLoadedOnce {
                            HomeStartupCard()
                        } else {
                            EmptyCountdownCard()
                        }

                        if isLoading && !hasLoadedOnce {
                            HomeStartupSection(title: "Loading home")
                        } else {
                            POWCard()
                        }

                        if currentSession == nil && !(isLoading && !hasLoadedOnce) {
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

                if let errorMessage {
                    VStack {
                        Spacer()
                        ToastView(message: errorMessage, type: .error)
                            .padding(.bottom, 20)
                    }
                }
            }
            .sheet(isPresented: $showRSVP, onDismiss: {
                sessionService.subscribeToCurrentSession()
            }) {
                if let session = sessionForRSVP {
                    RSVPView(session: session)
                        .transaction { $0.animation = nil }
                }
            }
            .onChange(of: showRSVP) { _, isPresented in
                if isPresented {
                    sessionService.unsubscribe()
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
        if !hasLoadedOnce { isLoading = true }
        errorMessage = nil
        do {
            try await sessionService.fetchCurrentSession()
            try await powService.fetchCurrentPoll()
            galleryURLs = (try? await chatService.fetchGalleryPhotos()) ?? []
            if currentSession == nil {
                leaderboard = try await sessionService.fetchLeaderboard()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        hasLoadedOnce = true
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
                    .font(.system(size: 30, weight: .black).width(.condensed))
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

private struct HomeStartupCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEXT RUN")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundColor(.appTextSecondary)

            Text("Getting the latest run...")
                .font(.system(size: 28, weight: .black).width(.condensed))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("We’ll drop you straight into home as soon as everything is ready.")
                .font(.subheadline)
                .foregroundColor(.appTextSecondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        )
    }
}

private struct HomeStartupSection: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundColor(.appTextSecondary)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.appSurface)
                .frame(height: 160)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                )
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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT RUN")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.6)
                        .foregroundColor(.appTextSecondary)

                    Text(session.formattedDate)
                        .font(.system(size: 28, weight: .black).width(.condensed))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                BadgeView.forStatus(session.effectiveStatus)
            }

            // Countdown — isolated via TimelineView, won't invalidate parent
            CountdownSection(session: session)

            // Details
            VStack(alignment: .leading, spacing: 12) {
                DetailRow(systemImage: "clock.fill", title: session.time)
                DetailRow(systemImage: "mappin.and.ellipse", title: session.location)
                DetailRow(systemImage: "creditcard.fill", title: session.priceDisplay)
            }

            // Spots
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

            // CTA
            Button(action: onRSVP) {
                Text(spotsLeft == 0 ? "RUN IS FULL" : (session.paymentsOpen ? "RSVP & PAY \(session.priceDisplay)" : "LOCK IN"))
                    .font(.system(size: 15, weight: .black))
                    .tracking(1.2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(spotsLeft == 0 ? Color.appSurfaceElevated : Color.appAccentOrange)
                    .foregroundColor(spotsLeft == 0 ? .white : .appBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(spotsLeft == 0 || session.isCompleted)
            .opacity((spotsLeft == 0 || session.isCompleted) ? 0.55 : 1)
        }
        .padding(22)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        )
    }
}

// Isolated countdown — TimelineView only invalidates itself, not the parent
private struct CountdownSection: View {
    let session: GameSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let isLive: Bool = {
                guard let start = session.sessionDateTime else { return false }
                let elapsed = now.timeIntervalSince(start)
                return elapsed >= 0 && elapsed < 7200
            }()

            if isLive {
                Text("HAPPENING NOW")
                    .font(.system(size: 22, weight: .black).width(.condensed))
                    .foregroundColor(.appAccentOrange)
            } else if let target = session.sessionDateTime {
                let remaining = target.timeIntervalSince(now)
                if remaining > 0 {
                    let total = Int(remaining)
                    let d = total / 86400
                    let h = (total % 86400) / 3600
                    let m = (total % 3600) / 60
                    let s = total % 60

                    HStack(spacing: 4) {
                        if d > 0 {
                            CountdownCardUnit(value: d, label: "d")
                        }
                        CountdownCardUnit(value: h, label: "h")
                        CountdownCardUnit(value: m, label: "m")
                        CountdownCardUnit(value: s, label: "s")
                    }
                }
            }
        }
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
                                .font(.system(size: 14, weight: .bold).width(.condensed))
                                .foregroundColor(.appTextTertiary)
                                .frame(width: 28)
                        }

                        Text(entry.playerName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer()

                        Text("\(entry.gameCount)")
                            .font(.system(size: 18, weight: .black).width(.condensed))
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

// MARK: - NBA Scores Card (live ESPN data)

private struct NBAScoreboardEvent: Identifiable, Equatable {
    let id: String
    let away: Side
    let home: Side
    let state: GameState
    /// Tipoff in user's local timezone for `pre` games.
    let startDate: Date?
    /// ESPN-formatted live string (e.g. "Q3 4:21") for `in` games.
    let liveDetail: String?

    struct Side: Equatable {
        let abbreviation: String
        let score: Int
        let logoURL: URL?
    }

    enum GameState: Equatable {
        case scheduled
        case live
        case final
    }
}

@MainActor
private final class NBAScoreboardViewModel: ObservableObject {
    @Published var events: [NBAScoreboardEvent] = []
    @Published var isLoading: Bool = false
    @Published var didLoad: Bool = false

    private let endpoint = URL(string: "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard")!

    func loadIfNeeded() async {
        guard !didLoad, !isLoading else { return }
        await load()
    }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            didLoad = true
        }
        do {
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(ESPNScoreboardResponse.self, from: data)
            events = decoded.events.compactMap(Self.map(event:))
        } catch {
            // Soft-fail: leave events empty so the card can show a friendly fallback.
            events = []
        }
    }

    private static func map(event: ESPNScoreboardResponse.Event) -> NBAScoreboardEvent? {
        guard let comp = event.competitions.first,
              comp.competitors.count == 2,
              let awayRaw = comp.competitors.first(where: { $0.homeAway == "away" }),
              let homeRaw = comp.competitors.first(where: { $0.homeAway == "home" })
        else { return nil }

        let stateString = event.status.type.state
        let state: NBAScoreboardEvent.GameState = {
            switch stateString {
            case "in": return .live
            case "post": return .final
            default: return .scheduled
            }
        }()

        let liveDetail: String? = {
            guard state == .live else { return nil }
            let clock = event.status.displayClock?.trimmingCharacters(in: .whitespaces) ?? ""
            let q = event.status.period.map { "Q\($0)" }
            return [q, clock.isEmpty ? nil : clock].compactMap { $0 }.joined(separator: " ")
        }()

        let startDate: Date? = state == .scheduled ? parseESPNDate(event.date) : nil

        return NBAScoreboardEvent(
            id: event.id,
            away: side(from: awayRaw),
            home: side(from: homeRaw),
            state: state,
            startDate: startDate,
            liveDetail: liveDetail
        )
    }

    private static func side(from competitor: ESPNScoreboardResponse.Event.Competition.Competitor) -> NBAScoreboardEvent.Side {
        let score = Int(competitor.score ?? "0") ?? 0
        let abbrev = competitor.team.abbreviation ?? "—"
        let logo = competitor.team.logo.flatMap(URL.init(string:))
        return .init(abbreviation: abbrev, score: score, logoURL: logo)
    }
}

/// ESPN's scoreboard endpoint sends timestamps like `2026-04-28T23:00Z` (no seconds),
/// which `ISO8601DateFormatter` won't accept. Try a few common shapes.
private func parseESPNDate(_ raw: String) -> Date? {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    if let d = iso.date(from: raw) { return d }
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: raw) { return d }

    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone(secondsFromGMT: 0)
    for format in [
        "yyyy-MM-dd'T'HH:mm'Z'",
        "yyyy-MM-dd'T'HH:mmZZZZZ",
        "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
    ] {
        df.dateFormat = format
        if let d = df.date(from: raw) { return d }
    }
    return nil
}

private struct ESPNScoreboardResponse: Decodable {
    let events: [Event]

    struct Event: Decodable {
        let id: String
        let date: String
        let competitions: [Competition]
        let status: Status

        struct Status: Decodable {
            let displayClock: String?
            let period: Int?
            let type: TypeInfo

            struct TypeInfo: Decodable {
                let state: String
            }
        }

        struct Competition: Decodable {
            let competitors: [Competitor]

            struct Competitor: Decodable {
                let homeAway: String
                let score: String?
                let team: Team

                struct Team: Decodable {
                    let abbreviation: String?
                    let logo: String?
                }
            }
        }
    }
}

private struct NBAScoresCard: View {
    @StateObject private var viewModel = NBAScoreboardViewModel()

    private var headerSubtitle: String {
        if viewModel.isLoading && viewModel.events.isEmpty { return "Loading scores…" }
        if viewModel.events.isEmpty { return "No games scheduled today" }
        let liveCount = viewModel.events.filter { $0.state == .live }.count
        if liveCount > 0 { return "\(liveCount) live · \(viewModel.events.count) total" }
        return "\(viewModel.events.count) game\(viewModel.events.count == 1 ? "" : "s") today"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "basketball.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.appAccentOrange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("NBA TODAY")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundColor(.appTextSecondary)
                    Text(headerSubtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }

                Spacer()

                Button {
                    if let url = URL(string: "https://www.espn.com/nba/scoreboard") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("ESPN")
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.appTextSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.appSurfaceElevated, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if viewModel.events.isEmpty {
                EmptyNBAScoresRow(isLoading: viewModel.isLoading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.events) { event in
                            NBAGameTile(event: event)
                        }
                    }
                }
                // Negative side padding lets tiles bleed slightly past card edge.
                .padding(.horizontal, -2)
            }
        }
        .padding(18)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        )
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.load() }
    }
}

private struct EmptyNBAScoresRow: View {
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isLoading ? "clock" : "basketball")
                .font(.system(size: 18))
                .foregroundColor(.appTextTertiary)

            Text(isLoading ? "Loading today's NBA scoreboard…" : "No NBA games today. Check ESPN for the schedule.")
                .font(.system(size: 13))
                .foregroundColor(.appTextSecondary)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct NBAGameTile: View {
    let event: NBAScoreboardEvent

    private static func formatStartTime(_ date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.minute], from: date)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = (comps.minute == 0) ? "ha" : "h:mma"
        f.amSymbol = "AM"
        f.pmSymbol = "PM"
        return f.string(from: date)
    }

    private var statusBadge: some View {
        let (text, color): (String, Color) = {
            switch event.state {
            case .scheduled:
                if let date = event.startDate {
                    return (NBAGameTile.formatStartTime(date), .appTextSecondary)
                }
                return ("SCHED", .appTextSecondary)
            case .live:
                return (event.liveDetail ?? "LIVE", .appAccentOrange)
            case .final:
                return ("FINAL", .appTextSecondary)
            }
        }()

        return Text(text.uppercased())
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .tracking(0.8)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func teamRow(_ side: NBAScoreboardEvent.Side, isWinner: Bool) -> some View {
        HStack(spacing: 8) {
            AsyncImage(url: side.logoURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    Circle().fill(Color.appSurfaceElevated)
                }
            }
            .frame(width: 22, height: 22)

            Text(side.abbreviation)
                .font(.system(size: 13, weight: isWinner ? .heavy : .semibold))
                .foregroundColor(.white)

            Spacer(minLength: 6)

            if event.state != .scheduled {
                Text("\(side.score)")
                    .font(.system(size: 15, weight: isWinner ? .heavy : .semibold, design: .rounded))
                    .foregroundColor(isWinner ? .white : .appTextSecondary)
                    .monospacedDigit()
            }
        }
    }

    private var awayWins: Bool {
        event.state == .final && event.away.score > event.home.score
    }

    private var homeWins: Bool {
        event.state == .final && event.home.score > event.away.score
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusBadge
            teamRow(event.away, isWinner: awayWins)
            teamRow(event.home, isWinner: homeWins)
        }
        .padding(12)
        .frame(width: 168, alignment: .leading)
        .background(Color.appSurfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 0.5)
        )
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthService())
        .environmentObject(SessionService())
        .environmentObject(NavigationCoordinator())
        .environmentObject(POWService())
}
