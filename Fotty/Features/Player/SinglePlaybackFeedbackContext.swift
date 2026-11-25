import Foundation

/// Ephemeral, reviewed-report seed for the existing single-player owner. Keep
/// transport identities, URLs, headers and raw provider errors out of the draft.
struct SinglePlaybackFeedbackContext: Identifiable, Equatable {
    let id = UUID()
    let expected: String
    let actual: String

    @MainActor
    static func make(model: LivePlayerViewModel) -> Self? {
        guard model.usesSingleStreamRanking, model.viewingPlaybackContext == .single,
              !model.isPlaybackSessionRetired else { return nil }
        let details = model.playbackQualityDetails()
        let match = safeMatchTitle(model.event.displayTitle) ?? "the selected match"
        let source = safeProvider(details["source"]) ?? "Unknown source"
        let ordinal = Int(details["source_index"] ?? "").flatMap { (1...1_000).contains($0) ? $0 : nil }
        let stage = FottyPlaybackStage(rawValue: details["last_observed_stage"] ?? "")?.rawValue ?? "unknown"
        let delivery = model.isUsingWebEmbed ? "Web" : "Native"
        var context = [
            "Match: \(match)",
            "Source: \(source)\(ordinal.map { " (option \($0))" } ?? "")",
            "Player: \(delivery)",
            "State: \(ViewingPlaybackCopy.status(model))",
            "Last observed stage: \(stage)"
        ]
        if model.error != nil { context.append("Failure category: \(model.lastFailureKind.rawValue)") }
        return Self(expected: "Watch \(match) with working video, sound and controls.",
                    actual: context.joined(separator: "\n"))
    }

    private static func safeMatchTitle(_ proposed: String) -> String? {
        let value = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 240, value.utf8.count <= 960,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              value.range(of: #"(?i)(?:://|https?:|www\.|token=|authorization|bearer\s|cookie=|[?=&@])"#,
                          options: .regularExpression) == nil else { return nil }
        return value
    }

    private static func safeProvider(_ proposed: String?) -> String? {
        guard let value = proposed,
              value.count <= 40, !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        if CuratedStreamSourceCatalog.all.contains(where: { $0.matchesOpaqueLabel(value) }) { return value }
        guard value.range(of: #"^(?:Score808|VIPLeague|MethStreams|Cricfree|StrikeOut)(?:[ #]*[0-9]{1,3})?$"#,
                          options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return value
    }
}
