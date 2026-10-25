import SwiftUI

/// Pieces shared by the label camera, the plate photo and the pantry scan.
enum CaptureColors {
    /// The camera screens sit on a slightly deeper black than the graphite page.
    static let ground = Color(hex: 0x0D0E0C)
    static let viewfinder = Color(hex: 0x1A1B18)
    static let segment = Color(hex: 0x1C1D1A)
    static let overlay = Color(hex: 0x0D0E0C, alpha: 0.82)
    static let progressTrack = Color(hex: 0x2E302B)
    static let stepperBorder = Color(hex: 0x3A3B37)
}

extension Router {
    /// Close the full-screen cover, then act once it has gone. Pushing while the cover
    /// is still animating out is unreliable, so wait for the dismissal.
    func closeCover(then action: (@MainActor () -> Void)? = nil) {
        cover = nil
        guard let action else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            action()
        }
    }
}

/// The 76 pt white shutter ring.
struct ShutterButton: View {
    var busy = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(Theme.text, lineWidth: 3)
                Circle().fill(Theme.text).padding(8)
                if busy { ProgressView().tint(Theme.graphite) }
            }
            .frame(width: 76, height: 76)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("Capture label")
    }
}

/// "Label | Plate" switch under the viewfinder.
struct CameraModeSwitch: View {
    enum Mode { case label, plate }
    var selected: Mode
    var onSelect: (Mode) -> Void

    var body: some View {
        HStack(spacing: 4) {
            item("Label", .label)
            item("Plate", .plate)
        }
        .padding(4)
        .background(Capsule().fill(CaptureColors.segment))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Camera mode")
    }

    private func item(_ title: String, _ mode: Mode) -> some View {
        let on = selected == mode
        return Button { if !on { onSelect(mode) } } label: {
            Text(title)
                .font(.system(size: 14, weight: on ? .semibold : .medium))
                .padding(.horizontal, 18)
                .frame(height: 36)
                .background(Capsule().fill(on ? Theme.text : .clear))
                .foregroundStyle(on ? Theme.graphite : Theme.amberText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The viewfinder: the live scanner, a frozen capture, or the fallback message.
struct LabelViewfinder: View {
    var camera: LabelCamera
    var frozen: UIImage?
    var fallbackText = "No live camera here. Take a photo of the label or pick one from your library."

    var body: some View {
        ZStack {
            CaptureColors.viewfinder
            if let frozen {
                Image(uiImage: frozen).resizable().scaledToFill()
            } else {
                switch camera.mode {
                case .checking:
                    ProgressView().tint(Theme.text3)
                case .live:
                    LiveLabelScanner(camera: camera)
                case .fallback:
                    VStack(spacing: 14) {
                        Image(systemName: "text.viewfinder").font(.system(size: 34, weight: .light)).foregroundStyle(Theme.text3)
                        Text(fallbackText)
                            .font(Typo.body).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }
                }
            }
        }
        .clipped()
    }
}

/// "Calories 150 · P 13 · C 21 · F 2" for a draft read so far.
extension FoodDraft {
    var readSummary: String {
        var parts: [String] = []
        if let kcal { parts.append("\(Format.int(kcal)) kcal") }
        if let protein { parts.append("P \(Format.trim(protein))") }
        if let carbs { parts.append("C \(Format.trim(carbs))") }
        if let fat { parts.append("F \(Format.trim(fat))") }
        if let fiber, fiber > 0 { parts.append("fiber \(Format.trim(fiber))") }
        return parts.joined(separator: " · ")
    }

    /// "1 cup · 40 g", "100 g", "serving".
    var servingSummary: String {
        if basis == .per100g { return servingGrams.map { "100 g · serving \(Format.trim($0)) g" } ?? "100 g" }
        let label = servingLabel ?? "serving"
        return servingGrams.map { "1 \(label) · \(Format.trim($0)) g" } ?? "1 \(label)"
    }

    /// Uncertain under either spelling: the label parser uses property names
    /// ("servingGrams"), the vision model snake_case ("serving_grams").
    func unsure(_ key: String) -> Bool {
        if uncertain.contains(key) { return true }
        let snake = key.reduce(into: "") { s, c in s += c.isUppercase ? "_" + c.lowercased() : String(c) }
        return uncertain.contains(snake)
    }

    /// The 4 kcal/g figure, P*4 + C*4 + F*9, used when the printed calories don't add up.
    var atwaterKcal: Double? {
        guard let protein, let carbs, let fat else { return nil }
        return (protein * 4 + carbs * 4 + fat * 9).rounded()
    }
}

/// Kcal left today, for the camera's top bar.
extension Ledger {
    func kcalLeftText(on day: String) -> String? {
        guard let left = status(.kcal, on: day).left else { return nil }
        return left >= 0 ? "\(Format.int(left)) left" : "\(Format.int(-left)) over"
    }
}
