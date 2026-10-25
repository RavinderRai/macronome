import SwiftUI

struct Placeholder: View {
    var name: String
    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(name)
            Spacer()
            Cap(name)
            Spacer()
        }
        .page()
    }
}
