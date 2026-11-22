import AppKit
import MawaqitKit
import SwiftUI

/// First-run screen: asks for the mosque's Mawaqit page.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @State private var address = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose your mosque")
                        .font(.headline)
                    Text("Prayer times come straight from its Mawaqit page.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    model.nearby.start()
                } label: {
                    Label("Find mosques near me", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.nearby.isBusy)

                NearbyMosqueList()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Or paste a Mawaqit link")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                MosqueAddressField(address: $address, actionTitle: "Load")
                Text("Open your mosque on mawaqit.net and copy the address from the browser, for example mawaqit.net/en/your-mosque.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error = model.errorMessage {
                    ErrorText(error)
                }
            }

            Divider()

            HStack {
                Link("Find a mosque on mawaqit.net", destination: MawaqitClient.website)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .padding(16)
    }
}

/// A text field for a Mawaqit link with a button that loads it.
struct MosqueAddressField: View {
    @Environment(AppModel.self) private var model
    @Binding var address: String
    let actionTitle: String
    var onSuccess: () -> Void = {}

    private var trimmed: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HStack(spacing: 8) {
            // Verbatim prompt: a URL in a plain string literal would be auto-linked.
            TextField("Mosque page link", text: $address, prompt: Text(verbatim: "https://mawaqit.net/en/your-mosque"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .onSubmit(load)
                .disabled(model.isLoading)
            Button(action: load) {
                ZStack {
                    Text(actionTitle).opacity(model.isLoading ? 0 : 1)
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(trimmed.isEmpty || model.isLoading)
        }
    }

    private func load() {
        guard !trimmed.isEmpty else { return }
        Task {
            if await model.selectMosque(address: trimmed) {
                onSuccess()
            }
        }
    }
}
