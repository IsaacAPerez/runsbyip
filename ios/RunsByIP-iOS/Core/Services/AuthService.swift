import Foundation
import UIKit
import AuthenticationServices
import CryptoKit
@preconcurrency import Supabase
@preconcurrency import Auth

@MainActor
final class AuthService: ObservableObject {
    @Published var currentUser: User?
    @Published var currentProfile: UserProfile?
    @Published var isAdmin = false
    @Published var isLoading = true

    private var authStateTask: Task<Void, Never>?
    private var supabase: SupabaseClient { SupabaseService.shared.client }
    private var currentNonce: String?

    init() {
        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in supabase.auth.authStateChanges {
                switch event {
                case .initialSession, .signedIn:
                    self.currentUser = session?.user
                    if session?.user != nil {
                        await self.loadProfile()
                    }
                case .signedOut:
                    self.currentUser = nil
                    self.currentProfile = nil
                    self.isAdmin = false
                default:
                    break
                }
                self.isLoading = false
            }
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    // MARK: - Sign in with Apple

    func signInWithApple() async throws {
        let nonce = randomNonceString()
        currentNonce = nonce
        let hashedNonce = sha256(nonce)

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let result = try await performAppleSignIn(request: request)

        guard let appleIDCredential = result.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = appleIDCredential.identityToken,
              let tokenString = String(data: identityTokenData, encoding: .utf8) else {
            throw AppError.authError("Failed to get Apple ID token")
        }

        try await supabase.auth.signInWithIdToken(credentials: .init(
            provider: .apple,
            idToken: tokenString,
            nonce: nonce
        ))
    }

    private func performAppleSignIn(request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = AppleSignInDelegate(continuation: continuation)
            let presentationProvider = AppleSignInPresentationProvider()
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = delegate
            controller.presentationContextProvider = presentationProvider
            objc_setAssociatedObject(controller, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            objc_setAssociatedObject(controller, "presentationProvider", presentationProvider, .OBJC_ASSOCIATION_RETAIN)
            controller.performRequests()
        }
    }

    // MARK: - Sign in with Google (OAuth)

    func signInWithGoogle() async throws {
        try await supabase.auth.signInWithOAuth(
            provider: .google,
            redirectTo: URL(string: "runsbyip://auth/callback")
        )
    }

    func handleOAuthCallback(url: URL) async throws {
        try await supabase.auth.session(from: url)
    }

    // MARK: - Sign Out

    func signOut() async throws {
        do {
            try await supabase.auth.signOut()
            currentUser = nil
            currentProfile = nil
            isAdmin = false
        } catch {
            throw AppError.authError(error.localizedDescription)
        }
    }

    // MARK: - Profile

    func loadProfile() async {
        guard let userId = currentUser?.id else { return }
        let idKey = userId.uuidString.lowercased()
        do {
            let profile: UserProfile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: idKey)
                .single()
                .execute()
                .value
            currentProfile = profile
            isAdmin = profile.role == "admin"
        } catch {
            isAdmin = false
        }
    }

    func updateProfile(displayName: String, bio: String) async throws {
        guard let userId = currentUser?.id else { return }
        let idKey = userId.uuidString.lowercased()
        do {
            let updated: UserProfile = try await supabase
                .from("profiles")
                .update(["display_name": displayName, "bio": bio])
                .eq("id", value: idKey)
                .select()
                .single()
                .execute()
                .value
            currentProfile = updated

            // Also update auth metadata so display_name stays in sync
            try await supabase.auth.update(user: UserAttributes(data: ["display_name": AnyJSON.string(displayName)]))
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    func uploadAvatar(imageData: Data) async throws -> String {
        guard let userId = currentUser?.id else { throw AppError.unauthorized }
        let path = "\(userId.uuidString.lowercased())/avatar.jpg"

        do {
            try await supabase.storage
                .from("avatars")
                .upload(path, data: imageData, options: FileOptions(contentType: "image/jpeg", upsert: true))

            let publicURL = try supabase.storage
                .from("avatars")
                .getPublicURL(path: path)

            let urlString = publicURL.absoluteString

            let updated: UserProfile = try await supabase
                .from("profiles")
                .update(["avatar_url": urlString])
                .eq("id", value: userId.uuidString.lowercased())
                .select()
                .single()
                .execute()
                .value
            currentProfile = updated

            try await supabase.auth.update(user: UserAttributes(data: ["avatar_url": AnyJSON.string(urlString)]))

            return urlString
        } catch {
            throw AppError.networkError(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(errorCode == errSecSuccess)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Apple Sign In Presentation Provider

private class AppleSignInPresentationProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: \.isKeyWindow) else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Apple Sign In Delegate

private class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let continuation: CheckedContinuation<ASAuthorization, Error>

    init(continuation: CheckedContinuation<ASAuthorization, Error>) {
        self.continuation = continuation
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation.resume(returning: authorization)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation.resume(throwing: error)
    }
}
