import Foundation

enum Format {
    /// 1700 -> "1,700". Rounds to whole numbers like fl.py's `fmt`.
    static func int(_ x: Double?) -> String {
        guard let x else { return "–" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: x.rounded())) ?? "\(Int(x.rounded()))"
    }

    /// 13.5 -> "13.5", 15.0 -> "15".
    static func trim(_ x: Double, digits: Int = 1) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = digits
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: x)) ?? String(x)
    }

    static func qty(_ q: Double) -> String {
        switch q {
        case 0.25: "¼"
        case 0.5: "½"
        case 0.75: "¾"
        case 1.5: "1½"
        default: trim(q, digits: 2)
        }
    }

    /// "350 g", "2 serv", "1 scoop", "½ can".
    static func amount(qty q: Double, unit: String) -> String {
        let u = unit.lowercased()
        if Ledger.gramUnits.contains(u) { return "\(trim(q, digits: 1)) \(u.hasPrefix("m") ? "ml" : "g")" }
        if u == "serving" || u == "servings" { return "\(qty(q)) serv" }
        return "\(qty(q)) \(u)"
    }

    /// "Farm Girl cinnamon crisps" -> "Cinnamon crisps". Drops a leading brand when the
    /// name has a lowercase tail, which is how labels get entered.
    static func shortName(_ name: String) -> String {
        let words = name.split(separator: " ").map(String.init)
        guard words.count > 2, let i = words.firstIndex(where: { $0.first?.isLowercase == true }), i > 0 else {
            return name
        }
        let tail = words[i...].joined(separator: " ")
        return tail.prefix(1).uppercased() + tail.dropFirst()
    }

    /// "Sat 24 Oct".
    static func dayHeader(_ day: String) -> String {
        guard let d = Clock.date(fromDay: day) else { return day }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }

    static func weekday(_ day: String) -> String {
        guard let d = Clock.date(fromDay: day) else { return day }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: d)
    }

    static func time(_ iso: String?) -> String {
        guard let d = Clock.parseISO(iso) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }

    /// "Just now", "12 min ago", "2:14 PM".
    static func relative(_ iso: String?, now: Date = Date()) -> String {
        guard let d = Clock.parseISO(iso) else { return "" }
        let s = now.timeIntervalSince(d)
        if s < 90 { return "Just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        return time(iso)
    }
}
