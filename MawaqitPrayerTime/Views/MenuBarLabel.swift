import SwiftUI

/// What sits in the menu bar: a crescent, plus the next prayer unless set to icon only.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let title = model.menuBarTitle
        HStack(spacing: 4) {
            Image(systemName: "moon.stars.fill")
            if !title.isEmpty {
                Text(title)
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(title.isEmpty ? "Mawaqit Prayer Time" : "Next prayer: \(title)")
    }
}
