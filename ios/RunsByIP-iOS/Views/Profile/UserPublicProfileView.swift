import SwiftUI

struct UserPublicProfileView: View {
    @EnvironmentObject var chatService: ChatService
    @Environment(\.dismiss) var dismiss

    let userId: String
    let displayName: String
    let avatarUrl: String?

    @State private var profile: UserProfile?
    @State private var isLoading = true

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
                                Text(profile?.displayName ?? displayName)
                                    .font(.title2.bold())
                                    .foregroundColor(.white)

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
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
        isLoading = false
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
