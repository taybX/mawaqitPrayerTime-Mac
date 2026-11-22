import MawaqitKit
import SwiftUI

/// Settings, shown inside the panel so there is no separate window to lose.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    let done: () -> Void
    let findNearby: () -> Void
    @State private var address = ""

    private static let notificationSettings =
        URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            HStack {
                Button(action: done) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .overlay {
                Text("Settings").font(.headline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            Form {
                Section("Mosque") {
                    Button(action: findNearby) {
                        Label("Find mosques near me", systemImage: "location")
                    }
                    MosqueAddressField(address: $address, actionTitle: "Change", onSuccess: done)
                    if let error = model.errorMessage {
                        ErrorText(error)
                    }
                }

                Section("Menu bar") {
                    Picker("Show", selection: $model.menuBarStyle) {
                        ForEach(MenuBarStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    Toggle("24-hour clock", isOn: $model.use24HourClock)
                }

                Section("Notifications") {
                    Toggle("Notify at prayer times", isOn: $model.notificationsEnabled)
                    if model.notificationsEnabled {
                        ForEach(Prayer.obligatory) { prayer in
                            Toggle(prayer.name, isOn: notifies(prayer))
                        }
                        Picker("Remind me before", selection: $model.reminderMinutes) {
                            Text("Off").tag(0)
                            ForEach([5, 10, 15, 20, 30], id: \.self) { minutes in
                                Text("\(minutes) minutes").tag(minutes)
                            }
                        }
                        if model.notificationsBlocked {
                            VStack(alignment: .leading, spacing: 4) {
                                ErrorText("Notifications are turned off for this app.")
                                Link("Open Notification Settings", destination: Self.notificationSettings)
                                    .font(.caption)
                            }
                        }
                    }
                }

                Section {
                    Toggle("Open at login", isOn: $model.launchAtLogin)
                }
            }
            .formStyle(.grouped)
        }
        .frame(height: 520)
        .onAppear { address = model.mosqueAddress }
    }

    private func notifies(_ prayer: Prayer) -> Binding<Bool> {
        Binding(
            get: { model.notifiedPrayers.contains(prayer) },
            set: { isOn in
                if isOn {
                    model.notifiedPrayers.insert(prayer)
                } else {
                    model.notifiedPrayers.remove(prayer)
                }
            }
        )
    }
}
