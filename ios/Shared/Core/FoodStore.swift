import Foundation
import Observation
import WidgetKit

/// Owns the event log on disk and the ledger replayed from it. The app and the widget
/// read the same file through the App Group container, so the widget is never stale.
@MainActor
@Observable
final class FoodStore {
    private(set) var ledger = Ledger()
    /// The last thing logged, for the confirmation card and Undo.
    private(set) var receipt: Receipt?
    private(set) var loadError: String?

    struct Receipt: Identifiable, Equatable {
        let id = UUID()
        var groupID: String
        var events: [Event]
        var replacedPlan: PlannedItem?
        var date = Date()
    }

    let fileURL: URL

    init(fileURL: URL = FoodStore.defaultURL) {
        self.fileURL = fileURL
        reload()
    }

    static var appGroupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "MacronomeAppGroup") as? String
    }

    /// `<App Group>/events.jsonl`, or Application Support when the group is not
    /// available (free signing on a device does not allow App Groups).
    static var defaultURL: URL {
        let fm = FileManager.default
        if let gid = appGroupID, let url = fm.containerURL(forSecurityApplicationGroupIdentifier: gid) {
            return url.appendingPathComponent("events.jsonl")
        }
        let dir = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return dir.appendingPathComponent("events.jsonl")
    }

    var today: String { Clock.dayString() }
    var isEmpty: Bool { ledger.events.isEmpty }

    func reload() {
        let data = (try? Data(contentsOf: fileURL)) ?? Data()
        ledger = Ledger(events: EventCodec.decodeLines(data))
    }

    /// Append events, replay, and refresh the widget.
    func append(_ events: [Event]) {
        guard !events.isEmpty else { return }
        do {
            try write(events)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        reload()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func append(_ event: Event) { append([event]) }

    private func write(_ events: [Event]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fileURL.path) { fm.createFile(atPath: fileURL.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        var text = events.map(EventCodec.encodeLine).joined(separator: "\n") + "\n"
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if handle.readData(ofLength: 1) != Data("\n".utf8) { text = "\n" + text }
            try handle.seekToEnd()
        }
        try handle.write(contentsOf: Data(text.utf8))
    }

    // MARK: logging

    /// Log entries and remember them for the confirmation card.
    func log(_ events: [Event], replacing plan: PlannedItem? = nil) {
        var all = events
        if let plan { all.append(Commands.deletePlan(plan.id)) }
        append(all)
        let gid = events.first?.string("group_id") ?? events.first?.id ?? ""
        receipt = Receipt(groupID: gid, events: events, replacedPlan: plan)
    }

    /// Undo the last log: delete its entries and restore a plan it replaced.
    func undoReceipt() {
        guard let r = receipt else { return }
        var events = r.events.filter { $0.type == "entry_add" }.map { Commands.deleteEntry($0.id) }
        if let p = r.replacedPlan {
            events.append(Commands.plan(label: p.label, detail: p.detail, macros: p.macros, day: p.day, meal: p.meal,
                                        mealID: p.mealID, components: p.components))
        }
        append(events)
        receipt = nil
    }

    func dismissReceipt() { receipt = nil }

    /// Replace a logged group with corrected entries (the Edit path on the card).
    func replace(group: LogGroup, with events: [Event]) {
        append(group.entries.map { Commands.deleteEntry($0.id) } + events)
        if receipt?.groupID == group.id {
            let gid = events.first?.string("group_id") ?? events.first?.id ?? group.id
            receipt = Receipt(groupID: gid, events: events, replacedPlan: receipt?.replacedPlan)
        }
    }

    // MARK: import / export

    /// Merge another events.jsonl (for example food-log's) into this one. Events
    /// already present are skipped by id.
    @discardableResult
    func importEvents(from data: Data) -> Int {
        let known = Set(ledger.events.map(\.id))
        let fresh = EventCodec.decodeLines(data).filter { !$0.id.isEmpty && !known.contains($0.id) }
        append(fresh)
        return fresh.count
    }

    func exportData() -> Data {
        Data((ledger.events.map(EventCodec.encodeLine).joined(separator: "\n") + "\n").utf8)
    }

    /// Bundled history (food-log/events.jsonl and food-log/meals.jsonl) imported once
    /// on first launch, when the build includes them.
    func seedIfNeeded() {
        guard isEmpty else { return }
        for name in ["events", "meals"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "jsonl"), let data = try? Data(contentsOf: url) {
                importEvents(from: data)
            }
        }
    }

    func eraseEverything() {
        try? FileManager.default.removeItem(at: fileURL)
        receipt = nil
        reload()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
