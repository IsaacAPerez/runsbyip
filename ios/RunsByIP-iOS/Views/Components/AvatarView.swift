import SwiftUI

struct AvatarView: View {
    let name: String
    let avatarUrl: String?
    let size: CGFloat

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        Group {
            if let urlString = avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(Color.appAccentOrange.opacity(0.2))
            Text(initials)
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundColor(.appAccentOrange)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        AvatarView(name: "Isaac Perez", avatarUrl: nil, size: 44)
        AvatarView(name: "John Doe", avatarUrl: nil, size: 32)
        AvatarView(name: "X", avatarUrl: nil, size: 60)
    }
    .padding()
    .background(Color.appBackground)
}
