import SwiftUI

struct PlayerRowView: View {
    let name: String
    let status: String

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.appAccentOrange.opacity(0.2))
                    .frame(width: 40, height: 40)

                Text(initials)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.appAccentOrange)
            }

            Text(name)
                .font(.body)
                .foregroundColor(.white)

            Spacer()

            BadgeView.forStatus(status)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack {
        PlayerRowView(name: "Isaac Perez", status: "paid")
        PlayerRowView(name: "John Doe", status: "pending")
    }
    .padding()
    .background(Color.appBackground)
}
