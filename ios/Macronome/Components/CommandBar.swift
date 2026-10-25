import SwiftUI

/// One input for logging and asking: camera, text, mic. Usual meals ride above it as
/// chips, led by a chat prompt.
struct CommandBar: View {
    struct Chip: Identifiable, Hashable {
        var id: String
        var title: String
        var kcal: Double?
        var isChat = false
    }

    @Binding var text: String
    var chips: [Chip] = []
    var placeholder = "Log or ask anything"
    var busy = false
    var onSubmit: (String) -> Void
    var onCamera: () -> Void
    var onMic: () -> Void
    var onChip: (Chip) -> Void = { _ in }
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            if !chips.isEmpty && !focused {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips) { chip in
                            Button { onChip(chip) } label: {
                                HStack(spacing: 8) {
                                    if chip.isChat { Image(systemName: "bubble.left").font(.system(size: 13)) }
                                    Text(chip.title)
                                    if let k = chip.kcal { Text(Format.int(k)).font(Typo.mono(13)).foregroundStyle(chip.isChat ? Theme.graphite : Theme.text3) }
                                }
                            }
                            .buttonStyle(chip.isChat ? ChipButtonStyle(background: Theme.text, foreground: Theme.graphite)
                                                     : ChipButtonStyle(background: Theme.surface, border: Color(hex: 0x3A3B37)))
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .scrollClipDisabled()
            }
            HStack(spacing: 4) {
                Button(action: onCamera) { RoundIcon(systemName: "camera") }
                    .accessibilityLabel("Photograph a label or a meal")
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.muted))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .frame(height: 48)
                    .accessibilityLabel("Log or ask")
                if busy {
                    ProgressView().tint(Theme.text).frame(width: 48, height: 48)
                } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: submit) {
                        RoundIcon(systemName: "arrow.up", background: Theme.text, foreground: Theme.graphite)
                    }
                    .accessibilityLabel("Send")
                } else {
                    Button(action: onMic) { MicButton() }.accessibilityLabel("Talk to log or ask")
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 60)
            .background(Capsule().fill(Theme.bar))
            .shadow(color: .black.opacity(0.5), radius: 14, y: 10)
            .padding(.horizontal, 12)
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [Theme.graphite.opacity(0), Theme.graphite], startPoint: .top, endPoint: .init(x: 0.5, y: 0.3))
                .ignoresSafeArea()
        )
    }

    private func submit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        onSubmit(t)
    }
}
