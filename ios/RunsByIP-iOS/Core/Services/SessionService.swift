import Foundation
@preconcurrency import Supabase
import Realtime

@MainActor
final class SessionService: ObservableObject {
    @Published var currentSession: GameSession?
    @Published var sessions: [GameSession] = []
    @Published var currentSessionRSVPCount: Int = 0

    private var supabase: SupabaseClient { SupabaseService.shared.client }
    private let jsonDecoder = JSONDecoder()
    private var sessionChannel: RealtimeChannelV2?
    private var rsvpChannel: RealtimeChannelV2?

    // MARK: - Sessions

    func fetchCurrentSession() async throws {
        do {
            // Use local timezone for date comparison (not UTC) so evening sessions aren't skipped
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            let today = formatter.string(from: Date())
            let results: [GameSession] = try await supabase
                .from("sessions")
                .select()
                .neq("status", value: "cancelled")
                .gte("date", value: String(today))
                .order("date", ascending: true)
                .limit(1)
                .execute()
                .value

            currentSession = results.first

            if let sessionId = results.first?.id {
                currentSessionRSVPCount = try await fetchPaidRSVPCount(for: sessionId)
            } else {
                currentSessionRSVPCount = 0
            }
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    func fetchAllSessions() async throws {
        do {
            sessions = try await supabase
                .from("sessions")
                .select()
                .order("date", ascending: false)
                .execute()
                .value
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    func cancelSession(id: String) async throws {
        do {
            try await supabase
                .from("sessions")
                .update(["status": "cancelled"])
                .eq("id", value: id)
                .execute()
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    // MARK: - RSVPs

    func fetchRSVPs(for sessionId: String) async throws -> [RSVP] {
        do {
            return try await supabase
                .from("rsvps")
                .select()
                .eq("session_id", value: sessionId)
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    func fetchPaidRSVPCount(for sessionId: String) async throws -> Int {
        do {
            let rsvps: [RSVP] = try await supabase
                .from("rsvps")
                .select()
                .eq("session_id", value: sessionId)
                .in("payment_status", values: ["paid", "cash"])
                .execute()
                .value
            return rsvps.count
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    // MARK: - Checkout

    func createCheckout(sessionId: String, playerName: String, playerEmail: String) async throws -> String {
        do {
            struct CheckoutRequest: Encodable {
                let sessionId: String
                let playerName: String
                let playerEmail: String

                enum CodingKeys: String, CodingKey {
                    case sessionId = "session_id"
                    case playerName = "player_name"
                    case playerEmail = "player_email"
                }
            }

            struct CheckoutResponse: Decodable {
                let clientSecret: String

                enum CodingKeys: String, CodingKey {
                    case clientSecret = "client_secret"
                }
            }

            let response: CheckoutResponse = try await supabase.functions
                .invoke(
                    "create-checkout",
                    options: .init(body: CheckoutRequest(
                        sessionId: sessionId,
                        playerName: playerName,
                        playerEmail: playerEmail
                    ))
                )

            return response.clientSecret
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    // MARK: - Leaderboard

    func fetchLeaderboard() async throws -> [LeaderboardEntry] {
        do {
            let rsvps: [RSVP] = try await supabase
                .from("rsvps")
                .select()
                .in("payment_status", values: ["paid", "cash"])
                .execute()
                .value

            var counts: [String: Int] = [:]
            for rsvp in rsvps {
                counts[rsvp.playerName, default: 0] += 1
            }

            return counts.map { LeaderboardEntry(playerName: $0.key, gameCount: $0.value) }
                .sorted { $0.gameCount > $1.gameCount }
                .prefix(8)
                .map { $0 }
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    // MARK: - Toggle Payments

    func togglePayments(sessionId: String, open: Bool) async throws {
        do {
            try await supabase
                .from("sessions")
                .update(["payments_open": open])
                .eq("id", value: sessionId)
                .execute()
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    // MARK: - Real-time Subscriptions

    func subscribeToCurrentSession() {
        unsubscribe()
        guard let sessionId = currentSession?.id else { return }

        sessionChannel = supabase.realtimeV2.channel("session-changes")
        guard let sessionChannel else { return }

        let updates = sessionChannel.postgresChange(UpdateAction.self, table: "sessions")

        Task { [weak self] in
            for await update in updates {
                guard let self else { return }
                if let session = try? update.decodeRecord(as: GameSession.self, decoder: jsonDecoder),
                   session.id == sessionId {
                    self.currentSession = session
                }
            }
        }

        Task { try? await sessionChannel.subscribeWithError() }

        rsvpChannel = supabase.realtimeV2.channel("rsvps-changes")
        guard let rsvpChannel else { return }

        let rsvpInserts = rsvpChannel.postgresChange(InsertAction.self, table: "rsvps")
        let rsvpUpdates = rsvpChannel.postgresChange(UpdateAction.self, table: "rsvps")

        Task { [weak self] in
            for await _ in rsvpInserts {
                guard let self, let id = self.currentSession?.id else { continue }
                self.currentSessionRSVPCount = (try? await self.fetchPaidRSVPCount(for: id)) ?? self.currentSessionRSVPCount
            }
        }

        Task { [weak self] in
            for await _ in rsvpUpdates {
                guard let self, let id = self.currentSession?.id else { continue }
                self.currentSessionRSVPCount = (try? await self.fetchPaidRSVPCount(for: id)) ?? self.currentSessionRSVPCount
            }
        }

        Task { try? await rsvpChannel.subscribeWithError() }
    }

    func unsubscribe() {
        Task {
            await sessionChannel?.unsubscribe()
            await rsvpChannel?.unsubscribe()
            sessionChannel = nil
            rsvpChannel = nil
        }
    }

    // MARK: - Create Session

    func createSession(date: String, time: String, location: String, maxPlayers: Int, priceCents: Int) async throws {
        struct NewSession: Encodable {
            let date: String
            let time: String
            let location: String
            let maxPlayers: Int
            let priceCents: Int
            let status: String

            enum CodingKeys: String, CodingKey {
                case date, time, location, status
                case maxPlayers = "max_players"
                case priceCents = "price_cents"
            }
        }

        do {
            try await supabase
                .from("sessions")
                .insert(NewSession(
                    date: date,
                    time: time,
                    location: location,
                    maxPlayers: maxPlayers,
                    priceCents: priceCents,
                    status: "open"
                ))
                .execute()
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }
}
