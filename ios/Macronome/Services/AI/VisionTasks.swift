import Foundation
import UIKit

/// Prompts and parsing for the two photo tasks: a plated meal and a nutrition label.
enum VisionTasks {
    /// Longest side ~1024 px as JPEG; vision models gain nothing from more and it
    /// keeps the upload and the image tokens small.
    static func downscaledJPEG(_ data: Data, maxSide: CGFloat = 1024) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8) ?? data
    }

    // MARK: plate

    static func plateRequest(image: Data, note: String?, ledger: Ledger) -> ModelRequest {
        var context: [String] = []
        if let diet = ledger.profile["diet"], !diet.isEmpty { context.append("Ravi's diet: \(diet).") }
        let system = """
        You estimate a plated or restaurant meal from a photo for a macro tracker. Identify each component, \
        estimate its cooked weight in grams, and estimate kcal, protein, carbs, fat and fiber for that weight \
        using typical reference values. Be realistic about oil and sauces in restaurant food. \(context.joined(separator: " "))
        Reply with JSON only:
        {"title": "Chipotle burrito bowl", "items": [{"label": "white rice", "grams": 180, "kcal": 230, "protein": 4, \
        "carbs": 50, "fat": 1, "fiber": 1}], "confidence": "low" | "medium" | "high", "note": "one short line on what \
        is most uncertain"}
        """
        var prompt = "Estimate this meal."
        if let note, !note.trimmingCharacters(in: .whitespaces).isEmpty { prompt += " Ravi says: \(note)" }
        return ModelRequest(system: [system], messages: [ModelMessage(role: .user, text: prompt)],
                            images: [downscaledJPEG(image)], jsonMode: true, maxTokens: 2000, timeout: 90)
    }

    static func parsePlate(_ raw: String) throws -> PlateEstimate {
        guard let o = ChatReplyParser.jsonObject(in: raw) else { throw ModelError.badResponse("no JSON in the plate estimate") }
        let items = (o["items"]?.array ?? []).compactMap { v -> PlateEstimate.Item? in
            guard let i = v.object, let label = i["label"]?.string ?? i["name"]?.string else { return nil }
            let m = Macros(kcal: i["kcal"]?.double ?? 0, protein: i["protein"]?.double ?? 0, carbs: i["carbs"]?.double ?? 0,
                           fat: i["fat"]?.double ?? 0, fiber: i["fiber"]?.double ?? 0)
            return PlateEstimate.Item(label: label, grams: i["grams"]?.double, macros: m)
        }
        guard !items.isEmpty else { throw ModelError.badResponse("no items in the plate estimate") }
        let confidence = o["confidence"]?.string?.lowercased()
        return PlateEstimate(title: o["title"]?.string ?? "Plate", items: items,
                             confidence: ["low", "medium", "high"].contains(confidence ?? "") ? confidence! : "low",
                             note: o["note"]?.string)
    }

    // MARK: label

    /// The fixed micronutrient keys from food-log/CLAUDE.md; totals only add up when
    /// the spelling matches across foods.
    static let microKeys = [
        "sat_fat_g", "trans_fat_g", "sugar_g", "added_sugar_g", "cholesterol_mg", "sodium_mg", "potassium_mg",
        "calcium_mg", "iron_mg", "magnesium_mg", "zinc_mg", "phosphorus_mg", "vitamin_a_ug", "vitamin_c_mg",
        "vitamin_d_ug", "vitamin_e_mg", "vitamin_k_ug", "thiamin_mg", "riboflavin_mg", "niacin_mg", "vitamin_b6_mg",
        "folate_ug", "vitamin_b12_ug", "omega3_g", "caffeine_mg",
    ]

    static func labelRequest(image: Data) -> ModelRequest {
        let system = """
        You read a nutrition facts label from a photo for a food tracker. Enter the numbers exactly as printed; \
        do not round, correct or recompute them.
        - basis: "serving" when the main column is per serving, "100g" when it is per 100 g or 100 ml.
        - serving_label: the household unit, singular and lowercase ("cup", "scoop", "slice", "bar"); \
        serving_grams: the gram or ml weight of one serving when printed.
        - kcal, protein, carbs (total carbohydrate), fat, fiber for the chosen basis. Add fiber_soluble and \
        fiber_insoluble only when printed.
        - micros: every other nutrient printed, using exactly these keys and units: \(microKeys.joined(separator: ", ")). \
        If only a %DV is printed, convert it with these daily values: calcium 1300 mg, iron 18 mg, potassium 4700 mg, \
        vitamin D 20 ug, sodium 2300 mg, magnesium 420 mg, zinc 11 mg, vitamin A 900 ug, vitamin C 90 mg, \
        folate 400 ug, vitamin B12 2.4 ug; list every converted key in "converted".
        - name: brand and product as on the package if visible; aliases: two or three short lowercase names \
        he might say.
        - uncertain: names of fields you could not read clearly (any of name, basis, serving_grams, \
        serving_label, kcal, protein, carbs, fat, fiber, or a micros key).
        - raw_text: the label text as you read it, compact, one line per row.
        Reply with JSON only: {"name": "...", "aliases": ["..."], "basis": "serving", "serving_label": "cup", \
        "serving_grams": 40, "kcal": 150, "protein": 13, "carbs": 21, "fat": 2, "fiber": 5, "micros": {"sodium_mg": 125}, \
        "converted": [], "uncertain": [], "raw_text": "..."}
        """
        return ModelRequest(system: [system], messages: [ModelMessage(role: .user, text: "Read this label.")],
                            images: [downscaledJPEG(image)], jsonMode: true, maxTokens: 2000, timeout: 90)
    }

    static func parseLabel(_ raw: String) throws -> FoodDraft {
        guard let o = ChatReplyParser.jsonObject(in: raw) else { throw ModelError.badResponse("no JSON in the label reading") }
        var d = FoodDraft()
        d.source = "label_photo"
        d.name = o["name"]?.string ?? ""
        if let a = o["aliases"]?.array {
            d.aliases = a.compactMap(\.string).joined(separator: ", ")
        } else if let a = o["aliases"]?.string {
            d.aliases = a
        }
        let basis = (o["basis"]?.string ?? "serving").lowercased()
        d.basis = basis.contains("100") ? .per100g : .serving
        d.servingGrams = o["serving_grams"]?.double
        d.servingLabel = o["serving_label"]?.string?.lowercased() ?? (d.basis == .serving ? "serving" : nil)
        d.kcal = o["kcal"]?.double
        d.protein = o["protein"]?.double
        d.carbs = o["carbs"]?.double
        d.fat = o["fat"]?.double
        d.fiber = o["fiber"]?.double
        d.fiberSoluble = o["fiber_soluble"]?.double
        d.fiberInsoluble = o["fiber_insoluble"]?.double
        var micros: [String: Double] = [:]
        for (k, v) in o["micros"]?.object ?? [:] {
            guard let n = v.double else { continue }
            micros[k.lowercased()] = n
        }
        d.micros = micros
        d.rawText = o["raw_text"]?.string
        var uncertain = Set((o["uncertain"]?.array ?? []).compactMap(\.string))
        for key in ["kcal", "protein", "carbs", "fat"] where o[key]?.double == nil { uncertain.insert(key) }
        if d.name.isEmpty { uncertain.insert("name") }
        d.uncertain = uncertain
        let converted = (o["converted"]?.array ?? []).compactMap(\.string)
        if !converted.isEmpty { d.notes = "Converted from %DV: \(converted.joined(separator: ", "))" }
        return d
    }
}
