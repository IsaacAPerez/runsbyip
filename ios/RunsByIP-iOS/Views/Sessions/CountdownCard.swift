import SwiftUI

struct CountdownCard: View {
    let session: GameSession
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var sessionDate: Date? {
        session.sessionDateTime
    }

    private var isLive: Bool {
        guard let start = sessionDate else { return false }
        // Session is "live" if it started within the last 2 hours
        let elapsed = now.timeIntervalSince(start)
        return elapsed >= 0 && elapsed < 7200
    }

    private var countdownComponents: (days: Int, hours: Int, minutes: Int, seconds: Int)? {
        guard let target = sessionDate else { return nil }
        let remaining = target.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        let total = Int(remaining)
        return (
            days: total / 86400,
            hours: (total % 86400) / 3600,
            minutes: (total % 3600) / 60,
            seconds: total % 60
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            // Orange accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.appAccentOrange)
                .frame(width: 4)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text("NEXT RUN")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1.6)
                        .foregroundColor(.appTextSecondary)

                    Spacer()

                    if isLive {
                        LiveBadge()
                    }
                }

                // Countdown or Live
                if isLive {
                    Text("HAPPENING NOW")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                } else if let c = countdownComponents {
                    HStack(spacing: 4) {
                        if c.days > 0 {
                            CountdownCardUnit(value: c.days, label: "d")
                        }
                        CountdownCardUnit(value: c.hours, label: "h")
                        CountdownCardUnit(value: c.minutes, label: "m")
                        CountdownCardUnit(value: c.seconds, label: "s")
                    }
                }

                // Session details
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.formattedDate)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))

                    HStack(spacing: 16) {
                        Label(session.time, systemImage: "clock.fill")
                        Label(session.location, systemImage: "mappin.and.ellipse")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.appTextSecondary)
                }
            }
            .padding(.leading, 18)
            .padding(.vertical, 4)
        }
        .padding(18)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        )
        .onReceive(timer) { _ in
            now = Date()
        }
    }
}

// MARK: - Countdown Unit

private struct CountdownCardUnit: View {
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 1) {
            Text("\(value)")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()

            Text(label)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.appAccentOrange)
                .padding(.top, 8)
        }
        .padding(.trailing, 6)
    }
}

// MARK: - Live Badge

private struct LiveBadge: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.appSuccess)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0.6 : 1.0)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            Text("LIVE NOW")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.0)
                .foregroundColor(.appSuccess)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.appSuccess.opacity(0.15), in: Capsule())
        .onAppear { isPulsing = true }
    }
}

// MARK: - Empty Countdown

struct EmptyCountdownCard: View {
    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.appBorder)
                .frame(width: 4)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 10) {
                Text("NEXT RUN")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundColor(.appTextSecondary)

                Text("No sessions scheduled")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.appTextSecondary)

                Text("Check back soon for the next run.")
                    .font(.system(size: 13))
                    .foregroundColor(.appTextTertiary)
            }
            .padding(.leading, 18)
        }
        .padding(18)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        )
    }
}
