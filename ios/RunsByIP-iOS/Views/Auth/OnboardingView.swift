import SwiftUI
import PhotosUI
import UIKit

struct OnboardingView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var notificationService: NotificationService
    @State private var currentPage = 0
    @State private var notificationGranted = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var displayName = ""
    @State private var bio = ""
    @State private var isSaving = false
    @State private var profileError: String?

    let onComplete: () -> Void

    private let totalPages = 5
    private let bioCharacterLimit = 160

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    howItWorksPage.tag(1)
                    notificationsPage.tag(2)
                    profileSetupPage.tag(3)
                    donePage.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // Dot indicators
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.appAccentOrange : Color.appBorder)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, AppSpacing.space24)

                // Navigation buttons
                if currentPage < totalPages - 1 && currentPage != 3 {
                    Button {
                        withAnimation { currentPage += 1 }
                    } label: {
                        Text(currentPage == 2 ? "NEXT" : "CONTINUE")
                            .font(.system(size: 15, weight: .black))
                            .tracking(1.2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.appAccentOrange)
                            .foregroundColor(.appBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppSpacing.space24)
                    .padding(.bottom, 40)
                } else if currentPage == totalPages - 1 {
                    Button {
                        completeOnboarding()
                    } label: {
                        Text("LET'S GO")
                            .font(.system(size: 15, weight: .black))
                            .tracking(1.2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.appAccentOrange)
                            .foregroundColor(.appBackground)
                            .clipShape(RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, AppSpacing.space24)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: AppSpacing.space24) {
            Spacer()

            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: .appAccentOrange.opacity(0.3), radius: 20, y: 8)

            VStack(spacing: 10) {
                Text("RunsByIP")
                    .font(.system(size: 38, weight: .black).width(.condensed))
                    .foregroundColor(.appTextPrimary)

                Text("Weekly pickup basketball in LA")
                    .font(.appBody)
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppSpacing.space32)
    }

    private var howItWorksPage: some View {
        VStack(spacing: AppSpacing.space32) {
            Spacer()

            Text("HOW IT WORKS")
                .font(.appMono)
                .tracking(1.6)
                .foregroundColor(.appTextSecondary)

            VStack(spacing: AppSpacing.space24) {
                OnboardingStep(number: "1", text: "RSVP & pay $10")
                OnboardingStep(number: "2", text: "Show up and hoop")
                OnboardingStep(number: "3", text: "Every Wednesday night")
            }

            Text("That's it. No fluff.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.appTextSecondary)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppSpacing.space32)
    }

    private var notificationsPage: some View {
        VStack(spacing: AppSpacing.space24) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 60))
                .foregroundColor(.appAccentOrange)

            VStack(spacing: 10) {
                Text("Stay in the loop")
                    .font(.appTitle)
                    .foregroundColor(.appTextPrimary)

                Text("Get notified when new sessions drop, spots open up, and the crew is chatting.")
                    .font(.appBody)
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.space16)
            }

            if !notificationGranted {
                Button {
                    requestNotifications()
                } label: {
                    HStack(spacing: AppSpacing.space8) {
                        Image(systemName: "bell.fill")
                        Text("ENABLE NOTIFICATIONS")
                            .font(.system(size: 13, weight: .black))
                            .tracking(1.0)
                    }
                    .padding(.horizontal, AppSpacing.space24)
                    .padding(.vertical, 14)
                    .background(Color.appSurfaceElevated)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: AppSpacing.space8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.appSuccess)
                    Text("Notifications enabled")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.appSuccess)
                }
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppSpacing.space32)
    }

    private var profileSetupPage: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.space24) {
                    Spacer().frame(height: 40)

                    VStack(spacing: 10) {
                        Text("Set up your profile")
                            .font(.appTitle)
                            .foregroundColor(.appTextPrimary)

                        Text("Add a photo and bio so the crew can recognize you.")
                            .font(.appBody)
                            .foregroundColor(.appTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.space16)
                    }

                    // Avatar picker
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            Group {
                                if let pendingImage {
                                    Image(uiImage: pendingImage)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    AvatarView(
                                        name: authService.currentProfile?.displayName ?? "Player",
                                        avatarUrl: authService.currentProfile?.avatarUrl,
                                        size: 110
                                    )
                                }
                            }
                            .frame(width: 110, height: 110)
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(Color.appBorder, lineWidth: 1)
                            )

                            Image(systemName: "camera.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.appAccentOrange)
                                .frame(width: 32, height: 32)
                                .background(Color.appSurfaceElevated, in: Circle())
                        }
                    }

                    // Name field (required)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Display Name")
                            .font(.appCaption)
                            .foregroundColor(.appTextSecondary)

                        TextField("Your name", text: $displayName)
                            .foregroundColor(.white)
                            .textContentType(.name)
                            .padding(14)
                            .background(Color.appSurfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius, style: .continuous))
                    }
                    .padding(.horizontal, AppSpacing.space8)

                    // Bio field
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Bio")
                                .font(.appCaption)
                                .foregroundColor(.appTextSecondary)
                            Spacer()
                            Text("\(bio.count)/\(bioCharacterLimit)")
                                .font(.appCaption)
                                .foregroundColor(.appTextSecondary)
                        }

                        TextField("Tell us about yourself", text: $bio, axis: .vertical)
                            .lineLimit(3...5)
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.appSurfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius, style: .continuous))
                            .onChange(of: bio) { _, newValue in
                                if newValue.count > bioCharacterLimit {
                                    bio = String(newValue.prefix(bioCharacterLimit))
                                }
                            }
                    }
                    .padding(.horizontal, AppSpacing.space8)

                    if let profileError {
                        HStack(spacing: AppSpacing.space8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.appError)
                            Text(profileError)
                                .font(.appCaption)
                                .foregroundColor(.white)
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(Color.appError.opacity(0.12), in: RoundedRectangle(cornerRadius: AppStyle.cornerRadius, style: .continuous))
                    }
                }
                .padding(.horizontal, AppSpacing.space24)
            }

            VStack(spacing: AppSpacing.space12) {
                Button {
                    saveProfileAndContinue()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(.appBackground)
                        } else {
                            Text("SAVE & CONTINUE")
                                .font(.system(size: 15, weight: .black))
                                .tracking(1.2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.appAccentOrange)
                    .foregroundColor(.appBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isSaving || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(displayName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)

                Button {
                    withAnimation { currentPage = 4 }
                } label: {
                    Text("Skip")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.appTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.space24)
            .padding(.bottom, 40)
        }
        .onAppear {
            if displayName.isEmpty {
                displayName = authService.currentProfile?.displayName
                    ?? authService.currentUser?.userMetadata["display_name"]?.stringValue
                    ?? ""
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    profileError = "Could not load image."
                    return
                }
                pendingImage = image
            }
        }
    }

    private var donePage: some View {
        VStack(spacing: AppSpacing.space24) {
            Spacer()

            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .appAccentOrange.opacity(0.3), radius: 16, y: 6)

            VStack(spacing: 10) {
                Text("You're in.")
                    .font(.system(size: 38, weight: .black).width(.condensed))
                    .foregroundColor(.appTextPrimary)

                Text("Let's hoop.")
                    .font(.system(size: 22, weight: .bold).width(.condensed))
                    .foregroundColor(.appAccentOrange)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppSpacing.space32)
    }

    // MARK: - Actions

    private func requestNotifications() {
        Task {
            let granted = await notificationService.requestPermission()
            await MainActor.run {
                notificationGranted = granted
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    private func saveProfileAndContinue() {
        isSaving = true
        profileError = nil

        Task {
            do {
                if let image = pendingImage,
                   let jpegData = image.jpegData(compressionQuality: 0.8) {
                    _ = try await authService.uploadAvatar(imageData: jpegData)
                    pendingImage = nil
                }

                let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
                try await authService.updateProfile(displayName: trimmedName, bio: trimmedBio)

                withAnimation { currentPage = 4 }
            } catch {
                profileError = error.localizedDescription
            }

            isSaving = false
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        onComplete()
    }
}

// MARK: - Onboarding Step

private struct OnboardingStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: AppSpacing.space16) {
            Text(number)
                .font(.system(size: 22, weight: .black).width(.condensed))
                .foregroundColor(.appAccentOrange)
                .frame(width: 44, height: 44)
                .background(Color.appSurface, in: Circle())
                .overlay(Circle().stroke(Color.appBorder, lineWidth: 1))

            Text(text)
                .font(.system(size: 20, weight: .bold).width(.condensed))
                .foregroundColor(.appTextPrimary)

            Spacer()
        }
    }
}
