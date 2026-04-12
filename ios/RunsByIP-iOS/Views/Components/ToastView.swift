import SwiftUI

enum ToastType {
    case success, error

    var color: Color {
        switch self {
        case .success: return .appSuccess
        case .error: return .appError
        }
    }

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

struct ToastView: View {
    let message: String
    let type: ToastType

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: type.icon)
                .foregroundColor(type.color)

            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.appSurfaceElevated.opacity(0.95))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .padding(.horizontal)
    }
}

#Preview {
    VStack(spacing: 20) {
        ToastView(message: "RSVP confirmed!", type: .success)
        ToastView(message: "Something went wrong", type: .error)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.appBackground)
}
