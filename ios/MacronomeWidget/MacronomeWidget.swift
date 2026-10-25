import AppIntents
import SwiftUI
import WidgetKit

@main
struct MacronomeWidgets: WidgetBundle {
    var body: some Widget {
        CaloriesWidget()
        ProteinWidget()
        LockScreenWidget()
        ListenControl()
    }
}

struct DayEntry: TimelineEntry {
    var date: Date
    var snapshot: DaySnapshot
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { DayEntry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    /// Today now, then a fresh day at midnight. The app reloads timelines on every log.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let now = current()
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        let tomorrow = DayEntry(date: midnight, snapshot: DaySnapshot(ledger: FoodStore.loadLedger(), day: Clock.dayString(midnight)))
        completion(Timeline(entries: [now, tomorrow], policy: .after(midnight.addingTimeInterval(60))))
    }

    private func current() -> DayEntry {
        DayEntry(date: .now, snapshot: DaySnapshot(ledger: FoodStore.loadLedger()))
    }
}

// MARK: - calories (small: number + buttons; medium: the segmented ring)

struct CaloriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Calories", provider: DayProvider()) { entry in
            CaloriesWidgetView(s: entry.snapshot)
        }
        .configurationDisplayName("Calories left")
        .description("What's left today, with the mic and camera one tap away.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - protein

struct ProteinWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Protein", provider: DayProvider()) { entry in
            ProteinWidgetView(s: entry.snapshot)
                .containerBackground(Theme.graphite, for: .widget)
                .widgetURL(URL(string: "macronome://today"))
        }
        .configurationDisplayName("Protein to go")
        .description("Grams of protein left today.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - lock screen

struct LockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockScreen", provider: DayProvider()) { entry in
            LockScreenView(s: entry.snapshot)
                .containerBackground(.clear, for: .widget)
                .widgetURL(URL(string: "macronome://listen"))
        }
        .configurationDisplayName("Calories left")
        .description("Calories and protein left, on the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Control Center / Action Button

struct ListenControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.macronome.app.listen") {
            ControlWidgetButton(action: OpenListeningIntent()) {
                Label("Log by voice", systemImage: "mic")
            }
        }
        .displayName("Log by voice")
        .description("Open Macronome listening.")
    }
}

#Preview("Medium", as: .systemMedium) {
    CaloriesWidget()
} timeline: {
    DayEntry(date: .now, snapshot: .sample)
}

#Preview("Small", as: .systemSmall) {
    CaloriesWidget()
} timeline: {
    DayEntry(date: .now, snapshot: .sample)
}
