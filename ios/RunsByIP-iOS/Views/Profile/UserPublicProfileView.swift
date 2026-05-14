import SwiftUI

struct UserPublicProfileView: View {
    @EnvironmentObject var chatService: ChatService
    @EnvironmentObject var powService: POWService
    @Environment(\.dismiss) var dismiss

    let userId: String
    let displayName: String
    let avatarUrl: String?

    @State private var profile: UserProfile?
    @State private var isLoading = true
    @State private var powWins: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if isLoading {
                    LoadingView(message: "Loading profile...")
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Avatar
                            AvatarView(
                                name: profile?.displayName ?? displayName,
                                avatarUrl: profile?.avatarUrl ?? avatarUrl,
                                size: 96
                            )
                            .padding(.top, 24)

                            // Name + Bio
                            VStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    Text(profile?.displayName ?? displayName)
                                        .font(.title2.bold())
                                        .foregroundColor(.white)
                                    if powWins > 0 {
                                        TrophyBadge(wins: powWins)
                                    }
                                }

                                if let bio = profile?.bio, !bio.isEmpty {
                                    Text(bio)
                                        .font(.subheadline)
                                        .foregroundColor(.appTextSecondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 32)
                                }
                            }

                            Divider()
                                .background(Color.appBorder)
                                .padding(.horizontal)

                            // Stats row
                            HStack(spacing: 0) {
                                StatPill(label: "POW wins", value: "\(powWins)")
                                Divider()
                                    .frame(height: 32)
                                    .background(Color.appBorder)
                                StatPill(label: "Role", value: profile?.role.capitalized ?? "Member")
                                Divider()
                                    .frame(height: 32)
                                    .background(Color.appBorder)
                                StatPill(label: "Member since", value: memberSince)
                            }
                            .background(Color.appSurface)
                            .cornerRadius(AppStyle.cardCornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppStyle.cardCornerRadius)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            )
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .condensedNavTitle("Profile")
                        .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.appAccentOrange)
                }
            }
            .task {
                await loadProfile()
            }
        }
    }

    private var memberSince: String {
        guard let createdAt = profile?.createdAt else { return "—" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: createdAt) else { return "—" }
        let display = DateFormatter()
        display.dateFormat = "MMM yyyy"
        return display.string(from: date)
    }

    private func loadProfile() async {
        do {
            profile = try await chatService.fetchProfile(userId: userId)
        } catch {
            // Fall back to what we already know
            profile = UserProfile(id: userId, email: nil, displayName: displayName, bio: nil, avatarUrl: avatarUrl, role: "member", createdAt: nil)
        }
        let nameForWins = profile?.displayName ?? displayName
        if !nameForWins.isEmpty {
            powWins = await powService.fetchWinCount(forDisplayName: nameForWins)
        }
        isLoading = false
    }
}

// MARK: - Trophy badge (POW wins)

struct TrophyBadge: View {
    let wins: Int

    var body: some View {
        HStack(spacing: 3) {
            Text("🏆")
                .font(.system(size: 13))
            if wins > 1 {
                Text("\(wins)")
                    .font(.system(size: 11, weight: .heavy).width(.condensed))
                    .foregroundColor(.appAccentOrange)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.appAccentOrange.opacity(0.18), in: Capsule())
        .overlay(Capsule().stroke(Color.appAccentOrange.opacity(0.45), lineWidth: 1))
    }
}

// MARK: - Stat Pill

private struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(.white)
            Text(label)
                .font(.caption)
                .foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
