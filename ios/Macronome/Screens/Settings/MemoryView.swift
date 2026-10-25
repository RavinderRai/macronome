import SwiftUI

/// The notes it has learned: profile keys that are not targets, modes or meals.
struct MemoryView: View {
    @Environment(FoodStore.self) private var store
    @State private var editing: MemoryNote?
    @State private var adding = false

    var body: some View {
        let notes = store.ledger.memoryNotes
        VStack(spacing: 0) {
            ScreenHeader("", trailing: AnyView(
                Button { adding = true } label: { Image(systemName: "plus").font(.system(size: 18)).frame(width: 44, height: 44) }
                    .foregroundStyle(Theme.text)
                    .accessibilityLabel("Add a note")))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("What it knows about you")
                        .font(.system(size: 30, weight: .semibold)).tracking(-0.9)
                        .padding(.bottom, 8)
                    Text("Things you've said or corrected. It reads these before suggesting anything.")
                        .font(Typo.body).lineSpacing(3).foregroundStyle(Theme.text2)
                        .padding(.bottom, 16)

                    VStack(spacing: 0) {
                        ForEach(notes) { note in row(note) }
                    }
                    .overlay(alignment: .top) { Hairline() }

                    if notes.isEmpty {
                        Text("Nothing yet. Notes appear as you correct it or tell it how you eat.")
                            .font(Typo.body).foregroundStyle(Theme.text3).padding(.top, 14)
                    }

                    Button { adding = true } label: { Label("Add a note", systemImage: "plus") }
                        .buttonStyle(LibPillStyle())
                        .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .page()
        .sheet(item: $editing) { MemoryNoteSheet(note: $0) }
        .sheet(isPresented: $adding) { MemoryNoteSheet(note: nil) }
    }

    private func row(_ note: MemoryNote) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(note.value).font(.system(size: 15)).lineSpacing(2)
                Cap(meta(note))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { editing = note } label: {
                Image(systemName: "pencil").font(.system(size: 17)).frame(width: 44, height: 44)
            }
            .foregroundStyle(Theme.text2)
            .padding(.top, -6).padding(.trailing, -10)
            .accessibilityLabel("Edit note: \(note.title)")
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func meta(_ note: MemoryNote) -> String {
        guard let d = Clock.parseISO(note.updatedAt) else { return note.title }
        return "\(note.title) · Updated \(HistWindow.shortDay(Clock.dayString(d)))"
    }
}

/// Edit, add or forget one note.
struct MemoryNoteSheet: View {
    var note: MemoryNote?
    @Environment(FoodStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var value = ""
    @State private var confirmForget = false

    private var key: String {
        if let note { return note.key }
        let slug = title.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
            .split(separator: "_").joined(separator: "_")
        return slug
    }

    /// Keys that belong to targets, modes and meals are not notes.
    private var keyProblem: String? {
        guard note == nil, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if key.hasPrefix("target_") || key.hasPrefix("meal_") || Ledger.structuralKeys.contains(key) {
            return "That name is used by a setting. Pick another."
        }
        if store.ledger.memoryNotes.contains(where: { $0.key == key }) { return "There is already a note with that name; edit it instead." }
        return nil
    }

    private var canSave: Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !key.isEmpty && keyProblem == nil
    }

    var body: some View {
        LibSheet(title: note == nil ? "New note" : note!.title, canSave: canSave, onSave: save) {
            if note == nil {
                LibTextField(label: "About", text: $title, prompt: "prep times, snacks…")
                if let keyProblem {
                    Text(keyProblem).font(.system(size: 13)).foregroundStyle(Theme.coral).padding(.top, 6)
                }
                Spacer().frame(height: 14)
            }
            TextField("", text: $value, prompt: Text("What it should remember").foregroundStyle(Theme.text3), axis: .vertical)
                .font(Typo.body)
                .lineLimit(4...14)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
            if note != nil {
                Button("Forget this note") { confirmForget = true }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                    .frame(minHeight: 44)
                    .padding(.top, 20)
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { if let note, value.isEmpty { value = note.value } }
        .confirmationDialog("Forget this note?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) {
                if let note { store.append(Commands.forgetMemory(note.key)) }
                dismiss()
            }
        } message: {
            Text(note.map { "“\($0.value.prefix(120))\($0.value.count > 120 ? "…" : "")” won't be read before suggestions any more." } ?? "")
        }
    }

    private func save() {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, !key.isEmpty, v != note?.value else { return }
        store.append(Commands.setProfile(key, v))
    }
}
