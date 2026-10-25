import SwiftUI
import UniformTypeIdentifiers

/// Targets, conventions, the bank, models, memory and the data on this phone.
struct SettingsView: View {
    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @AppStorage("onboarded") private var onboarded = false
    @AppStorage("initial") private var initial = "R"
    @AppStorage("checkOddAmounts") private var checkOddAmounts = true

    @State private var sheet: SettingsSheet?
    @State private var exporting = false
    @State private var exportDoc: EventsFile?
    @State private var importing = false
    @State private var importResult: String?
    @State private var eraseStep = 0

    enum SettingsSheet: String, Identifiable {
        case fiber, bank, today, diet, initial
        var id: String { rawValue }
    }

    var body: some View {
        let ledger = store.ledger
        let t = ledger.standingTargets

        VStack(spacing: 0) {
            ScreenHeader("")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings").font(.system(size: 30, weight: .semibold)).tracking(-0.9).padding(.bottom, 14)

                    group("Numbers") {
                        Button { router.push(.targets(onboarding: false)) } label: {
                            LibRow("Daily targets", value: [t.kcal, t.protein, t.carbs, t.fat].map { Format.int($0) }
                                .joined(separator: " · "), mono: true)
                        }
                        Button { sheet = .today } label: {
                            LibRow("Change today only", value: ledger.hasOverride(on: store.today)
                                   ? "\(Format.int(ledger.targets(on: store.today).kcal)) today" : "Lower day, refeed")
                        }
                        Menu {
                            Picker("Carbs", selection: Binding(get: { ledger.carbMode },
                                                               set: { store.append(Commands.setProfile("carb_mode", $0)) })) {
                                Text("Net of fiber").tag("net")
                                Text("Total").tag("total")
                            }
                        } label: {
                            LibRow("Carbs", value: ledger.carbMode == "net" ? "Net of fiber" : "Total")
                        }
                        Button { sheet = .fiber } label: {
                            LibRow("Fiber calories", value: SetFiberSheet.title(ledger.fiberMode))
                        }
                        Button { sheet = .bank } label: {
                            LibRow("Calorie bank", value: ledger.bank.map { "\(Format.trim($0)) kcal" } ?? "Not set")
                        }
                    }

                    group("You") {
                        Button { sheet = .diet } label: {
                            LibRow("Diet", value: dietSummary(ledger.profile["diet"]))
                        }
                        Button { router.push(.memory) } label: {
                            let n = ledger.memoryNotes.count
                            LibRow("What it knows about you", value: n == 1 ? "1 note" : "\(n) notes")
                        }
                        LibRow(title: "Check odd amounts", subtitle: "Ask when a spoken number looks wrong for the food") {
                            Toggle("Check odd amounts", isOn: $checkOddAmounts).labelsHidden().tint(Theme.text)
                        }
                        Button { sheet = .initial } label: {
                            LibRow("Initial", value: String(initial.prefix(1)))
                        }
                        Button { router.push(.aiSettings) } label: {
                            LibRow("Models", value: "Choose")
                        }
                    }

                    group("Phone") {
                        Button { router.push(.widgets) } label: { LibRow("Home screen widgets", value: "Preview") }
                    }

                    group("Data") {
                        Button {
                            exportDoc = EventsFile(data: store.exportData())
                            exporting = true
                        } label: { LibRow("Export everything", value: "events.jsonl") }
                        Button { importing = true } label: {
                            LibRow("Import a log", value: importResult ?? "events.jsonl")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stored on this phone").font(.system(size: 15, weight: .medium))
                            Text(store.fileURL.path).font(Typo.mono(11)).foregroundStyle(Theme.text3).textSelection(.enabled)
                            Text("\(ledger.events.count) events · \(ledger.entries.count) entries · \(ledger.foods.count) foods")
                                .font(Typo.mono(11)).foregroundStyle(Theme.text3)
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) { Hairline() }
                        Button {
                            onboarded = false
                            router.popToRoot()
                        } label: { LibRow("Run setup again", value: "") }
                        Button { eraseStep = 1 } label: {
                            LibRow(title: "Erase everything", titleColor: Theme.coral) { EmptyView() }
                        }
                    }

                    HStack {
                        Text("Macronome \(Self.version)").font(.system(size: 13)).foregroundStyle(Theme.text3)
                        Spacer()
                    }
                    .padding(.top, 28)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .page()
        .sheet(item: $sheet) { s in
            switch s {
            case .fiber: SetFiberSheet()
            case .bank: SetBankSheet()
            case .today: SetTodaySheet()
            case .diet: SetProfileSheet(title: "Diet", key: "diet", prompt: "vegan, no peanuts…")
            case .initial: SetInitialSheet(initial: $initial)
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDoc,
                      contentType: EventsFile.jsonl, defaultFilename: "events.jsonl") { _ in }
        .fileImporter(isPresented: $importing, allowedContentTypes: EventsFile.readable) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { importResult = "Couldn't read it"; return }
            let added = store.importEvents(from: data)
            importResult = added == 1 ? "Added 1 event" : "Added \(added) events"
        }
        .alert("Erase everything?", isPresented: Binding(get: { eraseStep == 1 }, set: { if !$0 && eraseStep == 1 { eraseStep = 0 } })) {
            Button("Cancel", role: .cancel) { eraseStep = 0 }
            Button("Continue", role: .destructive) { eraseStep = 2 }
        } message: {
            Text("Every food, entry, meal and note on this phone goes. Export first if you want a copy.")
        }
        .alert("This can't be undone", isPresented: Binding(get: { eraseStep == 2 }, set: { if !$0 && eraseStep == 2 { eraseStep = 0 } })) {
            Button("Keep my data", role: .cancel) { eraseStep = 0 }
            Button("Erase \(store.ledger.events.count) events", role: .destructive) {
                eraseStep = 0
                store.eraseEverything()
                onboarded = false
                router.popToRoot()
            }
        } message: {
            Text("The log at \(store.fileURL.lastPathComponent) is deleted. Nothing is backed up unless you exported it.")
        }
    }

    @ViewBuilder private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        Cap(title).padding(.top, title == "Numbers" ? 8 : 20).padding(.bottom, 6)
        VStack(spacing: 0) { content() }
            .overlay(alignment: .top) { Hairline() }
    }

    private func dietSummary(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Not set" }
        let first = raw.split(whereSeparator: { " -–—,.(".contains($0) }).first.map(String.init) ?? raw
        return first.prefix(1).uppercased() + first.dropFirst()
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "–"
        let b = info?["CFBundleVersion"] as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }
}

/// events.jsonl for the exporter.
struct EventsFile: FileDocument {
    static let jsonl = UTType(filenameExtension: "jsonl", conformingTo: .plainText) ?? .plainText
    static let readable: [UTType] = [jsonl, .plainText, .json, .data]
    static var readableContentTypes: [UTType] { readable }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

// MARK: - sheets

/// All five fiber conventions with today's calories under each; switching re-scores every day.
struct SetFiberSheet: View {
    @Environment(FoodStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pending: String?

    static func title(_ mode: String) -> String {
        switch mode {
        case "auto": "Auto, per label"
        case "label": "As printed"
        case "half": "Half, 2 kcal/g"
        case "net": "Net, 0 kcal/g"
        case "split": "Split by type"
        default: mode
        }
    }

    var body: some View {
        let ledger = store.ledger
        let day = ledger.entries(on: store.today).isEmpty ? (ledger.loggedDays.first ?? store.today) : store.today
        let scores = Dictionary(uniqueKeysWithValues: ledger.kcalUnderEachMode(day: day).map { ($0.mode, $0.kcal) })
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Fiber calories").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.foregroundStyle(Theme.text2).frame(minHeight: 44)
            }
            .padding(.top, 8)
            Text("How much of fiber's energy counts. Auto trusts each label. The others are for matching another tracker.")
                .font(.system(size: 14)).foregroundStyle(Theme.text2).padding(.bottom, 14)
            HStack {
                Cap("Convention")
                Spacer()
                Cap(day == store.today ? "Today" : Format.dayHeader(day))
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Hairline() }
            ForEach(Ledger.fiberModes, id: \.key) { mode in
                Button {
                    if mode.key != ledger.fiberMode { pending = mode.key }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: mode.key == ledger.fiberMode ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(mode.key == ledger.fiberMode ? Theme.text : Theme.text3)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.title(mode.key)).font(.system(size: 15, weight: .medium))
                            Text(mode.summary).font(.system(size: 13)).foregroundStyle(Theme.text3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(Format.int(scores[mode.key])).font(Typo.mono(15))
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) { Hairline() }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode.key == ledger.fiberMode ? .isSelected : [])
            }
            Text("Switching re-scores every day already logged, not just today.")
                .font(.system(size: 13)).foregroundStyle(Theme.text3).padding(.top, 12)
            Spacer()
        }
        .padding(.horizontal, 20)
        .foregroundStyle(Theme.text)
        .presentationBackground(Theme.surface)
        .presentationDragIndicator(.visible)
        .alert("Switch to \(Self.title(pending ?? ""))?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Cancel", role: .cancel) { pending = nil }
            Button("Switch") {
                if let p = pending { store.append(Commands.setProfile("fiber_mode", p)) }
                pending = nil
            }
        } message: {
            Text("Every logged day is re-scored under the new convention, so past totals and the history change too.")
        }
    }
}

/// Edit the bank number, keeping the explanation that follows it in the note.
struct SetBankSheet: View {
    @Environment(FoodStore.self) private var store
    @State private var value: Double?

    var body: some View {
        let raw = store.ledger.profile["calorie_bank"] ?? ""
        LibSheet(title: "Calorie bank", canSave: value != nil, onSave: { save(raw) }) {
            Text("Calories saved on days you finish under, to spend on a hungry day. It doesn't reset weekly.")
                .font(.system(size: 14)).foregroundStyle(Theme.text2).padding(.bottom, 12)
            NumberField(label: "In the bank", value: $value, unit: "kcal")
            let tail = Self.tail(raw)
            if !tail.isEmpty {
                Text(tail).font(.system(size: 13)).foregroundStyle(Theme.text3).padding(.top, 12)
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { if value == nil { value = store.ledger.bank } }
    }

    /// Everything after the leading number, e.g. " - built 2026-10-12 to 10-16 …".
    static func tail(_ raw: String) -> String {
        let scanner = Scanner(string: raw)
        scanner.charactersToBeSkipped = nil
        _ = scanner.scanCharacters(from: .whitespaces)
        guard scanner.scanDouble() != nil else { return raw }
        return String(raw[scanner.currentIndex...])
    }

    private func save(_ raw: String) {
        guard let value else { return }
        let tail = Self.tail(raw)
        let number = Format.trim(value).replacingOccurrences(of: ",", with: "")
        let text = raw.isEmpty ? number : number + (tail == raw ? " - " + raw : tail)
        store.append(Commands.setProfile("calorie_bank", text))
    }
}

/// A one-day target: keep protein and fat, take the difference out of carbs.
struct SetTodaySheet: View {
    @Environment(FoodStore.self) private var store
    @State private var kcal: Double?

    var body: some View {
        let s = store.ledger.standingTargets
        let carbs = Self.carbs(for: kcal, standing: s)
        LibSheet(title: "Today only", canSave: kcal != nil && s.kcal != nil, onSave: save) {
            Text("A lower day or a refeed. Other days keep the standing \(Format.int(s.kcal)).")
                .font(.system(size: 14)).foregroundStyle(Theme.text2).padding(.bottom, 12)
            NumberField(label: "Calories today", value: $kcal, unit: "kcal")
            HStack {
                Text("Carbs today").font(Typo.body).foregroundStyle(Theme.text2)
                Spacer()
                Text(carbs.map { "\(Format.int($0)) g" } ?? "–").font(Typo.mono(15))
            }
            .frame(minHeight: 48)
            .overlay(alignment: .bottom) { Hairline() }
            Text("Protein \(Format.int(s.protein)) g and fat \(Format.int(s.fat)) g stay as they are.")
                .font(.system(size: 13)).foregroundStyle(Theme.text3).padding(.top, 12)
        }
        .presentationDetents([.medium])
        .onAppear { if kcal == nil { kcal = store.ledger.targets(on: store.today).kcal } }
    }

    static func carbs(for kcal: Double?, standing s: Targets) -> Double? {
        guard let kcal, let sk = s.kcal, let sc = s.carbs else { return nil }
        return max(0, sc - (sk - kcal) / 4)
    }

    private func save() {
        guard let kcal else { return }
        let day = store.today
        var events = [Commands.setTarget(.kcal, kcal, day: day)]
        if let c = Self.carbs(for: kcal, standing: store.ledger.standingTargets) {
            events.append(Commands.setTarget(.carbs, (c * 10).rounded() / 10, day: day))
        }
        store.append(events)
    }
}

/// Free-text profile value (diet).
struct SetProfileSheet: View {
    var title: String
    var key: String
    var prompt: String
    @Environment(FoodStore.self) private var store
    @State private var text = ""

    var body: some View {
        LibSheet(title: title, canSave: !text.trimmingCharacters(in: .whitespaces).isEmpty,
                 onSave: { store.append(Commands.setProfile(key, text.trimmingCharacters(in: .whitespacesAndNewlines))) }) {
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.text3), axis: .vertical)
                .font(Typo.body)
                .lineLimit(3...10)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
            Text("Suggestions read this before offering anything.")
                .font(.system(size: 13)).foregroundStyle(Theme.text3).padding(.top, 10)
        }
        .presentationDetents([.medium, .large])
        .onAppear { if text.isEmpty { text = store.ledger.profile[key] ?? "" } }
    }
}

struct SetInitialSheet: View {
    @Binding var initial: String
    @State private var text = ""

    var body: some View {
        LibSheet(title: "Initial", canSave: !text.trimmingCharacters(in: .whitespaces).isEmpty,
                 onSave: { initial = String(text.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }) {
            LibTextField(label: "Shown on the top bar", text: $text, prompt: "R")
        }
        .presentationDetents([.height(220)])
        .onAppear { text = initial }
    }
}
