import Foundation

/// Turns spoken amounts into numerals before anything else reads the text, so
/// "a hundred and fifty grams" and "one and a half cups" survive the split on "and".
enum NumberWords {
    static let ones: [String: Double] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    static let tens: [String: Double] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    static let fractions: [String: Double] = [
        "half": 0.5, "halves": 0.5, "quarter": 0.25, "quarters": 0.25, "third": 1.0 / 3, "thirds": 1.0 / 3,
    ]

    /// Lowercased tokens with number phrases replaced by numerals ("1.5", "150").
    /// Punctuation that separates items (, . ; ! ?) comes back as its own token.
    static func tokens(_ text: String) -> [String] {
        var s = text.lowercased()
        for (glyph, ascii) in [("¼", " 1/4"), ("½", " 1/2"), ("¾", " 3/4"), ("⅓", " 1/3"), ("⅔", " 2/3"), ("⅛", " 1/8")] {
            s = s.replacingOccurrences(of: glyph, with: ascii)
        }
        s = s.replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "'", with: "")
        // 150g -> 150 g, x2 -> x 2. Decimal points and fractions stay inside numbers.
        s = s.replacingOccurrences(of: #"(\d)([a-z])"#, with: "$1 $2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([a-z])(\d)"#, with: "$1 $2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d),(\d{3})"#, with: "$1$2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([,;!?&+]|\.(?!\d))"#, with: " $1 ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[^a-z0-9.,;!?&+/ ]"#, with: " ", options: .regularExpression)
        let raw = s.split(separator: " ").map(String.init)
        return convert(raw)
    }

    static func value(of token: String) -> Double? {
        if let d = Double(token) { return d }
        let parts = token.split(separator: "/")
        if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 { return a / b }
        return nil
    }

    static func format(_ x: Double) -> String {
        if x == x.rounded() { return String(Int(x)) }
        return String((x * 10000).rounded() / 10000)
    }

    private static func convert(_ t: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < t.count {
            if let (v, next) = number(t, at: i) {
                out.append(format(v))
                i = next
            } else {
                out.append(t[i])
                i += 1
            }
        }
        return out
    }

    private static func isWordNumber(_ s: String) -> Bool { ones[s] != nil || tens[s] != nil }

    /// A number starting at `i`, and the index after it.
    private static func number(_ t: [String], at i: Int) -> (Double, Int)? {
        func tok(_ k: Int) -> String? { k < t.count ? t[k] : nil }
        var j = i
        var v: Double

        if tok(j) == "a" || tok(j) == "an" {
            guard let n = tok(j + 1) else { return nil }
            if n == "hundred" || n == "thousand" {
                j += 1
                guard let (whole, next) = integer(t, at: j) else { return nil }
                v = whole; j = next
            } else if let f = fractions[n], n != "halves", n != "quarters", n != "thirds" {
                v = f; j += 2
                return (v, skipOfArticle(t, j))
            } else if n == "couple" {
                v = 2; j += 2
                if tok(j) == "of" { j += 1 }
                return (v, j)
            } else {
                return nil
            }
        } else if tok(j) == "half" {
            v = 0.5; j += 1
            if tok(j) == "a" || tok(j) == "an" { j += 1 } else { j = skipOfArticle(t, j) }
            return (v, j)
        } else if tok(j) == "quarter" {
            v = 0.25; j += 1
            return (v, skipOfArticle(t, j))
        } else if let d = tok(j).flatMap(value(of:)) {
            v = d; j += 1
            // "1 1/2"
            if let f = tok(j), f.contains("/"), let fv = value(of: f), fv < 1 { v += fv; j += 1 }
        } else if let (whole, next) = integer(t, at: j) {
            v = whole; j = next
            // "one point five"
            if tok(j) == "point", let d = tok(j + 1).flatMap({ ones[$0] }), d < 10 {
                v += d / 10; j += 2
            }
        } else {
            return nil
        }

        // "three quarters", "two thirds"
        if let f = tok(j), let fv = fractions[f], f != "half" {
            v *= fv; j += 1
            return (v, skipOfArticle(t, j))
        }
        // "one and a half", "2 and 3/4", "two and three quarters"
        if tok(j) == "and" {
            if (tok(j + 1) == "a" || tok(j + 1) == "an"), let f = tok(j + 2), let fv = fractions[f] {
                return (v + fv, j + 3)
            }
            if let f = tok(j + 1), f.contains("/"), let fv = value(of: f), fv < 1 { return (v + fv, j + 2) }
            if let n = tok(j + 1).flatMap({ ones[$0] }), let f = tok(j + 2), f == "quarters" || f == "thirds" {
                return (v + n * fractions[f]!, j + 3)
            }
        }
        return (v, j)
    }

    /// "one hundred and fifty", "twenty five", "a thousand".
    private static func integer(_ t: [String], at i: Int) -> (Double, Int)? {
        var j = i
        var total = 0.0, current = 0.0
        var matched = false
        var lastWasScale = false
        while j < t.count {
            let w = t[j]
            if let v = ones[w] ?? tens[w] {
                current += v; matched = true; lastWasScale = false
            } else if w == "hundred" {
                current = max(current, 1) * 100; matched = true; lastWasScale = true
            } else if w == "thousand" {
                total += max(current, 1) * 1000; current = 0; matched = true; lastWasScale = true
            } else if w == "and", matched, lastWasScale, j + 1 < t.count, isWordNumber(t[j + 1]) {
                lastWasScale = false
            } else {
                break
            }
            j += 1
        }
        return matched ? (total + current, j) : nil
    }

    /// "a quarter of a cup": the "of a" belongs to the amount.
    private static func skipOfArticle(_ t: [String], _ j: Int) -> Int {
        if j + 1 < t.count, t[j] == "of", t[j + 1] == "a" || t[j + 1] == "an" || t[j + 1] == "the" { return j + 2 }
        return j
    }
}
