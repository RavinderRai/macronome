import SwiftUI

/// PantryScan.dc.html, step 2 of onboarding: point at label after label. Each one is
/// captured when the live read has serving, calories and macros, or with the shutter.
struct PantryScanView: View {
    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var services
    @AppStorage("onboarded") private var onboarded = false

    @State private var camera = LabelCamera()
    @State private var drafts: [FoodDraft] = OnboardingSession.drafts
    @State private var busy = false
    @State private var lastCapture = Date.distantPast
    @State private var lastSummary = ""
    @State private var flash: String?
    @State private var showCamera = false
    @State private var showLibrary = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Cap("Step 2 of 2", color: Theme.muted)
                Spacer()
                Button("Skip") { skip() }
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.amberText)
                    .padding(.horizontal, 10).frame(height: 44)
            }
            .padding(.leading, 20).padding(.trailing, 10)
            .frame(height: 56)

            VStack(alignment: .leading, spacing: 6) {
                Text("Build your foods").font(.system(size: 26, weight: .semibold)).tracking(-0.8)
                Text("Point at the nutrition label of anything you eat often. It captures when the label is sharp.")
                    .font(Typo.body).lineSpacing(3).foregroundStyle(Theme.amberText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            viewfinder
                .padding(.horizontal, 20).padding(.top, 20)

            addedStrip.padding(.top, 20)

            Spacer(minLength: 0)
            controls
        }
        .background(CaptureColors.ground.ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .task { await camera.prepare() }
        .onChange(of: camera.coverage) { _, c in autoCapture(c) }
        .imageSources(camera: $showCamera, library: $showLibrary) { image in read(image, live: nil) }
    }

    private var viewfinder: some View {
        ZStack(alignment: .topLeading) {
            LabelViewfinder(camera: camera, frozen: nil,
                            fallbackText: "No live camera here. Take or choose a photo of each label.")
            Corners().stroke(Theme.text, lineWidth: 2).padding(14).padding(.top, 42).allowsHitTesting(false)
            Text(flash ?? (busy ? "Reading the label" : camera.sawLabel ? "Reading serving, calories, macros" : "Point at a nutrition label"))
                .capStyle(flash == nil ? Theme.text : Theme.amber)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x0D0E0C, alpha: 0.7)))
                .padding(16)
            if camera.mode == .live && camera.sawLabel {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        Capsule().fill(Theme.amber).frame(width: geo.size.width * camera.coverage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Capsule().fill(CaptureColors.progressTrack))
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 54).padding(.bottom, 26)
                }
                .animation(.snappy, value: camera.coverage)
            }
        }
        .frame(height: 392)
        .frame(maxHeight: 392)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder private var addedStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Cap(drafts.isEmpty ? "None added yet" : "\(drafts.count) added", color: Theme.muted).padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(drafts.reversed()) { d in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(d.name.isEmpty ? "Unnamed label" : d.name)
                                .font(.system(size: 14, weight: .medium)).lineLimit(1)
                                .foregroundStyle(d.name.isEmpty ? Theme.text2 : Theme.text)
                            Text(d.kcal.map { "\(Format.int($0)) / \(d.basis == .per100g ? "100 g" : d.servingLabel ?? "serving")" } ?? "check numbers")
                                .font(Typo.mono(12)).foregroundStyle(Theme.muted)
                        }
                        .padding(12)
                        .frame(width: 132, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(CaptureColors.segment))
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(height: 62)
        }
    }

    private var controls: some View {
        HStack {
            Button { showLibrary = true } label: { RoundIcon(systemName: "photo.on.rectangle", size: 48, background: Theme.bar) }
                .accessibilityLabel("Choose a photo")
                .frame(maxWidth: .infinity, alignment: .leading)
            ShutterButton(busy: busy) { shoot() }
            Button("Done") { done() }
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 18).frame(height: 44)
                .background(Capsule().fill(Theme.text))
                .foregroundStyle(Theme.graphite)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(height: 120)
    }

    // MARK: capture

    private func autoCapture(_ coverage: Double) {
        guard coverage >= 1, !busy, camera.mode == .live, Date().timeIntervalSince(lastCapture) > 3,
              let live = camera.live, live.readSummary != lastSummary else { return }
        lastSummary = live.readSummary
        shoot()
    }

    private func shoot() {
        switch camera.mode {
        case .live:
            busy = true
            let live = camera.live
            Task {
                do {
                    let image = try await camera.capture()
                    read(image, live: live)
                } catch {
                    busy = false
                    flash = error.localizedDescription
                }
            }
        case .fallback:
            if LabelCamera.hasCamera { showCamera = true } else { showLibrary = true }
        case .checking:
            break
        }
    }

    private func read(_ image: UIImage, live: FoodDraft?) {
        busy = true
        lastCapture = Date()
        Task {
            var d = await LabelReader.read(image, live: live)
            if NutritionLabelParser.looksPoor(d), services.models.isConfigured(.smart), let data = LabelOCR.jpeg(image),
               var ai = try? await services.models.readLabel(imageData: data) {
                ai.rawText = ai.rawText ?? d.rawText
                d = ai
            }
            d.source = "label_photo"
            drafts.append(d)
            OnboardingSession.drafts = drafts
            flash = d.readSummary.isEmpty ? "Added, numbers to check" : "Added · " + d.readSummary
            busy = false
            lastCapture = Date()
            camera.resetLive()
            try? await Task.sleep(for: .seconds(2))
            flash = nil
        }
    }

    private func done() {
        guard !drafts.isEmpty else { return skip() }
        OnboardingSession.drafts = drafts
        let list = drafts
        router.closeCover { [router] in router.push(.pantryReview(list)) }
    }

    private func skip() {
        onboarded = true
        OnboardingSession.finish(store: store, router: router)
    }
}

/// Viewfinder corner brackets.
private struct Corners: Shape {
    var length: CGFloat = 26
    var radius: CGFloat = 6

    func path(in r: CGRect) -> Path {
        var p = Path()
        let l = length
        // top left
        p.move(to: CGPoint(x: r.minX, y: r.minY + l))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + l, y: r.minY), radius: radius)
        p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        // top right
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + l), radius: radius)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        // bottom right
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - l, y: r.maxY), radius: radius)
        p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        // bottom left
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - l), radius: radius)
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}
