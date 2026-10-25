import SwiftUI

/// PlatePhoto.dc.html: a photo of a plated or restaurant meal, estimated by the smart
/// model and logged as a one-off group. Never added to the food library.
struct PlatePhotoView: View {
    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var services

    @State private var photo: UIImage?
    @State private var note = ""
    @State private var estimate: PlateEstimate?
    /// Per-item portion scale, 1 = as estimated.
    @State private var scales: [UUID: Double] = [:]
    @State private var expanded: UUID?
    @State private var working = false
    @State private var error: String?
    @State private var adjusting = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var slot = MealSlot.guess()
    @FocusState private var noteFocused: Bool

    var body: some View {
        // Laid out in screen coordinates like the artboard: photo 330 tall, sheet from 300.
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            ZStack(alignment: .top) {
                CaptureColors.ground
                photoArea.frame(height: max(330, top + 250))
                sheet.padding(.top, max(300, top + 220))
                Button { router.closeCover() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
                .padding(.leading, 8).padding(.top, top + 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .ignoresSafeArea(edges: .top)
        }
        .background(CaptureColors.ground.ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .imageSources(camera: $showCamera, library: $showLibrary) { image in
            photo = image
            estimate = nil
            if services.models.isConfigured(.smart) { run() }
        }
    }

    // MARK: photo

    private var photoArea: some View {
        ZStack(alignment: .topLeading) {
            CaptureColors.viewfinder
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            } else {
                Circle().strokeBorder(Color(hex: 0x4A4C46), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: 230, height: 230)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Cap("Your photo", color: Theme.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let estimate {
                // Item names over the photo, as in the design; positions are not known.
                ChipFlow(spacing: 6) {
                    ForEach(estimate.items) { item in
                        Text(Format.shortName(item.label).lowercased())
                            .font(Typo.mono(12))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x0D0E0C, alpha: 0.75)))
                    }
                }
                .padding(.horizontal, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 30)
            }
        }
        .clipped()
    }

    // MARK: sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !services.models.isConfigured(.smart) {
                notConfigured
            } else if let estimate {
                result(estimate)
            } else {
                capture
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22).fill(Theme.surface)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: 14) {
            Cap("Estimate · one-off")
            Text("Plate photos need a smart model").font(Typo.title(24)).tracking(-0.5)
            Text("Estimating a plate from a photo is done by a vision model, and none is set up yet. Add one in Settings → Models. Labels don't need it: the label camera reads them on the phone.")
                .font(Typo.body).lineSpacing(4).foregroundStyle(Theme.planned)
            Spacer()
            HStack(spacing: 8) {
                Button("Scan a label") { router.cover = .labelScan }
                    .buttonStyle(OutlineButtonStyle(height: 52, fill: true))
                Button("Set up a model") { router.closeCover { [router] in router.push(.aiSettings) } }
                    .buttonStyle(.primary)
            }
        }
    }

    private var capture: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Cap("Estimate · one-off")
                Spacer()
                Cap("Portions from the photo")
            }
            Text(photo == nil ? "Photograph the plate" : working ? "Looking at the plate" : "Ready to estimate")
                .font(Typo.title(24)).tracking(-0.5)
            noteField
            if let error {
                Text(error).font(.system(size: 14)).foregroundStyle(Theme.coral)
            }
            Text("Restaurant meals and plates are logged as a one-off and don't go into your foods.")
                .font(.system(size: 14)).foregroundStyle(Theme.text3)
            Spacer()
            if photo != nil {
                HStack(spacing: 8) {
                    Button("Retake") { pick() }.buttonStyle(OutlineButtonStyle(height: 52, fill: true))
                    Button { run() } label: {
                        HStack(spacing: 8) {
                            if working { ProgressView().tint(Theme.graphite) }
                            Text(working ? "Estimating" : "Estimate")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(working)
                }
            } else {
                VStack(spacing: 14) {
                    CameraModeSwitch(selected: .plate) { _ in router.cover = .labelScan }
                    HStack {
                        Button { showLibrary = true } label: { RoundIcon(systemName: "photo.on.rectangle", size: 48, background: Theme.bar) }
                            .accessibilityLabel("Choose a photo")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ShutterButton { pick() }.accessibilityLabel("Take a photo")
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var noteField: some View {
        TextField("", text: $note, prompt: Text("Anything the photo won't show, like \"half the fries\"").foregroundStyle(Theme.text3), axis: .vertical)
            .font(.system(size: 15))
            .focused($noteFocused)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.graphite))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CaptureColors.stepperBorder, lineWidth: 1))
    }

    private func result(_ e: PlateEstimate) -> some View {
        let total = scaledTotal(e)
        let (lo, hi) = range(total.kcal, confidence: e.confidence)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Cap("Estimate · one-off")
                Spacer()
                Cap("\(e.confidence) confidence")
            }
            HStack(alignment: .bottom, spacing: 12) {
                Text(e.title).font(Typo.title(24)).tracking(-0.5).lineSpacing(1)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("~\(Format.int(total.kcal))").font(Typo.mono(26)).contentTransition(.numericText())
                    Text("\(Format.int(lo)) to \(Format.int(hi))").font(Typo.mono(12)).foregroundStyle(Theme.text3)
                }
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(e.items) { item in itemRow(item) }
                }
                .overlay(alignment: .top) { Hairline() }
                if let n = e.note, !n.isEmpty {
                    Text(n + " Restaurant meals don't go into your foods.")
                        .font(.system(size: 14)).lineSpacing(3).foregroundStyle(Theme.planned)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14)
                } else {
                    Text("Restaurant meals don't go into your foods.")
                        .font(.system(size: 14)).foregroundStyle(Theme.planned)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14)
                }
                if adjusting {
                    VStack(alignment: .leading, spacing: 10) {
                        noteField
                        Button { run() } label: {
                            HStack(spacing: 8) {
                                if working { ProgressView().tint(Theme.text) }
                                Text("Estimate again")
                            }
                        }
                        .buttonStyle(OutlineButtonStyle(height: 44, fill: true))
                        .disabled(working)
                        if let error { Text(error).font(.system(size: 13)).foregroundStyle(Theme.coral) }
                    }
                    .padding(.top, 12)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 8) {
                Button(adjusting ? "Done" : "Adjust") {
                    adjusting.toggle()
                    noteFocused = adjusting
                }
                .buttonStyle(OutlineButtonStyle(height: 52, fill: true))
                Menu {
                    ForEach(MealSlot.allCases) { s in
                        Button(s.title) { slot = s }
                    }
                } label: {
                    Text("Log as \(slot.rawValue)")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().fill(Theme.text))
                        .foregroundStyle(Theme.graphite)
                } primaryAction: {
                    log(e)
                }
                .layoutPriority(1)
            }
        }
    }

    private func itemRow(_ item: PlateEstimate.Item) -> some View {
        let scale = scales[item.id] ?? 1
        let open = expanded == item.id
        return VStack(spacing: 0) {
            Button { withAnimation(.snappy) { expanded = open ? nil : item.id } } label: {
                HStack(spacing: 8) {
                    Text(item.label).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    if let g = item.grams { Text("~\(Format.int(g * scale)) g").foregroundStyle(Theme.text3) }
                    Text("\(Format.int(item.macros.protein * scale)) P").foregroundStyle(Theme.text3).frame(width: 40, alignment: .trailing)
                    Text(Format.int(item.macros.kcal * scale)).frame(width: 40, alignment: .trailing)
                }
                .font(Typo.mono(13))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Change the portion")
            if open {
                HStack {
                    Text(scale == 0 ? "Not eaten" : "\(Int((scale * 100).rounded()))% of the estimate")
                        .font(.system(size: 13)).foregroundStyle(Theme.text2)
                    Spacer()
                    HStack(spacing: 0) {
                        Button { scales[item.id] = max(0, scale - 0.25) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                            .accessibilityLabel("Less \(item.label)")
                        Button { scales[item.id] = scale + 0.25 } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                            .accessibilityLabel("More \(item.label)")
                    }
                    .background(Capsule().fill(Theme.bar))
                }
                .padding(.bottom, 8)
            }
        }
        .overlay(alignment: .bottom) { Hairline() }
    }

    // MARK: logic

    private func pick() {
        if LabelCamera.hasCamera { showCamera = true } else { showLibrary = true }
    }

    private func run() {
        guard let photo, let data = LabelOCR.jpeg(photo, maxSide: 1400, quality: 0.75) else { return }
        working = true
        error = nil
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let e = try await services.models.estimatePlate(imageData: data, note: text.isEmpty ? nil : text, ledger: store.ledger)
                estimate = e
                scales = [:]
                expanded = nil
                adjusting = false
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }

    private func scaledTotal(_ e: PlateEstimate) -> Macros {
        e.items.reduce(.zero) { $0 + scaled($1.macros, scales[$1.id] ?? 1) }
    }

    private func scaled(_ m: Macros, _ s: Double) -> Macros {
        Macros(kcal: (m.kcal * s).rounded(), protein: Ledger.round2(m.protein * s), carbs: Ledger.round2(m.carbs * s),
               fat: Ledger.round2(m.fat * s), fiber: Ledger.round2(m.fiber * s))
    }

    /// A spread that widens as confidence drops, rounded to tens.
    private func range(_ kcal: Double, confidence: String) -> (Double, Double) {
        let spread = confidence == "high" ? 0.08 : confidence == "medium" ? 0.15 : 0.25
        return (((kcal * (1 - spread)) / 10).rounded() * 10, ((kcal * (1 + spread)) / 10).rounded() * 10)
    }

    private func log(_ e: PlateEstimate) {
        let gid = EventID.make()
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let events = e.items.compactMap { item -> Event? in
            let s = scales[item.id] ?? 1
            guard s > 0 else { return nil }
            return Commands.logEstimate(label: item.label, macros: scaled(item.macros, s), grams: item.grams.map { ($0 * s).rounded() },
                                        meal: slot, source: InputSource.photo.rawValue, confidence: e.confidence,
                                        note: trimmed.isEmpty ? nil : trimmed, groupID: gid, groupLabel: e.title)
        }
        guard !events.isEmpty else { return }
        store.log(events)
        router.closeCover()
    }
}
