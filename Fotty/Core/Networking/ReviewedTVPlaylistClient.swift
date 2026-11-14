import Foundation
import CryptoKit

/// Reviewed channel identities and public-playlist provenance. A channel's
/// presence never identifies its current match; fixtures need current typed
/// registry authority before the selected delivery can be resolved.
actor ReviewedTVPlaylistClient {
    static let shared = ReviewedTVPlaylistClient()
    nonisolated static let providerCode = "reviewedtv"
    nonisolated static let playlistURL = URL(string: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/us.m3u")!
    nonisolated static let englishPlaylistURL = URL(string: "https://raw.githubusercontent.com/doms9/iptv/default/M3U8/base.m3u8")!
    nonisolated static let ukPlaylistURL = URL(string: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/uk.m3u")!
    nonisolated static let australianPlaylistURL = URL(string: "https://raw.githubusercontent.com/iptv-org/iptv/master/streams/au.m3u")!
    nonisolated static let zillaLGPlaylistURL = URL(string: "https://raw.githubusercontent.com/abusaeeidx/IPTV-Scraper-Zilla/main/LGTV.m3u")!
    // Keep the established Willow names and TV1 binding compatible.
    nonisolated static let channelIdentifier = "Willow.us@SD"
    nonisolated static let providerEventID = "reviewed-tv:willow-main"
    nonisolated static let foxGuideStreamID = "reviewed-tv:fox-cricket-guide"
    nonisolated static let maximumBytes = 1_024 * 1_024
    private static let revision = "tv-channels-m3u-7"

    struct ChannelDefinition: Equatable, Sendable {
        let playlistIdentifier: String
        let playlistURL: URL
        let deliveryPath: String?
        let playbackUserAgent: String?
        let channelID: String
        let streamID: String
        let providerName: String
        let displayName: String
        let commentaryLanguage: CommentaryPreference
        let allowedDeliveryHosts: Set<String>
        // NBC's public playlist declares one fixed advertising channel ID.
        // Preserve it exactly: no tracking IDs, credentials, arbitrary query
        // fields, duplicate parameters or stripping the publisher's contract.
        var reviewedPlaylistQuery: String? {
            providerName == "TV9" ? "ads.xumo_channelId=99993008" : nil
        }
        let sports: Set<String>
        let markets: Set<String>
        fileprivate let playlistLabels: Set<String>
    }

    nonisolated static let channels: [ChannelDefinition] = [
        .init(playlistIdentifier: channelIdentifier, playlistURL: playlistURL, deliveryPath: nil, playbackUserAgent: nil, channelID: CricketBroadcastChannel.willow.canonicalID,
              streamID: providerEventID, providerName: "TV1", displayName: "Willow Cricket", commentaryLanguage: .english,
              allowedDeliveryHosts: ["tvsen5.aynaott.com"], sports: ["cricket"], markets: ["US"], playlistLabels: ["Willow"]),
        espn(1, identifier: "ESPNLatinAmerica.us@South", markets: ["PE", "BO", "PY", "UY"]),
        espn(2, identifier: "ESPN2LatinAmerica.us@South", markets: ["BO", "PY", "PE", "UY"]),
        espn(3, identifier: "ESPN3LatinAmerica.us@South", markets: ["BO", "CL", "CO", "EC", "PY", "UY", "VE"]),
        espn(4, identifier: "ESPN4LatinAmerica.us@South", markets: ["BO", "CO", "EC", "PY", "PE", "UY", "VE"]),
        espn(5, identifier: "ESPN5LatinAmerica.us@South", markets: ["BO", "CO", "EC", "PY", "PE", "UY", "VE"]),
        espn(6, identifier: "ESPN6LatinAmerica.us@SD", markets: ["BO", "CO", "EC", "PY", "PE", "UY", "VE", "DO", "BZ", "CR", "GT", "HN", "NI", "PA", "SV"]),
        espn(7, identifier: "ESPN7LatinAmerica.us@SD", markets: ["BO", "CO", "EC", "PY", "PE", "UY", "VE"]),
        .init(playlistIdentifier: "NBCSportsNOW.us@SD", playlistURL: playlistURL, deliveryPath: nil, playbackUserAgent: nil, channelID: "sports-channel:nbc-sports-now",
              streamID: "reviewed-tv:nbc-sports-now", providerName: "TV9", displayName: "NBC Sports NOW", commentaryLanguage: .english,
              allowedDeliveryHosts: ["d4whmvwm0rdvi.cloudfront.net"], sports: ["other"], markets: ["US"], playlistLabels: ["NBC Sports NOW"]),
        .init(playlistIdentifier: "SkySp.Cricket.uk", playlistURL: englishPlaylistURL,
              deliveryPath: "/secure/api/v1/6add40ae2d4a99e07363c860/playlist.m3u8", playbackUserAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36",
              channelID: "sports-channel:sky-sports-cricket", streamID: "reviewed-tv:sky-sports-cricket", providerName: "TV10",
              displayName: "Sky Sports Cricket", commentaryLanguage: .english,
              allowedDeliveryHosts: ["cdnlivetv.tv"], sports: ["cricket"],
              markets: ["GB"], playlistLabels: ["Sky Sports Cricket"]),
        .init(playlistIdentifier: "SkySp.Fball.uk", playlistURL: englishPlaylistURL,
              deliveryPath: "/secure/api/v1/6add40ae2d4a99e07363c88c/playlist.m3u8", playbackUserAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36",
              channelID: "sports-channel:sky-sports-football", streamID: "reviewed-tv:sky-sports-football", providerName: "TV11",
              displayName: "Sky Sports Football", commentaryLanguage: .english,
              allowedDeliveryHosts: ["cdnlivetv.tv"], sports: ["football"],
              markets: ["GB"], playlistLabels: ["Sky Sports Football"]),
        .init(playlistIdentifier: "TNT.Sports.1.HD.uk", playlistURL: englishPlaylistURL,
              deliveryPath: "/secure/api/v1/6add40ae2d4a99e07363c88f/playlist.m3u8", playbackUserAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36",
              channelID: "sports-channel:tnt-sports-1", streamID: "reviewed-tv:tnt-sports-1", providerName: "TV12",
              displayName: "TNT Sports 1", commentaryLanguage: .english,
              allowedDeliveryHosts: ["cdnlivetv.tv"], sports: ["football"],
              markets: ["GB"], playlistLabels: ["TNT Sports 1"]),
        .init(playlistIdentifier: "TNT.Sports.2.HD.uk", playlistURL: englishPlaylistURL,
              deliveryPath: "/secure/api/v1/6add40ae2d4a99e07363c892/playlist.m3u8", playbackUserAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36",
              channelID: "sports-channel:tnt-sports-2", streamID: "reviewed-tv:tnt-sports-2", providerName: "TV13",
              displayName: "TNT Sports 2", commentaryLanguage: .english,
              allowedDeliveryHosts: ["cdnlivetv.tv"], sports: ["football"],
              markets: ["GB"], playlistLabels: ["TNT Sports 2"]),
        .init(playlistIdentifier: "TNT.Sports.3.HD.uk", playlistURL: englishPlaylistURL,
              deliveryPath: "/secure/api/v1/6add40ae2d4a99e07363c897/playlist.m3u8", playbackUserAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36",
              channelID: "sports-channel:tnt-sports-3", streamID: "reviewed-tv:tnt-sports-3", providerName: "TV14",
              displayName: "TNT Sports 3", commentaryLanguage: .english,
              allowedDeliveryHosts: ["cdnlivetv.tv"], sports: ["football"],
              markets: ["GB"], playlistLabels: ["TNT Sports 3"]),
        .init(playlistIdentifier: "USA.Network.HD.us2", playlistURL: englishPlaylistURL,
              deliveryPath: "/dbbcY6NG/index.m3u8", playbackUserAgent: nil,
              channelID: "sports-channel:usa-network", streamID: "reviewed-tv:usa-network", providerName: "TV15",
              displayName: "USA Network", commentaryLanguage: .english,
              allowedDeliveryHosts: ["tvsen3.aynaott.com"], sports: ["football"],
              markets: ["US"], playlistLabels: ["USA Network"]),
        .init(playlistIdentifier: "beINSPORTSXTRA.us@SD", playlistURL: playlistURL,
              deliveryPath: "/playlist.m3u8", playbackUserAgent: nil,
              channelID: "sports-channel:bein-sports-xtra", streamID: "reviewed-tv:bein-sports-xtra", providerName: "TV17",
              displayName: "beIN SPORTS XTRA", commentaryLanguage: .english,
              allowedDeliveryHosts: ["bein-xtra-bein.amagi.tv"], sports: ["football"],
              markets: ["US"], playlistLabels: ["beIN SPORTS XTRA"]),
        .init(playlistIdentifier: "FIFAPlus.uk@English", playlistURL: ukPlaylistURL,
              deliveryPath: "/master/f36d25e7e52f1ba8d7e56eb859c636563214f541/UmFrdXRlblRWLWV1X0ZJRkFQbHVzRW5nbGlzaF9ITFM/playlist.m3u8", playbackUserAgent: nil,
              channelID: "sports-channel:fifa-plus", streamID: "reviewed-tv:fifa-plus", providerName: "TV21",
              displayName: "FIFA+", commentaryLanguage: .english, allowedDeliveryHosts: ["a62dad94.wurl.com"],
              sports: ["football"], markets: ["GB"], playlistLabels: ["FIFA+"]),
        .init(playlistIdentifier: "FIFAPlusWomen.uk@English", playlistURL: ukPlaylistURL,
              deliveryPath: "/master/f36d25e7e52f1ba8d7e56eb859c636563214f541/U2Ftc3VuZy1nYl9GSUZBUGx1c3dvbWVuX0hMUw/playlist.m3u8", playbackUserAgent: nil,
              channelID: "sports-channel:fifa-plus-women", streamID: "reviewed-tv:fifa-plus-women", providerName: "TV22",
              displayName: "FIFA+ Women", commentaryLanguage: .english, allowedDeliveryHosts: ["cffda8ff.wurl.com"],
              sports: ["football"], markets: ["GB"], playlistLabels: ["FIFA+ Women"]),
        .init(playlistIdentifier: "CricketGold.au@SD", playlistURL: australianPlaylistURL,
              deliveryPath: "/ptnr-yupptv/title-cricketgold/v1/master/611d79b11b77e2f571934fd80ca1413453772ac7/b2048bb8-1686-4432-aa50-647245383e0c/manifest.m3u8", playbackUserAgent: nil,
              channelID: "sports-channel:cricket-gold", streamID: "reviewed-tv:cricket-gold", providerName: "TV23",
              displayName: "Cricket Gold", commentaryLanguage: .english, allowedDeliveryHosts: ["streams2.sofast.tv"],
              sports: ["cricket"], markets: ["AU"], playlistLabels: ["Cricket Gold"]),
        .init(playlistIdentifier: "FoxSports1.us@HD", playlistURL: playlistURL,
              deliveryPath: "/foxsports1/index.m3u8", playbackUserAgent: nil,
              channelID: "sports-channel:fox-sports-1-us", streamID: "reviewed-tv:fox-sports-1-us", providerName: "TV24",
              displayName: "Fox Sports 1", commentaryLanguage: .english, allowedDeliveryHosts: ["tvsen7.aynascope.net"],
              sports: ["football", "baseball", "basketball"], markets: ["US"], playlistLabels: ["Fox Sports 1"]),
        tenies("Sky Sports Premier League", slug: "sky-sports-premier-league", provider: "TV25", pathID: "6add40ae2d4a99e07363c888"),
        tenies("TNT Sports 4", slug: "tnt-sports-4", provider: "TV26", pathID: "6add40ae2d4a99e07363c89b"),
        .init(playlistIdentifier: "24.7.Dummy.us", playlistURL: zillaLGPlaylistURL,
              deliveryPath: "/master/f36d25e7e52f1ba8d7e56eb859c636563214f541/TEdfRnVib1Nwb3J0c05ldHdvcmtfSExT/playlist.m3u8", playbackUserAgent: nil,
              channelID: "sports-channel:fubo-sports", streamID: "reviewed-tv:fubo-sports", providerName: "TV27",
              displayName: "Fubo Sports", commentaryLanguage: .english, allowedDeliveryHosts: ["ad993ce7.wurl.com"],
              sports: ["other"], markets: ["US"], playlistLabels: ["460 Fubo Sports"]),
    ]

    private nonisolated static func tenies(_ name: String, slug: String, provider: String, pathID: String) -> ChannelDefinition {
        let label = name + " FHD UK"
        let resource = "tenies-spacelivetv:" + label.replacingOccurrences(of: " ", with: "%20") + ":"
        let endpoint = URL(string: "https://live-addon-rust.vercel.app/stream/tv/")!
            .appendingPathComponent(resource + ".json")
        return .init(playlistIdentifier: resource, playlistURL: endpoint,
                     deliveryPath: "/secure/api/v1/" + pathID + "/playlist.m3u8", playbackUserAgent: nil,
                     channelID: "sports-channel:" + slug, streamID: "reviewed-tv:" + slug,
                     providerName: provider, displayName: name, commentaryLanguage: .english,
                     allowedDeliveryHosts: ["cdnlivetv.tv"], sports: ["football"], markets: ["GB"], playlistLabels: [label])
    }

    private nonisolated static let teniesHeaders = ["Referer": "https://cdnlivetv.tv/", "Origin": "https://cdnlivetv.tv"]
    private nonisolated static func isTenies(_ url: URL) -> Bool {
        url.host == "live-addon-rust.vercel.app" && channels.contains { $0.playlistURL == url }
    }

    private struct Delivery {
        let url: URL
        let headers: [String: String]
    }

    private struct ChannelDeliveries {
        var ledger = StreamAdmissionLedger()
        private(set) var offers: [Delivery] = []
        private var seen: Set<StreamDeliveryIdentity> = []
        var failure: CommunitySportsAddonError = .matchNotFound

        mutating func reject(_ reason: String) {
            ledger.record(reason)
            failure = .unsafeResponse
        }
        mutating func append(_ url: URL, headers: [String: String]) {
            guard seen.insert(.init(url: url, headers: headers)).inserted else { ledger.record("duplicate"); return }
            guard offers.count < StreamDeliveryPolicy.maximumSessionsPerProvider else { ledger.record("limit"); return }
            offers.append(.init(url: url, headers: headers))
        }
        func first() throws -> URL {
            guard let offer = offers.first else { throw failure }
            return offer.url
        }
    }

    private struct JSONDelivery: Decodable {
        let headers: [String: String]?
        let requiresDRM: Bool
        init(from decoder: Decoder) throws {
            headers = try? StreamDeliveryPolicy.decodeRequestHeaders(from: decoder)
            requiresDRM = StreamDeliveryPolicy.decodeRequiresDRM(from: decoder)
        }
    }

    private nonisolated static func defaultHeaders(for channel: ChannelDefinition) -> [String: String] {
        isTenies(channel.playlistURL) ? teniesHeaders : channel.playbackUserAgent.map { ["User-Agent": $0] } ?? [:]
    }

    private nonisolated static func deliveryHeaders(_ requested: [String: String], channel: ChannelDefinition) -> [String: String]? {
        guard let supplied = StreamDeliveryPolicy.requestHeaders(requested) else { return nil }
        return defaultHeaders(for: channel).merging(supplied) { _, advertised in advertised }
    }

    private nonisolated static func teniesDeliveries(_ data: Data, channel: ChannelDefinition) throws -> ChannelDeliveries {
        guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = document["streams"] as? [Any] else { throw CommunitySportsAddonError.unsafeResponse }
        var result = ChannelDeliveries()
        // This endpoint declares one station. Every returned row belongs in
        // its receipt, including malformed or mismatched rows.
        result.ledger.observe(streams.count)
        for row in streams {
            guard let stream = row as? [String: Any] else { result.reject("malformed"); continue }
            guard let title = stream["title"] as? String, channel.playlistLabels.contains(title) else {
                result.reject("filtered"); continue
            }
            guard let bytes = try? JSONSerialization.data(withJSONObject: stream),
                  let decoded = try? JSONDecoder().decode(JSONDelivery.self, from: bytes) else { result.reject("malformed"); continue }
            guard !decoded.requiresDRM else { result.reject("drm"); continue }
            guard let requested = decoded.headers else { result.reject("malformed_headers"); continue }
            if let reason = StreamDeliveryPolicy.headerRejection(requested) { result.reject(reason); continue }
            guard let headers = deliveryHeaders(requested, channel: channel) else { result.reject("malformed_headers"); continue }
            guard let raw = stream["url"] as? String else { result.reject("no_url"); continue }
            guard let url = URL(string: raw) else { result.reject("malformed"); continue }
            if let rejection = StreamDeliveryPolicy.rejection(url) { result.reject(rejection); continue }
            result.append(url, headers: headers)
        }
        return result
    }

    private nonisolated static func espn(_ number: Int, identifier: String, markets: Set<String>) -> ChannelDefinition {
        let name = number == 1 ? "ESPN" : "ESPN\(number)"
        let key = number == 1 ? "espn-latinamerica-south" : "espn\(number)-latinamerica-south"
        let label = number == 1 ? "ESPN Latin America" : "ESPN \(number) Latin America"
        return .init(playlistIdentifier: identifier, playlistURL: playlistURL, deliveryPath: nil, playbackUserAgent: nil, channelID: "sports-channel:" + key,
            streamID: "reviewed-tv:" + key, providerName: "TV\(number + 1)", displayName: name + " South", commentaryLanguage: .spanish,
            allowedDeliveryHosts: ["barinaslive1.boldmss.com"], sports: ["football", "baseball", "hockey"], markets: markets,
            playlistLabels: [label])
    }

    nonisolated static func channel(forChannelID id: String) -> ChannelDefinition? { channels.first { $0.channelID == id } }
    nonisolated static func channel(forStreamID id: String) -> ChannelDefinition? { channels.first { $0.streamID == id } }
    nonisolated static func channel(forProviderName name: String) -> ChannelDefinition? { channels.first { $0.providerName == name } }

    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    typealias ValidateDestination = @Sendable (URL) async throws -> Void
    typealias Enablement = @Sendable () async -> Bool
    typealias CurrentFixture = @Sendable (StreamPlaybackRequest, Date) async -> StreamPlaybackRequest?
    typealias ProgrammeMatches = @Sendable (StreamPlaybackRequest, Date) async -> [BroadcastRegistryMatch]
    private let fetch: Fetch
    private let validateDestination: ValidateDestination
    private let qualityStore: FottyQualityStore

    init(fetch: Fetch? = nil, validateDestination: ValidateDestination? = nil, qualityStore: FottyQualityStore = .shared) {
        self.qualityStore = qualityStore
        self.validateDestination = validateDestination ?? { try await LocalStreamProxyDestinationValidator.validate($0) }
        if let fetch { self.fetch = fetch }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            configuration.httpShouldSetCookies = false
            configuration.waitsForConnectivity = false
            let client = FottyBoundedHTTPClient(configuration: configuration)
            self.fetch = { request in
                let result = try await client.fetch(request, maximumBytes: Self.maximumBytes,
                    deadline: 8, acceptedStatusCodes: [200], redirectPolicy: { _, _ in false })
                return (result.data, result.http)
            }
        }
    }

    /// Fixed reviewed channel transport only. This supplies no fixture identity,
    /// programme claim, source toggle or new Watch path. Physical diagnostics
    /// can qualify the real adapter before a relevant live assignment exists.
    func channelDelivery(forProviderName name: String) async throws -> URL {
        guard let channel = Self.channel(forProviderName: name) else { throw CommunitySportsAddonError.matchNotFound }
        let data = try await readPlaylist(from: channel.playlistURL)
        let delivery = try Self.delivery(from: data, playlistURL: channel.playlistURL, channel: channel)
        try await validateDestination(delivery)
        try Task.checkCancellation()
        return delivery
    }

    private func readPlaylist(from playlistURL: URL = ReviewedTVPlaylistClient.playlistURL, checkAuthorization: () async throws -> Void = {}) async throws -> Data {
        try Task.checkCancellation()
        guard [Self.playlistURL, Self.englishPlaylistURL, Self.ukPlaylistURL, Self.australianPlaylistURL, Self.zillaLGPlaylistURL].contains(playlistURL) || Self.isTenies(playlistURL) else { throw CommunitySportsAddonError.unsafeResponse }
        try await validateDestination(playlistURL)
        var query = URLRequest(url: playlistURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        query.httpShouldHandleCookies = false
        query.setValue(Self.isTenies(playlistURL) ? "application/json" : "text/plain, application/vnd.apple.mpegurl", forHTTPHeaderField: "Accept")
        try await checkAuthorization()
        try Task.checkCancellation()
        let (data, response) = try await fetch(query)
        try Task.checkCancellation()
        guard response.statusCode == 200, response.url == playlistURL,
              (Self.isTenies(playlistURL) ? ["application/json"] : ["text/plain", "application/vnd.apple.mpegurl", "application/x-mpegurl", "application/octet-stream"])
                .contains(response.mimeType?.lowercased() ?? "") else { throw CommunitySportsAddonError.unsafeResponse }
        return data
    }

    /// A tune reads one fresh reviewed playlist for all independently admitted
    /// channel choices. A bad/missing sibling cannot erase a valid delivery.
    func resolve(for request: StreamPlaybackRequest, now: Date = Date(),
                 isEnabled: Enablement = { await StreamPluginRegistry.shared.enabledProviderCodes().contains(ReviewedTVPlaylistClient.providerCode) },
                 currentFixture: CurrentFixture = { request, at in
                     await MainActor.run { RegisteredDescriptorRecoveryPolicy.currentRequest(for: request,
                         in: MatchListViewModel.shared.playbackAdmissionCatalog, at: at) }
                 },
                 programmeMatches: ProgrammeMatches = { request, at in
                     await BroadcastRegistryClient.shared.lookup(for: request,
                         enabledProviderCodes: [ReviewedTVPlaylistClient.providerCode], at: at)
                 }) async throws -> [StreamSession] {
        let started = Date()
        var ledger = StreamAdmissionLedger(), fetchFailures = 0
        var admitted = 0, completion = "failed"
        defer {
            if Task.isCancelled { completion = "cancelled" }
            ledger.finish(admitted: admitted, completion: completion)
            qualityStore.recordStreamAdmission(sourceFamily: Self.providerCode, ledger: ledger,
                completion: completion, fetchFailures: fetchFailures)
        }
        let television = SportsTVStation.identifying(request)
        if television != nil, !(await isEnabled()) { throw CommunitySportsAddonError.matchNotFound }
        let requests: [StreamPlaybackRequest]
        if Self.supports(request, at: now) {
            requests = [request]
        } else {
            guard request.registryMatch == nil, CricketBroadcastChannel.identifying(request: request) == nil,
                  await isEnabled(), let current = await currentFixture(request, now) else {
                throw CommunitySportsAddonError.matchNotFound
            }
            requests = Self.lookupRequests(for: current, matches: await programmeMatches(current, now), at: now)
            guard !requests.isEmpty else { throw CommunitySportsAddonError.matchNotFound }
        }
        let hasAssociations = requests.contains { $0.registryMatch != nil }
        let requiresEnablement = hasAssociations || television != nil
        if requiresEnablement {
            guard await isEnabled() else { throw CommunitySportsAddonError.conflictingMatch }
        }
        var accepted: [StreamPlaybackRequest] = []
        for scoped in requests {
            if let association = scoped.registryMatch {
                guard let current = await currentFixture(scoped, now),
                      Self.programmeAssociation(for: current.usingRegistryMatch(association), at: now) != nil else { continue }
                accepted.append(current.usingRegistryMatch(association))
            } else { accepted.append(scoped) }
        }
        guard !accepted.isEmpty else { throw CommunitySportsAddonError.conflictingMatch }
        var playlistCache: [URL: Data] = [:]
        var resolved: [(StreamPlaybackRequest, StreamSession)] = []
        var firstFailure: Error?
        for scoped in accepted {
            var enumerated = false
            do {
                guard let channel = Self.selectedChannel(for: scoped, at: now) else { throw CommunitySportsAddonError.conflictingMatch }
                let data: Data
                if let cached = playlistCache[channel.playlistURL] { data = cached }
                else {
                    data = try await readPlaylist(from: channel.playlistURL) {
                        if requiresEnablement, !(await isEnabled()) { throw CommunitySportsAddonError.conflictingMatch }
                    }
                    playlistCache[channel.playlistURL] = data
                }
                let deliveries = try Self.deliveries(from: data, playlistURL: channel.playlistURL, channel: channel)
                enumerated = true
                ledger.observe(deliveries.ledger.offered)
                for (reason, count) in deliveries.ledger.dispositions { ledger.record(reason, count: count) }
                guard !deliveries.offers.isEmpty else { throw deliveries.failure }
                var validated: [Delivery] = []
                for delivery in deliveries.offers {
                    try Task.checkCancellation()
                    do {
                        try await validateDestination(delivery.url)
                        validated.append(delivery)
                    } catch {
                        try Task.checkCancellation()
                        ledger.record("validation")
                        if firstFailure == nil { firstFailure = error }
                    }
                }
                try Task.checkCancellation()
                let completedAt = now.addingTimeInterval(max(0, Date().timeIntervalSince(started)))
                let current: StreamPlaybackRequest
                if let association = scoped.registryMatch {
                    guard await isEnabled(), let fixture = await currentFixture(scoped, completedAt),
                          Self.programmeAssociation(for: fixture.usingRegistryMatch(association), at: completedAt) != nil else {
                        ledger.record("fixture_changed", count: validated.count)
                        throw CommunitySportsAddonError.conflictingMatch
                    }
                    current = fixture.usingRegistryMatch(association)
                } else { current = scoped }
                for delivery in validated {
                    resolved.append((current, try Self.session(for: current, delivery: delivery.url,
                        at: now, hasAlternatives: deliveries.offers.count > 1, requiredHeaders: delivery.headers)))
                    ledger.record("admitted")
                }
            } catch {
                if error is CancellationError || (error as? URLError)?.code == .cancelled { completion = "cancelled"; throw error }
                try Task.checkCancellation()
                if !enumerated, (error as? CommunitySportsAddonError) != .conflictingMatch,
                   (error as? CommunitySportsAddonError) != .matchNotFound { fetchFailures += 1 }
                if firstFailure == nil { firstFailure = error }
            }
        }
        if hasAssociations {
            guard await isEnabled() else { throw CommunitySportsAddonError.conflictingMatch }
            let completedAt = now.addingTimeInterval(max(0, Date().timeIntervalSince(started)))
            var currentResults: [(StreamPlaybackRequest, StreamSession)] = []
            for (scoped, session) in resolved {
                guard let association = scoped.registryMatch, let current = await currentFixture(scoped, completedAt),
                      Self.programmeAssociation(for: current.usingRegistryMatch(association), at: completedAt) != nil,
                      session.eventBinding?.matches(request: current.usingRegistryMatch(association), providerCode: Self.providerCode, at: completedAt) == true else { continue }
                currentResults.append((current.usingRegistryMatch(association), session))
            }
            resolved = currentResults
        }
        guard !resolved.isEmpty else { throw firstFailure ?? CommunitySportsAddonError.matchNotFound }
        if requiresEnablement, !(await isEnabled()) { throw CommunitySportsAddonError.conflictingMatch }
        try Task.checkCancellation()
        admitted = resolved.count
        completion = fetchFailures > 0 || firstFailure != nil ? "partial" : ledger.dispositions["limit", default: 0] > 0 ? "limited" : "complete"
        return resolved.map { $0.1 }
    }

    /// Renewal rechecks the selected channel and current programme/assignment;
    /// it cannot silently replace an expired TV2 selection with TV1 or TV3.
    func refreshedDescriptor(for session: StreamSession, request: StreamPlaybackRequest,
                             now: Date = Date(),
                             isEnabled: Enablement = {
                                 await StreamPluginRegistry.shared.enabledProviderCodes().contains(ReviewedTVPlaylistClient.providerCode)
                             },
                             currentFixture: CurrentFixture = { request, at in
                                 await MainActor.run { RegisteredDescriptorRecoveryPolicy.currentRequest(for: request,
                                     in: MatchListViewModel.shared.playbackAdmissionCatalog, at: at) }
                             },
                             programmeMatches: ProgrammeMatches = { request, at in
                                 await BroadcastRegistryClient.shared.lookup(for: request,
                                     enabledProviderCodes: [ReviewedTVPlaylistClient.providerCode], at: at)
                             }) async -> StreamSession? {
        let started = Date()
        guard !Task.isCancelled, let channel = Self.channel(forProviderName: session.providerName), session.canRefresh,
              session.playbackContract.endpoint == .directMedia, Self.admitsDelivery(session.playableURL, channel: channel),
              let old = session.eventBinding, old.providerCode == Self.providerCode,
              old.streamID == channel.streamID,
              old.matchesIdentity(request: request, providerCode: Self.providerCode),
              await isEnabled() else { return nil }
        var accepted = request
        if old.usesRegistryAssociation {
            guard (channel.providerName == "TV1" ? Self.isProgrammeID(old.providerEventID) : Self.isAssignmentID(old.providerEventID)),
                  let current = await currentFixture(request, now) else { return nil }
            let matches = await programmeMatches(current, now).filter {
                $0.broadcast.providerEventID == old.providerEventID && $0.broadcast.streamID == channel.streamID
                    && Self.programmeAssociation(for: current.usingRegistryMatch($0), at: now) != nil
            }
            guard matches.count == 1, let association = matches.first else { return nil }
            accepted = current.usingRegistryMatch(association)
        } else {
            let willow = channel.providerName == "TV1" && old.providerEventID == Self.providerEventID
                && CricketBroadcastChannel.identifying(request: request) == .willow
            let station = SportsTVStation.identifying(request)?.id == channel.channelID
                && old.providerEventID == channel.streamID
            guard (willow || station), request.registryMatch == nil else { return nil }
        }
        do {
            let candidates = try await resolve(for: accepted, now: now, isEnabled: isEnabled,
                currentFixture: currentFixture, programmeMatches: programmeMatches)
            try Task.checkCancellation()
            let completedAt = now.addingTimeInterval(max(0, Date().timeIntervalSince(started)))
            if old.usesRegistryAssociation {
                guard let current = await currentFixture(accepted, completedAt) else { return nil }
                let matches = await programmeMatches(current, completedAt).filter {
                    $0.broadcast.providerEventID == old.providerEventID && $0.broadcast.streamID == channel.streamID
                        && Self.programmeAssociation(for: current.usingRegistryMatch($0), at: completedAt) != nil
                }
                guard matches.count == 1, let association = matches.first else { return nil }
                accepted = current.usingRegistryMatch(association)
            }
            // Preserve the selected backup across a reorder. A lone source in
            // older sessions can still renew onto a publisher's replacement URL.
            let sameDelivery = candidates.first { $0.playableURL == session.playableURL && $0.requiredHeaders == session.requiredHeaders }
            let singleReplacement = candidates.count == 1 && session.diagnosticMetadata["tv_has_alternatives"] != "true"
            guard let fresh = sameDelivery ?? (singleReplacement ? candidates.first : nil),
                  let next = fresh.eventBinding,
                  next.providerEventID == old.providerEventID, next.streamID == old.streamID,
                  next.matches(request: accepted, providerCode: Self.providerCode, at: completedAt),
                  await isEnabled(), !Task.isCancelled else { return nil }
            return session.renewingDelivery(from: fresh, for: accepted, at: completedAt)
        } catch { return nil }
    }

    nonisolated static func supports(_ request: StreamPlaybackRequest, at now: Date = Date()) -> Bool {
        selectedChannel(for: request, at: now) != nil
    }

    nonisolated static func isProgrammeID(_ value: String) -> Bool { isOpaqueID(value, prefix: "reviewed-tv:programme:") }
    nonisolated static func isAssignmentID(_ value: String) -> Bool { isOpaqueID(value, prefix: "reviewed-tv:assignment:") }
    private nonisolated static func isOpaqueID(_ value: String, prefix: String) -> Bool {
        guard value.hasPrefix(prefix), value.utf8.count == prefix.utf8.count + 64 else { return false }
        return value.dropFirst(prefix.count).utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Structural channel authority only. matches() below owns exact current
    /// official identity and the source-local coverage-start relation.
    nonisolated static func supportsScheduledSport(_ broadcast: BroadcastRegistrySnapshot.Broadcast) -> Bool {
        if broadcast.sport == "football" { return true }
        return ((broadcast.sport == "baseball" && broadcast.competitionID == "mlb")
            || (broadcast.sport == "hockey" && broadcast.competitionID == "nhl"))
            && broadcast.squad?.gender == .men && broadcast.squad?.ageGroup == "senior"
    }

    nonisolated static func hasProgrammeShape(_ match: BroadcastRegistryMatch, at now: Date) -> Bool {
        guard match.permitsAutomaticProgramme(at: now) else { return false }
        let broadcast = match.broadcast
        if isFoxProgramme(broadcast) {
            guard match.link?.state == .listed, match.link?.matchMethod == .programme,
                  broadcast.resourceType == "tv", broadcast.verification == .dated, broadcast.issues.isEmpty,
                  (-300...BroadcastRegistrySnapshot.programmeLifetime).contains(now.timeIntervalSince(broadcast.observedAt)),
                  broadcast.expiresAt > now, broadcast.expiresAt > broadcast.observedAt,
                  broadcast.expiresAt.timeIntervalSince(broadcast.observedAt) <= BroadcastRegistrySnapshot.programmeLifetime,
                  let expiry = match.link?.expiresAt, expiry > now, expiry <= broadcast.expiresAt,
                  let start = broadcast.start, let end = broadcast.end, start <= now, now < end,
                  broadcast.expiresAt <= end else { return false }
            return true
        }
        guard broadcast.providerCode == providerCode, broadcast.resourceType == "tv",
              let id = broadcast.channelID, let channel = Self.channel(forChannelID: id),
              broadcast.streamID == channel.streamID, channel.sports.contains(broadcast.sport),
              broadcast.verification == .dated, broadcast.issues.isEmpty,
              match.link?.state == .listed,
              (-300...BroadcastRegistrySnapshot.programmeLifetime).contains(now.timeIntervalSince(broadcast.observedAt)),
              broadcast.expiresAt > now, broadcast.expiresAt > broadcast.observedAt,
              broadcast.expiresAt.timeIntervalSince(broadcast.observedAt) <= BroadcastRegistrySnapshot.programmeLifetime,
              let expiry = match.link?.expiresAt, expiry > now, expiry <= broadcast.expiresAt,
              let start = broadcast.start, start <= now else { return false }
        if channel.providerName == "TV1" {
            guard broadcast.kind == .programme, broadcast.sport == "cricket", isProgrammeID(broadcast.providerEventID),
                  match.link?.matchMethod == .programme, let end = broadcast.end,
                  now < end, broadcast.expiresAt <= end else { return false }
        } else {
            guard broadcast.kind == .event, Self.supportsScheduledSport(broadcast), isAssignmentID(broadcast.providerEventID),
                  match.link?.matchMethod == .channelAssignment, match.link?.startRelation == "channel-coverage",
                  broadcast.stationMarket == "UY", channel.markets.contains("UY"), broadcast.end == nil,
                  broadcast.format == nil, broadcast.day == nil, broadcast.matchOrdinal == nil else { return false }
        }
        return true
    }

    nonisolated static func programmeAssociation(for request: StreamPlaybackRequest, at now: Date) -> BroadcastRegistryMatch? {
        guard CricketBroadcastChannel.identifying(request: request) == nil,
              let match = request.registryMatch, hasProgrammeShape(match, at: now),
              match.matches(request: request, providerCode: providerCode,
                providerEventID: match.broadcast.providerEventID, streamID: match.broadcast.streamID, at: now) else { return nil }
        return match
    }

    /// Guide-only identity; Fox media still belongs to a separately enabled
    /// provider and must pass fresh exact-channel/market resolution.
    nonisolated static func isFoxProgramme(_ broadcast: BroadcastRegistrySnapshot.Broadcast) -> Bool {
        let wbbl: Set<String> = ["Adelaide Strikers Women", "Brisbane Heat Women", "Hobart Hurricanes Women",
            "Melbourne Renegades Women", "Melbourne Stars Women", "Perth Scorchers Women", "Sydney Sixers Women", "Sydney Thunder Women"]
        // Abu Dhabi T10 2026 franchises, exactly as the Worker's ESPN cohort names them.
        let t10: Set<String> = ["Arabian Aces", "UAE Bulls", "Royal Desert Champions", "Emirates Eagles", "Yas Lions", "United Tigers"]
        let clubs: Set<String>
        switch (broadcast.competitionID, broadcast.format, broadcast.squad?.gender) {
        case ("wbbl", .t20, .women): clubs = wbbl
        case ("abu-dhabi-t10", .t10, .men): clubs = t10
        default: return false
        }
        return broadcast.providerCode == providerCode && broadcast.kind == .programme && broadcast.sport == "cricket"
            && broadcast.scope == "cricket" && broadcast.channelID == CricketBroadcastChannel.foxCricket.canonicalID
            && broadcast.streamID == foxGuideStreamID
            && broadcast.providerEventID.range(of: #"^reviewed-tv:fox-programme:[a-f0-9]{64}$"#, options: .regularExpression) != nil
            && broadcast.matchOrdinal == nil && broadcast.day == nil && broadcast.stationMarket == nil
            && broadcast.squad?.ageGroup == "senior"
            && broadcast.participants.count == 2 && Set(broadcast.participants).count == 2
            && broadcast.participants.allSatisfy(clubs.contains)
    }

    @MainActor static func programmeLookupRequests(for request: StreamPlaybackRequest,
                                                  at now: Date = Date()) -> [StreamPlaybackRequest] {
        if request.registryMatch != nil { return programmeAssociation(for: request, at: now) == nil ? [] : [request] }
        return lookupRequests(for: request, matches: BroadcastRegistryClient.shared.lookup(for: request,
            enabledProviderCodes: [providerCode], at: now), at: now)
    }

    @MainActor static func programmeLookupRequest(for request: StreamPlaybackRequest,
                                                 at now: Date = Date()) -> StreamPlaybackRequest? {
        programmeLookupRequests(for: request, at: now).first
    }

    private nonisolated static func lookupRequests(for request: StreamPlaybackRequest,
                                                  matches: [BroadcastRegistryMatch], at now: Date) -> [StreamPlaybackRequest] {
        let valid = matches.filter { programmeAssociation(for: request.usingRegistryMatch($0), at: now) != nil }
        return channels.compactMap { channel in
            let candidates = valid.filter { $0.broadcast.channelID == channel.channelID }
            guard candidates.count == 1, let association = candidates.first else { return nil }
            return request.usingRegistryMatch(association)
        }
    }

    private nonisolated static func selectedChannel(for request: StreamPlaybackRequest, at now: Date) -> ChannelDefinition? {
        if CricketBroadcastChannel.identifying(request: request) == .willow, request.registryMatch == nil { return channels[0] }
        if let station = SportsTVStation.identifying(request) { return channel(forChannelID: station.id) }
        guard let association = programmeAssociation(for: request, at: now), let id = association.broadcast.channelID else { return nil }
        return channel(forChannelID: id)
    }

    nonisolated static func admitsDelivery(_ url: URL) -> Bool { admitsDelivery(url, channel: channels[0]) }

    nonisolated static func admitsDelivery(_ url: URL, channel: ChannelDefinition) -> Bool {
        channels.contains(channel) && StreamDeliveryPolicy.rejection(url) == nil
    }

    nonisolated static func willowDelivery(from data: Data, playlistURL: URL) throws -> URL {
        try delivery(from: data, playlistURL: playlistURL, channel: channels[0])
    }

    /// Exact selected station identity and trusted playlist provenance grant
    /// authority. Each advertised delivery then uses the common transport policy.
    nonisolated static func delivery(from data: Data, playlistURL: URL, channel: ChannelDefinition) throws -> URL {
        try deliveries(from: data, playlistURL: playlistURL, channel: channel).first()
    }

    private nonisolated static func deliveries(from data: Data, playlistURL: URL, channel: ChannelDefinition) throws -> ChannelDeliveries {
        guard channels.contains(channel), playlistURL == channel.playlistURL, data.count <= maximumBytes else { throw CommunitySportsAddonError.unsafeResponse }
        if isTenies(playlistURL) { return try teniesDeliveries(data, channel: channel) }
        guard let raw = String(data: data, encoding: .utf8) else { throw CommunitySportsAddonError.unsafeResponse }
        let text = raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw
        let lines = text.components(separatedBy: .newlines)
        guard lines.count <= 20_000,
              let first = lines.first, first == "#EXTM3U" || first.hasPrefix("#EXTM3U ") else { throw CommunitySportsAddonError.unsafeResponse }
        let identifierPattern = try NSRegularExpression(pattern: #"(?:^|\s)tvg-id="([^"]*)"(?=\s|,|$)"#)
        var pending: String?, scoped = false
        var requested: [String: String] = [:], rowFailure: String?
        var result = ChannelDeliveries()
        result.ledger.observe(0)
        func belongsToStation(_ metadata: String) -> Bool {
            guard metadata.contains("tvg-id=\"" + channel.playlistIdentifier + "\"") else { return false }
            if channel.playlistURL == zillaLGPlaylistURL {
                guard let comma = metadata.lastIndex(of: ",") else { return false }
                return channel.playlistLabels.contains(String(metadata[metadata.index(after: comma)...]).trimmingCharacters(in: .whitespaces))
            }
            return true
        }
        func merge(_ map: [String: String]) {
            for (name, value) in map {
                let lower = name.lowercased()
                if let previous = requested[lower], previous != value { rowFailure = "malformed_headers" }
                requested[lower] = value
            }
        }
        for rawLine in lines.dropFirst() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#EXTINF:") {
                if scoped { result.reject(rowFailure ?? "no_url") }
                pending = line; scoped = belongsToStation(line); requested = [:]; rowFailure = nil
                if scoped { result.ledger.observe(1) }
            }
            guard rawLine.utf8.count <= 8_192,
                  !rawLine.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0.value != 9 }) else {
                if scoped { result.reject("malformed") }
                pending = nil; scoped = false
                continue
            }
            if line.hasPrefix("#EXTINF:") { continue }
            if line.hasPrefix("#") {
                guard scoped else { continue }
                if line.hasPrefix("#EXTVLCOPT:") {
                    let value = String(line.dropFirst("#EXTVLCOPT:".count))
                    if let equal = value.firstIndex(of: "=") {
                        let name = String(value[..<equal]).lowercased()
                        let known = ["http-user-agent": "User-Agent", "http-referrer": "Referer", "http-referer": "Referer", "http-origin": "Origin", "http-cookie": "Cookie", "http-authorization": "Authorization"]
                        if let header = known[name] { merge([header: String(value[value.index(after: equal)...])]) }
                        else { rowFailure = "unsupported" }
                    } else { rowFailure = "malformed_headers" }
                } else if line.hasPrefix("#EXTHTTP:") {
                    let bytes = Data(line.dropFirst("#EXTHTTP:".count).utf8)
                    if let map = try? JSONDecoder().decode([String: String].self, from: bytes) { merge(map) }
                    else { rowFailure = "malformed_headers" }
                } else if line.hasPrefix("#EXT-X-KEY:") || line.hasPrefix("#EXT-X-SESSION-KEY:") {
                    rowFailure = "drm"
                } else if line.hasPrefix("#KODIPROP:") {
                    let value = String(line.dropFirst("#KODIPROP:".count))
                    if value.lowercased().contains("license") || value.lowercased().contains("drm") { rowFailure = "drm" }
                    else if let equal = value.firstIndex(of: "="),
                            ["inputstream.adaptive.manifest_headers", "inputstream.adaptive.stream_headers"].contains(String(value[..<equal])) {
                        let query = String(value[value.index(after: equal)...])
                        if let items = URLComponents(string: "https://headers.example/?" + query)?.queryItems {
                            for item in items {
                                if let value = item.value { merge([item.name: value]) } else { rowFailure = "malformed_headers" }
                            }
                        } else { rowFailure = "malformed_headers" }
                    } else { rowFailure = "unsupported" }
                }
                continue
            }
            defer { pending = nil; scoped = false; requested = [:]; rowFailure = nil }
            guard scoped, let metadata = pending else { continue }
            let source = metadata as NSString
            let attributes = identifierPattern.matches(in: metadata, range: NSRange(location: 0, length: source.length))
                .map { source.substring(with: $0.range(at: 1)) }
            guard attributes == [channel.playlistIdentifier], let comma = metadata.lastIndex(of: ",") else {
                result.reject("malformed"); continue
            }
            let label = String(metadata[metadata.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
            let base = label.replacingOccurrences(of: #"\s*\([0-9]{3,4}p\)$"#, with: "", options: .regularExpression)
            let matchesLabel = channel.providerName == "TV1"
                ? CricketBroadcastChannel.identifying(title: base) == .willow : channel.playlistLabels.contains(base)
            guard matchesLabel else { result.reject("filtered"); result.failure = .conflictingMatch; continue }
            if let rowFailure { result.reject(rowFailure); continue }
            if let reason = StreamDeliveryPolicy.headerRejection(requested) { result.reject(reason); continue }
            guard let headers = deliveryHeaders(requested, channel: channel) else { result.reject("malformed_headers"); continue }
            guard let url = URL(string: line) else { result.reject("malformed"); continue }
            if let rejection = StreamDeliveryPolicy.rejection(url) { result.reject(rejection); continue }
            result.append(url, headers: headers)
        }
        if scoped { result.reject(rowFailure ?? "no_url") }
        return result
    }

    nonisolated static func session(for request: StreamPlaybackRequest, delivery: URL, at now: Date, hasAlternatives: Bool = false, requiredHeaders: [String: String]? = nil) throws -> StreamSession {
        guard let channel = selectedChannel(for: request, at: now), admitsDelivery(delivery, channel: channel) else {
            throw CommunitySportsAddonError.unsafeResponse
        }
        let programme = programmeAssociation(for: request, at: now)
        let expiry = min(now.addingTimeInterval(StreamEventBinding.metadataLifetime), programme?.broadcast.end ?? .distantFuture,
                         programme?.acceptanceExpiresAt ?? .distantFuture)
        guard let binding = StreamEventBinding(request: request, providerCode: providerCode,
                providerEventID: programme?.broadcast.providerEventID ?? channel.streamID, streamID: channel.streamID,
                manifestRevision: revision, verifiedAt: now, expiresAt: expiry, at: now) else { throw CommunitySportsAddonError.unsafeResponse }
        let headers = requiredHeaders ?? defaultHeaders(for: channel)
        guard StreamDeliveryPolicy.requestHeaders(headers) != nil else { throw CommunitySportsAddonError.unsafeResponse }
        let key = PlavioSportsAddonClient.sourceKey(url: delivery, headers: headers)
        var details = ["source_family": providerCode, "manifest_result": "exact_channel_match",
                       "delivery": "reviewed_direct_hls", "source_key": key, "source_key_scope": "delivery"]
        if hasAlternatives { details["tv_has_alternatives"] = "true" }
        return StreamSession(matchID: request.matchID, playableURL: delivery, streamType: .hls,
            providerName: channel.providerName, requiredHeaders: headers, qualityLabel: nil, expiryTime: binding.expiresAt,
            canRefresh: true, diagnosticMetadata: details, createdAt: now,
            requiresGuardedRelay: true, eventBinding: binding)
    }
}
