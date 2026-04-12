import SwiftUI

struct BadgeView: View {
    let label: String
    let color: Color

    init(_ label: String, color: Color) {
        self.label = label
        self.color = color
    }

    static func forStatus(_ status: String) -> BadgeView {
        switch status.lowercased() {
        case "open":
            return BadgeView("Open", color: .appSuccess)
        case "confirmed":
            return BadgeView("Confirmed", color: .appAccentOrange)
        case "cancelled":
            return BadgeView("Cancelled", color: .appError)
        case "full":
            return BadgeView("Full", color: .appWarning)
        case "paid":
            return BadgeView("Paid", color: .appSuccess)
        case "cash":
            return BadgeView("Cash", color: .appSuccess)
        case "pending":
            return BadgeView("Pending", color: .appWarning)
        default:
            return BadgeView(status, color: .appTextSecondary)
        }
    }

    var body: some View {
        Text(label)
            .font(.caption.bold())
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .cornerRadius(AppStyle.badgeCornerRadius)
    }
}

#Preview {
    HStack {
        BadgeView.forStatus("open")
        BadgeView.forStatus("cancelled")
        BadgeView.forStatus("paid")
    }
    .padding()
    .background(Color.appBackground)
}
