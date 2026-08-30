import Foundation

enum TeamFollowKey {
    static func make(name: String, category: String) -> String {
        let normalizedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        
        return "\(category)|\(normalizedName)"
    }
}
