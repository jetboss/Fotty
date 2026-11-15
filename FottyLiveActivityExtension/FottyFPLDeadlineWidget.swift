import SwiftUI
import WidgetKit

/// Keep the installed widget kind so an upgrade does not leave a stale deadline
/// or an empty widget. This compatibility surface performs no network work.
private struct FottyFPLDeadlineEntry: TimelineEntry {
    let date: Date
}

private struct FottyFPLDeadlineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FottyFPLDeadlineEntry { .init(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (FottyFPLDeadlineEntry) -> Void) {
        completion(.init(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FottyFPLDeadlineEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: Date())], policy: .never))
    }
}

struct FottyFPLDeadlineWidget: Widget {
    private let kind = "FottyFPLDeadlineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FottyFPLDeadlineProvider()) { _ in
            VStack(alignment: .leading, spacing: 8) {
                Label("Fotty", systemImage: "sportscourt")
                    .font(.headline)
                Text("FPL tools have retired")
                    .font(.subheadline.weight(.semibold))
                Text("Open Fotty for live sport. Replace this widget with Sports Plan for your saved matches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(for: .widget) { Color.black }
            .foregroundStyle(.white)
            .widgetURL(URL(string: "fotty://fpl"))
        }
        .configurationDisplayName("Fotty — retired FPL widget")
        .description("Compatibility notice for an existing FPL widget. Use Sports Plan for saved matches.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
