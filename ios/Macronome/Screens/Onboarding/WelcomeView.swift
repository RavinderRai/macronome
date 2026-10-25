import SwiftUI
import UniformTypeIdentifiers

/// Welcome.dc.html. No accounts: everything stays on the phone, so "Continue with
/// Google" became "Get started", with a quiet way in for the food-log history.
struct WelcomeView: View {
    var onFinish: () -> Void
    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    HStack(spacing: 8) {
                        Text("macronome").font(.system(size: 20, weight: .semibold)).tracking(-0.4)
                        Circle().fill(Theme.amber).frame(width: 7, height: 7)
                    }
                    Text("Say what you ate.\n\(Text("That's the log.").foregroundStyle(Theme.fat))")
                        .font(.system(size: 46, weight: .semibold)).tracking(-1.8)
                        .lineSpacing(-4)
                        .fixedSize(horizontal: false, vertical: true)
                    example
                    steps
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 4) {
                if let importError {
                    Text(importError).font(.system(size: 13)).foregroundStyle(Theme.coral).multilineTextAlignment(.center)
                }
                Button("Get started") { router.push(.targets(onboarding: true)) }
                    .buttonStyle(.primary)
                    .frame(height: 56)
                Button("Import food-log history") { importing = true }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text2)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .page()
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.types, allowsMultipleSelection: true) { result in
            importFiles(result)
        }
    }

    private static let types: [UTType] = [UTType(filenameExtension: "jsonl"), .json, .plainText, .data].compactMap { $0 }

    private var example: some View {
        VStack(alignment: .leading, spacing: 14) {
            Cap("You say")
            Text("“Had the potato bowl with a hundred grams of cauliflower.”")
                .font(.system(size: 18, weight: .medium)).lineSpacing(3)
            Hairline()
            Cap("It logs")
            VStack(spacing: 6) {
                exampleRow("Russet potato", "350 g", "277")
                exampleRow("Cauliflower", "100 g", "25")
                exampleRow("Gusta veggie ground", "2 serv", "180")
                exampleRow("Mushroom gravy", "½ can", "59")
            }
            .font(Typo.mono(13))
            HStack(alignment: .firstTextBaseline) {
                Text("Potato bowl").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("541 kcal · \(Text("40 g P").foregroundStyle(Theme.amber))").font(Typo.mono(15))
            }
            .padding(.top, 4)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example: say “had the potato bowl with a hundred grams of cauliflower” and it logs the potato bowl, 541 kcal and 40 grams of protein.")
    }

    private func exampleRow(_ name: String, _ amount: String, _ kcal: String) -> some View {
        HStack(spacing: 8) {
            Text(name).frame(maxWidth: .infinity, alignment: .leading)
            Text(amount).foregroundStyle(Theme.text3)
            Text(kcal).frame(width: 32, alignment: .trailing)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            step("01", "Photograph the labels of foods you eat often. Once.")
            step("02", "Talk or type through the day. Nothing to search for.")
            step("03", "See what's left from your home screen.")
        }
    }

    private func step(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(n).font(Typo.mono(12)).foregroundStyle(Theme.text3)
            Text(text).font(.system(size: 15)).lineSpacing(2)
        }
    }

    /// events.jsonl (and meals.jsonl) from food-log. Already-known events are skipped.
    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            var count = 0
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { count += store.importEvents(from: data) }
            }
            if count > 0 {
                onFinish()
            } else {
                importError = "No food-log events found in that file. Pick food-log/events.jsonl."
            }
        }
    }
}
