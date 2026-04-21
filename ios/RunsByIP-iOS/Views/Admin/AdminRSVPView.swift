import SwiftUI

struct AdminRSVPView: View {
    @EnvironmentObject var sessionService: SessionService

    let session: GameSession

    @State private var rsvps: [RSVP] = []
    @State private var checkedIn: Set<String> = []
    @State private var teams: [[RSVP]]?
    @State private var isLoading = true
    @State private var showCancelConfirm = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) var dismiss

    // Every row in `rsvps` is a confirmed (paid) attendee — `rsvps` is the
    // canonical list.
    private var confirmed: [RSVP] { rsvps }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if isLoading {
                LoadingView(message: "Loading RSVPs...")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Session Header
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.formattedShortDate)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text(session.location)
                                    .font(.subheadline)
                                    .foregroundColor(.appTextSecondary)
                            }
                            Spacer()
                            BadgeView.forStatus(session.status)
                        }

                        // Actions
                        HStack(spacing: 12) {
                            Button {
                                randomizeTeams()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "shuffle")
                                    Text("Randomize Teams")
                                        .font(.subheadline.weight(.medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.appSurfaceElevated)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(confirmed.count < 6)

                            if !session.isCancelled {
                                Button {
                                    showCancelConfirm = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle")
                                        Text("Cancel")
                                            .font(.subheadline.weight(.medium))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.appError.opacity(0.15))
                                    .foregroundColor(.appError)
                                    .cornerRadius(10)
                                }
                            }
                        }

                        // Teams Display
                        if let teams {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Teams")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                ForEach(Array(teams.enumerated()), id: \.offset) { index, team in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Team \(index + 1)")
                                            .font(.subheadline.bold())
                                            .foregroundColor(.appAccentOrange)

                                        ForEach(team) { rsvp in
                                            Text("  \(rsvp.playerName)")
                                                .font(.subheadline)
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color.appSurface)
                            .cornerRadius(AppStyle.cardCornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppStyle.cardCornerRadius)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            )
                        }

                        // Confirmed RSVPs
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Confirmed (\(confirmed.count)/\(session.maxPlayers))")
                                .font(.headline)
                                .foregroundColor(.white)

                            if confirmed.isEmpty {
                                Text("No confirmed RSVPs")
                                    .font(.subheadline)
                                    .foregroundColor(.appTextSecondary)
                            } else {
                                ForEach(confirmed) { rsvp in
                                    AdminPlayerRow(
                                        rsvp: rsvp,
                                        isCheckedIn: checkedIn.contains(rsvp.id),
                                        onToggleCheckIn: { toggleCheckIn(rsvp) }
                                    )
                                }
                            }
                        }
                        .padding()
                        .background(Color.appSurface)
                        .cornerRadius(AppStyle.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppStyle.cardCornerRadius)
                                .stroke(Color.appBorder, lineWidth: 1)
                        )

                    }
                    .padding()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
                .confirmationDialog("Cancel Session?", isPresented: $showCancelConfirm) {
            Button("Cancel Session", role: .destructive) {
                cancelSession()
            }
        } message: {
            Text("This will mark the session as cancelled. This cannot be undone.")
        }
        .task {
            await loadRSVPs()
        }
    }

    private func loadRSVPs() async {
        do {
            rsvps = try await sessionService.fetchRSVPs(for: session.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleCheckIn(_ rsvp: RSVP) {
        if checkedIn.contains(rsvp.id) {
            checkedIn.remove(rsvp.id)
        } else {
            checkedIn.insert(rsvp.id)
        }
    }

    private func cancelSession() {
        Task {
            do {
                try await sessionService.cancelSession(id: session.id)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func randomizeTeams() {
        let players = confirmed.shuffled()
        let teamSize = players.count / 3
        let remainder = players.count % 3

        var result: [[RSVP]] = []
        var startIndex = 0
        for i in 0..<3 {
            let size = teamSize + (i < remainder ? 1 : 0)
            let endIndex = startIndex + size
            result.append(Array(players[startIndex..<endIndex]))
            startIndex = endIndex
        }
        teams = result
    }
}

// MARK: - Admin Player Row

struct AdminPlayerRow: View {
    let rsvp: RSVP
    let isCheckedIn: Bool
    let onToggleCheckIn: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PlayerRowView(name: rsvp.playerName)

            Toggle("", isOn: Binding(
                get: { isCheckedIn },
                set: { _ in onToggleCheckIn() }
            ))
            .tint(.appSuccess)
            .labelsHidden()

            Text(isCheckedIn ? "In" : "Out")
                .font(.caption)
                .foregroundColor(isCheckedIn ? .appSuccess : .appTextSecondary)
                .frame(width: 28)
        }
    }
}

#Preview {
    NavigationStack {
        AdminRSVPView(session: GameSession(
            id: "1",
            date: "2026-03-28",
            time: "6:00 PM",
            location: "Pan Pacific Park",
            priceCents: 1000,
            minPlayers: 10,
            maxPlayers: 15,
            status: "open",
            paymentsOpen: false,
            createdAt: ""
        ))
        .environmentObject(SessionService())
    }
}
