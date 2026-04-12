import Foundation

extension Date {
    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: self)
    }

    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: self)
    }

    var relativeTime: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)

        if interval < 0 {
            // Future date
            let futureInterval = -interval
            if futureInterval < 3600 {
                let minutes = Int(futureInterval / 60)
                return minutes <= 1 ? "in 1 minute" : "in \(minutes) minutes"
            } else if futureInterval < 86400 {
                let hours = Int(futureInterval / 3600)
                return hours == 1 ? "in 1 hour" : "in \(hours) hours"
            } else {
                let days = Int(futureInterval / 86400)
                return days == 1 ? "tomorrow" : "in \(days) days"
            }
        }

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if interval < 172800 {
            return "yesterday"
        } else {
            let days = Int(interval / 86400)
            return "\(days) days ago"
        }
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    var isFuture: Bool {
        self > Date()
    }
}
