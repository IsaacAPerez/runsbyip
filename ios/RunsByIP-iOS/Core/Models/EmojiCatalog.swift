import Foundation

/// Curated emoji set for the reaction picker. Not the full Unicode table —
/// we ship a focused list of what people actually use in chat reactions so
/// the picker is fast to load, easy to scan, and doesn't require a JSON
/// resource. ~180 emojis grouped into 8 tabs.
enum EmojiCategory: String, CaseIterable, Identifiable {
    case smileys = "Smileys"
    case people = "People"
    case sports = "Sports"
    case food = "Food"
    case activities = "Activities"
    case nature = "Nature"
    case objects = "Objects"
    case symbols = "Symbols"

    var id: String { rawValue }

    var systemIcon: String {
        switch self {
        case .smileys: return "face.smiling"
        case .people: return "person"
        case .sports: return "basketball"
        case .food: return "fork.knife"
        case .activities: return "party.popper"
        case .nature: return "leaf"
        case .objects: return "lightbulb"
        case .symbols: return "heart"
        }
    }

    var emojis: [String] {
        switch self {
        case .smileys:
            return ["😀","😂","🤣","😅","😊","😍","🥰","😘","😜","🤪","😎","🥳","🤩","🤔","😏","😬","😳","🥺","😭","😡","🤬","🤯","😱","🥶","🤢","🤮","😴","🤤","😇","🤠"]
        case .people:
            return ["👍","👎","👏","🙌","🙏","🤝","💪","🫡","🫶","🤞","👌","🤙","✌️","🤘","👋","🙋‍♂️","🙋‍♀️","💁","🙇","🧎","🚶","🏃","🕺","💃"]
        case .sports:
            return ["🏀","⛹️","🏆","🥇","🥈","🥉","🎯","🥅","🏟️","🤾","🏋️","🤸","🤺","⚽","🏈","⚾","🎾","🏐","🏉","🥏","🎱","🏓","🏸","🥊"]
        case .food:
            return ["🍕","🍔","🌭","🌮","🌯","🍟","🍗","🍖","🍣","🍜","🥗","🍦","🍩","🍪","🎂","🍰","🍫","🍿","🥤","☕","🍺","🍻","🥂","🍷","🧃","🥃"]
        case .activities:
            return ["🔥","💯","🎉","🎊","✨","⚡","💥","💫","🌟","⭐","🎁","🎈","🎵","🎶","🎤","🎮","🎰","🎲","🃏","🎬","📸","🎨"]
        case .nature:
            return ["🌞","🌝","🌚","🌙","🌎","🌊","🌈","☀️","⛅","🌧️","⛈️","🌩️","❄️","🌸","🌺","🌻","🌷","🌹","🌴","🌲","🍀","🌵","🪴","🐶","🐱","🦁","🐯","🐻","🐼"]
        case .objects:
            return ["💵","💸","💰","💎","👑","🏆","📱","💻","⌚","📷","🔋","💡","🔦","🛒","📦","✉️","📧","🔑","🔒","🛏️","🚗","✈️","🚀"]
        case .symbols:
            return ["❤️","🧡","💛","💚","💙","💜","🖤","🤍","💔","❣️","💕","💞","💓","💗","💖","💘","💝","☮️","✅","❌","❓","❗","‼️","⁉️","💤","💢","💦","🔇","🔊"]
        }
    }
}

enum EmojiCatalog {
    /// Curated "top reactions" row — surfaced first since they're what
    /// people use 95% of the time.
    static let popular: [String] = [
        "🔥", "😂", "🙌", "👀", "🏀", "💯", "❤️", "👍", "😍", "🎉"
    ]

    static func allCategories() -> [EmojiCategory] { EmojiCategory.allCases }
}
