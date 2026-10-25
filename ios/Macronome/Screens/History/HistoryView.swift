import SwiftUI

/// Week (or month) of kcal against target, averages, and the calorie bank.
struct HistoryView: View {
    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @State private var range: HistWindow.Range = .week
    @State private var offset = 0

    var body: some View {
        let ledger = store.ledger
        let today = store.today
        let window = HistWindow.window(range, today: today, offset: offset)
        let stats = ledger.histStats(window.days, today: today)
        let canGoBack = ledger.firstDay.map { window.days.first! > $0 } ?? false

        VStack(spacing: 0) {
            TopNav()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        rangePicker
                        Spacer()
                        HStack(spacing: 0) {
                            Button { offset += 1 } label: { Image(systemName: "chevron.left").frame(width: 32, height: 44) }
                                .disabled(!canGoBack)
                                .accessibilityLabel("Earlier")
                            Cap(window.title)
                            Button { offset = max(0, offset - 1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 44) }
                                .disabled(offset == 0)
                                .accessibilityLabel("Later")
                        }
                        .foregroundStyle(Theme.text2)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Cap(ledger.standingTargets.kcal.map { "Over or under \(Format.int($0))" } ?? "Over or under target")
                            Spacer()
                            Cap("kcal")
                        }
                        HistDiffChart(days: window.days, today: today, ledger: ledger, compact: range == .month) { day in
                            router.push(.day(day))
                        }
                        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in
                            guard abs(v.translation.width) > abs(v.translation.height) * 2 else { return }
                            if v.translation.width > 60, canGoBack { offset += 1 }
                            if v.translation.width < -60, offset > 0 { offset -= 1 }
                        })
                    }

                    averages(stats, ledger: ledger)
                    bank(window, ledger: ledger, today: today)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .animation(.snappy, value: offset)
            }
        }
        .page()
        .onChange(of: range) { offset = 0 }
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(HistWindow.Range.allCases) { r in
                Button(r.title) { range = r }
                    .font(.system(size: 14, weight: range == r ? .semibold : .medium))
                    .foregroundStyle(range == r ? Theme.text : Theme.text2)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Capsule().fill(range == r ? Theme.libBorder : .clear))
                    .accessibilityAddTraits(range == r ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.bar))
    }

    private func averages(_ s: HistStats, ledger: Ledger) -> some View {
        let t = ledger.standingTargets
        let n = s.fullDays.count
        return VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                stat("Avg kcal", value: s.avgKcal.map { Format.int($0) } ?? "–",
                     note: n == 0 ? "no full days" : n == 1 ? "1 full day" : "\(n) full days")
                Rectangle().fill(Theme.hairline).frame(width: 1)
                stat("Avg protein", value: s.avgProtein.map { "\(Format.int($0)) g" } ?? "–",
                     note: t.protein.map { "target \(Format.int($0))" } ?? "", capColor: Theme.amber).padding(.leading, 16)
            }
            .fixedSize(horizontal: false, vertical: true)
            Hairline()
            HStack(spacing: 0) {
                stat("Avg fat", value: s.avgFat.map { "\(Format.int($0)) g" } ?? "–",
                     note: t.fat.map { "target \(Format.int($0))" } ?? "")
                Rectangle().fill(Theme.hairline).frame(width: 1)
                stat("Days logged", value: "\(ledger.loggedDays.count)",
                     note: ledger.firstDay.map { "since \(HistWindow.shortDay($0))" } ?? "").padding(.leading, 16)
            }
            .fixedSize(horizontal: false, vertical: true)
            Hairline()
        }
    }

    private func stat(_ title: String, value: String, note: String, capColor: Color = Theme.text3) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Cap(title, color: capColor)
            Text(value).font(.system(size: 26, weight: .medium)).tracking(-0.8).monospacedDigit()
            Text(note).font(Typo.mono(12)).foregroundStyle(Theme.text3)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func bank(_ window: HistWindow, ledger: Ledger, today: String) -> some View {
        let moves = ledger.histBankMoves(window.days, today: today)
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Cap("Bank")
                Spacer()
                Text(ledger.bank.map { "\(Format.trim($0)) kcal" } ?? "Not set").font(Typo.mono(15))
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { Hairline() }
            ForEach(moves, id: \.day) { move in
                Button { router.push(.day(move.day)) } label: {
                    HStack {
                        Text("\(Format.dayHeader(move.day)) · \(move.change >= 0 ? "saved" : "spent")").foregroundStyle(Theme.text2)
                        Spacer()
                        Text(Self.signed(move.change))
                    }
                    .font(Typo.mono(13))
                    .frame(minHeight: 44)
                    .overlay(alignment: .bottom) { Hairline() }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if moves.isEmpty {
                Text("No finished days logged in this range.")
                    .font(.system(size: 13)).foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
            }
        }
    }

    /// "+39", "−40.5".
    static func signed(_ x: Double) -> String {
        let r = (x * 10).rounded() / 10
        if r == 0 { return "0" }
        return (r > 0 ? "+" : "−") + Format.trim(abs(r))
    }
}

/// Bars above the line are kcal past the target (coral), outlined bars below are kcal
/// under it. Today is drawn open.
struct HistDiffChart: View {
    var days: [String]
    var today: String
    var ledger: Ledger
    var compact = false
    var onTap: (String) -> Void

    private let height: CGFloat = 170
    private let mid: CGFloat = 84
    private let reach: CGFloat = 66

    var body: some View {
        let diffs = Dictionary(uniqueKeysWithValues: days.map { ($0, ledger.histDiff(on: $0)) })
        let maxAbs = max(60, diffs.values.compactMap { $0.map(abs) }.max() ?? 0)
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                Rectangle().fill(Theme.text).frame(height: 1).offset(y: mid)
                HStack(spacing: compact ? 2 : 10) {
                    ForEach(days, id: \.self) { day in
                        column(day, diff: diffs[day] ?? nil, maxAbs: maxAbs)
                    }
                }
            }
            .frame(height: height)
            HStack(spacing: compact ? 2 : 10) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    Text(label(day, index: i))
                        .font(Typo.cap).tracking(0.9).textCase(.uppercase)
                        .foregroundStyle(day == today ? Theme.text : Theme.text3)
                        .lineLimit(1).fixedSize()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func label(_ day: String, index: Int) -> String {
        if !compact { return day == today ? "Today" : Format.weekday(day) }
        let n = Int(day.suffix(2)) ?? 0
        return [1, 8, 15, 22, 29].contains(n) ? "\(n)" : ""
    }

    @ViewBuilder private func column(_ day: String, diff: Double?, maxAbs: Double) -> some View {
        let inset: CGFloat = compact ? 0 : 6
        Button { onTap(day) } label: {
            ZStack(alignment: .top) {
                Color.clear
                if day == today {
                    RoundedRectangle(cornerRadius: 2).stroke(Theme.tick, lineWidth: 1)
                        .frame(height: 3).padding(.horizontal, inset).offset(y: mid - 1)
                    if !compact { number("open").offset(y: mid + 10) }
                } else if let diff {
                    let h = max(3, CGFloat(abs(diff) / maxAbs) * reach)
                    if diff > 0 {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.coral)
                            .frame(height: h).padding(.horizontal, inset).offset(y: mid - h)
                        if !compact { number("+\(Format.int(diff))").offset(y: mid - h - 18) }
                    } else {
                        RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.text, lineWidth: 1.5)
                            .frame(height: h).padding(.horizontal, inset).offset(y: mid + 1)
                        if !compact { number(diff == 0 ? "0" : "−\(Format.int(-diff))").offset(y: mid + h + 4) }
                    }
                } else if day < today, !compact {
                    number("–").offset(y: mid + 6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day > today)
        .accessibilityLabel(accessibility(day, diff: diff))
    }

    private func number(_ s: String) -> some View {
        Text(s).font(Typo.mono(11)).foregroundStyle(Theme.text2).lineLimit(1).fixedSize()
            .frame(maxWidth: .infinity)
    }

    private func accessibility(_ day: String, diff: Double?) -> String {
        let name = day == today ? "Today" : Format.dayHeader(day)
        if day == today { return "\(name), still logging" }
        guard let diff else { return "\(name), nothing logged" }
        return "\(name), \(Format.int(abs(diff))) \(diff > 0 ? "over" : "under")"
    }
}
