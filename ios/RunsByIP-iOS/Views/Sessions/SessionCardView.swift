import SwiftUI

struct SessionCardView: View {
    let session: GameSession
    var rsvpCount: Int = 0
    var onRSVP: (() -> Void)?

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var sessionDate: Date? { session.sessionDateTime }
    private var weekday: String { session.formattedWeekday }
    private var shortDate: String { session.formattedMonthDay }

    private var countdown: (days: Int, hours: Int, minutes: Int, seconds: Int)? {
        guard let target = sessionDate, target > now else { return nil }
        let diff = Calendar.current.dateComponents([.day, .hour, .minute, .second], from: now, to: target)
        return (diff.day ?? 0, diff.hour ?? 0, diff.minute ?? 0, diff.second ?? 0)
    }

    private var isFull: Bool { rsvpCount >= session.maxPlayers }
    private var isCancelled: Bool { session.isCancelled }

    private var displayStatus: String {
        if isCancelled { return "cancelled" }
        if isFull { return "full" }
        return session.status
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Leading accent bar
            Rectangle()
                .fill(Color.appAccentOrange)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 16) {
                // Header: Date + Status
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(weekday)
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.5)
                            .foregroundColor(.appTextSecondary)

                        Text(shortDate)
                            .font(.system(size: 32, weight: .black))
                            .foregroundColor(.white)

                        Text(session.time)
                            .font(.subheadline)
                            .foregroundColor(.appTextSecondary)
                    }

                    Spacer()

                    BadgeView.forStatus(displayStatus)
                }

                // Location
                HStack(spacing: 6) {
                    Image(systemName: "mappin")
                        .foregroundColor(.appTextSecondary)
                    Text(session.location)
                        .font(.subheadline)
                        .foregroundColor(.appTextSecondary)
                }

                // RSVP Progress
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(rsvpCount)/\(session.maxPlayers) players")
                            .font(.caption)
                            .foregroundColor(.appTextSecondary)
                        Spacer()
                        Text(session.priceDisplay)
                            .font(.caption.bold())
                            .foregroundColor(.appAccentOrange)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.appBorder)
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.appAccentOrange)
                                .frame(
                                    width: geo.size.width * CGFloat(min(rsvpCount, session.maxPlayers)) / CGFloat(max(session.maxPlayers, 1)),
                                    height: 4
                                )
                        }
                    }
                    .frame(height: 4)
                }

                // Countdown
                if let cd = countdown {
                    HStack(spacing: 4) {
                        Text("\(String(format: "%dD", cd.days))")
                            .foregroundColor(.white)
                        Text("\(String(format: "%dH", cd.hours))")
                            .foregroundColor(.white)
                        Text("\(String(format: "%02dM", cd.minutes))")
                            .foregroundColor(.white)
                        Text("\(String(format: "%02dS", cd.seconds))")
                            .foregroundColor(.appAccentOrange)
                    }
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                }

                // Action Button
                if isCancelled {
                    // No button for cancelled sessions
                } else if isFull {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ALL SPOTS TAKEN")
                            .font(.system(size: 15, weight: .black))
                            .tracking(2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundColor(.appTextSecondary)
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.appBorder, lineWidth: 1.5)
                            )

                        Text("This run is currently full.")
                            .font(.caption)
                            .foregroundColor(.appTextSecondary)
                    }
                } else {
                    Button {
                        onRSVP?()
                    } label: {
                        Text("RSVP & PAY \(session.priceDisplay)")
                            .font(.system(size: 15, weight: .black))
                            .tracking(2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.appAccentOrange)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
            .padding(20)
        }
        .background(Color.appSurface)
        .cornerRadius(10)
        .onReceive(timer) { _ in
            now = Date()
        }
    }
}

struct CountdownUnit: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.bold().monospacedDigit())
                .foregroundColor(.white)
            Text(label)
                .font(.caption2)
                .foregroundColor(.appTextSecondary)
        }
    }
}

#Preview {
    SessionCardView(
        session: GameSession(
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
        ),
        rsvpCount: 8
    )
    .padding()
    .background(Color.appBackground)
}
