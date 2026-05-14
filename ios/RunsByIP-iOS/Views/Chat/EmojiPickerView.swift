import SwiftUI

/// Sheet-based emoji reaction picker. Tapping any emoji commits the
/// reaction and dismisses. Persists recently-used emojis to UserDefaults
/// across launches so the "Recent" row reflects the user's actual habits.
struct EmojiPickerView: View {
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: EmojiCategory = .smileys
    @State private var recents: [String] = EmojiPickerView.loadRecents()

    private static let recentsKey = "chat.emoji.recents"
    private static let recentsCap = 12

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !recents.isEmpty {
                        section(title: "Recent", emojis: recents)
                    }

                    section(title: "Popular", emojis: EmojiCatalog.popular)

                    section(title: selectedCategory.rawValue, emojis: selectedCategory.emojis)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                categoryBar
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.appAccentOrange)
                }
            }
            .navigationTitle("React")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.fraction(0.55), .large])
        .presentationDragIndicator(.visible)
    }

    private func section(title: String, emojis: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundColor(.appTextSecondary)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        commit(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 30))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var categoryBar: some View {
        HStack(spacing: 0) {
            ForEach(EmojiCategory.allCases) { category in
                Button {
                    selectedCategory = category
                } label: {
                    Image(systemName: category.systemIcon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(selectedCategory == category ? .appAccentOrange : .appTextSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.appSurface)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.appBorder), alignment: .top)
    }

    private func commit(_ emoji: String) {
        recents = ([emoji] + recents.filter { $0 != emoji }).prefix(Self.recentsCap).map { $0 }
        UserDefaults.standard.set(recents, forKey: Self.recentsKey)
        onPick(emoji)
        dismiss()
    }

    private static func loadRecents() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
    }
}
