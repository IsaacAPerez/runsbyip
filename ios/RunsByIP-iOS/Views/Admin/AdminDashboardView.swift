import SwiftUI
@preconcurrency import Supabase

struct AdminDashboardView: View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var authService: AuthService

    @State private var rsvpCounts: [String: Int] = [:]
    @State private var isLoading = true
    @State private var showCreateSession = false
    @State private var toastMessage: String?
    @State private var pushMessage = ""
    @State private var isSendingPush = false
    @State private var isCreatingPoll = false
    @State private var isTogglingPayments = false

    private var supabase: SupabaseClient { SupabaseService.shared.client }

    private var totalSessions: Int { sessionService.sessions.count }
    private var totalPlayers: Int { rsvpCounts.values.reduce(0, +) }
    private var totalRevenue: Int {
        sessionService.sessions.reduce(0) { sum, session in
            sum + (rsvpCounts[session.id] ?? 0) * session.priceCents
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if isLoading {
                    LoadingView(message: "Loading dashboard...")
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Stats
                            HStack(spacing: 12) {
                                StatCard(title: "Sessions", value: "\(totalSessions)", icon: "calendar")
                                StatCard(title: "Players", value: "\(totalPlayers)", icon: "person.3.fill")
                                StatCard(title: "Revenue", value: "$\(totalRevenue / 100)", icon: "dollarsign.circle.fill")
                            }
                            .padding(.horizontal)

                            // Create Session Button
                            Button {
                                showCreateSession = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Create Session")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.appAccentOrange)
                                .foregroundColor(.white)
                                .cornerRadius(AppStyle.buttonCornerRadius)
                            }
                            .padding(.horizontal)

                            // Toggle Payments
                            if let session = sessionService.currentSession {
                                AdminActionCard(title: "Current Session") {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text(session.formattedShortDate)
                                            .font(.subheadline.bold())
                                            .foregroundColor(.white)

                                        HStack {
                                            Text("Payments")
                                                .font(.subheadline)
                                                .foregroundColor(.appTextSecondary)

                                            Spacer()

                                            Button {
                                                togglePayments(session: session)
                                            } label: {
                                                Text(session.paymentsOpen ? "OPEN" : "CLOSED")
                                                    .font(.system(size: 12, weight: .black))
                                                    .tracking(0.8)
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 8)
                                                    .background(session.paymentsOpen ? Color.appSuccess.opacity(0.2) : Color.appError.opacity(0.2))
                                                    .foregroundColor(session.paymentsOpen ? .appSuccess : .appError)
                                                    .clipShape(Capsule())
                                            }
                                            .disabled(isTogglingPayments)
                                        }
                                    }
                                }
                            }

                            // Create POW Poll
                            AdminActionCard(title: "Player of the Week") {
                                Button {
                                    createPOWPoll()
                                } label: {
                                    HStack {
                                        if isCreatingPoll {
                                            ProgressView().tint(.white).scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "trophy.fill")
                                                .foregroundColor(Color(hex: "FFD700"))
                                            Text("Create POW Poll")
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.appSurfaceElevated)
                                    .foregroundColor(.white)
                                    .cornerRadius(AppStyle.buttonCornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius)
                                            .stroke(Color.appBorder, lineWidth: 1)
                                    )
                                }
                                .disabled(isCreatingPoll)
                            }

                            // Send Test Push
                            AdminActionCard(title: "Push Notification") {
                                VStack(spacing: 12) {
                                    TextField("Message...", text: $pushMessage)
                                        .padding(12)
                                        .background(Color.appSurfaceElevated)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.appBorder, lineWidth: 1)
                                        )

                                    Button {
                                        sendTestPush()
                                    } label: {
                                        HStack {
                                            if isSendingPush {
                                                ProgressView().tint(.white).scaleEffect(0.8)
                                            } else {
                                                Image(systemName: "paperplane.fill")
                                                Text("Send Test Push")
                                                    .fontWeight(.semibold)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(pushMessage.isEmpty ? Color.appSurfaceElevated : Color.appAccentOrange)
                                        .foregroundColor(.white)
                                        .cornerRadius(AppStyle.buttonCornerRadius)
                                    }
                                    .disabled(pushMessage.isEmpty || isSendingPush)
                                }
                            }

                            // Dev Info
                            AdminActionCard(title: "Dev Info") {
                                VStack(alignment: .leading, spacing: 10) {
                                    DevInfoRow(label: "User ID", value: authService.currentUser?.id.uuidString ?? "—")
                                    DevInfoRow(label: "Email", value: authService.currentProfile?.email ?? "—")
                                    DevInfoRow(label: "App Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                                    DevInfoRow(label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                                }
                            }

                            // Sessions List
                            VStack(alignment: .leading, spacing: 12) {
                                Text("All Sessions")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)

                                ForEach(sessionService.sessions) { session in
                                    NavigationLink(destination: AdminRSVPView(session: session)) {
                                        AdminSessionRow(
                                            session: session,
                                            rsvpCount: rsvpCounts[session.id] ?? 0
                                        )
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.top)
                        .padding(.bottom, 28)
                    }
                }

                if let toast = toastMessage {
                    VStack {
                        Spacer()
                        ToastView(message: toast, type: .success)
                            .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Admin")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showCreateSession) {
                CreateSessionView()
                    .onDisappear { Task { await loadData() } }
            }
            .task {
                await loadData()
            }
        }
    }

    private func loadData() async {
        do {
            try await sessionService.fetchAllSessions()
            try await sessionService.fetchCurrentSession()
            for session in sessionService.sessions {
                rsvpCounts[session.id] = try await sessionService.fetchPaidRSVPCount(for: session.id)
            }
        } catch {
            // Dashboard degrades gracefully
        }
        isLoading = false
    }

    private func togglePayments(session: GameSession) {
        isTogglingPayments = true
        Task {
            do {
                try await sessionService.togglePayments(sessionId: session.id, open: !session.paymentsOpen)
                try await sessionService.fetchCurrentSession()
                showToast("Payments \(session.paymentsOpen ? "closed" : "opened")")
            } catch {
                showToast("Failed to toggle payments")
            }
            isTogglingPayments = false
        }
    }

    private func createPOWPoll() {
        isCreatingPoll = true
        Task {
            do {
                // Find the most recent completed session (past date)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = .current
                let today = formatter.string(from: Date())

                let pastSessions: [GameSession] = try await supabase
                    .from("sessions")
                    .select()
                    .lt("date", value: today)
                    .neq("status", value: "cancelled")
                    .order("date", ascending: false)
                    .limit(1)
                    .execute()
                    .value

                guard let lastSession = pastSessions.first else {
                    showToast("No completed sessions found")
                    isCreatingPoll = false
                    return
                }

                // Create poll opening now, closing in 3 days
                let now = ISO8601DateFormatter().string(from: Date())
                let closesAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3 * 86400))

                struct PollInsert: Encodable {
                    let sessionId: String
                    let opensAt: String
                    let closesAt: String
                    let status: String

                    enum CodingKeys: String, CodingKey {
                        case sessionId = "session_id"
                        case opensAt = "opens_at"
                        case closesAt = "closes_at"
                        case status
                    }
                }

                try await supabase
                    .from("pow_polls")
                    .insert(PollInsert(
                        sessionId: lastSession.id,
                        opensAt: now,
                        closesAt: closesAt,
                        status: "open"
                    ))
                    .execute()

                showToast("POW poll created for \(lastSession.formattedShortDate)")
            } catch {
                showToast("Failed: \(error.localizedDescription)")
            }
            isCreatingPoll = false
        }
    }

    private func sendTestPush() {
        guard !pushMessage.isEmpty else { return }
        isSendingPush = true
        let message = pushMessage
        Task {
            do {
                let url = URL(string: "https://ncjgkthruvapcogqaxhi.supabase.co/functions/v1/send-push")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let payload: [String: String] = [
                    "type": "custom",
                    "title": "RunsByIP",
                    "body": message
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let (_, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    showToast("Push sent!")
                    pushMessage = ""
                } else {
                    showToast("Push failed")
                }
            } catch {
                showToast("Push failed: \(error.localizedDescription)")
            }
            isSendingPush = false
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            toastMessage = nil
        }
    }
}

// MARK: - Admin Action Card

private struct AdminActionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.appTextSecondary)

            content
        }
        .padding(16)
        .background(Color.appSurface)
        .cornerRadius(AppStyle.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.cardCornerRadius)
                .stroke(Color.appBorder, lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

// MARK: - Dev Info Row

private struct DevInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.appTextSecondary)

            Spacer()

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.appAccentOrange)
                .font(.title3)

            Text(value)
                .font(.title2.bold())
                .foregroundColor(.white)

            Text(title)
                .font(.caption)
                .foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.appSurface)
        .cornerRadius(AppStyle.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.cardCornerRadius)
                .stroke(Color.appBorder, lineWidth: 1)
        )
    }
}

// MARK: - Admin Session Row

struct AdminSessionRow: View {
    let session: GameSession
    let rsvpCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.formattedShortDate)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)

                Text("\(rsvpCount)/\(session.maxPlayers) players")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            BadgeView.forStatus(session.status)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.appTextTertiary)
        }
        .padding()
        .background(Color.appSurface)
        .cornerRadius(AppStyle.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppStyle.cardCornerRadius)
                .stroke(Color.appBorder, lineWidth: 1)
        )
    }
}

#Preview {
    AdminDashboardView()
        .environmentObject(SessionService())
        .environmentObject(AuthService())
}
