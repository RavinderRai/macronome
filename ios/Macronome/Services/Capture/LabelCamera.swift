import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import VisionKit

/// The live label camera: VisionKit's DataScanner reading text while you aim, and a
/// still capture that goes through the full OCR. Where the scanner is not available
/// (simulator, older phones, camera denied) screens fall back to the photo pickers.
@MainActor
@Observable
final class LabelCamera: NSObject, DataScannerViewControllerDelegate {
    enum Mode { case checking, live, fallback }

    private(set) var mode: Mode = .checking
    /// What the scanner reads right now, parsed. Drives the "reading" bar.
    private(set) var live: FoodDraft?
    private(set) var coverage: Double = 0
    /// Any nutrition-panel words in view.
    private(set) var sawLabel = false

    @ObservationIgnored weak var controller: DataScannerViewController?
    @ObservationIgnored private var lastParse = Date.distantPast
    @ObservationIgnored private var pendingItems: [RecognizedItem] = []

    static var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func prepare() async {
        guard mode == .checking else { return }
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        mode = DataScannerViewController.isSupported && DataScannerViewController.isAvailable ? .live : .fallback
    }

    func capture() async throws -> UIImage {
        guard let controller else { throw CaptureError.noCamera }
        return try await controller.capturePhoto()
    }

    func resetLive() {
        live = nil
        coverage = 0
        sawLabel = false
    }

    enum CaptureError: LocalizedError {
        case noCamera
        var errorDescription: String? { "The camera isn't ready." }
    }

    // MARK: DataScannerViewControllerDelegate

    func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        update(allItems)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        update(allItems)
    }

    func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
        update(allItems)
    }

    /// Parsing a frame takes a few milliseconds; twice a second is plenty for the bar.
    private func update(_ items: [RecognizedItem]) {
        pendingItems = items
        guard Date().timeIntervalSince(lastParse) > 0.5 else { return }
        lastParse = Date()
        let pieces: [LabelOCR.Piece] = pendingItems.compactMap { item in
            guard case .text(let t) = item else { return nil }
            let b = t.bounds
            let minX = min(b.topLeft.x, b.bottomLeft.x), maxX = max(b.topRight.x, b.bottomRight.x)
            let minY = min(b.topLeft.y, b.topRight.y), maxY = max(b.bottomLeft.y, b.bottomRight.y)
            return LabelOCR.Piece(text: t.transcript, box: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
        }
        let text = LabelOCR.rows(pieces, yUp: false).joined(separator: "\n")
        let folded = text.lowercased()
        sawLabel = ["nutrition", "valeur nutritive", "calories", "protein", "lipides", "glucides"].contains(where: folded.contains)
        guard sawLabel else {
            live = nil
            coverage = 0
            return
        }
        let d = NutritionLabelParser.parse(text)
        live = d
        coverage = NutritionLabelParser.coverage(d)
    }
}

/// VisionKit's live text scanner.
struct LiveLabelScanner: UIViewControllerRepresentable {
    let camera: LabelCamera

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["en-CA", "fr-CA"])],
            qualityLevel: .accurate, recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: false, isHighlightingEnabled: false)
        vc.delegate = camera
        camera.controller = vc
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: ()) {
        vc.stopScanning()
    }
}

/// The system camera for a single still, used when the live scanner is unavailable.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

extension View {
    /// The system camera and the photo library as image sources, for the fallback path.
    func imageSources(camera: Binding<Bool>, library: Binding<Bool>, onImage: @escaping (UIImage) -> Void) -> some View {
        modifier(ImageSources(showCamera: camera, showLibrary: library, onImage: onImage))
    }
}

private struct ImageSources: ViewModifier {
    @Binding var showCamera: Bool
    @Binding var showLibrary: Bool
    var onImage: (UIImage) -> Void
    @State private var item: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(onImage: onImage).ignoresSafeArea()
            }
            .photosPicker(isPresented: $showLibrary, selection: $item, matching: .images)
            .onChange(of: item) { _, new in
                guard let new else { return }
                Task { @MainActor in
                    if let data = try? await new.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        onImage(image)
                    }
                    item = nil
                }
            }
    }
}
