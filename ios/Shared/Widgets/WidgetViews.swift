import AppIntents
import SwiftUI
import WidgetKit

// Widget faces, shared so the app can preview them in Settings.

struct CaloriesWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    var s: DaySnapshot
    /// Set when drawn outside WidgetKit, e.g. the in-app preview.
    var forcedFamily: WidgetFamily?
    private var family: WidgetFamily { forcedFamily ?? environmentFamily }

    var body: some View {
        Group {
            if family == .systemMedium { medium } else { small }
        }
        .containerBackground(family == .systemMedium ? Theme.graphite : Theme.surface, for: .widget)
        .widgetURL(URL(string: "macronome://today"))
    }

    private var leftLabel: String { s.kcalLeft < 0 ? "kcal over" : "kcal left" }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Format.int(abs(s.kcalLeft)))
                    .font(.system(size: 52, weight: .medium)).tracking(-2.9).monospacedDigit()
                    .foregroundStyle(s.kcalLeft < 0 ? Theme.coral : Theme.text)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(leftLabel).font(Typo.mono(12)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            HStack {
                WidgetCameraButton(size: 44, background: Theme.raised)
                Spacer()
                WidgetMicButton(size: 52)
            }
        }
        .padding(16)
    }

    private var medium: some View {
        HStack(spacing: 18) {
            ZStack {
                MacroRing(split: s.split, target: s.kcalTarget, lineWidth: 14)
                VStack(spacing: 3) {
                    Text(Format.int(abs(s.kcalLeft)))
                        .font(.system(size: 30, weight: .medium)).tracking(-1.5).monospacedDigit()
                        .foregroundStyle(s.kcalLeft < 0 ? Theme.coral : Theme.text)
                    Text(leftLabel).font(Typo.mono(11)).foregroundStyle(Theme.text3)
                }
            }
            .frame(width: 128, height: 128)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Format.int(s.kcalLeft)) of \(Format.int(s.kcalTarget)) kcal left")
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    legend("Protein", s.split.protein, Theme.amber, label: Theme.amber)
                    legend("Carbs", s.split.carbs, Theme.text, label: Theme.text2)
                    legend("Fat", s.split.fat, Theme.fat, label: Theme.text2)
                }
                .padding(.top, 4)
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    Spacer()
                    WidgetCameraButton(size: 44, background: Theme.bar)
                    WidgetMicButton(size: 52)
                }
            }
        }
        .padding(16)
    }

    private func legend(_ name: String, _ kcal: Double, _ color: Color, label: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).foregroundStyle(label)
            Spacer(minLength: 4)
            Text("\(Format.int(kcal)) kcal").foregroundStyle(Theme.text)
        }
        .font(Typo.mono(12))
    }
}

/// One donut segmented by the calories each macro contributed; the rest of the
/// target is the empty track. Past the target the whole ring turns coral.
struct MacroRing: View {
    var split: (protein: Double, carbs: Double, fat: Double)
    var target: Double
    var lineWidth: CGFloat

    var body: some View {
        let total = max(target, split.protein + split.carbs + split.fat, 1)
        let over = split.protein + split.carbs + split.fat > target && target > 0
        let parts: [(Double, Color)] = [(split.protein, Theme.amber), (split.carbs, Theme.text), (split.fat, Theme.fat)]
        let gap = 0.008
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                let start = parts[..<i].reduce(0) { $0 + $1.0 } / total
                let end = start + part.0 / total
                if part.0 > 0 {
                    Circle()
                        .trim(from: start, to: max(start, end - gap))
                        .stroke(over ? Theme.coral : part.1, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
        }
        .padding(lineWidth / 2)
    }
}

struct WidgetMicButton: View {
    var size: CGFloat
    var body: some View {
        Button(intent: OpenListeningIntent()) {
            Image(systemName: "mic").font(.system(size: size * 0.42, weight: .semibold))
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.amber))
                .foregroundStyle(Theme.graphite)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Talk to log")
    }
}

struct WidgetCameraButton: View {
    var size: CGFloat
    var background: Color
    var body: some View {
        Button(intent: OpenCameraIntent()) {
            Image(systemName: "camera").font(.system(size: size * 0.42))
                .frame(width: size, height: size)
                .background(Circle().fill(background))
                .foregroundStyle(Theme.text)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photograph a label")
    }
}

struct ProteinWidgetView: View {
    var s: DaySnapshot
    var body: some View {
        let p = s.protein
        let left = p.left ?? 0
        VStack(alignment: .leading) {
            Text("PROTEIN").capStyle(Theme.amber)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(Format.int(max(0, left))).font(.system(size: 44, weight: .medium)).tracking(-2.2).monospacedDigit()
                    Text(" g").font(.system(size: 16))
                }
                Text(left > 0 ? "to go · \(Format.int(p.eaten))/\(Format.int(p.target))" : "met · \(Format.int(p.eaten)) g")
                    .font(Typo.mono(12)).foregroundStyle(Theme.text2)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule().fill(Theme.amber).frame(width: g.size.width * min(1, p.fraction))
                    }
                }
                .frame(height: 4)
            }
        }
        .foregroundStyle(Theme.text)
    }
}

struct LockScreenView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    var s: DaySnapshot
    var forcedFamily: WidgetFamily?
    private var family: WidgetFamily { forcedFamily ?? environmentFamily }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(max(s.kcalEaten, 0), max(s.kcalTarget, 1)), in: 0...max(s.kcalTarget, 1)) {
                Text("kcal")
            } currentValueLabel: {
                Text(Format.int(s.kcalLeft)).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryInline:
            Text("\(Format.int(s.kcalLeft)) kcal left · \(Format.int(s.protein.left)) g P")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Format.int(s.kcalLeft)) kcal left").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Text("P \(Format.int(s.protein.left)) · C \(Format.int(s.carbs.left)) · F \(Format.int(s.fat.left))")
                    .font(Typo.mono(12))
                ProgressView(value: min(1, s.kcalTarget > 0 ? s.kcalEaten / s.kcalTarget : 0))
            }
        }
    }
}
