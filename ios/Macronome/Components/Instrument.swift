import SwiftUI

/// The top of Today: date and bank caps, the big calories-left numeral, the day strip.
struct CaloriesHeader: View {
    var day: String
    var dayNumber: Int?
    var bank: Double?
    var left: Double
    var eaten: Double
    var target: Double
    /// "23 after the plan" in amber, shown when something is planned.
    var afterPlan: Double?
    var segments: [DayStrip.Segment]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Cap(dayNumber.map { "\(Format.dayHeader(day)) · Day \($0)" } ?? Format.dayHeader(day))
                Spacer()
                if let bank { Cap("Bank \(Format.trim(bank))") }
            }
            HStack(alignment: .bottom) {
                Text(Format.int(abs(left)))
                    .numeralStyle(100)
                    .foregroundStyle(left < 0 ? Theme.coral : Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: left))
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(left < 0 ? "kcal over" : "kcal left").font(.system(size: 16, weight: .medium))
                    if let afterPlan {
                        Text(afterPlan >= 0 ? "\(Format.int(afterPlan)) after the plan" : "\(Format.int(-afterPlan)) over with the plan")
                            .font(Typo.mono(13)).foregroundStyle(afterPlan >= 0 ? Theme.amber : Theme.coral)
                    } else {
                        Text("\(Format.int(eaten)) of \(Format.int(target))").font(Typo.mono(13)).foregroundStyle(Theme.text3)
                    }
                }
                .padding(.bottom, 4)
            }
            .accessibilityElement(children: .combine)
            DayStrip(segments: segments, target: target)
        }
        .animation(.snappy, value: left)
    }
}

/// Ruler-style strip: solid is eaten, hatched is planned, coral is past the target. A
/// tick every 100 kcal and a scale underneath.
struct DayStrip: View {
    struct Segment: Identifiable, Hashable {
        var id: String
        var kcal: Double
        var planned = false
    }

    var segments: [Segment]
    var target: Double
    var showScale = true

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let total = max(target, segments.reduce(0) { $0 + $1.kcal })
                let gaps = CGFloat(max(0, segments.count)) * 2
                let usable = max(0, geo.size.width - gaps)
                HStack(spacing: 2) {
                    ForEach(laidOut(total: total)) { s in
                        bar(s).frame(width: max(2, usable * s.kcal / max(total, 1)))
                    }
                    Rectangle().fill(Theme.track)
                }
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .frame(height: 12)
            if showScale {
                Canvas { ctx, size in
                    let step = size.width * 100 / max(target, 1)
                    guard step > 2 else { return }
                    var x: CGFloat = 0
                    while x <= size.width + 0.5 {
                        ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Theme.tick))
                        x += step
                    }
                }
                .frame(height: 5)
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        Text("0")
                        ForEach([500.0, 1000, 1500, 2000, 2500].filter { $0 < target * 0.92 }, id: \.self) { mark in
                            Text(Format.int(mark)).offset(x: w * mark / target - 10)
                        }
                        Text(Format.int(target)).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(Typo.mono(11)).foregroundStyle(Theme.text3)
                }
                .frame(height: 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    /// Splits whatever crosses the target into a coral overflow segment.
    private func laidOut(total: Double) -> [Segment] {
        var out: [Segment] = []
        var running = 0.0
        for s in segments {
            if !s.planned, running + s.kcal > target {
                let under = max(0, target - running)
                if under > 0 { out.append(Segment(id: s.id, kcal: under)) }
                out.append(Segment(id: s.id + "-over", kcal: s.kcal - under, planned: false))
            } else {
                out.append(s)
            }
            running += s.kcal
        }
        return out
    }

    @ViewBuilder private func bar(_ s: Segment) -> some View {
        if s.id.hasSuffix("-over") {
            Rectangle().fill(Theme.coral)
        } else if s.planned {
            Hatch(color: Theme.text)
        } else {
            Rectangle().fill(Theme.text)
        }
    }

    private var accessibility: String {
        let eaten = segments.filter { !$0.planned }.reduce(0) { $0 + $1.kcal }
        let planned = segments.filter(\.planned).reduce(0) { $0 + $1.kcal }
        return "\(Format.int(eaten)) eaten" + (planned > 0 ? ", \(Format.int(planned)) planned" : "") + ", of \(Format.int(target))"
    }
}

/// Three macro columns: protein, net carbs, fat.
struct MacroColumns: View {
    var rows: [MacroStatus]
    /// Planned grams per macro, hatched after the solid bar.
    var planned: Macros?
    var showNumbers = true

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(rows.filter { [.protein, .carbs, .fat].contains($0.key) }, id: \.key) { r in
                column(r).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func plannedGrams(_ key: MacroStatus.Key) -> Double? {
        guard let p = planned else { return nil }
        switch key {
        case .protein: return p.protein
        case .carbs: return p.netCarbs
        case .fat: return p.fat
        default: return nil
        }
    }

    private func column(_ r: MacroStatus) -> some View {
        let over = (r.left ?? 0) < 0
        let pg = plannedGrams(r.key)
        return VStack(alignment: .leading, spacing: 7) {
            Cap(r.label)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(Format.int(abs(r.left ?? r.eaten)))
                    .font(.system(size: 26, weight: .medium)).tracking(-0.8).monospacedDigit()
                    .foregroundStyle(over ? Theme.coral : Theme.text)
                    .contentTransition(.numericText())
                Text(r.target == nil ? " g" : over ? " g over" : " g left")
                    .font(.system(size: 14)).foregroundStyle(Theme.text2)
            }
            GeometryReader { geo in
                let t = max(r.target ?? 1, 1)
                let solid = min(1, r.eaten / t)
                let hatched = pg.map { min(1 - solid, $0 / t) } ?? 0
                HStack(spacing: 0) {
                    Rectangle().fill(over ? Theme.coral : Theme.color(for: r.key)).frame(width: geo.size.width * solid)
                    if hatched > 0 {
                        Hatch(color: Theme.color(for: r.key), spacing: 4, outlined: false).frame(width: geo.size.width * hatched)
                    }
                    Spacer(minLength: 0)
                }
                .background(Theme.track)
                .clipShape(Capsule())
            }
            .frame(height: 4)
            if showNumbers {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Format.int(r.eaten)) / \(Format.int(r.target))")
                    if let pg, let t = r.target { Text("plan \(Format.int(r.eaten + pg))").opacity(t > 0 ? 1 : 0) }
                }
                .font(Typo.mono(12)).foregroundStyle(Theme.text3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One logged row: name, components, kcal and protein.
struct EntryRow: View {
    var group: LogGroup
    var justLogged = false

    var body: some View {
        HStack(spacing: 12) {
            if justLogged {
                Circle().fill(Theme.amber).frame(width: 6, height: 6).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(group.label).font(Typo.row).foregroundStyle(Theme.text).lineLimit(1)
                if justLogged {
                    Cap("Just now", color: Theme.amber)
                } else if !group.subtitle.isEmpty {
                    Text(group.subtitle).font(.system(size: 13)).foregroundStyle(Theme.text3).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.int(group.macros.kcal)).font(Typo.mono(15))
                if !justLogged {
                    Text("\(Format.int(group.macros.protein)) g P").font(Typo.mono(12)).foregroundStyle(Theme.text3)
                }
            }
        }
        .frame(minHeight: justLogged ? 60 : 64)
        .padding(.horizontal, justLogged ? 12 : 0)
        .background {
            if justLogged { RoundedRectangle(cornerRadius: 12).fill(Theme.deepAmber) }
        }
        .padding(.horizontal, justLogged ? -12 : 0)
        .overlay(alignment: .bottom) { if !justLogged { Hairline() } }
        .contentShape(Rectangle())
    }
}

/// A dashed planned row with its "Ate it" action.
struct PlannedRow: View {
    var plan: PlannedItem
    var ateIt: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.label).font(Typo.row).foregroundStyle(Theme.planned)
                Cap([plan.meal?.title, plan.detail].compactMap { $0 }.joined(separator: " · "))
            }
            Spacer(minLength: 8)
            Text(Format.int(plan.macros.kcal)).font(Typo.mono(15)).foregroundStyle(Theme.planned)
            Button("Ate it", action: ateIt).buttonStyle(OutlineButtonStyle(height: 44))
        }
        .padding(.leading, 14).padding(.trailing, 6)
        .frame(minHeight: 60)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.tick, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

/// Day strip segments for a day: one per logged group, then planned items hatched.
extension Ledger {
    func stripSegments(on day: String, includePlans: Bool = true) -> [DayStrip.Segment] {
        var out = groups(on: day).map { DayStrip.Segment(id: $0.id, kcal: $0.macros.kcal) }
        if includePlans {
            out += plans(on: day).map { DayStrip.Segment(id: $0.id, kcal: $0.macros.kcal, planned: true) }
        }
        return out
    }
}
