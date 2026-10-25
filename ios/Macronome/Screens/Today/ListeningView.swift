import SwiftUI

/// Voice capture on a deep amber panel. Listens as soon as it opens, shows what it is
/// hearing and what that matches in the library, and logs when you stop.
struct ListeningView: View {
    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var services

    @State private var started = Date()
    @State private var levels = Array(repeating: Float(0), count: 32)
    @State private var typing = false
    @State private var typed = ""
    @State private var draft: LogDraft?
    @FocusState private var fieldFocused: Bool

    private var speech: SpeechRecognizer { services.speech }
    private var spoken: String { typing ? typed : speech.transcript }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if typing {
                typeField
            } else {
                transcript
                meter
            }
            understood
            Spacer(minLength: 0)
            controls
        }
        .padding(20)
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(600), .large])
        .presentationBackground(Theme.deepAmber)
        .presentationCornerRadius(28)
        .presentationDragIndicator(.hidden)
        .task {
            speech.contextualStrings = store.ledger.sortedMeals.map(\.name) + store.ledger.sortedFoods.flatMap { [$0.name] + $0.aliases }
            started = Date()
            await speech.start()
            if speech.error != nil { switchToTyping() }
        }
        .onChange(of: spoken) { _, text in reparse(text) }
        .onChange(of: speech.level) { _, level in
            levels.removeFirst()
            levels.append(level)
        }
        .onChange(of: speech.error) { _, error in
            if error != nil, !typing { switchToTyping() }
        }
        .onDisappear { if speech.isListening { speech.reset() } }
    }

    // MARK: parts

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.amber).frame(width: 8, height: 8)
                .phaseAnimator([1.0, 0.35]) { dot, phase in dot.opacity(speech.isListening ? phase : 1) }
                    animation: { _ in .easeInOut(duration: 0.7) }
                .accessibilityHidden(true)
            Cap(typing ? "Type it" : speech.isListening ? "Listening" : "Starting", color: Theme.text)
            Spacer()
            if speech.isListening {
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    let s = Int(ctx.date.timeIntervalSince(started))
                    Text(String(format: "%d:%02d", s / 60, s % 60)).font(Typo.mono(12)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var transcript: some View {
        Group {
            if speech.transcript.isEmpty {
                Text("Say what you ate\(Text("|").foregroundStyle(Theme.amber))").foregroundStyle(Theme.muted)
            } else {
                Text("\(speech.transcript)\(Text(" |").foregroundStyle(Theme.amber))")
            }
        }
        .font(.system(size: 25, weight: .medium))
        .tracking(-0.4)
        .lineSpacing(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var meter: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { i, v in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.amber.opacity(0.35 + 0.65 * Double(i) / Double(levels.count)))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(4, CGFloat(v) * 44))
            }
        }
        .frame(height: 44)
        .animation(.linear(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }

    private var typeField: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = speech.error {
                Text(error).font(.system(size: 14)).foregroundStyle(Theme.amberText).fixedSize(horizontal: false, vertical: true)
            }
            TextField("", text: $typed, prompt: Text("What did you eat?").foregroundStyle(Theme.muted), axis: .vertical)
                .font(.system(size: 22, weight: .medium))
                .focused($fieldFocused)
                .submitLabel(.done)
                .onSubmit(finish)
                .lineLimit(1...4)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Hairline(color: Theme.amberDivider) }
        }
    }

    @ViewBuilder private var understood: some View {
        if let draft, !(draft.lines.isEmpty && draft.unresolved.isEmpty) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Cap("Understood so far", color: Theme.muted)
                    Spacer()
                    if let plan = matchedPlan(draft) {
                        Cap(plan.meal == .dinner ? "Matches tonight's plan" : "Matches today's plan", color: Theme.amber)
                    }
                }
                VStack(spacing: 8) {
                    ForEach(draft.lines) { line in
                        HStack(spacing: 8) {
                            Text(LogDraft.displayName(line.food.name)).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Format.amount(qty: line.qty, unit: line.unit))
                            Text(wasText(line) ?? "").foregroundStyle(Theme.amber).frame(width: 74, alignment: .trailing)
                        }
                        .foregroundStyle(line.mentioned ? Theme.text : Theme.muted)
                    }
                    ForEach(draft.unresolved) { item in
                        HStack {
                            Text("“\(item.label ?? item.phrase)”").lineLimit(1)
                            Spacer()
                            Text("not in your foods")
                        }
                        .foregroundStyle(Theme.muted)
                    }
                }
                .font(Typo.mono(13))
            }
            .padding(.top, 16)
            .overlay(alignment: .top) { Hairline(color: Theme.amberDivider) }
            .animation(.snappy, value: draft.lines.map(\.id))
        }
    }

    private var controls: some View {
        HStack {
            Button("Cancel") {
                speech.reset()
                router.sheet = nil
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.amberText)
            .frame(minWidth: 64, minHeight: 44, alignment: .leading)
            Spacer()
            Button(action: finish) {
                Group {
                    if typing {
                        Image(systemName: "arrow.up").font(.system(size: 24, weight: .semibold))
                    } else {
                        RoundedRectangle(cornerRadius: 2.5).frame(width: 22, height: 22)
                    }
                }
                .frame(width: 68, height: 68)
                .background(Circle().fill(Theme.amber))
                .foregroundStyle(Theme.graphite)
            }
            .accessibilityLabel(typing ? "Log it" : "Stop and log")
            .disabled(typing && typed.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer()
            Button(typing ? "Talk" : "Type") {
                if typing {
                    typing = false
                    Task { started = Date(); await speech.start() }
                } else {
                    switchToTyping()
                }
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.amberText)
            .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
            .disabled(typing && speech.error != nil)
        }
    }

    // MARK: logic

    private func wasText(_ line: LogDraft.Line) -> String? {
        guard line.changedFromDefault, let q = line.defaultQty else { return nil }
        let unit = line.defaultUnit ?? line.unit
        return unit == line.unit && Ledger.gramUnits.contains(unit) ? "was \(Format.trim(q))" : "was \(Format.amount(qty: q, unit: unit))"
    }

    private func matchedPlan(_ draft: LogDraft) -> PlannedItem? {
        LogCoordinator.shared.matchingPlan(draft, ledger: store.ledger, day: Clock.dayString())
    }

    private func reparse(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, LogIntent.of(t) == .log else { draft = nil; return }
        let ledger = store.ledger
        let parse = LogCoordinator.shared.interpreter.parse(t, ledger: ledger)
        draft = LogDraft(items: parse.items, slot: parse.slot, ledger: ledger, readings: parse.readings)
    }

    private func switchToTyping() {
        let heard = speech.isListening ? speech.stop() : speech.transcript
        if typed.isEmpty { typed = heard }
        typing = true
        fieldFocused = true
    }

    private func finish() {
        let text = (typing ? typed : speech.stop()).trimmingCharacters(in: .whitespacesAndNewlines)
        let source: InputSource = typing && speech.transcript.isEmpty ? .text : .voice
        speech.reset()
        guard !text.isEmpty else {
            router.sheet = nil
            return
        }
        // A question swaps this sheet for the chat; a log closes it and shows the card.
        if LogIntent.of(text) == .question {
            router.sheet = .chat(prompt: text)
            return
        }
        router.sheet = nil
        let store = store, router = router, models = services.models
        Task { await LogCoordinator.shared.submit(text, source: source, store: store, router: router, models: models) }
    }
}
