import Foundation

/// Token similarity for misheard dictation. Generic on purpose: edit distance plus a
/// sound-alike key, so "serial" finds "cereal" and "Gusto" finds "Gusta" without a list
/// of known mishearings.
enum Fuzzy {
    /// Words that never identify a food on their own.
    static let stopwords: Set<String> = [
        "a", "an", "the", "of", "my", "some", "and", "with", "on", "in", "to", "for", "bit", "little", "like", "um", "uh",
    ]

    static func tokens(_ s: String) -> [String] {
        s.lowercased()
            .replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "'", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    static func content(_ tokens: [String]) -> [String] {
        tokens.filter { !stopwords.contains($0) && NumberWords.value(of: $0) == nil }
    }

    /// "patties" -> "patty", "potatoes" -> "potato", "meatballs" -> "meatball".
    static func singular(_ w: String) -> String {
        if w.count > 4, w.hasSuffix("ies") { return String(w.dropLast(3)) + "y" }
        if w.count > 4, w.hasSuffix("oes") || w.hasSuffix("ches") || w.hasSuffix("shes") { return String(w.dropLast(2)) }
        if w.count > 3, w.hasSuffix("s"), !w.hasSuffix("ss") { return String(w.dropLast()) }
        return w
    }

    /// 0...1. 1 is the same word, ~0.8 a plausible mishearing.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        if singular(a) == singular(b) { return 0.95 }
        let x = Array(a), y = Array(b)
        let longest = max(x.count, y.count)
        guard longest > 0 else { return 0 }
        var score = 1 - Double(levenshtein(x, y)) / Double(longest)
        let shortest = min(x.count, y.count)
        if shortest >= 4, a.hasPrefix(b) || b.hasPrefix(a) { score = max(score, 0.8) }
        let ka = phoneticKey(a), kb = phoneticKey(b)
        if shortest >= 3, abs(x.count - y.count) <= 2, score >= 0.5, !ka.isEmpty {
            if ka == kb { score = max(score, 0.8) }
            // A swallowed last consonant: "bold" for "bowl".
            else if min(ka.count, kb.count) >= 2, abs(ka.count - kb.count) == 1, ka.hasPrefix(kb) || kb.hasPrefix(ka) {
                score = max(score, 0.75)
            }
        }
        return score
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    /// Soundex-style consonant classes over the whole word, first letter included, so
    /// "serial"/"cereal" and "ball"/"bowl" share a key.
    static func phoneticKey(_ w: String) -> String {
        var out = ""
        var last: Character?
        for ch in w.lowercased() {
            let code: Character?
            switch ch {
            case "b", "f", "p", "v": code = "1"
            case "c", "g", "j", "k", "q", "s", "x", "z": code = "2"
            case "d", "t": code = "3"
            case "l": code = "4"
            case "m", "n": code = "5"
            case "r": code = "6"
            default: code = nil
            }
            guard let code else { continue }
            if code != last { out.append(code) }
            last = code
        }
        return out
    }

    struct Match {
        var score: Double
        /// Every segment token was accounted for by the candidate or its synonyms.
        var coverage: Double
        var isExact: Bool { score >= 0.999 && coverage >= 0.999 }
    }

    /// How well a candidate name explains the spoken words. The best window of the
    /// segment is compared token by token, in any order; words that belong to the
    /// candidate's other names ("of serial" after "full bowl") count as covered.
    static func match(segment: [String], name: [String], vocabulary: Set<String>) -> Match? {
        let seg = content(segment)
        let cand = content(name)
        guard !seg.isEmpty, !cand.isEmpty else { return nil }
        var best: (avg: Double, used: Set<Int>)?
        if cand.count <= seg.count {
            for start in 0...(seg.count - cand.count) {
                let window = Array(start..<(start + cand.count))
                var used = Set<Int>()
                var total = 0.0
                var ok = true
                for c in cand {
                    var top = (idx: -1, sim: 0.0)
                    for k in window where !used.contains(k) {
                        let s = similarity(seg[k], c)
                        if s > top.sim { top = (k, s) }
                    }
                    if top.idx < 0 || top.sim < 0.6 { ok = false; break }
                    used.insert(top.idx)
                    total += top.sim
                }
                guard ok else { continue }
                let avg = total / Double(cand.count)
                if best == nil || avg > best!.avg { best = (avg, used) }
            }
        } else {
            // The candidate is longer than what was said: only a partial explanation.
            var used = Set<Int>()
            var total = 0.0
            for c in cand {
                if let (k, s) = seg.indices.filter({ !used.contains($0) }).map({ ($0, similarity(seg[$0], c)) }).max(by: { $0.1 < $1.1 }), s >= 0.8 {
                    used.insert(k); total += s
                }
            }
            guard used.count == seg.count else { return nil }
            best = (total / Double(cand.count), used)
        }
        guard let best else { return nil }
        var covered = best.used
        for (k, w) in seg.enumerated() where !covered.contains(k) {
            if vocabulary.contains(where: { similarity($0, w) >= 0.8 }) { covered.insert(k) }
        }
        let coverage = Double(covered.count) / Double(seg.count)
        return Match(score: best.avg * (0.75 + 0.25 * coverage), coverage: coverage)
    }
}
