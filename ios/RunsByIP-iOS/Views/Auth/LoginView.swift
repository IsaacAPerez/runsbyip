import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var authService: AuthService

    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App icon + branding
                VStack(spacing: AppSpacing.space16) {
                    Image("AppIconImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    VStack(spacing: AppSpacing.space8) {
                        Text("RunsByIP")
                            .font(.appTitle)
                            .foregroundColor(.appTextPrimary)

                        Text("Weekly pickup basketball")
                            .font(.appBody)
                            .foregroundColor(.appTextSecondary)
                    }
                }

                Spacer()

                // Error message
                if let errorMessage {
                    Text(errorMessage)
                        .font(.appCaption)
                        .foregroundColor(.appError)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.space24)
                        .padding(.bottom, AppSpacing.space16)
                }

                // Sign-in buttons
                VStack(spacing: AppSpacing.space12) {
                    // Sign in with Apple
                    Button {
                        signInWithApple()
                    } label: {
                        HStack(spacing: AppSpacing.space8) {
                            if isLoading {
                                ProgressView()
                                    .tint(.appBackground)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 18, weight: .semibold))
                                Text("Sign in with Apple")
                                    .font(.system(size: 15, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius, style: .continuous))
                    }
                    .disabled(isLoading)

                    // Sign in with Google
                    Button {
                        signInWithGoogle()
                    } label: {
                        HStack(spacing: AppSpacing.space12) {
                            Image("GoogleLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Sign in with Google")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.appSurface)
                        .foregroundColor(.appTextPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius, style: .continuous)
                                .stroke(Color.appBorder, lineWidth: 1)
                        )
                    }
                    .disabled(isLoading)
                }
                .padding(.horizontal, AppSpacing.space24)

                Spacer().frame(height: 56)
            }
        }
    }

    private func signInWithApple() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.signInWithApple()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func signInWithGoogle() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await authService.signInWithGoogle()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService())
}
