import SwiftUI
import WidgetKit

@main
struct MacronomeWidgets: WidgetBundle {
    var body: some Widget { CaloriesWidget() }
}

struct CaloriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Calories", provider: Provider()) { entry in
            Text("\(Int(entry.left))").containerBackground(Theme.graphite, for: .widget)
        }
    }

    struct Entry: TimelineEntry { var date: Date; var left: Double }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: .now, left: 759) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(placeholder(in: context)) }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [placeholder(in: context)], policy: .never))
        }
    }
}
