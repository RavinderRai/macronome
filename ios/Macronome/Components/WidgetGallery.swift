import SwiftUI
import WidgetKit

/// The widgets drawn with today's numbers, so you can see them before adding one.
struct WidgetGallery: View {
    @Environment(FoodStore.self) private var store

    var body: some View {
        let s = DaySnapshot(ledger: store.ledger, day: store.today)
        VStack(spacing: 0) {
            ScreenHeader("Widgets")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Cap("Medium")
                    face(CaloriesWidgetView(s: s, forcedFamily: .systemMedium), width: 338, height: 158, background: Theme.graphite)
                    Cap("Small")
                    HStack(spacing: 16) {
                        face(CaloriesWidgetView(s: s, forcedFamily: .systemSmall), width: 158, height: 158, background: Theme.surface)
                        face(ProteinWidgetView(s: s).padding(16), width: 158, height: 158, background: Theme.graphite)
                    }
                    Cap("Lock Screen")
                    HStack(spacing: 16) {
                        LockScreenView(s: s, forcedFamily: .accessoryCircular).frame(width: 72, height: 72)
                        LockScreenView(s: s, forcedFamily: .accessoryRectangular).frame(width: 170, height: 72, alignment: .leading)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 22).fill(Color(hex: 0x2B2D29)))
                    Text("Long-press the Home Screen, tap Edit, then Add Widget and search for Macronome. The mic and camera buttons open the app straight to listening or the label camera.")
                        .font(Typo.body).foregroundStyle(Theme.text2).lineSpacing(3)
                }
                .padding(20)
            }
        }
        .page()
    }

    private func face(_ v: some View, width: CGFloat, height: CGFloat, background: Color) -> some View {
        v.frame(width: width, height: height)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}
