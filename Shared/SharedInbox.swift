import Foundation

/// Hand-off between the Share extension and the app, stored in the shared App Group.
/// The extension can't write to the app's SwiftData store or open the importer itself,
/// so it leaves the shared item here and the app picks it up when it next becomes active.
struct SharedItem: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case link, text }

    var id = UUID()
    var kind: Kind
    var value: String
    var date = Date()
}

enum SharedInbox {
    static let groupID = "group.com.jorvanus.Ambit"
    private static let key = "pendingShares"
    private static let maxItems = 10
    static let maxTextLength = 100_000

    private static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    @discardableResult
    static func add(_ item: SharedItem) -> Bool {
        guard let defaults else { return false }
        var items = load(from: defaults)
        items.append(item)
        save(Array(items.suffix(maxItems)), to: defaults)
        return true
    }

    /// Returns and clears everything waiting, oldest first.
    static func takeAll() -> [SharedItem] {
        guard let defaults else { return [] }
        let items = load(from: defaults)
        if !items.isEmpty { defaults.removeObject(forKey: key) }
        return items
    }

    /// Classifies shared text: a lone http(s) URL is a link, anything else is itinerary text.
    static func item(forShared string: String) -> SharedItem? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if !trimmed.contains(where: \.isWhitespace), lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return SharedItem(kind: .link, value: trimmed)
        }
        return SharedItem(kind: .text, value: String(trimmed.prefix(maxTextLength)))
    }

    private static func load(from defaults: UserDefaults) -> [SharedItem] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SharedItem].self, from: data)) ?? []
    }

    private static func save(_ items: [SharedItem], to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
    }
}
