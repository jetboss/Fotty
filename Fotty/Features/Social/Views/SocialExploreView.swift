import SwiftUI

struct SocialExploreView: View {
    @Binding var searchText: String
    @Binding var searchScope: SocialDiscoveryScope
    @Binding var searchSort: SocialDiscoverySort
    let discoverableEntries: [SocialDiscoveryEntry]
    let blockedAccountIDs: Set<String>
    let hasDiscoveryQuery: Bool
    let areAllAccountsBlocked: Bool
    
    let isFollowing: (String) -> Bool
    let onToggleFollow: (SocialDiscoveryEntry) -> Void
    let onMute: (SocialDiscoveryEntry) -> Void
    let onBlock: (SocialDiscoveryEntry) -> Void
    let onReport: (SocialDiscoveryEntry) -> Void
    let onClearBlocked: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: FottyTheme.spacingMD) {
            SectionHeader(
                title: "Search & Discovery",
                subtitle: "Find people by name, username, or category"
            )

            VStack(spacing: FottyTheme.spacingSM) {
                searchHeader
                filtersHeader

                if discoverableEntries.isEmpty {
                    emptyStateSection
                } else {
                    resultsList
                    blockedStatusFooter
                }
            }
            .padding(.horizontal, FottyTheme.spacingMD)
        }
    }
    
    private var searchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FottyTheme.textTertiary)
            TextField("Search social accounts", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(.horizontal, FottyTheme.spacingMD)
        .padding(.vertical, 10)
        .cardStyle()
    }
    
    private var filtersHeader: some View {
        VStack(spacing: 8) {
            Picker("Category", selection: $searchScope) {
                ForEach(SocialDiscoveryScope.allCases) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            
            HStack {
                Text("Sort")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FottyTheme.textSecondary)
                Spacer()
                Picker("Sort", selection: $searchSort) {
                    ForEach(SocialDiscoverySort.allCases) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(.horizontal, FottyTheme.spacingMD)
        .padding(.vertical, 10)
        .cardStyle()
    }
    
    private var emptyStateSection: some View {
        Group {
            if areAllAccountsBlocked {
                VStack(alignment: .leading, spacing: 10) {
                    socialEmptyStateCard(text: "All discovered accounts are currently blocked.")
                    Button("Clear Blocked Accounts") {
                        onClearBlocked()
                    }
                    .pillButtonStyle(accent: true)
                }
            } else {
                socialEmptyStateCard(text: hasDiscoveryQuery ? "No accounts match your search." : "No social accounts available yet.")
            }
        }
    }
    
    private var resultsList: some View {
        ForEach(discoverableEntries) { account in
            SocialDiscoveryRow(
                entry: account,
                isFollowing: isFollowing(account.id),
                onFollow: { onToggleFollow(account) },
                onMute: { onMute(account) },
                onBlock: { onBlock(account) },
                onReport: { onReport(account) }
            )
        }
    }
    
    private var blockedStatusFooter: some View {
        Group {
            if !blockedAccountIDs.isEmpty {
                HStack {
                    Text("\(blockedAccountIDs.count) blocked")
                        .font(.system(size: 11))
                        .foregroundStyle(FottyTheme.textSecondary)
                    Spacer()
                    Button("Clear Blocked Accounts") {
                        onClearBlocked()
                    }
                    .pillButtonStyle(accent: true)
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    private func socialEmptyStateCard(text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark.fill")
                .font(.system(size: 32))
                .foregroundStyle(FottyTheme.textTertiary)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(FottyTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(FottyTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
