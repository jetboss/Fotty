import XCTest
@testable import Fotty

final class CNCSportsAddonTests: XCTestCase {
    private let kickoff = ISO8601DateFormatter().date(from: "2026-10-24T00:00:00Z")!
    // Synthetic URL-safe opaque values, never decoded into an endpoint or date.
    private let fixtureID = "cnc:" + String(repeating: "A", count: 1218) + "=="
    private let secondID = "cnc:" + String(repeating: "B", count: 1218) + "=="
    private let delivery = "https://edgestream7.pro/hls/offline_fixture.m3u8"

    func testReviewedManifestRequiresExactIdentityStringResourcesAndOneFixedCatalog() throws {
        let manifest = try CNCSportsAddonClient.validateManifest(data: data(manifestJSON()))
        XCTAssertEqual(manifest.id, "com.cncverse.stremiobridge")
        XCTAssertEqual(manifest.version, "1.0.30")
        XCTAssertEqual(CNCSportsAddonClient.catalogID, "cnc_LivXowLiveEvents_tv")
        for mutation: [String: Any] in [
            ["id": "com.lookalike"], ["version": "https://private.example/key"],
            ["resources": ["catalog", "stream"]], ["resources": ["catalog", "meta", "stream", "stream"]],
            ["resources": [["name": "catalog"], ["name": "meta"], ["name": "stream"]]],
            ["types": ["sport"]], ["types": ["tv", "unknown"]],
            ["catalogs": [["id": "another-catalog", "type": "tv"]]],
            ["catalogs": [["id": CNCSportsAddonClient.catalogID, "type": "tv"], ["id": CNCSportsAddonClient.catalogID, "type": "tv"]]],
            ["behaviorHints": ["configurationRequired": true]]
        ] {
            XCTAssertThrowsError(try CNCSportsAddonClient.validateManifest(data: data(manifestJSON().merging(mutation) { _, new in new })))
        }
    }

    func testObservedNHLAliasesOnlyPreselectMetadataAndExplicitUTCFinishesTheJoin() throws {
        let row = catalogEntry()
        XCTAssertEqual(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(), from: [row]), [fixtureID])
        let meta = metadata()
        XCTAssertEqual(CNCSportsAddonClient.explicitKickoff(for: meta), kickoff)
        XCTAssertEqual(try CNCSportsAddonClient.selectMetadata(for: request(), catalog: [row], metadata: [meta]).id, fixtureID)
        let reverse = catalogEntry(name: "🔴 Canadiens vs Blackhawks")
        XCTAssertEqual(try CNCSportsAddonClient.selectMetadata(for: request(), catalog: [reverse],
            metadata: [metadata(name: "Montreal Canadiens vs Chicago Blackhawks")]).id, fixtureID)
        XCTAssertNil(SportsTeamIdentity.known(name: "Blackhawks", category: "hockey"), "No global alias was installed")
        XCTAssertNil(SportsTeamIdentity.known(name: "Canadiens", category: "hockey"))
    }

    func testObservedCapitalsFlyersNamesJoinOnlyTheCorroboratedFullNHLPair() throws {
        let request = capitalsFlyersRequest()
        let row = catalogEntry(name: "🔴 Capitals vs Flyers")
        let meta = metadata(name: "Capitals vs Flyers", description: capitalsFlyersDescription)
        XCTAssertEqual(try CNCSportsAddonClient.preselectedCatalogIDs(for: request, from: [row]), [fixtureID])
        XCTAssertEqual(try CNCSportsAddonClient.selectMetadata(for: request, catalog: [row], metadata: [meta]).id, fixtureID)
        let reversed = catalogEntry(name: "🔴 Flyers vs Capitals")
        let fullNames = metadata(name: "Philadelphia Flyers vs Washington Capitals", description: capitalsFlyersDescription)
        XCTAssertEqual(try CNCSportsAddonClient.selectMetadata(for: request, catalog: [reversed], metadata: [fullNames]).id, fixtureID)
        XCTAssertNil(SportsTeamIdentity.known(name: "Capitals", category: "hockey"), "Alias remains source-local")
        XCTAssertNil(SportsTeamIdentity.known(name: "Flyers", category: "hockey"))
    }

    func testCapitalsFlyersAliasesCannotAdmitOtherSquadsExtendedNamesOrConflictingSibling() throws {
        let request = capitalsFlyersRequest()
        for name in ["🔴 Capitals Women vs Flyers Women", "🔴 Capitals U19 vs Flyers U19",
                     "🔴 Capitals Reserves vs Flyers Reserves", "🔴 College Capitals vs Flyers",
                     "🔴 Other Capitals vs Flyers", "🔴 Capitals vs Other Flyers"] {
            XCTAssertTrue(try CNCSportsAddonClient.preselectedCatalogIDs(for: request,
                from: [catalogEntry(name: name)]).isEmpty, name)
        }
        let exact = catalogEntry(name: "🔴 Capitals vs Flyers")
        let conflict = catalogEntry(name: "🔴 Other Capitals vs Flyers")
        XCTAssertThrowsError(try CNCSportsAddonClient.preselectedCatalogIDs(for: request, from: [exact, conflict])) {
            XCTAssertEqual($0 as? CommunitySportsAddonError, .conflictingMatch)
        }
    }

    func testNormalClientDiscoversObservedCapitalsFlyersThroughExactMetadataBeforeStreams() async throws {
        let session = try fixtureSession(catalog: .json(["metas": [catalogJSON(name: "🔴 Capitals vs Flyers")]]),
            meta: .json(["meta": metadataJSON(name: "Capitals vs Flyers", description: capitalsFlyersDescription)]))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let request = capitalsFlyersRequest()
        let values = try await CNCSportsAddonClient(session: session).resolve(for: request, now: request.kickoffDate!)
        XCTAssertEqual(values.map(\.providerName), ["LS1"])
        XCTAssertEqual(values.first?.matchID, "sports-fixture:nhl:2026020199")
        let resolved = try XCTUnwrap(values.first)
        let binding = try XCTUnwrap(resolved.eventBinding)
        XCTAssertEqual(binding.providerEventID, fixtureID)
        XCTAssertEqual(binding.streamID, fixtureID)
        XCTAssertTrue(binding.matches(request: request, providerCode: "cncsports", at: try XCTUnwrap(request.kickoffDate)))
        XCTAssertTrue(LiveStreamResolver.supportsDescriptorRenewal(resolved))
        XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", catalogPath, metaPath(fixtureID), streamPath(fixtureID)])
    }

    @MainActor
    func testRegisteredTorontoUtahLookupPublishesTheVerifiedCNCBackup() async throws {
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-04T00:00:00Z"))
        let teams = ["Toronto Maple Leafs", "Utah Mammoth"]
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:nhl:2026020236", sport: "hockey",
            competitionID: "nhl", competitionName: "NHL", eventKind: .match, title: teams.joined(separator: " vs "),
            participants: [.init(id: "tor", name: teams[0]), .init(id: "uta", name: teams[1])],
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: start, verified: true)
        let event = EventReference(id: metadata.fixtureID, title: metadata.title, category: "hockey",
            date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: teams[0], badge: nil), away: .init(name: teams[1], badge: nil)),
            sources: [], sportsFixture: metadata, competitionID: "nhl")
        let request = StreamPlaybackRequest(event: event), expiry = start.addingTimeInterval(600)
        let record = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "c", count: 64),
            providerCode: "cncsports", providerEventID: fixtureID, streamID: fixtureID, resourceType: "tv",
            scope: "hockey", kind: .event, sport: "hockey", title: metadata.title, participants: teams, start: start,
            competitionID: "nhl", squad: metadata.squad, observedAt: start, expiresAt: expiry, verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: record.id, providerCode: "cncsports",
            state: .listed, matchMethod: .exact, fixtureFingerprint: .init(fixtureID: event.id, sport: "hockey",
                start: start, participants: teams, competitionID: "nhl", squad: metadata.squad), expiresAt: expiry)
        let association = BroadcastRegistryMatch(broadcast: record, link: link, provider: .init(providerCode: "cncsports",
            scope: "hockey", status: .available, observedAt: start, expiresAt: expiry))
        let shortTitle = "Maple Leafs vs Mammoth"
        let session = try fixtureSession(catalog: .json(["metas": [catalogJSON(name: "🔴 " + shortTitle)]]),
            meta: .json(["meta": metadataJSON(name: shortTitle, description:
                "📌 Hockey\n🏆 NHL\n🕐 Nov 04, 2026 00:00 UTC\n\n📡 Available Servers: 1")]))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session)
        let scoped = request.usingRegistryMatch(association)
        XCTAssertTrue(association.matches(request: scoped, providerCode: "cncsports", providerEventID: fixtureID, streamID: fixtureID, at: start))
        XCTAssertEqual(ReviewedSportsFixtureMatcher.requestIdentity(for: scoped)?.pair,
            BroadcastRegistrySnapshot.participantPair(teams, sport: "hockey"))
        XCTAssertEqual(try CNCSportsAddonClient.preselectedCatalogIDs(for: scoped,
            from: [catalogEntry(name: shortTitle)]), [fixtureID])
        XCTAssertEqual(try CNCSportsAddonClient.selectMetadata(for: scoped,
            catalog: [catalogEntry(name: shortTitle)], metadata: [self.metadata(name: shortTitle, description:
                "📌 Hockey\n🏆 NHL\n🕐 Nov 04, 2026 00:00 UTC\n\n📡 Available Servers: 1")], at: start).id, fixtureID)
        let choices = try await LiveStreamResolver.resolveRegisteredOptionalSessions(for: request, providerCode: "cncsports",
            associations: [association], resolve: { try await client.resolve(for: $0, now: start) }, clock: { start })
        XCTAssertEqual(choices.map(\.providerName), ["LS1"])
        XCTAssertEqual(choices.first?.eventBinding?.usesRegistryAssociation, true)
        XCTAssertTrue(try CNCSportsAddonClient.preselectedCatalogIDs(for: request,
            from: [catalogEntry(name: "🔴 Maple Leafs U19 vs Mammoth U19")]).isEmpty)
    }

    func testObservedCapitalsFlyersAliasStillRejectsWrongDateLeagueAndSquadBeforeStreams() async throws {
        for meta in [
            metadataJSON(name: "Capitals vs Flyers", description: capitalsFlyersDescription.replacingOccurrences(of: "Oct 28", with: "Oct 27")),
            metadataJSON(name: "Capitals vs Flyers", description: capitalsFlyersDescription.replacingOccurrences(of: "NHL", with: "College")),
            metadataJSON(name: "Capitals Women vs Flyers Women", description: capitalsFlyersDescription)
        ] {
            let session = try fixtureSession(catalog: .json(["metas": [catalogJSON(name: "🔴 Capitals vs Flyers")]]),
                meta: .json(["meta": meta]))
            defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
            do {
                _ = try await CNCSportsAddonClient(session: session).resolve(for: capitalsFlyersRequest())
                XCTFail("Exact aliases cannot replace independent date, league or squad proof")
            } catch { XCTAssertTrue(error is CommunitySportsAddonError) }
            XCTAssertFalse(CNCFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
        }
    }

    func testOnlyReviewedNHLSportCompetitionAndFullEnglishUTCDescriptionSupplyDate() {
        let original = description()
        let invalid: [String?] = [nil, "LIVE", "Oct 24, 2026 00:00 UTC", original + "\n",
            original.replacingOccurrences(of: "Hockey", with: "Basketball"),
            original.replacingOccurrences(of: "NHL", with: "NBA"),
            original.replacingOccurrences(of: "UTC", with: "GMT"),
            original.replacingOccurrences(of: "Oct 24, 2026", with: "Oct 24"),
            original.replacingOccurrences(of: "Oct 24, 2026", with: "Feb 31, 2026"),
            original.replacingOccurrences(of: "00:00", with: "24:00"),
            original.replacingOccurrences(of: "\n", with: "\r\n"),
            original.replacingOccurrences(of: "Servers: 1", with: "Servers: unknown"),
            original.replacingOccurrences(of: "\n\n", with: "\n")]
        for value in invalid {
            let meta = metadata(description: value)
            XCTAssertNil(CNCSportsAddonClient.explicitKickoff(for: meta))
            XCTAssertThrowsError(try CNCSportsAddonClient.selectMetadata(for: request(), catalog: [catalogEntry()], metadata: [meta]))
        }
    }

    func testOpaqueIDsRemainLiteralBoundedAndNeverGrantEmbeddedAddressAuthority() {
        XCTAssertTrue(CNCSportsAddonClient.isSafeFixtureID(fixtureID))
        for id in ["", "cnc:", "cnc:a/b", "cnc:a?token=value", "cnc:a#fragment", "cnc:a%2Fb",
                   "cnc:a:b", "cnc:a=b", "cnc:a===", "cnc:a\n", "cnc:" + String(repeating: "A", count: 4093)] {
            XCTAssertFalse(CNCSportsAddonClient.isSafeFixtureID(id))
        }
        XCTAssertTrue(CNCSportsAddonClient.isSafeFixtureID("cnc:" + String(repeating: "A", count: 4092)))
    }

    func testPreselectionRejectsUnreviewedSquadsSportPlaceholderAndMoreThanTwoExactIDs() throws {
        for name in ["🔴 Blackhawks Women vs Canadiens Women", "🔴 Blackhawks U19 vs Canadiens U19", "🔴 Blackhawks Reserves vs Canadiens Reserves",
                     "🔴 Other Blackhawks vs Canadiens", "🔴 TBC vs Canadiens", "🔴 Blackhawks vs Other Team",
                     "🔴 Blackhawks vs Canadiens | Women's Hockey", "🔴 Blackhawks vs Canadiens vs Bruins"] {
            XCTAssertTrue(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(), from: [catalogEntry(name: name)]).isEmpty)
        }
        XCTAssertTrue(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(category: "football"), from: [catalogEntry()]).isEmpty)
        let undated = StreamPlaybackRequest(matchID: "existing", displayTitle: "Chicago Blackhawks vs Montreal Canadiens",
            homeTeam: "Chicago Blackhawks", awayTeam: "Montreal Canadiens", category: "hockey")
        XCTAssertTrue(try CNCSportsAddonClient.preselectedCatalogIDs(for: undated, from: [catalogEntry()]).isEmpty)
        let rows = [catalogEntry(), catalogEntry(id: secondID), catalogEntry(id: "cnc:third")]
        XCTAssertThrowsError(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(), from: rows)) {
            XCTAssertEqual($0 as? CommunitySportsAddonError, .conflictingMatch)
        }
        XCTAssertEqual(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(), from: [rows[0], rows[0], rows[1]]).count, 2)
    }

    func testMalformedCatalogMetadataOrEffectiveTargetSiblingCannotDisappearBeforeSelection() throws {
        let exact = catalogEntry()
        let malformed = [catalogEntry(name: "Other Club vs Another Club"), catalogEntry(type: "movie"),
            CNCSportsCatalogEntry(id: fixtureID, name: "🔴 Blackhawks vs Canadiens", hasMalformedIdentity: true),
            CNCSportsCatalogEntry(id: "cnc:other", effectiveID: fixtureID, name: "Other vs Another", hasMalformedIdentity: true)]
        for row in malformed {
            for entries in [[exact, row], [row, exact]] {
                XCTAssertThrowsError(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(), from: entries)) {
                    XCTAssertEqual($0 as? CommunitySportsAddonError, .conflictingMatch)
                }
            }
        }
        var raw = catalogJSON(); raw["name"] = NSNull()
        let decoded = try JSONDecoder().decode(CNCSportsCatalogEntry.self, from: data(raw))
        XCTAssertEqual(decoded.id, fixtureID); XCTAssertTrue(decoded.hasMalformedIdentity)
        XCTAssertThrowsError(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(), from: [exact, decoded]))
        for hints: Any in [NSNull(), [:], ["defaultVideoId": "cnc:other"],
                           ["defaultVideoId": fixtureID, "proxyHeaders": [:]]] {
            var changed = catalogJSON(); changed["behaviorHints"] = hints
            let row = try JSONDecoder().decode(CNCSportsCatalogEntry.self, from: data(changed))
            XCTAssertTrue(row.hasMalformedIdentity)
            XCTAssertThrowsError(try CNCSportsAddonClient.preselectedCatalogIDs(for: request(), from: [exact, row]))
        }
    }

    func testMetadataMustCorroborateIDTypePairSquadAndExactRequestTime() throws {
        for meta in [metadata(id: secondID), metadata(type: "movie"), metadata(name: "Blackhawks vs Bruins"),
                     metadata(name: "Blackhawks Women vs Canadiens Women"), metadata(name: "Blackhawks U19 vs Canadiens U19"),
                     metadata(description: description(time: "20:00"))] {
            XCTAssertThrowsError(try CNCSportsAddonClient.selectMetadata(for: request(), catalog: [catalogEntry()], metadata: [meta]))
        }
        let boundary = request(at: kickoff.addingTimeInterval(900))
        XCTAssertEqual(try CNCSportsAddonClient.selectMetadata(for: boundary, catalog: [catalogEntry()], metadata: [metadata()]).id, fixtureID)
        XCTAssertThrowsError(try CNCSportsAddonClient.selectMetadata(for: request(at: kickoff.addingTimeInterval(901)),
            catalog: [catalogEntry()], metadata: [metadata()]))
        let rows = [catalogEntry(), catalogEntry(id: secondID)]
        XCTAssertThrowsError(try CNCSportsAddonClient.selectMetadata(for: request(), catalog: rows,
            metadata: [metadata(), metadata(id: secondID)])) {
            XCTAssertEqual($0 as? CommunitySportsAddonError, .conflictingMatch)
        }
        XCTAssertEqual(try CNCSportsAddonClient.selectMetadata(for: request(), catalog: rows,
            metadata: [metadata(), metadata(id: secondID, description: description(time: "21:00"))]).id, fixtureID)
    }

    func testReviewedHLSKeepsExactPublicHeadersGuardedRelayAndOpaqueLabels() throws {
        let values = try sessions([streamJSON()])
        let session = try XCTUnwrap(values.first)
        XCTAssertEqual(session.providerName, "LS1"); XCTAssertEqual(session.streamType, .hls)
        XCTAssertEqual(session.requiredHeaders, CNCSportsAddonClient.reviewedHeaders)
        XCTAssertEqual(session.legacySource.headers, session.requiredHeaders)
        XCTAssertTrue(session.requiresLocalProxy); XCTAssertTrue(session.legacySource.requiresLocalProxy)
        XCTAssertNil(session.nativeOriginProfile); XCTAssertNil(session.nativePlaylistProfile)
        XCTAssertFalse(session.canRefresh)
        XCTAssertEqual(session.diagnosticMetadata["source_family"], "cncsports")
        XCTAssertEqual(session.diagnosticMetadata["source_key"]?.count, 27)
        XCTAssertTrue(session.diagnosticMetadata["source_key"]?.hasPrefix("ls_") == true)
        XCTAssertFalse(session.diagnosticMetadata.description.contains("https://"))
        XCTAssertFalse(session.diagnosticMetadata.description.contains("edgestream"))
    }

    func testDeliveryAdmissionRejectsEveryUnreviewedOriginPortPathAndQuery() throws {
        for value in ["http://edgestream7.pro/hls/fixture.m3u8", "https://edgestream7.pro:8443/hls/fixture.m3u8",
            "https://edgestream7.pro.evil.example/hls/fixture.m3u8", "https://cdn.edgestream7.pro/hls/fixture.m3u8",
            "https://edgestream7.pro./hls/fixture.m3u8", "https://127.0.0.1/hls/fixture.m3u8",
            "https://user@edgestream7.pro/hls/fixture.m3u8", "https://user:secret@edgestream7.pro/hls/fixture.m3u8",
            "https://edgestream7.pro/hls/fixture.m3u8?token=unreviewed", "https://edgestream7.pro/hls/fixture.m3u8#player",
            "https://edgestream7.pro/hls/fixture.mp4", "https://edgestream7.pro/other/fixture.m3u8",
            "https://edgestream7.pro/hls/fixture/extra.m3u8", "https://edgestream7.pro/hls//fixture.m3u8",
            "https://edgestream7.pro/hls/fixture%2Fextra.m3u8", "https://edgestream7.pro/hls/%66ixture.m3u8",
            "https://edgestream7.pro/hls/../fixture.m3u8", "https://edgestream7.pro/hls/.m3u8",
            "https://edgestream4.pro/hls/fixture.m3u8"] {
            XCTAssertTrue(try sessions([streamJSON(url: value)]).isEmpty)
        }
        XCTAssertEqual(try sessions([streamJSON(url: "https://edgestream7.pro:443/hls/fixture.m3u8")]).count, 1)
    }

    func testRequiredHeaderDonationProviderAndMalformedSiblingContractsFailClosed() throws {
        let rejected: [[String: Any]] = [
            streamJSON(name: "Other LivXowProvider"), streamJSON(name: "🎬LivXowProviderLookalike"),
            streamJSON(name: "🎬LivXowProvider\nAuto"), streamJSON(name: "🎬LivXowProvider \u{200D} Auto"),
            streamJSON(name: "🎬LivXowProvider \u{202E} Auto"),
            streamJSON(headers: [:]), streamJSON(headers: ["User-Agent": "unknown"]),
            streamJSON(headers: CNCSportsAddonClient.reviewedHeaders.merging(["Cookie": "private"]) { _, new in new }),
            streamJSON(headers: CNCSportsAddonClient.reviewedHeaders.merging(["Origin": "https://other.example"]) { _, new in new }),
            streamJSON(headers: CNCSportsAddonClient.reviewedHeaders.merging(["Referer": "https://streame.center/other"]) { _, new in new }),
            streamJSON(headers: CNCSportsAddonClient.reviewedHeaders.merging(["User-Agent": "Chrome/112"]) { _, new in new }),
            streamJSON().merging(["externalUrl": "https://example.com"]) { _, new in new },
            streamJSON().merging(["infoHash": "unreviewed"]) { _, new in new },
            streamJSON().merging(["drm": ["license": "unreviewed"]]) { _, new in new },
            streamJSON().merging(["behaviorHints": NSNull()]) { _, new in new },
            streamJSON().merging(["behaviorHints": ["proxyHeaders": ["request": NSNull()]]]) { _, new in new },
            streamJSON().merging(["behaviorHints": ["proxyHeaders": ["request": CNCSportsAddonClient.reviewedHeaders,
                "response": ["Access-Control-Allow-Origin": "*"]]]]) { _, new in new }
        ]
        for row in rejected { XCTAssertTrue(try sessions([row]).isEmpty) }
        let donation: [String: Any] = ["name": "support the project", "externalUrl": "https://example.com"]
        XCTAssertEqual(try sessions([donation, rejected[0], streamJSON()]).map(\.providerName), ["LS1"])
    }

    func testSixDeliveryCapDeduplicationAndHeaderSortedOpaqueKeyAreStable() throws {
        let rows = (0..<8).map { streamJSON(url: "https://edgestream7.pro/hls/fixture_\($0).m3u8") }
        let sessions = try sessions([rows[0]] + rows)
        XCTAssertEqual(sessions.count, 6); XCTAssertEqual(sessions.map(\.providerName), (1...6).map { "LS\($0)" })
        let url = try XCTUnwrap(URL(string: delivery))
        let headers = CNCSportsAddonClient.reviewedHeaders
        let reversed = Dictionary(uniqueKeysWithValues: headers.sorted { $0.key > $1.key })
        XCTAssertEqual(CNCSportsAddonClient.sourceKey(url: url, headers: headers), CNCSportsAddonClient.sourceKey(url: url, headers: reversed))
        XCTAssertNotEqual(CNCSportsAddonClient.sourceKey(url: url, headers: headers), CNCSportsAddonClient.sourceKey(url: url, headers: [:]))
    }

    func testMetadataOriginAndConfigurationRemainBoundedWithoutCookiesOrCredentials() {
        XCTAssertTrue(CNCSportsAddonClient.isSafeMetadataURL(CNCSportsAddonClient.manifestURL))
        for value in ["http://cncverse.dpdns.org/manifest.json", "https://cncverse.dpdns.org:8443/manifest.json",
            "https://cncverse.dpdns.org.evil.example/manifest.json", "https://user@cncverse.dpdns.org/manifest.json",
            "https://cncverse.dpdns.org/manifest.json?key=private", "https://cncverse.dpdns.org/manifest.json#other"] {
            XCTAssertFalse(CNCSportsAddonClient.isSafeMetadataURL(URL(string: value)!))
        }
        let config = CNCSportsAddonClient.makeConfiguration()
        XCTAssertEqual(config.timeoutIntervalForRequest, 7); XCTAssertEqual(config.timeoutIntervalForResource, 12)
        XCTAssertFalse(config.waitsForConnectivity); XCTAssertNil(config.httpCookieStorage); XCTAssertNil(config.urlCredentialStorage)
        XCTAssertFalse(CNCSportsAddonClient.supports(category: "football"))
        XCTAssertTrue(CNCSportsAddonClient.supports(category: "cricket"))
        XCTAssertFalse(CNCSportsAddonClient.supports(category: "basketball"))
        XCTAssertFalse(CNCSportsAddonClient.supports(category: "nba"))
        XCTAssertTrue(CNCSportsAddonClient.supports(category: "hockey"))
        XCTAssertTrue(CNCSportsAddonClient.supports(category: "nhl"))
    }

    func testBatchSharesOneCatalogAndLeavesDateVerificationToWatch() async throws {
        let session = try fixtureSession(catalog: .json(["metas": [catalogJSON(),
            catalogJSON(id: secondID, name: "🔴 Capitals vs Flyers")]]))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session)
        let requests = [request(), capitalsFlyersRequest(), request(category: "football")]
        let rows = try await client.catalogMatches(for: requests, now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.needsVerification, .needsVerification, .unsupported])
        XCTAssertEqual(rows.prefix(2).map(\.providerEventID), [fixtureID, secondID])
        XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", catalogPath])
        _ = try await client.catalogMatches(for: requests, now: kickoff.addingTimeInterval(1))
        XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", catalogPath], "Exact-meta and streams remain Watch-only")
    }

    func testBatchRetainsCatalogSiblingConflictWithoutFetchingMetadata() async throws {
        let session = try fixtureSession(catalog: .json(["metas": [catalogJSON(), catalogJSON(name: "🔴 Other vs Another")]]))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let rows = try await CNCSportsAddonClient(session: session).catalogMatches(for: [request()], now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.conflicting])
        XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", catalogPath])
    }

    func testCancelledCatalogBatchCannotPublishOrStartMetadata() async throws {
        let gate = CNCFixtureGate("batch catalog")
        let session = try fixtureSession(catalog: .controlled(gate))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session), requests = [request()]
        let operation = Task { try await client.catalogMatches(for: requests, now: self.kickoff) }
        defer { operation.cancel(); gate.respond(.failure(URLError(.cancelled))) }
        await fulfillment(of: [gate.started], timeout: 2)
        operation.cancel(); gate.respond(try .json(["metas": [catalogJSON()]]))
        do { _ = try await operation.value; XCTFail("Cancelled batch cannot publish") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", catalogPath])
    }

    @MainActor
    func testBatchKeepsNHLOnlyScopeAndRequestBoundWithoutReads() async throws {
        let session = try fixtureSession()
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let base = request()
        let event = EventReference(id: base.matchID, title: base.displayTitle, category: "hockey",
            date: Int64(kickoff.timeIntervalSince1970), poster: nil, popular: false, teams: nil, sources: [], competitionID: "ahl")
        let otherLeague = StreamPlaybackRequest(matchID: base.matchID, displayTitle: base.displayTitle,
            homeTeam: base.homeTeam, awayTeam: base.awayTeam, category: "hockey", kickoffDate: kickoff, preferredEvent: event)
        let client = CNCSportsAddonClient(session: session)
        let rows = try await client.catalogMatches(for: [otherLeague, request(category: "cricket")], now: kickoff)
        XCTAssertEqual(rows.map(\.outcome), [.unsupported, .unsupported])
        do { _ = try await client.catalogMatches(for: Array(repeating: base, count: 257), now: kickoff); XCTFail("Bound") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .invalidResponse) }
        XCTAssertTrue(CNCFixtureProtocol.paths.isEmpty)
    }

    func testActualClientRoutesOpaqueIDThroughMetadataBeforeStreamsAndRetainsStageTimeouts() async throws {
        let session = try fixtureSession(); defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session)
        let result = try await client.resolve(for: request(), now: kickoff)
        XCTAssertEqual(result.map(\.providerName), ["LS1"])
        XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", catalogPath, metaPath(fixtureID), streamPath(fixtureID)])
        XCTAssertEqual(CNCFixtureProtocol.timeouts, [7, 7, 7, 11])
        XCTAssertTrue(CNCFixtureProtocol.hosts.allSatisfy { $0 == "cncverse.dpdns.org" })
        _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(1))
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == metaPath(fixtureID) }.count, 2, "Metadata is not retained in an unbounded cache")
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 1)
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == catalogPath }.count, 1)
    }

    func testCatalogPreselectionBoundsStopBeforeAnyMetadataRequest() async throws {
        for rows in [[], [catalogJSON(name: "🔴 Other vs Another")],
                     [catalogJSON(), catalogJSON(id: secondID), catalogJSON(id: "cnc:third")]] {
            let session = try fixtureSession(catalog: .json(["metas": rows]))
            defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
            do { _ = try await CNCSportsAddonClient(session: session).resolve(for: request()); XCTFail("Expected no source") }
            catch { XCTAssertTrue(error is CommunitySportsAddonError) }
            XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", catalogPath])
        }
    }

    func testInvalidOrConflictingMetadataCannotReachStreamEndpoint() async throws {
        for value in [metadataJSON(name: "Other vs Another"), metadataJSON(description: "LIVE"),
                      metadataJSON(description: description(time: "20:00")), metadataJSON(id: secondID)] {
            let session = try fixtureSession(meta: .json(["meta": value]))
            defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
            do { _ = try await CNCSportsAddonClient(session: session).resolve(for: request()); XCTFail("Expected no source") }
            catch { XCTAssertTrue(error is CommunitySportsAddonError) }
            XCTAssertFalse(CNCFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
        }
    }

    func testMetadataFailureKeepsItsActualStageAndCancelsTheLane() async throws {
        let session = try fixtureSession(meta: .status(503)); defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        do { _ = try await CNCSportsAddonClient(session: session).resolve(for: request()); XCTFail("Expected metadata failure") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .httpFailure(statusCode: 503, stage: .metadata)) }
        XCTAssertFalse(CNCFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
    }

    func testTwoExactPairMetadataRequestsRunInParallelBeforeDatedSelection() async throws {
        let first = CNCFixtureGate("first metadata"); let second = CNCFixtureGate("second metadata")
        let session = try fixtureSession(catalog: .json(["metas": [catalogJSON(), catalogJSON(id: secondID)]]),
                                        meta: .controlled(first))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        CNCFixtureProtocol.setResponse(.controlled(second), for: metaPath(secondID))
        let operation = Task { try await CNCSportsAddonClient(session: session).resolve(for: self.request()) }
        defer { operation.cancel() }
        await fulfillment(of: [first.started, second.started], timeout: 3)
        first.respond(try .json(["meta": metadataJSON()]))
        second.respond(try .json(["meta": metadataJSON(id: secondID, description: description(time: "21:00"))]))
        let result = try await operation.value
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0.hasPrefix("/meta/") }.count, 2)
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0.hasPrefix("/stream/") }, [streamPath(fixtureID)])
    }

    func testEmptyCatalogUsesShortTTLAndValidCatalogUsesTwoMinuteTTL() async throws {
        let session = try fixtureSession(catalog: .json(["metas": []])); defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session)
        for offset in [0.0, 14.0] {
            do { _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(offset)); XCTFail("Expected empty") }
            catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        }
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == catalogPath }.count, 1)
        CNCFixtureProtocol.setResponse(try .json(["metas": [catalogJSON()]]), for: catalogPath)
        _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(15))
        _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(134))
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == catalogPath }.count, 2)
        _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(135))
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == catalogPath }.count, 3)
    }

    func testLateOlderManifestCannotOverwriteNewerPublishedSnapshot() async throws {
        let gate = CNCFixtureGate("older manifest")
        let session = try fixtureSession(manifest: .controlled(gate)); defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session)
        let older = Task { try await client.resolve(for: self.request(), now: self.kickoff) }; defer { older.cancel() }
        await fulfillment(of: [gate.started], timeout: 3)
        CNCFixtureProtocol.setResponse(try .json(manifestJSON(version: "newer")), for: "/manifest.json")
        _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(1))
        gate.respond(try .json(manifestJSON(version: "older")))
        let original = try await older.value
        XCTAssertEqual(original.first?.diagnosticMetadata["addon_version"], "older")
        let current = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(2))
        XCTAssertEqual(current.first?.diagnosticMetadata["addon_version"], "newer")
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == "/manifest.json" }.count, 2)
    }

    func testLateOlderCatalogCannotOverwriteNewerPublishedSnapshot() async throws {
        let gate = CNCFixtureGate("older catalog")
        let session = try fixtureSession(catalog: .controlled(gate)); defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let client = CNCSportsAddonClient(session: session)
        let older = Task { try await client.resolve(for: self.request(), now: self.kickoff) }; defer { older.cancel() }
        await fulfillment(of: [gate.started], timeout: 3)
        CNCFixtureProtocol.setResponse(try .json(["metas": [catalogJSON()]]), for: catalogPath)
        _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(1))
        gate.respond(try .json(["metas": []]))
        do { _ = try await older.value; XCTFail("Expected original caller's empty catalog") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        _ = try await client.resolve(for: request(), now: kickoff.addingTimeInterval(2))
        XCTAssertEqual(CNCFixtureProtocol.paths.filter { $0 == catalogPath }.count, 2)
    }

    func testCatalogRowAndTransportBodyLimitsRejectBeforeMetadata() async throws {
        let rows = Array(repeating: catalogJSON(id: "cnc:row"), count: 601)
        for response in [try CNCFixtureProtocol.Response.json(["metas": rows]),
                         .body(Data(repeating: 32, count: 512 * 1024 + 1))] {
            let session = try fixtureSession(catalog: response); defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
            do { _ = try await CNCSportsAddonClient(session: session).resolve(for: request()); XCTFail("Expected bounded rejection") }
            catch { XCTAssertTrue(error is CommunitySportsAddonError) }
            XCTAssertFalse(CNCFixtureProtocol.paths.contains { $0.hasPrefix("/meta/") })
        }
    }

    @MainActor
    private func wbblRequest(at start: Date? = nil, format: CricketFixtureCatalog.Format = .t20,
                             verified: Bool = true, conflict: Bool = false,
                             status: CricketFixtureCatalog.Status = .scheduled) -> StreamPlaybackRequest {
        let start = start ?? ISO8601DateFormatter().date(from: "2026-11-05T04:40:00Z")!
        let home = "Adelaide Strikers Women", away = "Brisbane Heat Women", competition = "Women's Big Bash League"
        let metadata = CricketFixtureMetadata(fixtureID: "offline-wbbl", competitionID: "wbbl",
            competitionName: competition, format: format, status: status, observedAt: start, verified: verified)
        let event = EventReference(id: CricketFixtureCatalog.fixtureIDPrefix + metadata.fixtureID,
            title: "\(competition) · \(home) vs \(away)", category: "cricket",
            date: Int64(start.timeIntervalSince1970 * 1000), poster: nil, popular: false,
            teams: .init(home: .init(name: home, badge: nil), away: .init(name: away, badge: nil)), sources: [],
            hasCatalogIdentityConflict: conflict, cricketFixture: metadata)
        return StreamPlaybackRequest(event: event)
    }

    private var wbblName: String { "Adelaide Strikers Women vs Brisbane Heat Women" }
    private var wbblDescription: String {
        "📌 Cricket\n🏆 Women's Big Bash League\n🕐 Nov 05, 2026 04:40 UTC\n\n📡 Available Servers: 7"
    }
    private var wbblDelivery: String {
        "https://bl.rutube.ru/livestream/" + String(repeating: "a", count: 32)
            + "/index.m3u8?s=" + String(repeating: "A", count: 22) + "&e=4102444800&scheme=https"
    }
    private func wbblStreamJSON() -> [String: Any] {
        ["name": "🎬PlayZTVProvider 😮‍💨 Auto • CNCVerse Bridge", "title": "SKY CRICKET - AQ", "url": wbblDelivery,
         "behaviorHints": ["bingeGroup": "cncverse-playztv-live-events", "notWebReady": true,
                           "filename": "Offline WBBL", "proxyHeaders": ["request": CNCSportsAddonClient.reviewedCricketHeaders]]]
    }

    @MainActor
    func testWBBLRequiresAcceptedOfficialFormatExactDateTeamsAndCompetition() throws {
        let request = wbblRequest(), row = catalogEntry(name: "🔜 " + wbblName)
        let meta = metadata(name: wbblName, description: wbblDescription)
        XCTAssertTrue(CNCSportsAddonClient.supportsReviewedCricket(request))
        XCTAssertFalse(CNCSportsAddonClient.supportsReviewedCricket(wbblRequest(format: .test)))
        XCTAssertFalse(CNCSportsAddonClient.supportsReviewedCricket(wbblRequest(format: .odi)))
        XCTAssertFalse(CNCSportsAddonClient.supportsReviewedCricket(wbblRequest(verified: false)))
        XCTAssertFalse(CNCSportsAddonClient.supportsReviewedCricket(wbblRequest(conflict: true)))
        for status: CricketFixtureCatalog.Status in [.finished, .postponed, .cancelled] {
            XCTAssertFalse(CNCSportsAddonClient.supportsReviewedCricket(wbblRequest(status: status)))
        }
        XCTAssertEqual(try CNCSportsAddonClient.selectCricketMetadata(for: request, catalog: [row], metadata: [meta],
            at: request.kickoffDate!).id, fixtureID)
        for text in [wbblDescription.replacingOccurrences(of: "Nov 05", with: "Nov 06"),
                     wbblDescription.replacingOccurrences(of: "04:40", with: "04:41"),
                     wbblDescription.replacingOccurrences(of: "Women's Big Bash League", with: "Big Bash League"),
                     wbblDescription.replacingOccurrences(of: "UTC", with: "IST"),
                     wbblDescription.replacingOccurrences(of: "Nov 05", with: "Feb 30")] {
            XCTAssertThrowsError(try CNCSportsAddonClient.selectCricketMetadata(for: request, catalog: [row],
                metadata: [metadata(name: wbblName, description: text)], at: request.kickoffDate!))
        }
        XCTAssertThrowsError(try CNCSportsAddonClient.selectCricketMetadata(for: request, catalog: [row],
            metadata: [metadata(name: "Adelaide Strikers vs Brisbane Heat", description: wbblDescription)], at: request.kickoffDate!))
        XCTAssertThrowsError(try CNCSportsAddonClient.cricketCatalogIDs(for: request,
            from: [row, catalogEntry(name: "🔜 Perth Scorchers Women vs Sydney Thunder Women")]))
    }

    func testWBBLTransportRejectsOtherHostsPathsCredentialsDRMAndExpiredSignatures() throws {
        XCTAssertTrue(CNCSportsAddonClient.isAdmittedCricketDelivery(URL(string: wbblDelivery)!))
        for value in [wbblDelivery.replacingOccurrences(of: "https://", with: "http://"),
                      wbblDelivery.replacingOccurrences(of: "bl.rutube.ru", with: "bl.rutube.ru.example.com"),
                      wbblDelivery.replacingOccurrences(of: "/livestream/", with: "/other/"),
                      wbblDelivery.replacingOccurrences(of: "4102444800", with: "1000000000"),
                      wbblDelivery + "&cookie=private", wbblDelivery + "&s=duplicate", wbblDelivery + "#fragment",
                      wbblDelivery.replacingOccurrences(of: "bl.rutube.ru", with: "user:pass@bl.rutube.ru")] {
            XCTAssertFalse(CNCSportsAddonClient.isAdmittedCricketDelivery(URL(string: value)!), value)
        }
        XCTAssertFalse(CNCSportsAddonClient.isAdmittedCricketHeaders(["User-Agent": "Mozilla/5.0 \r\nCookie: private"]))
        XCTAssertFalse(CNCSportsAddonClient.isAdmittedCricketHeaders(CNCSportsAddonClient.reviewedCricketHeaders.merging(["Cookie":"private"]) { _, b in b }))
        var drm = wbblStreamJSON(); drm["clearkey"] = "not-admitted"
        XCTAssertFalse(try JSONDecoder().decode(CNCSportsStreamEntry.self, from: data(drm)).isReviewedCricketContract)
        var response = wbblStreamJSON()
        response["behaviorHints"] = ["bingeGroup": "cncverse-playztv-live-events", "notWebReady": true,
            "proxyHeaders": ["request": CNCSportsAddonClient.reviewedCricketHeaders, "response": ["Set-Cookie": "private"]]]
        XCTAssertFalse(try JSONDecoder().decode(CNCSportsStreamEntry.self, from: data(response)).isReviewedCricketContract)
    }

    @MainActor
    func testWBBLResolutionUsesNormalAdapterAndPreservesGuardedRelayAndRenewalBinding() async throws {
        let request = wbblRequest()
        var manifest = manifestJSON(version: "2.73.31")
        manifest["catalogs"] = [["id": CNCSportsAddonClient.catalogID, "type": "tv"],
                                ["id": CNCSportsAddonClient.cricketCatalogID, "type": "tv"]]
        let session = try fixtureSession(manifest: .json(manifest),
            meta: .json(["meta": metadataJSON(name: wbblName, description: wbblDescription)]),
            streams: .json(["streams": [wbblStreamJSON(), streamJSON()]]))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let cricketPath = "/catalog/tv/" + CNCSportsAddonClient.cricketCatalogID + ".json"
        CNCFixtureProtocol.setResponse(try .json(["metas": [catalogJSON(name: "🔜 " + wbblName)]]), for: cricketPath)
        let client = CNCSportsAddonClient(session: session)
        let catalog = try await client.catalogMatches(for: [request], now: request.kickoffDate!)
        XCTAssertEqual(catalog.first?.outcome, .needsVerification)
        let sessions = try await client.resolve(for: request, now: request.kickoffDate!)
        XCTAssertEqual(sessions.map(\.providerName), ["LS1"])
        let result = try XCTUnwrap(sessions.first)
        XCTAssertEqual(result.requiredHeaders, CNCSportsAddonClient.reviewedCricketHeaders)
        XCTAssertEqual(result.requiresGuardedRelay, true)
        XCTAssertTrue(result.eventBinding?.matches(request: request, providerCode: "cncsports", at: request.kickoffDate!) == true)
        XCTAssertTrue(LiveStreamResolver.supportsDescriptorRenewal(result))
        XCTAssertFalse(CNCSportsAddonClient.isReviewedNativeSession(result), "Do not inherit NHL-specific timing before measurement")
        XCTAssertEqual(CNCFixtureProtocol.paths, ["/manifest.json", cricketPath, metaPath(fixtureID), streamPath(fixtureID)])
    }

    @MainActor
    func testNormalWatchOnlyAddsCNCCricketForItsReviewedFixtureAndExistingOptIn() throws {
        let definition = try XCTUnwrap(CuratedStreamSourceCatalog.definition(forProviderCode: "cncsports"))
        let good = wbblRequest()
        XCTAssertTrue(definition.supportsOptionalFixture(event: good.preferredEvent!))
        XCTAssertEqual(CuratedStreamSourceCatalog.discoveryPlan(for: good,
            enabledProviderCodes: ["cncsports"], at: good.kickoffDate!).optionalSources.map(\.providerCode), ["cncsports"])
        XCTAssertTrue(CuratedStreamSourceCatalog.discoveryPlan(for: good,
            enabledProviderCodes: [], at: good.kickoffDate!).optionalSources.isEmpty)
        for other in [wbblRequest(format: .test), wbblRequest(verified: false), wbblRequest(status: .finished)] {
            XCTAssertFalse(definition.supportsOptionalFixture(event: other.preferredEvent!))
            XCTAssertTrue(CuratedStreamSourceCatalog.discoveryPlan(for: other,
                enabledProviderCodes: ["cncsports"], at: other.kickoffDate!).optionalSources.isEmpty)
        }
    }

    @MainActor
    func testCricketCatalogFailureCannotEraseExistingNHLEvidenceAndViceVersa() async throws {
        for failingCricket in [true, false] {
            var manifest = manifestJSON()
            manifest["catalogs"] = [["id": CNCSportsAddonClient.catalogID, "type": "tv"],
                                    ["id": CNCSportsAddonClient.cricketCatalogID, "type": "tv"]]
            let session = try fixtureSession(manifest: .json(manifest))
            defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
            let cricketPath = "/catalog/tv/" + CNCSportsAddonClient.cricketCatalogID + ".json"
            CNCFixtureProtocol.setResponse(try .json(["metas": [catalogJSON(name: "🔜 " + wbblName)]]), for: cricketPath)
            CNCFixtureProtocol.setResponse(.status(503), for: failingCricket ? cricketPath : catalogPath)
            let results = try await CNCSportsAddonClient(session: session).catalogMatches(for: [request(), wbblRequest()])
            XCTAssertEqual(results[failingCricket ? 0 : 1].outcome, .needsVerification)
            if case .failed = results[failingCricket ? 1 : 0].outcome {} else { XCTFail("Failure must remain scoped to its catalog") }
        }
    }

    @MainActor
    func testWBBLConflictingMetadataCannotReachStreamsOrUseNHLCatalog() async throws {
        let request = wbblRequest()
        var manifest = manifestJSON()
        manifest["catalogs"] = [["id": CNCSportsAddonClient.catalogID, "type": "tv"],
                                ["id": CNCSportsAddonClient.cricketCatalogID, "type": "tv"]]
        let session = try fixtureSession(manifest: .json(manifest),
            meta: .json(["meta": metadataJSON(name: wbblName,
                description: wbblDescription.replacingOccurrences(of: "04:40", with: "05:40"))]))
        defer { session.invalidateAndCancel(); CNCFixtureProtocol.reset() }
        let cricketPath = "/catalog/tv/" + CNCSportsAddonClient.cricketCatalogID + ".json"
        CNCFixtureProtocol.setResponse(try .json(["metas": [catalogJSON(name: "🔜 " + wbblName)]]), for: cricketPath)
        do { _ = try await CNCSportsAddonClient(session: session).resolve(for: request, now: request.kickoffDate!); XCTFail("Expected mismatch") }
        catch { XCTAssertEqual(error as? CommunitySportsAddonError, .matchNotFound) }
        XCTAssertFalse(CNCFixtureProtocol.paths.contains(catalogPath))
        XCTAssertFalse(CNCFixtureProtocol.paths.contains { $0.hasPrefix("/stream/") })
    }

    private var catalogPath: String { "/catalog/tv/" + CNCSportsAddonClient.catalogID + ".json" }
    private func metaPath(_ id: String) -> String { "/meta/tv/" + id + ".json" }
    private func streamPath(_ id: String) -> String { "/stream/tv/" + id + ".json" }
    private func request(category: String = "hockey", at: Date? = nil) -> StreamPlaybackRequest {
        .init(matchID: "existing-nhl-fixture", displayTitle: "Chicago Blackhawks vs Montreal Canadiens",
              homeTeam: "Chicago Blackhawks", awayTeam: "Montreal Canadiens", category: category, kickoffDate: at ?? kickoff)
    }
    private func capitalsFlyersRequest() -> StreamPlaybackRequest {
        .init(matchID: "sports-fixture:nhl:2026020199", displayTitle: "Washington Capitals vs Philadelphia Flyers",
              homeTeam: "Washington Capitals", awayTeam: "Philadelphia Flyers", category: "hockey",
              kickoffDate: ISO8601DateFormatter().date(from: "2026-10-28T23:30:00Z")!)
    }
    private var capitalsFlyersDescription: String {
        "📌 Hockey\n🏆 NHL\n🕐 Oct 28, 2026 23:30 UTC\n\n📡 Available Servers: 1"
    }
    private func description(time: String = "00:00") -> String { "📌 Hockey\n🏆 NHL\n🕐 Oct 24, 2026 \(time) UTC\n\n📡 Available Servers: 1" }
    private func catalogEntry(id: String? = nil, type: String = "tv", name: String = "🔴 Blackhawks vs Canadiens") -> CNCSportsCatalogEntry {
        .init(id: id ?? fixtureID, type: type, name: name)
    }
    private func metadata(id: String? = nil, type: String = "tv", name: String = "Blackhawks vs Canadiens",
                          description: String?) -> CNCSportsMetadata {
        .init(id: id ?? fixtureID, type: type, name: name, description: description)
    }
    private func metadata(id: String? = nil, type: String = "tv", name: String = "Blackhawks vs Canadiens") -> CNCSportsMetadata {
        metadata(id: id, type: type, name: name, description: description())
    }
    private func catalogJSON(id: String? = nil, name: String = "🔴 Blackhawks vs Canadiens") -> [String: Any] {
        let id = id ?? fixtureID
        return ["id": id, "type": "tv", "name": name, "behaviorHints": ["defaultVideoId": id]]
    }
    private func metadataJSON(id: String? = nil, name: String = "Blackhawks vs Canadiens", description: String? = nil) -> [String: Any] {
        ["id": id ?? fixtureID, "type": "tv", "name": name, "description": description ?? self.description()]
    }
    private func manifestJSON(version: String = "1.0.30") -> [String: Any] {
        ["id": "com.cncverse.stremiobridge", "version": version, "resources": ["catalog", "meta", "stream", "subtitles"],
         "types": ["movie", "series", "other", "tv"], "catalogs": [["id": CNCSportsAddonClient.catalogID, "type": "tv"]],
         "behaviorHints": ["configurable": false]]
    }
    private func streamJSON(url: String? = nil, name: String = "🎬LivXowProvider 😮‍💨 Auto • CNCVerse Bridge",
                            headers: [String: String] = CNCSportsAddonClient.reviewedHeaders) -> [String: Any] {
        ["url": url ?? delivery, "name": name, "title": "Offline fixture • HLS",
         "behaviorHints": ["proxyHeaders": ["request": headers]]]
    }
    private func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private func sessions(_ rows: [[String: Any]]) throws -> [StreamSession] {
        let streams = rows.compactMap { try? JSONDecoder().decode(CNCSportsStreamEntry.self, from: data($0)) }
        return CNCSportsAddonClient.makeSessions(from: streams, request: request(), addOnVersion: "1.0.30")
    }
    private func fixtureSession(manifest: CNCFixtureProtocol.Response? = nil, catalog: CNCFixtureProtocol.Response? = nil,
                                meta: CNCFixtureProtocol.Response? = nil, streams: CNCFixtureProtocol.Response? = nil) throws -> URLSession {
        CNCFixtureProtocol.configure([
            "/manifest.json": try manifest ?? .json(manifestJSON()), catalogPath: try catalog ?? .json(["metas": [catalogJSON()]]),
            metaPath(fixtureID): try meta ?? .json(["meta": metadataJSON()]),
            streamPath(fixtureID): try streams ?? .json(["streams": [["name": "donation", "externalUrl": "https://example.com"], streamJSON()]])
        ])
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [CNCFixtureProtocol.self]
        configuration.waitsForConnectivity = false; return URLSession(configuration: configuration)
    }
}

/// Every adapter request ends in this offline fixture transport, never a site.
private final class CNCFixtureProtocol: URLProtocol {
    enum Response {
        case body(Data), failure(Error), status(Int), controlled(CNCFixtureGate)
        static func json(_ value: [String: Any]) throws -> Response { .body(try JSONSerialization.data(withJSONObject: value)) }
    }
    private static let lock = NSLock()
    private static var responses: [String: Response] = [:]
    private static var recordedPaths: [String] = []
    private static var recordedTimeouts: [TimeInterval] = []
    private static var recordedHosts: [String] = []
    static var paths: [String] { lock.lock(); defer { lock.unlock() }; return recordedPaths }
    static var timeouts: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return recordedTimeouts }
    static var hosts: [String] { lock.lock(); defer { lock.unlock() }; return recordedHosts }
    static func configure(_ value: [String: Response]) {
        lock.lock(); responses = value; recordedPaths = []; recordedTimeouts = []; recordedHosts = []; lock.unlock()
    }
    static func reset() { configure([:]) }
    static func setResponse(_ value: Response, for path: String) { lock.lock(); responses[path] = value; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let path = request.url?.path ?? ""
        Self.recordedPaths.append(path); Self.recordedTimeouts.append(request.timeoutInterval)
        Self.recordedHosts.append(request.url?.host ?? "")
        let result = Self.responses[path] ?? .failure(URLError(.fileDoesNotExist)); Self.lock.unlock(); complete(result)
    }
    private func complete(_ result: Response) {
        switch result {
        case .body(let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
        case .status(let status):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed); client?.urlProtocolDidFinishLoading(self)
        case .failure(let error): client?.urlProtocol(self, didFailWithError: error)
        case .controlled(let gate): gate.start { [weak self] result in self?.complete(result) }
        }
    }
    override func stopLoading() {}
}

private final class CNCFixtureGate {
    let started: XCTestExpectation
    private let lock = NSLock()
    private var completion: ((CNCFixtureProtocol.Response) -> Void)?
    private var pending: CNCFixtureProtocol.Response?
    init(_ name: String) { started = XCTestExpectation(description: name) }
    func start(_ completion: @escaping (CNCFixtureProtocol.Response) -> Void) {
        lock.lock(); let pending = self.pending; self.pending = nil
        if pending == nil { self.completion = completion }; lock.unlock(); started.fulfill()
        if let pending { completion(pending) }
    }
    func respond(_ result: CNCFixtureProtocol.Response) {
        lock.lock(); let completion = self.completion; self.completion = nil
        if completion == nil { pending = result }; lock.unlock(); completion?(result)
    }
}

/// The registry is a hint, not a gate: when every registered association
/// misses, the same provider's exact direct lookup still gets a chance.
final class RegistryHintDirectFallbackTests: XCTestCase {
    private let start = ISO8601DateFormatter().date(from: "2026-11-07T12:30:00Z")!

    private actor CallCounter {
        private(set) var count = 0
        func hit() { count += 1 }
    }

    private struct ResolveFailure: Error {}

    private func association() -> (StreamPlaybackRequest, BroadcastRegistryMatch) {
        let teams = ["Leeds United", "Tottenham Hotspur"]
        let metadata = SportsFixtureMetadata(fixtureID: "sports-fixture:premier-league:560632", sport: "football",
            competitionID: "premier-league", competitionName: "Premier League", eventKind: .match,
            title: teams.joined(separator: " vs "),
            participants: [.init(id: "lee", name: teams[0]), .init(id: "tot", name: teams[1])],
            squad: .init(gender: .men, ageGroup: "senior"), status: .live, observedAt: start, verified: true)
        let event = EventReference(id: metadata.fixtureID, title: metadata.title, category: "football",
            date: Int64(start.timeIntervalSince1970), poster: nil, popular: false,
            teams: .init(home: .init(name: teams[0], badge: nil), away: .init(name: teams[1], badge: nil)),
            sources: [], sportsFixture: metadata, competitionID: "premier-league")
        let request = StreamPlaybackRequest(event: event), expiry = start.addingTimeInterval(3600)
        let record = BroadcastRegistrySnapshot.Broadcast(id: "br:" + String(repeating: "d", count: 64),
            providerCode: "communitysports", providerEventID: "cs-event", streamID: "cs-event", resourceType: "tv",
            scope: "football", kind: .event, sport: "football", title: metadata.title, participants: teams, start: start,
            competitionID: "premier-league", squad: metadata.squad, observedAt: start, expiresAt: expiry,
            verification: .dated, issues: [])
        let link = BroadcastRegistrySnapshot.Link(fixtureID: event.id, broadcastID: record.id,
            providerCode: "communitysports", state: .listed, matchMethod: .exact,
            fixtureFingerprint: .init(fixtureID: event.id, sport: "football", start: start, participants: teams,
                competitionID: "premier-league", squad: metadata.squad), expiresAt: expiry)
        let match = BroadcastRegistryMatch(broadcast: record, link: link, provider: .init(providerCode: "communitysports",
            scope: "football", status: .available, observedAt: start, expiresAt: expiry))
        return (request, match)
    }

    private func session(_ path: String) -> StreamSession {
        StreamSession(matchID: "sports-fixture:premier-league:560632",
            playableURL: URL(string: "https://direct.example/" + path + ".m3u8")!, streamType: .hls, providerName: "CS")
    }

    func testRegisteredFailureFallsBackToDirectExactLookup() async throws {
        let (request, match) = association(), calls = CallCounter(), direct = session("direct")
        let clock = start
        let choices = try await LiveStreamResolver.resolveRegisteredOptionalSessions(for: request,
            providerCode: "communitysports", associations: [match],
            resolve: { _ in throw ResolveFailure() }, clock: { clock },
            fallback: { await calls.hit(); return [direct] })
        XCTAssertEqual(choices.map(\.playableURL), [direct.playableURL])
        let count = await calls.count
        XCTAssertEqual(count, 1)
    }

    func testUnadmittedRegisteredResultsFallBackToDirectLookup() async throws {
        // A stale association whose descriptor no longer binds to the registry
        // entry is filtered out; the direct lane must still run.
        let (request, match) = association(), direct = session("direct")
        let clock = start
        let choices = try await LiveStreamResolver.resolveRegisteredOptionalSessions(for: request,
            providerCode: "communitysports", associations: [match],
            resolve: { _ in [self.session("unbound")] }, clock: { clock },
            fallback: { [direct] })
        XCTAssertEqual(choices.map(\.playableURL), [direct.playableURL])
    }

    func testWithoutFallbackRegisteredMissStillThrows() async {
        let (request, match) = association()
        let clock = start
        do {
            _ = try await LiveStreamResolver.resolveRegisteredOptionalSessions(for: request,
                providerCode: "communitysports", associations: [match],
                resolve: { _ in throw ResolveFailure() }, clock: { clock })
            XCTFail("Expected the registered miss to throw without a fallback")
        } catch { XCTAssertTrue(error is ResolveFailure) }
    }

    func testEmptyFallbackPreservesOriginalFailure() async {
        let (request, match) = association()
        let clock = start
        do {
            _ = try await LiveStreamResolver.resolveRegisteredOptionalSessions(for: request,
                providerCode: "communitysports", associations: [match],
                resolve: { _ in throw ResolveFailure() }, clock: { clock }, fallback: { [] })
            XCTFail("Expected an empty direct lookup to keep the original failure")
        } catch { XCTAssertTrue(error is ResolveFailure) }
    }

    func testFallbackDeliveriesAreDeduplicated() async throws {
        let (request, match) = association(), direct = session("direct")
        let clock = start
        let choices = try await LiveStreamResolver.resolveRegisteredOptionalSessions(for: request,
            providerCode: "communitysports", associations: [match],
            resolve: { _ in throw ResolveFailure() }, clock: { clock },
            fallback: { [direct, self.session("direct"), self.session("second")] })
        XCTAssertEqual(choices.count, 2)
    }

    func testCancellationNeverStartsDirectFallback() async {
        let (request, match) = association(), calls = CallCounter()
        let clock = start
        let task = Task {
            try await LiveStreamResolver.resolveRegisteredOptionalSessions(for: request,
                providerCode: "communitysports", associations: [match],
                resolve: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    throw ResolveFailure()
                }, clock: { clock },
                fallback: { await calls.hit(); return [] })
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        let count = await calls.count
        XCTAssertEqual(count, 0)
    }
}
