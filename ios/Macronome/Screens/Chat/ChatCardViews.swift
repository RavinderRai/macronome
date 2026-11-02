import SwiftUI

/// The cards an agent reply leaves in the chat (ChatLogAndAsk, ChatWhatIf and
/// ChatTargets on the design canvas). Every number on them was computed by the tools.
struct ChatCardView: View {
    var card: ChatCard
    var undone: Bool
    var onUndo: () -> Void
    /// Tapping an option row starts a reply about it.
    var onPick: (String) -> Void

    var body: some View {
        switch card {
        case .logged(let c): LogCardView(card: c, undone: undone, onUndo: onUndo)
        case .options(let c): OptionsCardView(card: c, onPick: onPick)
        case .targets(let c): TargetsCardView(card: c, undone: undone, onUndo: onUndo)
        case .remembered(let c): RememberedCardView(card: c, undone: undone, onUndo: onUndo)
        }
    }
}

private struct LogCardView: View {
    var card: LogCard
    var undone: Bool
    var onUndo: () -> Void

    var body: some View {
        if undone {
            UndoneRow(text: "Removed from the log")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Cap(heading, color: Theme.amber)
                    Spacer()
                    Button("Undo", action: onUndo)
                        .font(Typo.cap).foregroundStyle(Theme.amberText)
                        .frame(minHeight: 32)
                }
                ForEach(Array(card.groups.enumerated()), id: \.offset) { _, g in
                    VStack(alignment: .leading, spacing: 4) {
                        if showsDays || card.groups.count > 1 {
                            Cap([g.title, g.slot].compactMap { $0 }.joined(separator: " · "), color: Theme.muted)
                        }
                        if g.rows.count > 1 || g.name != g.rows.first?.label {
                            HStack {
                                Text(g.name).font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text(Format.int(g.kcal)).font(Typo.mono(14))
                            }
                        }
                        ForEach(Array(g.rows.enumerated()), id: \.offset) { _, r in
                            HStack(spacing: 8) {
                                Text(r.amount.map { "\(r.label) · \($0)" } ?? r.label)
                                    .foregroundStyle(Theme.amberText).lineLimit(1)
                                Spacer(minLength: 4)
                                if r.estimate {
                                    Text("ESTIMATE").font(Typo.cap).foregroundStyle(Theme.amber)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0x6A4C1E)))
                                }
                                Text(Format.int(r.kcal))
                            }
                            .font(Typo.mono(13))
                        }
                    }
                }
                if let a = card.assumption, !a.isEmpty {
                    Text(a).font(.system(size: 13)).foregroundStyle(Theme.amberText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                StatusBlock(status: card.status)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.deepAmber))
            .accessibilityElement(children: .contain)
        }
    }

    private var showsDays: Bool { card.groups.contains { $0.title != "Today" } }

    private var heading: String {
        if card.edited == true { return "Updated" }
        let entries = card.groups.count
        if entries == 1, let slot = card.groups.first?.slot { return "Logged · \(slot)" }
        return entries == 1 ? "Logged" : "Logged \(entries)"
    }
}

/// "Left 238 · 16 P · 27 C · 31 F" and the budget with the evening bowl held back.
private struct StatusBlock: View {
    var status: StatusLine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(Theme.amberDivider).frame(height: 1)
            HStack {
                Text("Left").foregroundStyle(Theme.muted)
                Spacer()
                leftLine
            }
            if let hb = status.holdBack, let k = status.afterHoldBackKcal {
                HStack {
                    Text("\(hb) held back").foregroundStyle(Theme.muted)
                    Spacer()
                    heldBackLine(k)
                }
            }
        }
        .font(Typo.mono(13))
    }

    private var leftLine: Text {
        var t = Text(status.kcal.map(signed) ?? "–").foregroundStyle((status.kcal ?? 0) < 0 ? Theme.coral : Theme.text)
        if let p = status.protein { t = t + Text(" · ") + Text("\(Format.int(p)) P").foregroundStyle(Theme.amber) }
        if let c = status.carbs { t = t + Text(" · \(Format.int(c)) \(status.carbsLabel)") }
        if let f = status.fat { t = t + Text(" · \(Format.int(f)) F") }
        return t
    }

    private func heldBackLine(_ k: Double) -> Text {
        var t = Text(signed(k)).foregroundStyle(k < 0 ? Theme.coral : Theme.text)
        if let p = status.afterHoldBackProtein { t = t + Text(" · ") + Text("\(Format.int(p)) P").foregroundStyle(Theme.amber) }
        return t
    }

    private func signed(_ k: Double) -> String { k < 0 ? "\(Format.int(-k)) over" : Format.int(k) }
}

private struct OptionsCardView: View {
    var card: OptionsCard
    var onPick: (String) -> Void

    private let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.fixed(44), alignment: .trailing),
                           GridItem(.fixed(30), alignment: .trailing), GridItem(.fixed(84), alignment: .trailing)]

    var body: some View {
        VStack(spacing: 0) {
            row(Cap(card.title), Cap("kcal"), Cap("P"), Cap("Left"))
                .padding(.top, 10).padding(.bottom, 6)
            ForEach(Array(card.rows.enumerated()), id: \.offset) { _, r in
                Button { onPick(r.label) } label: {
                    row(Text(r.label).font(.system(size: 14, weight: .medium)).multilineTextAlignment(.leading),
                        Text(Format.int(r.kcal)).font(Typo.mono(13)),
                        Text(Format.int(r.protein)).font(Typo.mono(13)).foregroundStyle(r.hitsProtein ? Theme.amber : Theme.text3),
                        spare(r.spare))
                        .frame(minHeight: 48)
                        .foregroundStyle((r.spare ?? 0) < 0 ? Theme.text3 : Theme.text)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Rectangle().fill(Theme.bar).frame(height: 1) }
                .accessibilityLabel("\(r.label), \(Format.int(r.kcal)) kcal, \(Format.int(r.protein)) grams protein")
            }
            if let hb = card.holdBack, let k = card.holdBackKcal {
                row(HStack(spacing: 8) {
                        Hatch(color: Theme.tick).frame(width: 14, height: 10)
                        Text("\(hb), held back").font(.system(size: 13))
                    },
                    Text(Format.int(k)).font(Typo.mono(13)),
                    Text(Format.int(card.holdBackProtein)).font(Typo.mono(13)),
                    Text(""))
                    .foregroundStyle(Theme.text3)
                    .frame(minHeight: 40)
                    .overlay(alignment: .top) { Rectangle().fill(Theme.bar).frame(height: 1) }
            }
        }
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.graphite))
    }

    private func row(_ a: some View, _ b: some View, _ c: some View, _ d: some View) -> some View {
        LazyVGrid(columns: columns, spacing: 0) { a; b; c; d }
    }

    private func spare(_ s: Double?) -> some View {
        Group {
            if let s {
                Text(s >= 0 ? "\(Format.int(s)) spare" : "\(Format.int(-s)) over")
                    .foregroundStyle(s >= 0 ? Theme.amberText : Theme.coral)
                    .lineLimit(1).minimumScaleFactor(0.8)
            } else {
                Text("")
            }
        }
        .font(Typo.mono(13))
    }
}

private struct TargetsCardView: View {
    var card: TargetsCard
    var undone: Bool
    var onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Cap(undone ? "Targets unchanged" : "Targets from today", color: Theme.amber)
                Spacer()
                if !undone {
                    Button("Undo", action: onUndo).font(Typo.cap).foregroundStyle(Theme.amberText).frame(minHeight: 32)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Cap("Was", color: Theme.muted).gridColumnAlignment(.trailing)
                    Text("")
                    Cap("Now", color: Theme.muted).gridColumnAlignment(.trailing)
                }
                ForEach(Array(card.rows.enumerated()), id: \.offset) { _, r in
                    GridRow {
                        Text(r.label).font(.system(size: 14)).foregroundStyle(Theme.amberText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(value(r.was, r.unit)).foregroundStyle(Theme.muted)
                        Text("→").foregroundStyle(Color(hex: 0x6A4C1E)).accessibilityHidden(true)
                        Text(value(undone ? r.was : r.now, r.unit))
                            .foregroundStyle(r.label == "Protein" ? Theme.amber : Theme.text)
                    }
                    .font(Typo.mono(14))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.deepAmber))
    }

    private func value(_ v: Double?, _ unit: String) -> String { v.map { Format.int($0) + unit } ?? "–" }
}

private struct RememberedCardView: View {
    var card: RememberedCard
    var undone: Bool
    var onUndo: () -> Void

    var body: some View {
        if undone {
            UndoneRow(text: "Not remembered")
        } else {
            HStack(spacing: 12) {
                Image(systemName: "bookmark").foregroundStyle(Theme.amber).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Cap("Remembered · \(card.kind.capitalized)")
                    Text(card.text).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button("Undo", action: onUndo).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.amberText)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0x3A3B37)))
        }
    }
}

private struct UndoneRow: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 14)).foregroundStyle(Theme.text3)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0x3A3B37), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}
