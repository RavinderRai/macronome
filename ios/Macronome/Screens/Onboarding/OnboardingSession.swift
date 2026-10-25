import SwiftUI

/// State carried across the onboarding screens. Nothing is written to the log until
/// onboarding finishes: RootView leaves onboarding as soon as the store has events, so
/// writing the targets at step 1 would cut the flow short.
@MainActor
enum OnboardingSession {
    /// Targets and profile events from step 1, written on finish.
    static var pending: [Event] = []
    /// Labels read in the pantry scan, kept while hopping between scan and review.
    static var drafts: [FoodDraft] = []

    /// Write everything staged plus `extra`, mark onboarding done and land on Today.
    static func finish(store: FoodStore, router: Router, extra: [Event] = []) {
        let events = pending + extra
        pending = []
        drafts = []
        UserDefaults.standard.set(true, forKey: "onboarded")
        router.cover = nil
        router.popToRoot()
        router.tab = .today
        store.append(events)
    }
}

/// Off-white track with a dark knob, as in Targets.dc.html.
struct PillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                configuration.label
                Spacer(minLength: 8)
                Capsule()
                    .fill(configuration.isOn ? Theme.text : Theme.track)
                    .frame(width: 52, height: 32)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(configuration.isOn ? Theme.graphite : Theme.text3).frame(width: 26, height: 26).padding(3)
                    }
                    .animation(.snappy, value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// Round outlined − and + used on the targets rows.
struct RoundStepButton: View {
    var systemName: String
    var label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(CaptureColors.stepperBorder, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A choice chip: filled off-white when selected, outlined otherwise.
struct ChoiceChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: selected ? .semibold : .medium))
                .padding(.horizontal, 18).frame(height: 44)
                .background(Capsule().fill(selected ? Theme.text : .clear))
                .overlay(Capsule().stroke(selected ? .clear : CaptureColors.stepperBorder, lineWidth: 1))
                .foregroundStyle(selected ? Theme.graphite : Theme.text)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
