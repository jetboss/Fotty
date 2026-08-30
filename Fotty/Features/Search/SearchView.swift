import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var results: [AnalyticalDataEngine.EventReference] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchError: String?
    @State private var selectionError: String?
    @State private var debounceTask: Task<Void, Never>?
    
    @Environment(LiveScoreService.self) private var liveScoreService
    @EnvironmentObject private var socialCloudStore: SocialCloudStore
    @State private var selectedMatch: FootballMatch?
    
    var body: some View {
        ZStack {
            FottyTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Search bar
                searchBar
                
                if isSearching {
                    Spacer()
                    ProgressView()
                        .tint(FottyTheme.accentText)
                    Spacer()
                } else if let searchError {
                    searchErrorState(searchError)
                } else if results.isEmpty && hasSearched {
                    emptyState
                } else if results.isEmpty {
                    promptState
                } else {
                    resultsList
                }
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $selectedMatch) { match in
            NavigationStack {
                MatchHubView(fixtureId: String(match.id), showModalDismissButton: true)
                    .environment(liveScoreService)
                    .environmentObject(socialCloudStore)
            }
            .fottyStandardSheetChrome()
        }
        .alert("Match Details Unavailable", isPresented: Binding(
            get: { selectionError != nil },
            set: { if !$0 { selectionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(selectionError ?? "This match is not in the current score feed.")
        }
        .onDisappear {
            debounceTask?.cancel()
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: FottyTheme.spacingSM) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FottyTheme.textTertiary)
            
            TextField("Search teams, leagues, matches...", text: $query)
                .foregroundStyle(FottyTheme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    debounceTask?.cancel()
                    debounceTask = Task { await performSearch() }
                }
            
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    hasSearched = false
                    searchError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FottyTheme.textTertiary)
                }
            }
        }
        .padding(FottyTheme.spacingMD)
        .glassBackground()
        .padding(.horizontal, FottyTheme.spacingMD)
        .padding(.vertical, FottyTheme.spacingSM)
        .onChange(of: query) { _, newValue in
            debounceTask?.cancel()
            
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            searchError = nil
            guard !trimmed.isEmpty else {
                isSearching = false
                results = []
                hasSearched = false
                return
            }
            
            debounceTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await performSearch()
            }
        }
    }
    
    private func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        
        isSearching = true
        searchError = nil
        
        do {
            let allEvents = try await AnalyticalDataEngine.allLiveEvents()
            let filtered = allEvents.filter { event in
                let title = (event.title ?? "").lowercased()
                let home = event.homeName.lowercased()
                let away = event.awayName.lowercased()
                let category = event.normalizedCategory.lowercased()
                
                return title.contains(trimmed) || 
                       home.contains(trimmed) || 
                       away.contains(trimmed) || 
                       category.contains(trimmed)
            }
            guard !Task.isCancelled,
                  query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed else {
                return
            }
            
            withAnimation {
                self.results = filtered
                self.hasSearched = true
                self.isSearching = false
            }
        } catch {
            guard !Task.isCancelled,
                  query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed else {
                return
            }
            self.isSearching = false
            self.searchError = "Search could not reach the match catalog. Check your connection and try again."
        }
    }
    
    // MARK: - States
    
    private var promptState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "figure.soccer")
                .font(.system(size: 48))
                .foregroundStyle(FottyTheme.textTertiary)
            Text("Find Your Match")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FottyTheme.textPrimary)
            Text("Search for live matches, upcoming fixtures, or your favorite teams.")
                .font(.system(size: 14))
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(FottyTheme.textTertiary)
            Text("No Results Found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FottyTheme.textPrimary)
            Text("We couldn't find any matches for \"\(query)\".")
                .font(.system(size: 14))
                .foregroundStyle(FottyTheme.textSecondary)
            Spacer()
        }
    }

    private func searchErrorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Search Unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                debounceTask?.cancel()
                debounceTask = Task { await performSearch() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: FottyTheme.spacingMD) {
                ForEach(results) { event in
                    Button {
                        if let match = liveScoreService.findMatch(home: event.homeName, away: event.awayName) {
                            selectedMatch = match
                        } else {
                            selectionError = "Detailed score data for \(event.homeName) vs \(event.awayName) is not available yet."
                        }
                    } label: {
                        SearchEventCard(event: event)
                    }
                }
            }
            .padding(FottyTheme.spacingMD)
        }
    }
}

struct SearchEventCard: View {
    let event: AnalyticalDataEngine.EventReference
    
    var body: some View {
        HStack(spacing: FottyTheme.spacingMD) {
            // Badges
            HStack(spacing: -12) {
                TeamBadgeView(badgeURL: event.homeBadgeURL, teamName: event.homeName, size: 44)
                TeamBadgeView(badgeURL: event.awayBadgeURL, teamName: event.awayName, size: 44)
                    .background(Circle().fill(FottyTheme.surface).padding(2))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title ?? "\(event.homeName) vs \(event.awayName)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FottyTheme.textPrimary)
                    .lineLimit(1)
                
                HStack {
                    Text(event.categoryDisplayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FottyTheme.accentText)
                    
                    if let kickoff = event.kickoffDate {
                        Text("•")
                            .foregroundStyle(FottyTheme.textTertiary)
                        Text(kickoff.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 12))
                            .foregroundStyle(FottyTheme.textSecondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(FottyTheme.textTertiary)
        }
        .padding(FottyTheme.spacingMD)
        .background(FottyTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}
