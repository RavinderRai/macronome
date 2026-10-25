import SwiftUI

/// LabelScan.dc.html: aim at the nutrition panel, capture, check what was read, then
/// continue to the new-food form.
struct LabelScanView: View {
    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var services

    @State private var camera = LabelCamera()
    @State private var frozen: UIImage?
    @State private var draft: FoodDraft?
    @State private var reading = false
    @State private var readingWithAI = false
    @State private var error: String?
    @State private var showCamera = false
    @State private var showLibrary = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                LabelViewfinder(camera: camera, frozen: frozen)
                if frozen == nil && camera.mode == .live {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.amber, lineWidth: 1.5)
                        .padding(EdgeInsets(top: 72, leading: 52, bottom: 120, trailing: 52))
                        .allowsHitTesting(false)
                }
                VStack {
                    Spacer()
                    panel
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 12)
            controls
        }
        .background(CaptureColors.ground.ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .task { await camera.prepare() }
        .imageSources(camera: $showCamera, library: $showLibrary) { image in read(image) }
    }

    // MARK: pieces

    private var topBar: some View {
        HStack {
            Button { router.closeCover() } label: {
                Image(systemName: "xmark").font(.system(size: 19, weight: .regular)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close camera")
            Spacer()
            if let left = store.ledger.kcalLeftText(on: store.today) {
                Text(left).font(Typo.mono(13)).foregroundStyle(Theme.muted).padding(.trailing, 12)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
    }

    @ViewBuilder private var panel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let draft {
                resultPanel(draft)
            } else if reading {
                HStack {
                    Cap("Reading the label", color: Theme.amber)
                    Spacer()
                    ProgressView().tint(Theme.text3).controlSize(.small)
                }
                progress(0.85)
            } else if camera.mode == .live {
                HStack {
                    Cap(camera.sawLabel ? "Label found" : "Point at the nutrition facts", color: camera.sawLabel ? Theme.amber : Theme.text3)
                    Spacer()
                    if camera.sawLabel { Cap(camera.coverage >= 1 ? "Ready" : "Hold still", color: Theme.muted) }
                }
                Text(camera.live.map { $0.readSummary.isEmpty ? "Reading serving, calories, macros" : $0.readSummary } ?? "Reading serving, calories, macros")
                    .font(.system(size: 16, weight: .medium)).lineLimit(1)
                progress(camera.coverage)
            } else if camera.mode == .fallback {
                Cap("Take or choose a photo", color: Theme.text3)
            }
            if let error {
                Text(error).font(.system(size: 13)).foregroundStyle(Theme.text2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(CaptureColors.overlay))
        .opacity(camera.mode == .checking && draft == nil ? 0 : 1)
        .animation(.snappy, value: draft)
    }

    private func progress(_ fraction: Double) -> some View {
        GeometryReader { geo in
            Capsule().fill(Theme.amber).frame(width: geo.size.width * min(1, max(0.04, fraction)))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Capsule().fill(CaptureColors.progressTrack))
        }
        .frame(height: 3)
        .animation(.snappy, value: fraction)
    }

    private func resultPanel(_ d: FoodDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Cap(NutritionLabelParser.looksPoor(d) ? "Partly read" : "Read from the label", color: NutritionLabelParser.looksPoor(d) ? Theme.text3 : Theme.amber)
                Spacer()
                Cap("Per " + d.servingSummary, color: Theme.muted)
            }
            VStack(spacing: 0) {
                readRow("Calories", d.kcal, "", key: "kcal", d)
                readRow("Protein", d.protein, "g", key: "protein", d, color: Theme.amber)
                readRow("Carbs", d.carbs, "g", key: "carbs", d)
                readRow("Fiber", d.fiber, "g", key: "fiber", d)
                readRow("Fat", d.fat, "g", key: "fat", d)
            }
            if !d.micros.isEmpty {
                Text("+ \(d.micros.count) more on the label, saved too")
                    .font(Typo.mono(12)).foregroundStyle(Theme.text3)
            }
            if NutritionLabelParser.looksPoor(d) {
                Text(services.models.isConfigured(.smart)
                     ? "Some numbers didn't come through. Retake it closer, or let the AI read it."
                     : "Some numbers didn't come through. Retake it closer, or fill them in on the next screen.")
                    .font(.system(size: 13)).foregroundStyle(Theme.text2)
            }
        }
    }

    private func readRow(_ label: String, _ value: Double?, _ unit: String, key: String, _ d: FoodDraft, color: Color = Theme.text) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(color)
            if d.unsure(key) { Cap("Check", color: Theme.amber) }
            Spacer()
            Text(value.map { Format.trim($0) + (unit.isEmpty ? "" : " \(unit)") } ?? "–")
                .font(Typo.mono(14)).foregroundStyle(value == nil ? Theme.text3 : Theme.text)
        }
        .frame(height: 28)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 16) {
            if let draft {
                VStack(spacing: 8) {
                    if NutritionLabelParser.looksPoor(draft) && services.models.isConfigured(.smart) {
                        Button { readWithAI() } label: {
                            HStack(spacing: 8) {
                                if readingWithAI { ProgressView().tint(Theme.text) }
                                Text("Read with AI")
                            }
                        }
                        .buttonStyle(OutlineButtonStyle(fill: true))
                        .disabled(readingWithAI)
                    }
                    HStack(spacing: 8) {
                        Button("Retake") { retake() }
                            .buttonStyle(OutlineButtonStyle(fill: true))
                        Button("Continue") { proceed(draft) }
                            .buttonStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .layoutPriority(1.4)
                    }
                }
                .frame(height: 120, alignment: .bottom)
            } else {
                CameraModeSwitch(selected: .label) { _ in router.cover = .platePhoto }
                HStack {
                    Button { showLibrary = true } label: { RoundIcon(systemName: "photo.on.rectangle", size: 48, background: Theme.bar) }
                        .accessibilityLabel("Choose a photo")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ShutterButton(busy: reading) { shoot() }
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20))
    }

    // MARK: actions

    private func shoot() {
        error = nil
        switch camera.mode {
        case .live:
            reading = true
            Task {
                do {
                    let image = try await camera.capture()
                    read(image)
                } catch {
                    reading = false
                    self.error = error.localizedDescription
                }
            }
        case .fallback:
            if LabelCamera.hasCamera { showCamera = true } else { showLibrary = true }
        case .checking:
            break
        }
    }

    private func read(_ image: UIImage) {
        frozen = image
        reading = true
        let live = camera.live
        Task {
            var d = await LabelReader.read(image, live: live)
            d.source = "label_photo"
            draft = d
            reading = false
            if NutritionLabelParser.looksPoor(d) && services.models.isConfigured(.smart) && d.kcal == nil && d.protein == nil {
                // Nothing usable from OCR at all: go straight to the vision model.
                readWithAI()
            }
        }
    }

    private func readWithAI() {
        guard let image = frozen, let data = LabelOCR.jpeg(image) else { return }
        readingWithAI = true
        error = nil
        Task {
            do {
                var d = try await services.models.readLabel(imageData: data)
                d.rawText = d.rawText ?? draft?.rawText
                if d.source == "manual" { d.source = "label_photo" }
                draft = d
            } catch {
                self.error = error.localizedDescription
            }
            readingWithAI = false
        }
    }

    private func retake() {
        frozen = nil
        draft = nil
        error = nil
        camera.resetLive()
    }

    private func proceed(_ d: FoodDraft) {
        router.closeCover { [router] in router.push(.newFood(d)) }
    }
}
