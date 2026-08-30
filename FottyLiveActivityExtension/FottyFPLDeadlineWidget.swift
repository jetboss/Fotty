import SwiftUI
import WidgetKit

private struct FottyFPLDeadlineEntry: TimelineEntry {
    let date: Date
    let gameweek: Int?
    let gameweekName: String
    let deadline: Date?
    let sourceStatus: String

    static let placeholder = FottyFPLDeadlineEntry(
        date: Date(),
        gameweek: 2,
        gameweekName: "Gameweek 2",
        deadline: Date().addingTimeInterval(36 * 60 * 60),
        sourceStatus: "Official FPL"
    )
}

private struct FottyFPLDeadlineProvider: TimelineProvider {
    private struct Bootstrap: Decodable {
        let events: [Event]
    }

    private struct Event: Decodable {
        let id: Int
        let name: String
        let deadlineTime: String
        let finished: Bool
        let isCurrent: Bool
        let isNext: Bool

        enum CodingKeys: String, CodingKey {
            case id, name, finished
            case deadlineTime = "deadline_time"
            case isCurrent = "is_current"
            case isNext = "is_next"
        }

        var deadline: Date? {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: deadlineTime) ?? ISO8601DateFormatter().date(from: deadlineTime)
        }
    }

    func placeholder(in context: Context) -> FottyFPLDeadlineEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (FottyFPLDeadlineEntry) -> Void) {
        completion(.placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FottyFPLDeadlineEntry>) -> Void) {
        Task {
            let entry = await loadEntry()
            let nextRefresh = min(
                entry.deadline?.addingTimeInterval(60) ?? Date().addingTimeInterval(60 * 60),
                Date().addingTimeInterval(60 * 60)
            )
            completion(Timeline(entries: [entry], policy: .after(max(Date().addingTimeInterval(15 * 60), nextRefresh))))
        }
    }

    private func loadEntry() async -> FottyFPLDeadlineEntry {
        guard let url = URL(string: "https://fantasy.premierleague.com/api/bootstrap-static/") else {
            return unavailableEntry()
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return unavailableEntry()
            }
            let bootstrap = try JSONDecoder().decode(Bootstrap.self, from: data)
            let now = Date()
            let event = bootstrap.events
                .filter { !$0.finished && ($0.deadline ?? .distantPast) > now }
                .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
                .first
                ?? bootstrap.events.first(where: { $0.isNext || $0.isCurrent })
            guard let event else { return unavailableEntry() }
            return FottyFPLDeadlineEntry(
                date: now,
                gameweek: event.id,
                gameweekName: event.name,
                deadline: event.deadline,
                sourceStatus: "Official FPL"
            )
        } catch {
            return unavailableEntry()
        }
    }

    private func unavailableEntry() -> FottyFPLDeadlineEntry {
        FottyFPLDeadlineEntry(
            date: Date(),
            gameweek: nil,
            gameweekName: "FPL deadline",
            deadline: nil,
            sourceStatus: "Open Fotty to refresh"
        )
    }
}

struct FottyFPLDeadlineWidget: Widget {
    private let kind = "FottyFPLDeadlineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FottyFPLDeadlineProvider()) { entry in
            FottyFPLDeadlineWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.055, green: 0.057, blue: 0.066)
                }
                .widgetURL(URL(string: "fotty://fpl"))
        }
        .configurationDisplayName("FPL Deadline")
        .description("See the next official FPL deadline and jump straight into your Fotty plan.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct FottyFPLDeadlineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FottyFPLDeadlineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "soccerball")
                    .foregroundStyle(accent)
                Text("FOTTY FPL")
                    .font(.caption.weight(.black))
                    .foregroundStyle(accent)
                Spacer()
                if let gameweek = entry.gameweek {
                    Text("GW\(gameweek)")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(accent)
                        .clipShape(Capsule())
                }
            }

            Spacer(minLength: 0)

            Text(entry.gameweekName)
                .font(family == .systemSmall ? .headline.weight(.black) : .title3.weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let deadline = entry.deadline {
                Text(deadline, style: .timer)
                    .font(family == .systemSmall ? .title3.weight(.black) : .title2.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("until deadline")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if family == .systemSmall {
                    Label(entry.sourceStatus, systemImage: "checkmark.shield.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Deadline unavailable")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Open Fotty to refresh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if family == .systemMedium {
                Spacer(minLength: 0)
                HStack {
                    Label(entry.sourceStatus, systemImage: "checkmark.shield.fill")
                    Spacer()
                    Label("Open plan", systemImage: "arrow.up.forward.app.fill")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        if let gameweek = entry.gameweek, let deadline = entry.deadline {
            return "Fotty FPL, Gameweek \(gameweek), deadline \(deadline.formatted(date: .abbreviated, time: .shortened)), official FPL"
        }
        return "Fotty FPL deadline unavailable. Open Fotty to refresh."
    }

    private var accent: Color {
        Color(red: 0.96, green: 0.63, blue: 0.13)
    }
}
