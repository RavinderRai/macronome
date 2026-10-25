import XCTest

/// OCR text as Vision returns it: one line per row of the panel, labels and values
/// joined, in reading order.
final class NutritionLabelParserTests: XCTestCase {
    func testCanadianCerealLabel() {
        let text = """
        Nutrition Facts
        Valeur nutritive
        Per 1 cup (40 g) / pour 1 tasse (40 g)
        Calories 150   % Daily Value* / % valeur quotidienne*
        Fat / Lipides 2 g   3 %
        Saturated / saturés 0.5 g   3 %
        + Trans / trans 0 g
        Carbohydrate / Glucides 21 g
        Fibre / Fibres 5 g   18 %
        Soluble Fibre / Fibres solubles 5 g
        Sugars / Sucres 0 g   0 %
        Protein / Protéines 13 g
        Cholesterol / Cholestérol 0 mg
        Sodium 125 mg   5 %
        Potassium 250 mg   5 %
        Calcium 50 mg   4 %
        Iron / Fer 3 mg   17 %
        *5% or less is a little, 15% or more is a lot
        *5 % ou moins c'est peu, 15 % ou plus c'est beaucoup
        """
        let d = NutritionLabelParser.parse(text)
        XCTAssertEqual(d.basis, .serving)
        XCTAssertEqual(d.servingLabel, "cup")
        XCTAssertEqual(d.servingGrams, 40)
        XCTAssertEqual(d.kcal, 150)
        XCTAssertEqual(d.fat, 2)
        XCTAssertEqual(d.carbs, 21)
        XCTAssertEqual(d.fiber, 5)
        XCTAssertEqual(d.fiberSoluble, 5)
        XCTAssertNil(d.fiberInsoluble)
        XCTAssertEqual(d.protein, 13)
        XCTAssertEqual(d.micros, [
            "sat_fat_g": 0.5, "trans_fat_g": 0, "sugar_g": 0, "cholesterol_mg": 0, "sodium_mg": 125,
            "potassium_mg": 250, "calcium_mg": 50, "iron_mg": 3,
        ])
        XCTAssertTrue(d.uncertain.isEmpty, "\(d.uncertain)")
        XCTAssertNil(d.labelArithmeticWarning)
        XCTAssertEqual(d.source, "label_photo")
        XCTAssertNil(d.notes)
    }

    func testUSProteinPowderLabel() {
        let text = """
        Nutrition Facts
        About 30 servings per container
        Serving size 1 scoop (31g)
        Amount per serving
        Calories
        120
        % Daily Value*
        Total Fat 1.5g 2%
        Saturated Fat 0g 0%
        Trans Fat 0g
        Cholesterol 5mg 2%
        Sodium 160mg 7%
        Total Carbohydrate 3g 1%
        Dietary Fiber <1g 2%
        Total Sugars 1g
        Includes 0g Added Sugars 0%
        Protein 24g 48%
        Vitamin D 0mcg 0%
        Calcium 130mg 10%
        Iron 0.4mg 2%
        Potassium 180mg 4%
        * The % Daily Value (DV) tells you how much a nutrient in a serving of food contributes to a daily diet.
        2,000 calories a day is used for general nutrition advice.
        """
        let d = NutritionLabelParser.parse(text)
        XCTAssertEqual(d.servingLabel, "scoop")
        XCTAssertEqual(d.servingGrams, 31)
        XCTAssertEqual(d.kcal, 120)
        XCTAssertEqual(d.fat, 1.5)
        XCTAssertEqual(d.carbs, 3)
        XCTAssertEqual(d.protein, 24)
        // "<1 g" is recorded as half a gram and flagged.
        XCTAssertEqual(d.fiber, 0.5)
        XCTAssertTrue(d.uncertain.contains("fiber"))
        XCTAssertEqual(d.micros["sat_fat_g"], 0)
        XCTAssertEqual(d.micros["trans_fat_g"], 0)
        XCTAssertEqual(d.micros["cholesterol_mg"], 5)
        XCTAssertEqual(d.micros["sodium_mg"], 160)
        XCTAssertEqual(d.micros["sugar_g"], 1)
        XCTAssertEqual(d.micros["added_sugar_g"], 0)
        XCTAssertEqual(d.micros["vitamin_d_ug"], 0)
        XCTAssertEqual(d.micros["calcium_mg"], 130)
        XCTAssertEqual(d.micros["iron_mg"], 0.4)
        XCTAssertEqual(d.micros["potassium_mg"], 180)
        XCTAssertEqual(d.micros.count, 10)
        XCTAssertNil(d.labelArithmeticWarning)
    }

    func testCannedBeansWithPercentOnlyMineralsAndBadArithmetic() {
        let text = """
        Nutrition Facts / Valeur nutritive
        Per 1/2 cup (130 mL) / par 1/2 tasse (130 mL)
        Amount   % Daily Value
        Teneur   % valeur quotidienne
        Calories / Calories 100
        Fat / Lipides 0.5 g   1 %
        Saturated / saturés 0.1 g
        + Trans / trans 0 g   1 %
        Cholesterol / Cholestérol 0 mg
        Sodium / Sodium 280 mg   12 %
        Carbohydrate / Glucides 27 g   9 %
        Fibre / Fibres 7 g   28 %
        Sugars / Sucres 1 g
        Protein / Protéines 7 g
        Vitamin A / Vitamine A   0 %
        Vitamin C / Vitamine C   0 %
        Calcium / Calcium   4 %
        Iron / Fer   15 %
        """
        let d = NutritionLabelParser.parse(text)
        // Half a cup is not "1 cup": stored per serving with a note.
        XCTAssertEqual(d.servingLabel, "serving")
        XCTAssertEqual(d.servingGrams, 130)
        XCTAssertEqual(d.notes?.contains("serving is 1/2 cup (130 mL)"), true, d.notes ?? "")
        XCTAssertEqual(d.notes?.contains("converted from %DV"), true)
        XCTAssertEqual(d.kcal, 100)
        XCTAssertEqual(d.protein, 7)
        XCTAssertEqual(d.carbs, 27)
        XCTAssertEqual(d.fiber, 7)
        XCTAssertEqual(d.fat, 0.5)
        XCTAssertEqual(d.micros["sodium_mg"], 280)
        XCTAssertEqual(d.micros["sat_fat_g"], 0.1)
        // %DV only: 4 % of 1300 mg and 15 % of 18 mg, flagged as converted.
        XCTAssertEqual(d.micros["calcium_mg"], 52)
        XCTAssertEqual(d.micros["iron_mg"], 2.7)
        XCTAssertEqual(d.micros["vitamin_a_ug"], 0)
        XCTAssertEqual(d.micros["vitamin_c_mg"], 0)
        XCTAssertTrue(d.uncertain.isSuperset(of: ["calcium_mg", "iron_mg"]))
        XCTAssertFalse(d.uncertain.contains("kcal"))
        // 7*4 + 27*4 + 0.5*9 = 140.5 (126.5 with fiber at 2): the label is off.
        XCTAssertNotNil(d.labelArithmeticWarning)
    }

    func testMessyOCR() {
        let text = """
        NUTRITI0N FACTS VALEUR NUTRITIVE
        Per l bar (45g) / pour 1 barre (45g)
        Calories 2O0
        Fat/Lipides 8g 11%
        Saturated/saturés 3.5 g 18 %
        +Trans/trans Og
        Carbohydrate/Glucides 24g 8%
        Fibre/Fibres 1O g 36 %
        Sugars/Sucres <1 g 1 %
        Protein/Protéines 129
        Cholesterol/Cholestérol Omg
        Sodium190mg 8%
        Potassium 2l0 mg 4 %
        Calcium 8 %
        Iron/Fer 2,5 mg 14 %
        """
        let d = NutritionLabelParser.parse(text)
        XCTAssertEqual(d.servingLabel, "bar")
        XCTAssertEqual(d.servingGrams, 45)
        XCTAssertEqual(d.kcal, 200)
        XCTAssertEqual(d.fat, 8)
        XCTAssertEqual(d.carbs, 24)
        XCTAssertEqual(d.fiber, 10)
        // "12g" read as "129": impossible in a 45 g bar, so the 9 is dropped and flagged.
        XCTAssertEqual(d.protein, 12)
        XCTAssertTrue(d.uncertain.contains("protein"))
        XCTAssertEqual(d.micros["sat_fat_g"], 3.5)
        XCTAssertEqual(d.micros["trans_fat_g"], 0)
        XCTAssertEqual(d.micros["sugar_g"], 0.5)
        XCTAssertTrue(d.uncertain.contains("sugar_g"))
        XCTAssertEqual(d.micros["cholesterol_mg"], 0)
        XCTAssertEqual(d.micros["sodium_mg"], 190)
        XCTAssertEqual(d.micros["potassium_mg"], 210)
        XCTAssertEqual(d.micros["calcium_mg"], 104)
        XCTAssertEqual(d.micros["iron_mg"], 2.5)
        XCTAssertNil(d.labelArithmeticWarning)
    }

    func testPer100gAndSideBySideColumns() {
        // A per-100 g panel where Vision split each row into label and value.
        let text = """
        Nutrition Facts
        Per 100 g / pour 100 g
        Calories 240
        Fat / Lipides 10 g 13 %
        Carbohydrate / Glucides 9 g
        Fibre / Fibres
        2 g
        Protein / Protéines 28 g
        Sodium 620 mg 27 %
        Vitamin B12 / Vitamine B12 2.4 µg 100 %
        """
        let d = NutritionLabelParser.parse(text)
        XCTAssertEqual(d.basis, .per100g)
        XCTAssertNil(d.servingLabel)
        XCTAssertEqual(d.kcal, 240)
        XCTAssertEqual(d.fiber, 2)
        XCTAssertEqual(d.protein, 28)
        XCTAssertEqual(d.micros["vitamin_b12_ug"], 2.4)
        XCTAssertNil(d.micros["thiamin_mg"])
        XCTAssertFalse(NutritionLabelParser.looksPoor(d))
        XCTAssertEqual(NutritionLabelParser.coverage(d), 1)
    }

    func testEmptyTextIsPoor() {
        let d = NutritionLabelParser.parse("Best before 2026 OC 12")
        XCTAssertTrue(NutritionLabelParser.looksPoor(d))
        XCTAssertEqual(NutritionLabelParser.coverage(d), 0)
    }

    func testServingUnits() {
        XCTAssertEqual(NutritionLabelParser.parseServing("2 tbsp (32 g)")?.label, "serving")
        XCTAssertEqual(NutritionLabelParser.parseServing("1 tbsp (15 ml) / 1 c. à soupe")?.label, "tbsp")
        XCTAssertEqual(NutritionLabelParser.parseServing("1 slice (35 g)")?.grams, 35)
        XCTAssertEqual(NutritionLabelParser.parseServing("1 sausage (100 g)")?.label, "sausage")
        XCTAssertEqual(NutritionLabelParser.parseServing("2/3 cup (55g)")?.grams, 55)
    }
}
