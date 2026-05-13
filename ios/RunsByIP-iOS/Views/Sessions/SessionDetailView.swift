import SwiftUI

struct SessionDetailView: View {
    @EnvironmentObject var sessionService: SessionService
    @EnvironmentObject var appConfig: AppConfigService

    let session: GameSession

    private var discountCents: Int { appConfig.iosDiscountCents }
    private var effectivePrice: String { session.effectivePriceDisplay(iosDiscountCents: discountCents) }
    private var hasDiscount: Bool { discountCents > 0 && session.effectivePriceCents(iosDiscountCents: discountCents) < session.priceCents }

    @State private var rsvps: [RSVP] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showRSVP = false

    // Every row in `rsvps` is a confirmed (paid) attendee.
    private var confirmed: [RSVP] { rsvps }
    private var isFull: Bool { confirmed.count >= session.maxPlayers }

    private var headerBadgeStatus: String {
        if session.isCancelled { return "cancelled" }
        if session.isCompleted { return "completed" }
        if isFull { return "full" }
        return session.effectiveStatus
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if isLoading {
                LoadingView(message: "Loading details...")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Session Info
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(session.formattedDate)
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                Spacer()
                                BadgeView.forStatus(headerBadgeStatus)
                            }

                            HStack(spacing: 16) {
                                Label(session.time, systemImage: "clock")
                                Label(session.location, systemImage: "mappin")
                            }
                            .font(.subheadline)
                            .foregroundColor(.appTextSecondary)

                            HStack(spacing: 8) {
                                if hasDiscount {
                                    Text(session.priceDisplay)
                                        .font(.subheadline)
                                        .foregroundColor(.appTextTertiary)
                                        .strikethrough()
                                }
                                Text("\(effectivePrice) per player")
                                    .font(.subheadline.bold())
                                    .foregroundColor(.appAccentOrange)
                            }
                            if hasDiscount {
                                Text("Save \((session.priceCents - session.effectivePriceCents(iosDiscountCents: discountCents)).currencyDisplay) in app")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.appSuccess)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.appSuccess.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding()
                        .background(Color.appSurface)
                        .cornerRadius(AppStyle.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppStyle.cardCornerRadius)
                                .stroke(Color.appBorder, lineWidth: 1)
                        )

                        // Confirmed Players
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Players (\(confirmed.count)/\(session.maxPlayers))")
                                .font(.headline)
                                .foregroundColor(.white)

                            if confirmed.isEmpty {
                                Text("No confirmed players yet")
                                    .font(.subheadline)
                                    .foregroundColor(.appTextSecondary)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(confirmed) { rsvp in
                                    PlayerRowView(name: rsvp.playerName)
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

                        if session.isCompleted {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Run completed")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                Text("This session is in the past and no longer accepts RSVPs.")
                                    .font(.subheadline)
                                    .foregroundColor(.appTextSecondary)
                            }
                            .padding()
                            .background(Color.appSurface)
                            .cornerRadius(AppStyle.cardCornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppStyle.cardCornerRadius)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            )
                        } else if isFull {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("All spots taken")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                Text("This run has reached capacity.")
                                    .font(.subheadline)
                                    .foregroundColor(.appTextSecondary)
                            }
                            .padding()
                            .background(Color.appSurface)
                            .cornerRadius(AppStyle.cardCornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppStyle.cardCornerRadius)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            )
                        }

                        // RSVP Button
                        if !session.isCancelled && !session.isCompleted && !isFull {
                            Button {
                                showRSVP = true
                            } label: {
                                Text("RSVP & Pay")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.appAccentOrange)
                                    .foregroundColor(.appBackground)
                                    .cornerRadius(AppStyle.buttonCornerRadius)
                            }
                        }
                    }
                    .padding()
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
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRSVP) {
            RSVPView(session: session)
        }
        .task {
            await loadRSVPs()
        }
    }

    private func loadRSVPs() async {
        isLoading = true
        errorMessage = nil

        do {
            rsvps = try await sessionService.fetchRSVPs(for: session.id)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(session: GameSession(
            id: "1",
            date: "2026-03-28",
            time: "6:00 PM",
            location: "Pan Pacific Park",
            priceCents: 0,
            minPlayers: 10,
            maxPlayers: 15,
            status: "open",
            paymentsOpen: false,
            createdAt: ""
        ))
        .environmentObject(SessionService())
    }
}
