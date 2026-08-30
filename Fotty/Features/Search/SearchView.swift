import SwiftUI

/// A search projection of Home's already-loaded catalog. Search never fetches
/// a second feed, so its results, timing, reminders, badges, and Watch actions
/// cannot disagree with the Home lineup.
@MainActor
enum HomeSportsSearch {
    enum Result: Identifiable {
        case fixture(HomeSportsDiscovery.Item)
        case channel(AnalyticalDataEngine.EventReference)

        var id: String { event.id }
        var event: AnalyticalDataEngine.EventReference {
            switch self {
            case .fixture(let item): item.event
            case .channel(let event): event
            }
        }
    }

    static func results(
        in discovery: HomeSportsDiscovery,
        query: String,
        leagueName: (AnalyticalDataEngine.EventReference) -> String? = { _ in nil }
    ) -> [Result] {
        let normalizedQuery = normalized(query)
        let tokens = normalizedQuery.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }
        let exactFootballLeagues = Set(
            AnalyticalDataEngine.FootballLeagueTab.allCases
                .filter { $0 != .all && $0 != .other }
                .map { normalized($0.displayName) }
        )

        func matches(_ event: AnalyticalDataEngine.EventReference) -> Bool {
            // "Premier League" must not accidentally return Caribbean Premier
            // League fixtures simply because both contain the same two words.
            if exactFootballLeagues.contains(normalizedQuery) {
                return normalized(leagueName(event) ?? "") == normalizedQuery
            }
            var fields = [
                event.displayTitle,
                event.title ?? "",
                event.homeName,
                event.awayName,
                event.normalizedCategory,
                event.categoryDisplayName,
                leagueName(event) ?? ""
            ]
            if event.isCPLFixture { fields.append("Caribbean Premier League CPL") }
            if event.isBroadcastChannel { fields.append("channel broadcast") }
            let haystack = normalized(fields.joined(separator: " "))
            return tokens.allSatisfy(haystack.contains)
        }

        return discovery.items.filter { matches($0.event) }.map(Result.fixture)
            + discovery.channels.filter(matches).map(Result.channel)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .joined(separator: " ")
    }
}

struct SearchView: View {
    let discovery: HomeSportsDiscovery
    let isSaved: (String) -> Bool
    let canWatch: (AnalyticalDataEngine.EventReference) -> Bool
    let onOpen: (AnalyticalDataEngine.EventReference) -> Void
    let onDetails: (AnalyticalDataEngine.EventReference) -> Void
    let onSave: (AnalyticalDataEngine.EventReference) -> Void

    @State private var query = ""
    @Environment(LiveScoreService.self) private var liveScoreService
    @Environment(\.dismiss) private var dismiss

    private var results: [HomeSportsSearch.Result] {
        HomeSportsSearch.results(in: discovery, query: query, leagueName: leagueName(for:))
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    promptState
                } else if results.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FottyTheme.background.ignoresSafeArea())
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Team, league, sport, or channel"
            )
            .searchSuggestions {
                if query.isEmpty {
                    ForEach(["Premier League", "CPL", "Cricket", "Basketball"], id: \.self) { suggestion in
                        Text(suggestion).searchCompletion(suggestion)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("global-sports-search")
    }

    private var promptState: some View {
        ContentUnavailableView {
            Label("Find what is on", systemImage: "magnifyingglass")
        } description: {
            Text("Search every listed sport, team, league, match, or channel. Results use the same lineup and Watch availability as Home.")
        }
        .padding(FottyTheme.spacingLG)
    }

    private var emptyState: some View {
        ContentUnavailableView.search(text: query)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(resultSummary)
                    .font(FottyTheme.typeMeta)
                    .foregroundStyle(FottyTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)

                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    if index > 0 { Divider().overlay(FottyTheme.border) }
                    resultRow(result)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, FottyTheme.spacingMD)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func resultRow(_ result: HomeSportsSearch.Result) -> some View {
        switch result {
        case .fixture(let item):
            HomeDiscoveryRow(
                item: item,
                isSaved: isSaved(item.id),
                onOpen: { onOpen(item.event) },
                onSave: { onSave(item.event) }
            )
            .accessibilityIdentifier("search-result-\(item.id)")
        case .channel(let event):
            LiveEventCard(
                event: event,
                onWatchTap: canWatch(event) ? { onOpen(event) } : nil,
                onDetailsTap: { onDetails(event) },
                isSaved: isSaved(event.id),
                onSaveTap: { onSave(event) }
            )
            .padding(.vertical, 6)
            .accessibilityIdentifier("search-result-\(event.id)")
        }
    }

    private var resultSummary: String {
        results.count == 1 ? "1 result" : "\(results.count) results"
    }

    private func leagueName(for event: AnalyticalDataEngine.EventReference) -> String? {
        guard event.normalizedCategory == "football" else { return nil }
        let official = liveScoreService.findMatch(
            home: event.homeName,
            away: event.awayName,
            near: event.kickoffDate
        )
        return AnalyticalDataEngine.footballLeagueTab(for: event, officialMatch: official).displayName
    }
}
