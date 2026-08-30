import SwiftUI

// Hex color parser for SwiftUI
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 1)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

enum TeamColorResolver {
    static let teamColors: [String: Color] = [
        // National teams
        "argentina": Color(hex: "#74acdf"),
        "egypt": Color(hex: "#ce1126"),
        "switzerland": Color(hex: "#da291c"),
        "colombia": Color(hex: "#fcd116"),
        "france": Color(hex: "#002395"),
        "morocco": Color(hex: "#c1272d"),
        "mexico": Color(hex: "#006847"),
        "south africa": Color(hex: "#007a4d"),
        "south korea": Color(hex: "#cd1125"),
        "korea": Color(hex: "#cd1125"),
        "czech": Color(hex: "#11457e"),
        "canada": Color(hex: "#ff0000"),
        "bosnia": Color(hex: "#002f6c"),
        "usa": Color(hex: "#002868"),
        "united states": Color(hex: "#002868"),
        "netherlands": Color(hex: "#ff4f00"),
        "belgium": Color(hex: "#e30613"),
        "brazil": Color(hex: "#ffdf00"),
        "germany": Color(hex: "#ffffff"),
        "england": Color(hex: "#ce1124"),
        "italy": Color(hex: "#113a5d"),
        "spain": Color(hex: "#c60b1e"),
        "portugal": Color(hex: "#ff0000"),
        "croatia": Color(hex: "#ff0000"),
        "uruguay": Color(hex: "#0081c6"),
        "japan": Color(hex: "#bc002d"),
        "australia": Color(hex: "#00008b"),

        // Clubs
        "arsenal": Color(hex: "#ef0107"),
        "chelsea": Color(hex: "#034694"),
        "barcelona": Color(hex: "#004d98"),
        "real madrid": Color(hex: "#8a9bb8"),
        "liverpool": Color(hex: "#c8102e"),
        "manchester united": Color(hex: "#da291c"),
        "manchester city": Color(hex: "#6cabdd"),
        "bayern munich": Color(hex: "#dc052d"),
        "juventus": Color(hex: "#7d7d7d"),
        "inter milan": Color(hex: "#0068a8"),
        "tottenham": Color(hex: "#132257"),
        "paris saint-germain": Color(hex: "#002F6C"),
        "psg": Color(hex: "#002F6C"),
        "dortmund": Color(hex: "#FDE100"),
        "milan": Color(hex: "#E30613"),
        "ac milan": Color(hex: "#E30613"),
        "atletico madrid": Color(hex: "#CB3524"),
        "ajax": Color(hex: "#D2122E")
    ]

    private static var resolvedCache: [String: Color] = [:]
    private static let lock = NSLock()

    static func resolve(teamName: String) -> Color? {
        let name = teamName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        lock.lock()
        if let cached = resolvedCache[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        for (key, color) in teamColors {
            if name.contains(key) {
                lock.lock()
                resolvedCache[name] = color
                lock.unlock()
                return color
            }
        }
        
        // Deterministic fallback: Hash the name to generate a consistent, vibrant color (HSL style)
        var hash: UInt64 = 5381
        for char in name.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(char)
        }
        
        // Map hash to a hue value between 0.0 and 1.0
        let hue = Double(hash % 360) / 360.0
        let color = Color(hue: hue, saturation: 0.85, brightness: 0.95)
        lock.lock()
        resolvedCache[name] = color
        lock.unlock()
        return color
    }
}
