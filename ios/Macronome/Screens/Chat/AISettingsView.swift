import SwiftUI

/// Settings → Models. Two tiers, each pointing at a service the user chooses. In the
/// vocabulary of Settings.dc.html: caps headers, hairline rows, plain text.
struct AISettingsView: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader("")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Models").font(.system(size: 30, weight: .semibold)).tracking(-0.9)
                        .padding(.bottom, 8)
                    Text("Fast handles logging, so the frequent work stays cheap or free. Smart runs the chat and reads photos.")
                        .font(.system(size: 14)).foregroundStyle(Theme.text2).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 8)

                    TierSection(tier: .fast, title: "Fast", subtitle: "Logging")
                    TierSection(tier: .smart, title: "Smart", subtitle: "Chat · photos")
                    UsageSection(usage: services.models.usage)

                    Text("Keys stay on this phone in the Keychain. Requests go straight from the phone to the service you choose; nothing passes through Macronome. A Claude Pro or Max subscription can't be used here, only an API key.")
                        .font(.system(size: 13)).foregroundStyle(Theme.text3).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 24)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .page()
    }
}

private struct TierSection: View {
    var tier: ModelRouter.Tier
    var title: String
    var subtitle: String

    @Environment(AppServices.self) private var services
    @State private var keyDraft = ""
    @State private var testing = false
    @State private var result: (ok: Bool, message: String)?
    @FocusState private var keyFocused: Bool

    private var models: ModelRouter { services.models }
    private var config: TierConfig { models.config(tier) }
    private var other: ModelRouter.Tier { tier == .fast ? .smart : .fast }

    private func set(_ change: (inout TierConfig) -> Void) {
        var c = config
        change(&c)
        models.update(tier, c)
        result = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCap(title: title, trailing: subtitle)
            VStack(spacing: 0) {
                providerRow
                switch config.kind {
                case .onDevice: onDeviceRows
                case .openAI: openAIRows
                case .anthropic: anthropicRows
                case .off: offRow
                }
                if config.kind != .off { testRow }
            }
            .overlay(alignment: .top) { Hairline() }
        }
        .onChange(of: keyFocused) { _, f in if !f { saveKey() } }
    }

    // MARK: rows

    private var providerRow: some View {
        Menu {
            ForEach(ProviderKind.allCases) { kind in
                Button {
                    set { c in
                        guard kind != c.kind else { return }
                        c.kind = kind
                        c.model = ""
                        c.baseURL = kind == .openAI ? ServicePreset.openAI[0].baseURL : ""
                    }
                } label: {
                    if kind == config.kind { Label(kind.title, systemImage: "checkmark") } else { Text(kind.title) }
                }
            }
        } label: {
            SettingsRow(label: "Provider", value: config.kind.title, chevron: true)
        }
    }

    private var onDeviceRows: some View {
        SettingsRow(label: "Status", value: OnDeviceModel.statusText,
                    note: OnDeviceModel.isAvailable
                        ? "Free and private. Text only, so photos use Smart."
                        : tier == .smart ? "Photos and the chat need a cloud model here." : nil)
    }

    private var offRow: some View {
        SettingsRow(label: "Status", value: "Off",
                    note: tier == .smart ? "The chat uses Fast when it can; photos need a cloud model." : "Logging still works for foods in your library.")
    }

    private var preset: ServicePreset? { ServicePreset.matching(config.baseURL) }

    @ViewBuilder private var openAIRows: some View {
        Menu {
            ForEach(ServicePreset.openAI) { p in
                Button {
                    set { $0.baseURL = p.baseURL }
                } label: {
                    if p.id == preset?.id { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                }
            }
        } label: {
            SettingsRow(label: "Service", value: preset?.name ?? "Custom", chevron: true, note: preset?.note.nilIfEmpty)
        }
        FieldRow(label: "Base URL", placeholder: "https://…/v1", text: binding(\.baseURL), keyboard: .URL)
        FieldRow(label: "Model", placeholder: tier == .fast ? (preset?.fastModel ?? "model name") : (preset?.smartModel ?? "model name"),
                 text: binding(\.model))
        keyRow(optional: config.isLocal)
    }

    @ViewBuilder private var anthropicRows: some View {
        FieldRow(label: "Model", placeholder: tier == .fast ? ServicePreset.anthropicFast : ServicePreset.anthropicSmart,
                 text: binding(\.model))
        keyRow(optional: false)
    }

    private func keyRow(optional: Bool) -> some View {
        let shared = !models.hasOwnKey(tier) && models.apiKey(tier) != nil
        let placeholder = models.hasOwnKey(tier) ? "Saved" : shared ? "Using the \(other.rawValue) key" : optional ? "Not needed" : "Paste key"
        return HStack(spacing: 12) {
            Text("API key").font(.system(size: 15, weight: .medium))
            SecureField("", text: $keyDraft, prompt: Text(placeholder).foregroundStyle(Theme.text3))
                .font(Typo.mono(14))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($keyFocused)
                .submitLabel(.done)
                .onSubmit(saveKey)
            if models.hasOwnKey(tier) && keyDraft.isEmpty {
                Button("Clear") { models.setAPIKey(nil, for: tier); result = nil }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text2)
            }
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var testRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                saveKey()
                testing = true
                Task {
                    result = await models.test(tier)
                    testing = false
                }
            } label: {
                if testing { ProgressView().tint(Theme.text) } else { Text("Test") }
            }
            .buttonStyle(OutlineButtonStyle(height: 40))
            .disabled(testing)
            if let result {
                Text(result.message)
                    .font(.system(size: 13))
                    .foregroundStyle(result.ok ? Theme.text2 : Theme.text)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !models.isConfigured(tier) {
                Text(missing).font(.system(size: 13)).foregroundStyle(Theme.text3)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private var missing: String {
        switch config.kind {
        case .onDevice: "Not available"
        case .off: ""
        default:
            config.trimmedModel.isEmpty ? "Add a model name" : config.kind == .openAI && config.trimmedBaseURL.isEmpty
                ? "Add a base URL" : "Add an API key"
        }
    }

    // MARK: helpers

    private func binding(_ key: WritableKeyPath<TierConfig, String>) -> Binding<String> {
        Binding(get: { config[keyPath: key] }, set: { v in set { $0[keyPath: key] = v } })
    }

    private func saveKey() {
        let k = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        models.setAPIKey(k, for: tier)
        keyDraft = ""
        result = nil
    }
}

private struct UsageSection: View {
    var usage: UsageLog

    var body: some View {
        let today = usage.on(Clock.dayString())
        let month = usage.total(lastDays: 30)
        VStack(alignment: .leading, spacing: 0) {
            SettingsCap(title: "Today", trailing: nil)
            VStack(spacing: 0) {
                if today.isEmpty {
                    SettingsRow(label: "No requests yet", value: "")
                } else {
                    ForEach(today, id: \.key) { row in
                        UsageRow(name: row.key, counts: row.counts)
                    }
                }
                if month.requests > 0 {
                    UsageRow(name: "Last 30 days", counts: month)
                }
            }
            .overlay(alignment: .top) { Hairline() }
            Text("Token counts are what each service reported. Check its pricing page to turn them into money.")
                .font(.system(size: 13)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }
}

private struct UsageRow: View {
    var name: String
    var counts: UsageCounts
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.system(size: 15, weight: .medium)).lineLimit(1).truncationMode(.middle)
            Text(UsageLog.summary(counts) + (counts.cached > 0 ? " · \(UsageLog.tokens(counts.cached)) cached" : ""))
                .font(Typo.mono(12)).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - row vocabulary from Settings.dc.html

private struct SettingsCap: View {
    var title: String
    var trailing: String?
    var body: some View {
        HStack {
            Cap(title)
            Spacer()
            if let trailing { Cap(trailing) }
        }
        .padding(.top, 24).padding(.bottom, 6)
    }
}

private struct SettingsRow: View {
    var label: String
    var value: String
    var chevron = false
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 12) {
                Text(label).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                Text(value).font(.system(size: 14)).foregroundStyle(Theme.text2).lineLimit(1)
                if chevron {
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text3)
                }
            }
            if let note {
                Text(note).font(.system(size: 13)).foregroundStyle(Theme.text3).multilineTextAlignment(.leading)
            }
        }
        .padding(.vertical, note == nil ? 0 : 10)
        .frame(maxWidth: .infinity, minHeight: note == nil ? 52 : 64, alignment: .leading)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
    }
}

private struct FieldRow: View {
    var label: String
    var placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .asciiCapable

    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 15, weight: .medium))
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.text3))
                .font(Typo.mono(14))
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
        }
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
