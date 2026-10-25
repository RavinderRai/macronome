import SwiftUI

/// The chat as a sheet over Today (ChatSheet.dc.html). Options are chosen like radio
/// buttons; "Add to today" lands the chosen one on Today as a dashed planned entry.
struct ChatSheet: View {
    var initialPrompt: String?

    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var services
    @State private var chat = ChatSession()
    @State private var input = ""
    @State private var sentInitial = false
    @FocusState private var focused: Bool

    private var today: String { store.today }
    private var kcalLeft: Double? { store.ledger.status(.kcal, on: today).left }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let tier = services.models.chatTier {
                if tier == .fast { fastNotice }
                conversation
                inputBar
            } else {
                emptyState
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface)
        .presentationCornerRadius(22)
        .task {
            guard let p = initialPrompt, !sentInitial, services.models.chatTier != nil else { return }
            sentInitial = true
            await chat.send(p, models: services.models, store: store)
        }
        .onChange(of: services.speech.transcript) { _, t in
            if services.speech.isListening { input = t }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Chat").font(.system(size: 17, weight: .semibold))
            Spacer()
            if let left = kcalLeft {
                Text(left >= 0 ? "\(Format.int(left)) left" : "\(Format.int(-left)) over")
                    .font(Typo.mono(13)).foregroundStyle(left >= 0 ? Theme.text3 : Theme.coral)
                    .padding(.trailing, 4)
            }
            if !chat.messages.isEmpty {
                Button { chat.reset(); input = "" } label: { RoundIcon(systemName: "square.and.pencil", size: 44) }
                    .accessibilityLabel("New chat")
                    .disabled(chat.busy)
            }
            Button { router.sheet = nil } label: { RoundIcon(systemName: "xmark", size: 44) }
                .accessibilityLabel("Close chat")
        }
        .padding(.leading, 20).padding(.trailing, 8)
        .frame(height: 52)
        .padding(.top, 14)
    }

    private var fastNotice: some View {
        HStack(spacing: 8) {
            Text("Using the fast model. A smart model plans better.")
                .font(.system(size: 13)).foregroundStyle(Theme.text3)
            Spacer(minLength: 4)
            Button("Models") { openModels() }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    // MARK: conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if chat.messages.isEmpty && !chat.busy { suggestions }
                    ForEach(chat.messages) { m in
                        message(m).id(m.id)
                    }
                    if chat.busy {
                        Cap("Thinking…").padding(.vertical, 4).id("busy")
                    }
                    if let error = chat.error {
                        errorRow(error).id("error")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.count) { scrollToEnd(proxy) }
            .onChange(of: chat.busy) { scrollToEnd(proxy) }
            .onAppear { scrollToEnd(proxy, animated: false) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let target: AnyHashable? = chat.error != nil ? "error" : chat.busy ? "busy" : chat.messages.last.map { AnyHashable($0.id) }
        guard let target else { return }
        if animated { withAnimation(.snappy) { proxy.scrollTo(target, anchor: .bottom) } } else { proxy.scrollTo(target, anchor: .bottom) }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plans come from your own foods, and every number is worked out from your library.")
                .font(Typo.body).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(["What can I have for dinner?", "I want a snack", "How will today land?"], id: \.self) { s in
                Button(s) { submit(s) }.buttonStyle(.chip)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder private func message(_ m: ChatMessage) -> some View {
        switch m.role {
        case .user:
            Text(m.text)
                .font(.system(size: 15)).lineSpacing(3)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 4,
                                                   topTrailingRadius: 18).fill(Theme.bar))
                .frame(maxWidth: 300, alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .textSelection(.enabled)
        case .assistant, .system:
            VStack(alignment: .leading, spacing: 14) {
                if !m.text.isEmpty {
                    Text(m.text).font(.system(size: 15)).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if !m.options.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(m.options) { o in
                            OptionCard(option: o, ledger: store.ledger, selected: chat.selected(in: m)?.id == o.id) {
                                chat.select(o, in: m)
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Options")
                    if let o = chat.selected(in: m) { restOfToday(o) }
                }
            }
        }
    }

    private func errorRow(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error).font(.system(size: 14)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if chat.messages.last?.role == .user {
                    Button("Try again") { Task { await chat.retry(models: services.models, store: store) } }
                        .buttonStyle(OutlineButtonStyle(height: 40))
                }
                if error.contains("Settings") {
                    Button("Models") { openModels() }.buttonStyle(OutlineButtonStyle(height: 40))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.graphite))
    }

    // MARK: rest of today

    /// Where the day lands with the chosen option plus anything already planned. All
    /// numbers come from the ledger.
    private func restOfToday(_ option: MealOption) -> some View {
        let ledger = store.ledger
        let planID = chat.planID(for: option)
        let logged = chat.isLogged(option)
        let optionMacros = ChatReplyParser.macros(option.components, ledger: ledger)
        let others = ledger.plans(on: today).filter { $0.id != planID }
        let kcal = ledger.status(.kcal, on: today)
        let protein = ledger.status(.protein, on: today)
        let pending = (logged ? Macros.zero : optionMacros) + others.reduce(.zero) { $0 + $1.macros }
        let landsKcal = kcal.eaten + pending.kcal
        let landsProtein = protein.eaten + pending.protein

        return VStack(alignment: .leading, spacing: 10) {
            Cap("Rest of today")
            VStack(alignment: .leading, spacing: 6) {
                if !logged {
                    planRow(option.slot?.title ?? "Next", option.title, optionMacros.kcal)
                }
                ForEach(others) { p in planRow(p.meal?.title ?? "Later", p.label, p.macros.kcal) }
            }
            Hairline()
            landing(kcal: landsKcal, target: kcal.target, protein: landsProtein, proteinTarget: protein.target)
            HStack(spacing: 8) {
                if logged {
                    Cap("Logged").frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Button(planID == nil ? "Add to today" : "Added to today") {
                        chat.plan(option, store: store)
                        router.sheet = nil
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(planID != nil)
                    .opacity(planID != nil ? 0.5 : 1)
                    Button("Log it") {
                        do {
                            try chat.log(option, store: store)
                            router.sheet = nil
                        } catch {
                            chat.error = error.localizedDescription
                        }
                    }
                    .buttonStyle(OutlineButtonStyle(fill: true))
                }
            }
            .font(.system(size: 14, weight: .semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.graphite))
    }

    private func planRow(_ slot: String, _ label: String, _ kcal: Double) -> some View {
        HStack(spacing: 8) {
            Text(slot).foregroundStyle(Theme.text3).frame(width: 72, alignment: .leading)
            Text(label).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.int(kcal))
        }
        .font(Typo.mono(13))
    }

    private func landing(kcal: Double, target: Double?, protein: Double, proteinTarget: Double?) -> some View {
        var s = AttributedString("Lands at ")
        s += mono(Format.int(kcal))
        if let target {
            let diff = target - kcal
            s += AttributedString(", ")
            s += mono(Format.int(abs(diff)))
            s += AttributedString(diff >= 0 ? " under." : " over.")
        } else {
            s += AttributedString(" kcal.")
        }
        s += AttributedString(" Protein ends at ")
        s += mono(Format.int(protein))
        if let proteinTarget {
            s += AttributedString(" of ")
            s += mono(Format.int(proteinTarget))
        }
        s += AttributedString(".")
        return Text(s).font(.system(size: 14)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }

    private func mono(_ t: String) -> AttributedString {
        var a = AttributedString(t)
        a.font = Typo.mono(14)
        return a
    }

    // MARK: input

    private var inputBar: some View {
        HStack(spacing: 4) {
            TextField("", text: $input, prompt: Text("Reply, or say what you ate").foregroundStyle(Theme.text3))
                .font(.system(size: 16))
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { submit(input) }
                .frame(height: 48)
                .padding(.leading, 18)
                .accessibilityLabel("Reply or log")
            if chat.busy {
                ProgressView().tint(Theme.text).frame(width: 46, height: 46)
            } else if !input.trimmingCharacters(in: .whitespaces).isEmpty && !services.speech.isListening {
                Button { submit(input) } label: {
                    RoundIcon(systemName: "arrow.up", size: 46, background: Theme.text, foreground: Theme.graphite)
                }
                .accessibilityLabel("Send")
            } else {
                Button(action: toggleMic) {
                    if services.speech.isListening {
                        RoundIcon(systemName: "stop.fill", size: 46, background: Theme.amber, foreground: Theme.graphite)
                    } else {
                        MicButton(size: 46)
                    }
                }
                .accessibilityLabel(services.speech.isListening ? "Stop and send" : "Talk")
            }
        }
        .padding(.trailing, 4)
        .frame(height: 56)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Color(hex: 0x3A3B37), lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .padding(.top, 4)
    }

    private func submit(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !chat.busy else { return }
        input = ""
        Task { await chat.send(t, models: services.models, store: store) }
    }

    private func toggleMic() {
        let speech = services.speech
        if speech.isListening {
            let t = speech.stop()
            submit(t.isEmpty ? input : t)
        } else {
            focused = false
            speech.reset()
            Task { await speech.start() }
        }
    }

    // MARK: not configured

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Chat needs a model").font(.system(size: 22, weight: .semibold)).tracking(-0.5)
            Text("The chat plans meals from your foods and what is left today. It runs on a model you choose: add an API key from Anthropic, or from any OpenAI-compatible service such as OpenRouter, Groq or Gemini.")
                .font(Typo.body).foregroundStyle(Theme.text2).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("Keys stay on this phone. Logging works without one.")
                .font(.system(size: 13)).foregroundStyle(Theme.text3)
            Button("Set up models") { openModels() }
                .buttonStyle(.primaryCompact)
                .padding(.top, 6)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openModels() {
        router.sheet = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            router.push(.aiSettings)
        }
    }
}

/// One meal idea: title, kcal and protein computed from the ledger, components, prep.
struct OptionCard: View {
    var option: MealOption
    var ledger: Ledger
    var selected: Bool
    var onSelect: () -> Void

    var body: some View {
        let m = ChatReplyParser.macros(option.components, ledger: ledger)
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(option.title).font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.leading)
                    Text("\(Format.int(m.kcal)) kcal · \(Text("\(Format.int(m.protein)) g P").foregroundStyle(Theme.amber))")
                        .font(Typo.mono(13))
                    if !componentsLine.isEmpty {
                        Text(componentsLine).font(.system(size: 13)).foregroundStyle(Theme.text3)
                            .multilineTextAlignment(.leading)
                    }
                    if let d = option.detail { Cap(d) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    if selected {
                        Circle().fill(Theme.text)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.graphite)
                    } else {
                        Circle().stroke(Theme.tick, lineWidth: 1.5)
                    }
                }
                .frame(width: 22, height: 22)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Theme.text : Theme.hairline, lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// "300 g Russet potato · 2 serv Gusta ground".
    private var componentsLine: String {
        option.components.compactMap { c in
            ledger.foods[c.foodID].map { "\(Format.amount(qty: c.qty, unit: c.unit)) \(Format.shortName($0.name))" }
        }.joined(separator: " · ")
    }
}
