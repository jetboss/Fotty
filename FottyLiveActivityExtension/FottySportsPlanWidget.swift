import SwiftUI
import UIKit
import WidgetKit

private struct FottySportsPlanEntry: TimelineEntry {
    let date: Date
    let snapshot: SportsWidgetSnapshot?
}

private struct FottySportsPlanProvider: TimelineProvider {
    func placeholder(in context: Context) -> FottySportsPlanEntry {
        // Neutral gallery placeholder; no fabricated live match/score.
        .init(date: Date(), snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (FottySportsPlanEntry) -> Void) {
        completion(load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FottySportsPlanEntry>) -> Void) {
        let entry = load()
        var entries = [entry]
        for expiry in entry.snapshot?.expiryDates ?? [] where expiry > entry.date {
            entries.append(.init(date: expiry, snapshot: entry.snapshot))
        }
        // Earliest request, not a promised poll. WidgetKit owns its refresh budget.
        completion(.init(entries: entries, policy: .after(entry.date.addingTimeInterval(15 * 60))))
    }
    private func load() -> FottySportsPlanEntry {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SportsWidgetSnapshot.appGroup) != nil,
              let data = UserDefaults(suiteName: SportsWidgetSnapshot.appGroup)?.data(forKey: SportsWidgetSnapshot.storageKey) else {
            return .init(date: Date(), snapshot: nil)
        }
        return .init(date: Date(), snapshot: SportsWidgetSnapshot.decode(data))
    }
}

struct FottySportsPlanWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FottySportsPlanWidget", provider: FottySportsPlanProvider()) { entry in
            FottySportsPlanWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
                .widgetURL(URL(string: "fotty://sports-plan"))
        }
        .configurationDisplayName("Your sports plan")
        .description("Your saved matches and scheduled starts. Open Fotty for current availability.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct FottySportsPlanWidgetView: View {
    let entry: FottySportsPlanEntry
    @Environment(\.widgetFamily) private var family
    private let accent = Color(red: 0.96, green: 0.63, blue: 0.13)
    private var rows: [SportsWidgetSnapshot.Match] {
        guard let snapshot = entry.snapshot, snapshot.isFresh(at: entry.date) else { return [] }
        return Array(snapshot.matches.filter { $0.effectivePhase(at: entry.date) != .finished }
            .prefix(family == .systemLarge ? 4 : 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your sports plan").font(.headline)
                Spacer(minLength: 4)
                Image(systemName: "sportscourt").foregroundStyle(accent)
            }
            if rows.isEmpty {
                Spacer(minLength: 0)
                Image(systemName: "calendar").font(.title2).foregroundStyle(.secondary)
                Text(entry.snapshot?.matches.isEmpty == true ? "Save a match in Fotty" : "Open Fotty for your plan")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(rows) { match in
                    // Small widgets have one whole-widget destination. Per-row
                    // links are supported only by the larger system families.
                    if family != .systemSmall, let url = match.deepLink {
                        Link(destination: url) { matchRow(match) }
                    } else { matchRow(match) }
                    if family == .systemLarge, match.id != rows.last?.id { Divider() }
                }
                Spacer(minLength: 0)
                if family != .systemSmall {
                    Text("Open Fotty for current streams").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func matchRow(_ match: SportsWidgetSnapshot.Match) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                badge(match.homeBadgeFile, category: match.category)
                if !match.awayName.isEmpty { badge(match.awayBadgeFile, category: match.category) }
                if family != .systemSmall {
                    Text(match.competition ?? sportName(match.category))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let score = match.currentScore(at: entry.date) {
                    Text(score).font(.headline).monospacedDigit()
                }
            }
            Text(match.awayName.isEmpty ? match.homeName : "\(match.homeName) · \(match.awayName)")
                .font(.subheadline.weight(.semibold)).lineLimit(family == .systemSmall ? 3 : 2)
                .foregroundStyle(.primary)
            HStack(spacing: 5) {
                switch match.effectivePhase(at: entry.date) {
                case .live: Text("Live").foregroundStyle(.red)
                case .listed: Text("Broadcast listed").foregroundStyle(.secondary)
                case .unconfirmed: Text("Open for latest status").foregroundStyle(.secondary)
                case .finished: Text("Finished").foregroundStyle(.secondary)
                case .scheduled:
                    if let kickoff = match.kickoff {
                        Text(kickoff, style: .time)
                    } else { Text("Time to be confirmed") }
                }
            }
            .font(.caption).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func badge(_ filename: String?, category: String) -> some View {
        if let filename, let url = SportsWidgetSnapshot.badgeURL(filename: filename),
           let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > 0, size <= 128 * 1024,
           let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count <= 128 * 1024,
           let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit().frame(width: 26, height: 26)
        } else {
            Image(systemName: sportSymbol(category)).font(.body).foregroundStyle(.secondary).frame(width: 26, height: 26)
        }
    }
    private func sportSymbol(_ category: String) -> String {
        switch category {
        case "football": return "soccerball"
        case "basketball": return "basketball"
        case "baseball": return "baseball"
        case "tennis": return "tennisball"
        case "hockey": return "hockey.puck"
        case "american-football": return "american.football"
        case "cricket": return "cricket.ball"
        default: return "sportscourt"
        }
    }
    private func sportName(_ category: String) -> String {
        category.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
