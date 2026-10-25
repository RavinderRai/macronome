import UIKit
import Vision

/// On-device text recognition for label photos. Vision returns one observation per
/// run of text, so a panel row ("Fat / Lipides 2 g" ... "3 %") can come back in
/// pieces; `rows` stitches them back into lines before the parser sees them.
enum LabelOCR {
    struct Piece: Sendable {
        var text: String
        /// Normalized, origin at the bottom left (Vision's convention).
        var box: CGRect
    }

    static func text(in image: UIImage) async throws -> String {
        guard let cg = image.cgImage else { return "" }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "en-CA"), Locale.Language(identifier: "fr-CA")]
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: cg, orientation: CGImagePropertyOrientation(image.imageOrientation))
        let pieces = observations.compactMap { o -> Piece? in
            guard let s = o.topCandidates(1).first?.string else { return nil }
            return Piece(text: s, box: o.boundingBox.cgRect)
        }
        return rows(pieces).joined(separator: "\n")
    }

    /// Group pieces whose vertical centres line up into rows, top to bottom, each row
    /// read left to right.
    static func rows(_ pieces: [Piece], yUp: Bool = true) -> [String] {
        var rows: [(mid: CGFloat, height: CGFloat, items: [Piece])] = []
        let sorted = pieces.sorted { yUp ? $0.box.midY > $1.box.midY : $0.box.midY < $1.box.midY }
        for p in sorted {
            if let i = rows.firstIndex(where: { abs($0.mid - p.box.midY) < min($0.height, p.box.height) * 0.5 }) {
                rows[i].items.append(p)
            } else {
                rows.append((p.box.midY, p.box.height, [p]))
            }
        }
        return rows.map { row in row.items.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
    }

    /// A JPEG small enough to send to a vision model.
    static func jpeg(_ image: UIImage, maxSide: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        guard scale < 1 else { return image.jpegData(compressionQuality: quality) }
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

/// Reads a captured label photo into a draft. Anything the photo's OCR missed but the
/// live scanner saw is filled in from the live read and flagged.
enum LabelReader {
    static func read(_ image: UIImage, live: FoodDraft? = nil) async -> FoodDraft {
        let text = (try? await LabelOCR.text(in: image)) ?? ""
        var d = NutritionLabelParser.parse(text)
        guard let live else { return d }
        func fill(_ path: WritableKeyPath<FoodDraft, Double?>, _ name: String) {
            if d[keyPath: path] == nil, let v = live[keyPath: path] {
                d[keyPath: path] = v
                d.uncertain.insert(name)
            }
        }
        fill(\.kcal, "kcal")
        fill(\.protein, "protein")
        fill(\.carbs, "carbs")
        fill(\.fat, "fat")
        fill(\.fiber, "fiber")
        fill(\.servingGrams, "servingGrams")
        for (k, v) in live.micros where d.micros[k] == nil {
            d.micros[k] = v
            d.uncertain.insert(k)
        }
        if d.rawText?.isEmpty ?? true { d.rawText = live.rawText }
        return d
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
