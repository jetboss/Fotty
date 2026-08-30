import Foundation

enum MatchCardFormatting {
    /// Compact club label for dense cards without dropping to a single word.
    static func compactTeamName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let known: [String: String] = [
            "manchester united": "Man United",
            "manchester city": "Man City",
            "tottenham hotspur": "Spurs",
            "nottingham forest": "Nott'm Forest",
            "wolverhampton wanderers": "Wolves",
            "brighton & hove albion": "Brighton",
            "brighton hove albion": "Brighton",
            "west ham united": "West Ham",
            "newcastle united": "Newcastle",
            "leicester city": "Leicester",
            "sheffield wednesday": "Sheff Wed",
            "sheffield united": "Sheff Utd",
            "west bromwich albion": "West Brom",
            "queens park rangers": "QPR",
            "atletico madrid": "Atlético",
            "athletic club": "Athletic",
            "paris saint germain": "PSG",
            "paris saint-germain": "PSG",
            "bayern munich": "Bayern",
            "borussia dortmund": "Dortmund",
            "inter milan": "Inter",
            "ac milan": "Milan",
            "independiente santa fe": "Santa Fe",
            "athletico paranaense": "Athletico-PR"
        ]

        if let short = known[trimmed.lowercased()] {
            return short
        }

        var result = trimmed
        let suffixes = [" FC", " CF", " SC", " AFC", " FC.", " C.F."]
        for suffix in suffixes where result.uppercased().hasSuffix(suffix.uppercased()) {
            result = String(result.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }

        // Unknown clubs keep their identity; the view wraps instead of inventing initials.
        return result
    }

    /// Tighter label for two-column fixture rows. Hero and discovery surfaces
    /// keep `compactTeamName`, which preserves more of the club's full name.
    static func denseTeamName(_ name: String) -> String {
        compactTeamName(name)
    }
}
