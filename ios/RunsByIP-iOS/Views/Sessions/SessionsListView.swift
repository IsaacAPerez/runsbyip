import SwiftUI

struct SessionsListView: View {
    @EnvironmentObject var sessionService: SessionService

    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if isLoading {
                    LoadingView(message: "Loading sessions...")
                } else if sessionService.sessions.isEmpty {
                    EmptyStateView(
                        icon: "📅",
                        title: "No Sessions Yet",
                        subtitle: "Sessions will appear here once created"
                    )
                } else {
                    List(sessionService.sessions) { session in
                        NavigationLink(destination: SessionDetailView(session: session)) {
                            SessionRowView(session: session)
                        }
                        .listRowBackground(Color.appSurface)
                        .listRowSeparatorTint(Color.appBorder)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                if let errorMessage {
                    VStack {
                        Spacer()
                        ToastView(message: errorMessage, type: .error)
                            .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Sessions")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                await loadSessions()
            }
            .refreshable {
                await loadSessions()
            }
        }
    }

    private func loadSessions() async {
        isLoading = sessionService.sessions.isEmpty
        errorMessage = nil
        do {
            try await sessionService.fetchAllSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    let session: GameSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.formattedShortDate)
                    .font(.headline)
                    .foregroundColor(.white)

                Text("\(session.time) - \(session.location)")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            BadgeView.forStatus(session.status)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SessionsListView()
        .environmentObject(SessionService())
}
