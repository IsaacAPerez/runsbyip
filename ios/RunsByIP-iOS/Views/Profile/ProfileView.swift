import SwiftUI
import PhotosUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var notificationService: NotificationService

    @State private var isEditing = false
    @State private var editName = ""
    @State private var editBio = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingImage: UIImage?
    @State private var isSaving = false
    @State private var notificationsEnabled = false
    @State private var showSignOutConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var errorMessage: String?

    private let bioCharacterLimit = 160

    private var profile: UserProfile? { authService.currentProfile }

    private var displayName: String {
        profile?.displayName ?? authService.currentUser?.userMetadata["display_name"]?.stringValue ?? "Player"
    }

    private var email: String {
        profile?.email ?? authService.currentUser?.email ?? ""
    }

    private var memberSince: String {
        guard let createdAt = profile?.createdAt,
              let date = iso8601Date(from: createdAt) else { return "—" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    private var trimmedName: String {
        editName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedBio: String {
        String(editBio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(bioCharacterLimit))
    }

    private var canSaveProfile: Bool {
        !trimmedName.isEmpty && trimmedName.isValidDisplayName && trimmedBio.count <= bioCharacterLimit && !isSaving
    }

    private var hasAvatar: Bool {
        pendingImage != nil || !(profile?.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private var bioText: String? {
        let bio = profile?.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return bio.isEmpty ? nil : bio
    }

    private var versionText: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        profileHeaderCard
                            .padding(.horizontal)
                            .padding(.top, 12)

                        if let errorMessage {
                            errorBanner(errorMessage)
                                .padding(.horizontal)
                        }

                        if isEditing {
                            editCard
                                .padding(.horizontal)
                        }

                        settingsCard
                            .padding(.horizontal)

                        signOutButton
                            .padding(.horizontal)

                        deleteAccountButton
                            .padding(.horizontal)

                        Text("RunsByIP v\(versionText)")
                            .font(.caption)
                            .foregroundColor(.appTextSecondary)
                            .padding(.bottom, 24)
                    }
                }
            }
            .condensedNavTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSaving {
                        ProgressView().tint(.appAccentOrange)
                    } else if isEditing {
                        Button("Save") { saveProfile() }
                            .foregroundColor(canSaveProfile ? .appAccentOrange : .appTextSecondary)
                            .fontWeight(.semibold)
                            .disabled(!canSaveProfile)
                    } else {
                        Button("Edit") {
                            beginEditing()
                        }
                        .foregroundColor(.appAccentOrange)
                    }
                }

                if isEditing {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            cancelEditing()
                        }
                        .foregroundColor(.appTextSecondary)
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task { await loadPhotoLocally(item) }
            }
            .onChange(of: notificationsEnabled) { oldValue, enabled in
                guard enabled != oldValue else { return }

                if enabled {
                    Task {
                        let status = await notificationService.authorizationStatus()
                        if status == .notDetermined {
                            // First time — ask in-app
                            let granted = await notificationService.requestPermission()
                            if granted {
                                await MainActor.run {
                                    UIApplication.shared.registerForRemoteNotifications()
                                }
                            }
                            notificationsEnabled = granted
                        } else if status == .denied {
                            // Previously denied — must go to Settings
                            openSystemNotificationSettings()
                            // Re-check after returning from Settings
                            try? await Task.sleep(for: .seconds(1))
                            notificationsEnabled = await notificationService.authorizationGranted()
                        } else {
                            // Already authorized, just re-register
                            await MainActor.run {
                                UIApplication.shared.registerForRemoteNotifications()
                            }
                            notificationsEnabled = true
                        }
                    }
                } else {
                    // Can't revoke programmatically — send to Settings
                    openSystemNotificationSettings()
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        notificationsEnabled = await notificationService.authorizationGranted()
                    }
                }
            }
            .confirmationDialog("Sign Out?", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    Task { try? await authService.signOut() }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .confirmationDialog(
                "Delete Account?",
                isPresented: $showDeleteAccountConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Forever", role: .destructive) {
                    Task { await performAccountDeletion() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account, profile, chat messages, photos, and push notification settings. This action cannot be undone.")
            }
            .task {
                notificationsEnabled = await notificationService.authorizationGranted()
            }
        }
    }

    private var profileHeaderCard: some View {
        VStack(spacing: 20) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let pendingImage {
                        Image(uiImage: pendingImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        AvatarView(
                            name: displayName,
                            avatarUrl: profile?.avatarUrl,
                            size: 96
                        )
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.appBorder, lineWidth: 1)
                )

                if isEditing {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.appAccentOrange)
                            .frame(width: 32, height: 32)
                            .background(Color.appSurfaceElevated, in: Circle())
                    }
                }
            }

            VStack(spacing: 8) {
                Text(displayName)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                if !email.isEmpty {
                    Text(email)
                        .font(.subheadline)
                        .foregroundColor(.appTextSecondary)
                        .multilineTextAlignment(.center)
                }

                if let bioText {
                    Text(bioText)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }

            HStack(spacing: 12) {
                compactInfoPill(title: "Role", value: profile?.role.capitalized ?? "Member")
                compactInfoPill(title: "Member since", value: memberSince)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        )
    }

    private var editCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit profile")
                .font(.headline)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)

                TextField("Display name", text: $editName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .foregroundColor(.white)
                    .padding(14)
                    .background(Color.appSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Bio")
                        .font(.caption)
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Text("\(trimmedBio.count)/\(bioCharacterLimit)")
                        .font(.caption)
                        .foregroundColor(.appTextSecondary)
                }

                TextField("Add a short bio", text: $editBio, axis: .vertical)
                    .lineLimit(3...5)
                    .foregroundColor(.white)
                    .padding(14)
                    .background(Color.appSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: editBio) { _, newValue in
                        if newValue.count > bioCharacterLimit {
                            editBio = String(newValue.prefix(bioCharacterLimit))
                        }
                    }
            }

            Text("Name must be 2–50 characters. Photo uploads when you save.")
                .font(.caption)
                .foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        )
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
                .foregroundColor(.white)

            infoRow(title: "Email", value: email.isEmpty ? "No email available" : email, systemImage: "envelope.fill")

            Toggle(isOn: $notificationsEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notifications")
                        .foregroundColor(.white)
                        .font(.subheadline.bold())
                    Text(notificationsEnabled ? "Enabled for session updates and reminders." : "Turn on alerts so session updates do not slip by.")
                        .font(.caption)
                        .foregroundColor(.appTextSecondary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: .appTextSecondary))
            .padding(16)
            .background(Color.appSurfaceElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            infoRow(title: "Photo", value: hasAvatar ? "Added" : "Not added", systemImage: "person.crop.circle")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        )
    }

    private var signOutButton: some View {
        Button {
            showSignOutConfirm = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.appError)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.appError.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var deleteAccountButton: some View {
        VStack(spacing: 8) {
            Button {
                guard !isDeletingAccount else { return }
                errorMessage = nil
                showDeleteAccountConfirm = true
            } label: {
                HStack(spacing: 10) {
                    if isDeletingAccount {
                        ProgressView().tint(.appError)
                    } else {
                        Image(systemName: "trash")
                    }
                    Text(isDeletingAccount ? "Deleting…" : "Delete Account")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.appError)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.appError.opacity(0.6), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isDeletingAccount)

            Text("Permanently removes your account and all associated data.")
                .font(.caption2)
                .foregroundColor(.appTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    private func performAccountDeletion() async {
        isDeletingAccount = true
        errorMessage = nil
        defer { isDeletingAccount = false }

        do {
            try await authService.deleteAccount()
            // On success, AuthService clears its session — the root view
            // observer in AppRouter swaps the UI back to LoginView automatically.
        } catch {
            errorMessage = "Could not delete account: \(error.localizedDescription)"
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.appError)
            Text(message)
                .font(.caption)
                .foregroundColor(.white)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.appError.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appError.opacity(0.18), lineWidth: 1)
        )
    }

    private func compactInfoPill(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(.white)
            Text(title)
                .font(.caption)
                .foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(Color.appSurfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func infoRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundColor(.appAccentOrange)
                .frame(width: 36, height: 36)
                .background(Color.appAccentOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text(value)
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.appSurfaceElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func beginEditing() {
        editName = displayName
        editBio = profile?.bio ?? ""
        errorMessage = nil
        isEditing = true
    }

    private func cancelEditing() {
        isEditing = false
        pendingImage = nil
        selectedPhoto = nil
        errorMessage = nil
    }

    private func saveProfile() {
        guard trimmedName.isValidDisplayName else {
            errorMessage = "Name must be 2–50 characters."
            return
        }

        guard trimmedBio.count <= bioCharacterLimit else {
            errorMessage = "Bio must be \(bioCharacterLimit) characters or less."
            return
        }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                if let image = pendingImage,
                   let jpegData = image.jpegData(compressionQuality: 0.8) {
                    _ = try await authService.uploadAvatar(imageData: jpegData)
                    pendingImage = nil
                }

                try await authService.updateProfile(displayName: trimmedName, bio: trimmedBio)
                isEditing = false
            } catch {
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }

    private func loadPhotoLocally(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = "Could not load image."
            return
        }

        pendingImage = image
    }

    private func openSystemNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }

        UIApplication.shared.open(url)
    }

    private func iso8601Date(from value: String) -> Date? {
        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractionalSeconds.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthService())
        .environmentObject(NotificationService())
}
