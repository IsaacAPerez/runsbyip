import Foundation
@preconcurrency import Supabase

@MainActor
final class POWService: ObservableObject {
    @Published var currentPoll: POWPoll?
    @Published var tallies: [POWVoteTally] = []
    @Published var eligiblePlayers: [String] = []
    @Published var userVotedFor: String?

    private var supabase: SupabaseClient { SupabaseService.shared.client }

    // MARK: - Fetch Current Poll

    func fetchCurrentPoll() async throws {
        do {
            let results: [POWPoll] = try await supabase
                .from("current_pow")
                .select()
                .limit(1)
                .execute()
                .value

            currentPoll = results.first

            if let poll = results.first {
                if poll.isOpen {
                    try await fetchTallies()
                    try await fetchEligiblePlayers(sessionId: poll.sessionId)
                }
                checkUserVote()
            }
        } catch {
            // View that doesn't exist yet or no data — not a hard error
            currentPoll = nil
        }
    }

    // MARK: - Fetch Vote Tallies

    func fetchTallies() async throws {
        do {
            tallies = try await supabase
                .from("pow_vote_tallies")
                .select()
                .order("vote_count", ascending: false)
                .execute()
                .value
        } catch {
            tallies = []
        }
    }

    // MARK: - Fetch Eligible Players (paid RSVPs for the session)

    func fetchEligiblePlayers(sessionId: String) async throws {
        do {
            let rsvps: [RSVP] = try await supabase
                .from("rsvps")
                .select()
                .eq("session_id", value: sessionId)
                .in("payment_status", values: ["paid", "cash"])
                .order("player_name", ascending: true)
                .execute()
                .value

            eligiblePlayers = rsvps.map(\.playerName)
        } catch {
            eligiblePlayers = []
        }
    }

    // MARK: - Cast Vote

    func castVote(pollId: String, voterName: String, voterEmail: String, votedForName: String) async throws {
        struct VoteInsert: Encodable {
            let pollId: String
            let voterName: String
            let voterEmail: String
            let votedForName: String

            enum CodingKeys: String, CodingKey {
                case pollId = "poll_id"
                case voterName = "voter_name"
                case voterEmail = "voter_email"
                case votedForName = "voted_for_name"
            }
        }

        do {
            try await supabase
                .from("pow_votes")
                .insert(VoteInsert(
                    pollId: pollId,
                    voterName: voterName,
                    voterEmail: voterEmail,
                    votedForName: votedForName
                ))
                .execute()

            // Save voter info for next time
            UserDefaults.standard.set(voterName, forKey: "pow_voter_name")
            UserDefaults.standard.set(voterEmail, forKey: "pow_voter_email")
            userVotedFor = votedForName

            try await fetchTallies()
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    // MARK: - Check if user already voted

    private func checkUserVote() {
        // Check local storage first
        if let poll = currentPoll {
            if let localVote = UserDefaults.standard.string(forKey: "pow_voted_for_\(poll.id)") {
                userVotedFor = localVote
                return
            }
        }

        // Fall back to server check via email
        guard let email = UserDefaults.standard.string(forKey: "pow_voter_email"),
              !email.isEmpty else {
            userVotedFor = nil
            return
        }
        for tally in tallies {
            if tally.voterList.contains(where: { $0.localizedCaseInsensitiveCompare(email) == .orderedSame }) {
                userVotedFor = tally.votedForName
                return
            }
        }
        userVotedFor = nil
    }

    func checkUserVoteFromServer() async {
        guard let poll = currentPoll,
              let email = UserDefaults.standard.string(forKey: "pow_voter_email"),
              !email.isEmpty else {
            userVotedFor = nil
            return
        }

        do {
            let votes: [POWVote] = try await supabase
                .from("pow_votes")
                .select()
                .eq("poll_id", value: poll.id)
                .eq("voter_email", value: email)
                .limit(1)
                .execute()
                .value

            userVotedFor = votes.first?.votedForName
        } catch {
            // Silently fail
        }
    }
}
