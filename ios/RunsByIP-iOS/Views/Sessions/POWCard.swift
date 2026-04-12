import SwiftUI

struct POWCard: View {
    @EnvironmentObject var powService: POWService

    @State private var isLoading = true

    var body: some View {
        Group {
            if let poll = powService.currentPoll {
                if poll.isOpen {
                    votingOpenCard(poll: poll)
                } else if poll.isClosed, poll.winnerName != nil {
                    winnerCard(poll: poll)
                } else {
                    EmptyView()
                }
            } else if !isLoading {
                dormantCard
            }
        }
        .task {
            try? await powService.fetchCurrentPoll()
            isLoading = false
        }
    }

    // MARK: - Voting Open

    @ViewBuilder
    private func votingOpenCard(poll: POWPoll) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "basketball.fill")
                    .foregroundColor(.appAccentOrange)
                    .font(.system(size: 16))

                Text("PLAYER OF THE WEEK")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(.appTextSecondary)

                Spacer()
            }

            Text(poll.closesInText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.appAccentOrange)

            // User's vote status
            if let votedFor = powService.userVotedFor {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.appSuccess)
                    Text("You voted for \(votedFor)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.appSuccess)
                }
                .padding(.vertical, 4)
            }

            // Horizontal scrollable player chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // Show tallied players first, then eligible players without votes
                    let talliedNames = Set(powService.tallies.map(\.votedForName))
                    let untallied = powService.eligiblePlayers.filter { !talliedNames.contains($0) }

                    ForEach(powService.tallies) { tally in
                        PlayerChip(
                            name: tally.votedForName,
                            voteCount: tally.voteCount,
                            isVotedFor: powService.userVotedFor == tally.votedForName,
                            canVote: powService.userVotedFor == nil
                        ) {
                            vote(for: tally.votedForName, pollId: poll.id)
                        }
                    }

                    ForEach(untallied, id: \.self) { name in
                        PlayerChip(
                            name: name,
                            voteCount: 0,
                            isVotedFor: false,
                            canVote: powService.userVotedFor == nil
                        ) {
                            vote(for: name, pollId: poll.id)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(22)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        )
    }

    // MARK: - Vote (stored locally + server)

    private func vote(for playerName: String, pollId: String) {
        guard powService.userVotedFor == nil else { return }

        // Store locally immediately
        powService.userVotedFor = playerName
        UserDefaults.standard.set(playerName, forKey: "pow_voted_for_\(pollId)")

        // Also persist to server (fire and forget)
        Task {
            try? await powService.castVote(
                pollId: pollId,
                voterName: playerName,
                voterEmail: "local-vote@runsbyip.app",
                votedForName: playerName
            )
        }
    }

    // MARK: - Winner Card

    @ViewBuilder
    private func winnerCard(poll: POWPoll) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "trophy.fill")
                    .foregroundColor(Color(hex: "FFD700"))
                    .font(.system(size: 18))

                Text("PLAYER OF THE WEEK")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(.appTextSecondary)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(poll.winnerName ?? "")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "FFD700"))

                if let votes = poll.winnerVotes {
                    Text("\(votes) vote\(votes == 1 ? "" : "s")")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.appTextSecondary)
                }
            }

            // Decorative stars
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "FFD700").opacity(Double(5 - i) / 5.0))
                }
            }
        }
        .padding(22)
        .background {
            ZStack {
                Color.appSurface
                LinearGradient(
                    colors: [Color(hex: "FFD700").opacity(0.05), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(hex: "FFD700").opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Dormant Card

    private var dormantCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "basketball.fill")
                .foregroundColor(.appTextTertiary)
                .font(.system(size: 16))

            Text("POW voting opens after the next session")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.appTextTertiary)

            Spacer()
        }
        .padding(18)
        .background(Color.appSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.appBorder.opacity(0.5), lineWidth: 1)
        )
    }
}

// MARK: - Player Chip

private struct PlayerChip: View {
    let name: String
    let voteCount: Int
    let isVotedFor: Bool
    let canVote: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            if canVote { onTap() }
        }) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isVotedFor ? .appAccentOrange : .white)
                    .lineLimit(1)

                if voteCount > 0 {
                    Text("\(voteCount)")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(.appAccentOrange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.appAccentOrange.opacity(0.15), in: Capsule())
                }

                if isVotedFor {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.appSuccess)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                isVotedFor
                    ? Color.appAccentOrange.opacity(0.12)
                    : Color.appSurfaceElevated,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(
                        isVotedFor ? Color.appAccentOrange.opacity(0.4) : Color.appBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canVote)
        .opacity(canVote || isVotedFor ? 1 : 0.5)
    }
}
