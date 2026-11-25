import Foundation

/// Parses only the public calendar and player markup actually published by
/// Score808. A page is a candidate for one dated event, never a permanent feed.
enum Score808SiteCatalog {
    static let maximumDocumentBytes = 1_048_576
    static let maximumEvents = 1_000
    static let lookupLeadTime: TimeInterval = 30 * 60
    static let lookupTailTime: TimeInterval = 3 * 60 * 60
    static let kickoffTolerance: TimeInterval = 5 * 60

    static func widgetIDs(in html: String) -> [String] {
        guard html.utf8.count <= maximumDocumentBytes else { return [] }
        let markup = visibleMarkup(html)
        var seen = Set<String>()
        return matches(#"<[a-z][a-z0-9:-]*\b([^<>]*)>"#, in: markup).flatMap { tag in
            guard let attributes = attributes(in: tag[1]), let classes = attributes["class"] else {
                return [String]()
            }
            return classes.split(whereSeparator: \.isWhitespace).compactMap { token in
                let prefix = "elfsight-app-"
                guard token.hasPrefix(prefix) else { return nil }
                let id = String(token.dropFirst(prefix.count)).lowercased()
                guard isWidgetID(id), seen.insert(id).inserted else { return nil }
                return id
            }
        }
    }

    static func matchingWatchPage(
        in data: Data,
        widgetID: String,
        homeTeam: String,
        awayTeam: String,
        kickoff: Date,
        now: Date,
        registeredEventID: String? = nil
    ) -> URL? {
        guard data.count <= maximumDocumentBytes,
              isWidgetID(widgetID),
              now.timeIntervalSince(kickoff) >= -lookupLeadTime,
              now.timeIntervalSince(kickoff) <= lookupTailTime,
              let boot = try? JSONDecoder().decode(Boot.self, from: data),
              boot.status == 1,
              let widget = boot.data?.widgets[widgetID], widget.status == 1,
              let settings = widget.data?.settings,
              settings.selectedEventsProvider == "manual",
              settings.events.count <= maximumEvents else { return nil }

        let home = teamKey(homeTeam)
        let away = teamKey(awayTeam)
        guard !home.isEmpty, !away.isEmpty, home != away else { return nil }

        if let registeredEventID, !registeredEventID.hasPrefix("score808:" + widgetID + ":") { return nil }
        let current = settings.events.compactMap { currentEvent($0, at: now) }
        let matching = current.filter { event in
            guard registeredEventID.map({ $0 == "score808:" + widgetID + ":" + (event.id ?? "") }) ?? true,
                  abs(event.start.timeIntervalSince(kickoff)) <= kickoffTolerance,
                  let pair = teamPair(event.name) else { return false }
            return pair.0 == home && pair.1 == away
        }
        guard matching.count == 1, let selected = matching.first else { return nil }

        // The site reuses articles for successive broadcasts. If its calendar
        // assigns this page to two current events, we cannot identify its feed.
        guard current.filter({ pageIdentity($0.page) == pageIdentity(selected.page) }).count == 1 else {
            return nil
        }
        return selected.page
    }

    /// Only the two observed Score808 host spellings can become Watch pages.
    /// The transport must apply the same rule to the response's final URL.
    static func safeWatchPageURL(_ value: String) -> URL? {
        guard value.utf8.count <= 4_096,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.contains("\\"),
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              ["score808live.tv", "www.score808live.tv"].contains(host),
              components.user == nil, components.password == nil,
              components.port == nil,
              components.query == nil, components.fragment == nil,
              !components.path.isEmpty,
              let url = components.url else { return nil }
        return url
    }

    /// This proves the observed player structure, not decoded playback. Do not
    /// infer readiness from a generic HTML response, a script, or a JW shell.
    static func playerEvidence(in html: String) -> Bool {
        guard html.utf8.count <= maximumDocumentBytes else { return false }
        let markup = visibleMarkup(html)
        let text = markup.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
            .lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let unavailable = [
            "embedding disabled", "channel is unavailable", "stream is unavailable",
            "stream is not available", "stream not available", "broadcast is unavailable"
        ]
        guard !unavailable.contains(where: text.contains) else { return false }

        return matches(#"<video-js\b([^<>]*)>(.*?)</video-js\s*>"#, in: markup).contains { video in
            guard let attributes = attributes(in: video[1]),
                  attributes["id"] == "my-video",
                  let setup = attributes["data-setup"], setup.utf8.count <= 4_096,
                  let setupData = setup.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: setupData)) is [String: Any] else { return false }
            return matches(#"<source\b([^<>]*)/?>"#, in: video[2]).contains { source in
                guard let values = self.attributes(in: source[1]),
                      let sourceURL = values["src"],
                      let type = values["type"]?.lowercased(),
                      ["application/x-mpegurl", "application/vnd.apple.mpegurl"].contains(type),
                      let url = URLComponents(string: sourceURL),
                      url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
                      url.user == nil, url.password == nil, url.port == nil,
                      url.fragment == nil, url.path.lowercased().hasSuffix(".m3u8"),
                      url.url != nil else { return false }
                return true
            }
        }
    }

    private struct Boot: Decodable {
        let status: Int
        let data: BootData?
    }

    private struct BootData: Decodable { let widgets: [String: Widget] }
    private struct Widget: Decodable { let status: Int; let data: WidgetData? }
    private struct WidgetData: Decodable { let settings: Settings? }
    private struct Settings: Decodable {
        let selectedEventsProvider: String?
        let events: [Event]
    }
    private struct Event: Decodable {
        let id: String?
        let name: String?
        let start: EventDate?
        let end: EventDate?
        let timeZone: String?
        let visible: Bool?
        let repeatPeriod: String?
        let actions: [Action]?

        private enum CodingKeys: String, CodingKey { case id, name, start, end, timeZone, visible, repeatPeriod, actions }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            // Legacy calendar lookup did not depend on this field. An absent
            // or non-string ID cannot execute a registry link, but must not
            // invalidate a separately dated ordinary calendar lookup.
            id = try? values.decode(String.self, forKey: .id)
            name = try values.decodeIfPresent(String.self, forKey: .name)
            start = try values.decodeIfPresent(EventDate.self, forKey: .start)
            end = try values.decodeIfPresent(EventDate.self, forKey: .end)
            timeZone = try values.decodeIfPresent(String.self, forKey: .timeZone)
            // Elfsight's published event normalizer defaults an absent field to
            // true. Explicit null/false still fails the current-event guard;
            // malformed field types retain normal strict decoding rejection.
            visible = values.contains(.visible) ? try values.decodeIfPresent(Bool.self, forKey: .visible) : true
            repeatPeriod = try values.decodeIfPresent(String.self, forKey: .repeatPeriod)
            actions = try values.decodeIfPresent([Action].self, forKey: .actions)
        }
    }
    private struct EventDate: Decodable { let type: String?; let date: String?; let time: String? }
    private struct Action: Decodable {
        let type: String?
        let text: String?
        let primary: Bool?
        let link: Link?
    }
    private struct Link: Decodable { let type: String?; let value: String? }
    private struct CurrentEvent { let id: String?; let name: String; let start: Date; let page: URL }

    private static func currentEvent(_ event: Event, at now: Date) -> CurrentEvent? {
        guard event.visible == true, event.repeatPeriod == "noRepeat",
              let name = event.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.utf8.count <= 256,
              let zoneName = event.timeZone, TimeZone.knownTimeZoneIdentifiers.contains(zoneName),
              let zone = TimeZone(identifier: zoneName),
              let start = date(event.start, in: zone), let end = date(event.end, in: zone),
              end > start, end.timeIntervalSince(start) <= 4 * 60 * 60,
              now >= start.addingTimeInterval(-lookupLeadTime),
              now < end, now <= start.addingTimeInterval(lookupTailTime),
              let actions = event.actions, actions.count <= 10 else { return nil }
        let pages = actions.compactMap { action -> URL? in
            guard action.type == "link", action.primary == true,
                  action.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "watch now",
                  action.link?.type == "url", let value = action.link?.value else { return nil }
            return safeWatchPageURL(value)
        }
        guard pages.count == 1, let page = pages.first else { return nil }
        return CurrentEvent(id: event.id, name: name, start: start, page: page)
    }

    private static func date(_ value: EventDate?, in zone: TimeZone) -> Date? {
        guard let value, value.type == "datetime", let day = value.date, let time = value.time,
              day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              time.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let dateParts = day.split(separator: "-").compactMap { Int($0) }
        let timeParts = time.split(separator: ":").compactMap { Int($0) }
        guard dateParts.count == 3, timeParts.count == 2,
              (2000...2100).contains(dateParts[0]), (1...12).contains(dateParts[1]),
              (1...31).contains(dateParts[2]), (0...23).contains(timeParts[0]),
              (0...59).contains(timeParts[1]) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let requested = DateComponents(
            year: dateParts[0], month: dateParts[1], day: dateParts[2],
            hour: timeParts[0], minute: timeParts[1], second: 0
        )
        guard let result = calendar.date(from: requested) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: result)
        guard roundTrip.year == requested.year, roundTrip.month == requested.month,
              roundTrip.day == requested.day, roundTrip.hour == requested.hour,
              roundTrip.minute == requested.minute, roundTrip.second == requested.second else { return nil }
        return result
    }

    private static func teamPair(_ name: String) -> (String, String)? {
        let separators = matches(#"\s+(?:vs\.?|v\.?|versus)\s+"#, in: name)
        guard separators.count == 1 else { return nil }
        let parts = name.components(separatedBy: separators[0][0])
        guard parts.count == 2 else { return nil }
        let home = teamKey(parts[0]), away = teamKey(parts[1])
        guard !home.isEmpty, !away.isEmpty, home != away else { return nil }
        return (home, away)
    }

    private static func teamKey(_ value: String) -> String {
        if let known = FootballCompetitionCatalog.canonicalClubID(for: value) { return known }
        return value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.map { $0.lowercased() }.joined(separator: " ")
    }

    private static func pageIdentity(_ url: URL) -> String {
        // Both host spellings and a WordPress trailing slash address one page.
        url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func isWidgetID(_ value: String) -> Bool {
        value.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#, options: .regularExpression) != nil
    }

    private static func visibleMarkup(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<!--.*?(?:-->|$)|<(script|style)\b[^>]*>.*?(?:</\1\s*>|$)"#, with: "", options: .regularExpression)
    }

    private static func attributes(in tag: String) -> [String: String]? {
        let pairs = matches(#"([a-z_:][a-z0-9_.:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#, in: tag)
        var result: [String: String] = [:]
        for pair in pairs {
            let name = pair[1].lowercased()
            guard result[name] == nil, pair[4].isEmpty else { return nil }
            result[name] = pair[2].isEmpty ? pair[3] : pair[2]
        }
        return result
    }

    private static func matches(_ pattern: String, in input: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let source = input as NSString
        return regex.matches(in: input, range: NSRange(location: 0, length: source.length)).map { match in
            (0..<match.numberOfRanges).map { index in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : source.substring(with: range)
            }
        }
    }
}
