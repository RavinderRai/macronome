import SwiftUI

struct Cap: View {
    var text: String
    var color: Color = Theme.text3
    init(_ text: String, color: Color = Theme.text3) { self.text = text; self.color = color }
    var body: some View { Text(text).capStyle(color) }
}

/// "BREAKFAST ····· 272" with a hairline under it.
struct SectionHeader: View {
    var title: String
    var trailing: String?
    var rule = true
    var body: some View {
        HStack {
            Cap(title)
            Spacer()
            if let trailing { Cap(trailing) }
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { if rule { Hairline() } }
    }
}

struct Hairline: View {
    var color: Color = Theme.hairline
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

/// Off-white filled pill, the one primary action on a screen ("Add to today").
struct PrimaryButtonStyle: ButtonStyle {
    var fill = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 22)
            .frame(minHeight: 48)
            .frame(maxWidth: fill ? .infinity : nil)
            .background(Capsule().fill(Theme.text))
            .foregroundStyle(Theme.graphite)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Outlined pill ("Change", "Ate it").
struct OutlineButtonStyle: ButtonStyle {
    var border: Color = Theme.text
    var height: CGFloat = 48
    var fill = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height < 48 ? 14 : 15, weight: .semibold))
            .padding(.horizontal, height < 48 ? 14 : 22)
            .frame(minHeight: height)
            .frame(maxWidth: fill ? .infinity : nil)
            .overlay(Capsule().stroke(border, lineWidth: 1))
            .foregroundStyle(Theme.text)
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Raised dark pill used on bars and chips.
struct ChipButtonStyle: ButtonStyle {
    var background: Color = Theme.bar
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Capsule().fill(background))
            .foregroundStyle(Theme.text)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var primaryCompact: PrimaryButtonStyle { PrimaryButtonStyle(fill: false) }
}

extension ButtonStyle where Self == OutlineButtonStyle {
    static var outline: OutlineButtonStyle { OutlineButtonStyle() }
}

extension ButtonStyle where Self == ChipButtonStyle {
    static var chip: ChipButtonStyle { ChipButtonStyle() }
}

/// "− ¾ cup +" amount stepper.
struct AmountStepper: View {
    @Binding var qty: Double
    var unit: String
    var step: Double = 0.25
    var minimum: Double = 0

    var body: some View {
        HStack(spacing: 0) {
            Button { qty = max(minimum, qty - step) } label: {
                Image(systemName: "minus").frame(width: 44, height: 44)
            }
            Text(Format.amount(qty: qty, unit: unit))
                .font(Typo.mono(15))
                .frame(minWidth: 84)
                .contentTransition(.numericText())
            Button { qty += step } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(Theme.text)
        .background(Capsule().fill(Theme.bar))
        .animation(.snappy, value: qty)
    }
}

/// Small round icon button (camera, close).
struct RoundIcon: View {
    var systemName: String
    var size: CGFloat = 48
    var background: Color = .clear
    var foreground: Color = Theme.text
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .regular))
            .frame(width: size, height: size)
            .background(Circle().fill(background))
            .foregroundStyle(foreground)
            .contentShape(Circle())
    }
}

/// Amber mic button, the only amber control.
struct MicButton: View {
    var size: CGFloat = 48
    var body: some View {
        Image(systemName: "mic")
            .font(.system(size: size * 0.44, weight: .semibold))
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.amber))
            .foregroundStyle(Theme.graphite)
            .contentShape(Circle())
    }
}

/// Screen scaffolding: graphite page, back chevron + title row.
struct ScreenHeader: View {
    var title: String
    var trailing: AnyView?
    @Environment(\.dismiss) private var dismiss

    init(_ title: String, trailing: AnyView? = nil) { self.title = title; self.trailing = trailing }

    var body: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44)
            }
            .foregroundStyle(Theme.text)
            .accessibilityLabel("Back")
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer()
            trailing
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
    }
}

extension View {
    /// Graphite page with the system navigation bar hidden; screens draw their own.
    func page() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.graphite.ignoresSafeArea())
            .foregroundStyle(Theme.text)
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// A labelled number field used on targets and food forms.
struct NumberField: View {
    var label: String
    @Binding var value: Double?
    var unit: String = ""
    var body: some View {
        HStack {
            Text(label).font(Typo.body).foregroundStyle(Theme.text2)
            Spacer()
            TextField("–", value: $value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Typo.mono(15))
                .frame(maxWidth: 110)
            if !unit.isEmpty { Text(unit).font(Typo.mono(13)).foregroundStyle(Theme.text3).frame(width: 36, alignment: .leading) }
        }
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { Hairline() }
    }
}
