import SwiftUI

/// The window that drops down from the menu bar icon.
struct PanelView: View {
    @Environment(AppModel.self) private var model
    @State private var page: Page = .timetable

    private enum Page {
        case timetable, settings, nearby
    }

    var body: some View {
        Group {
            if model.schedule == nil {
                SetupView()
            } else {
                switch page {
                case .timetable:
                    TimetableView { page = .settings }
                case .settings:
                    SettingsView(done: { page = .timetable }, findNearby: { page = .nearby })
                case .nearby:
                    NearbyPage(back: { page = .settings }, chosen: { page = .timetable })
                }
            }
        }
        .frame(width: 340)
    }
}

/// A short warning line used under fields and in the footer.
struct ErrorText: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
