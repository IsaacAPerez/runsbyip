import SwiftUI

struct LoadingView: View {
    var message: String?

    var body: some View {
        VStack(spacing: 16) {
            AppSpinner(size: .lg)

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.appTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
}

#Preview {
    LoadingView(message: "Loading sessions...")
}
