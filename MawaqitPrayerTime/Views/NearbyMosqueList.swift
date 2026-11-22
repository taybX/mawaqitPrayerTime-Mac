import MawaqitKit
import SwiftUI

/// Results of "Find mosques near me": tap one that's on Mawaqit to use it.
struct NearbyMosqueList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    var maxHeight: CGFloat = 280
    var onChosen: () -> Void = {}

    private static let locationSettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!

    var body: some View {
        let search = model.nearby
        switch search.phase {
        case .idle:
            EmptyView()
        case .locating:
            progress("Finding your location…")
        case .searching:
            progress("Looking for mosques nearby…")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                ErrorText(message)
                if search.locationDenied {
                    Link("Open Location Services settings", destination: Self.locationSettings)
                        .font(.caption)
                }
            }
        case .done:
            if search.places.isEmpty {
                Text("No mosques found within \(Int(NearbyMosqueSearch.radius / 1000)) km.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(search.places) { place in
                            PlaceRow(place: place) { choose(place) }
                        }
                    }
                }
                .frame(maxHeight: maxHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func progress(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func choose(_ place: NearbyMosqueSearch.Place) {
        switch place.status {
        case .found(let match):
            model.useFoundMosque(match)
            onChosen()
        case .unchecked:
            Task {
                if let match = await model.nearby.check(place.id) {
                    model.useFoundMosque(match)
                    onChosen()
                }
            }
        case .notFound:
            openURL(NearbyMosqueSearch.webSearchURL(for: place.candidate))
        case .checking:
            break
        }
    }
}

private struct PlaceRow: View {
    let place: NearbyMosqueSearch.Place
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "building.columns")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.candidate.name)
                        .lineLimit(1)
                    status
                        .font(.caption)
                }
                Spacer(minLength: 6)
                Text(Self.format(place.distance))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering && isClickable ? Color.primary.opacity(0.07) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(helpText)
    }

    private var isClickable: Bool {
        if case .checking = place.status { return false }
        return true
    }

    @ViewBuilder private var status: some View {
        let city = place.candidate.city.map { "\($0) · " } ?? ""
        switch place.status {
        case .found:
            Text("\(city)\(Image(systemName: "checkmark.circle.fill")) On Mawaqit")
                .foregroundStyle(.tint)
        case .checking:
            Text("\(city)Checking Mawaqit…")
                .foregroundStyle(.secondary)
        case .unchecked:
            Text("\(city)Click to check Mawaqit")
                .foregroundStyle(.secondary)
        case .notFound:
            Text("\(city)Not matched · Search \(Image(systemName: "arrow.up.right"))")
                .foregroundStyle(.secondary)
        }
    }

    private var helpText: String {
        switch place.status {
        case .found: "Use this mosque"
        case .notFound: "Search mawaqit.net for this mosque in your browser, then paste its link"
        case .unchecked: "Look for this mosque on Mawaqit"
        case .checking: "Looking for this mosque on Mawaqit…"
        }
    }

    static func format(_ metres: Double) -> String {
        metres < 1_000
            ? "\(Int((metres / 10).rounded()) * 10) m"
            : String(format: "%.1f km", metres / 1_000)
    }
}

/// The nearby list as its own page, opened from Settings.
struct NearbyPage: View {
    @Environment(AppModel.self) private var model
    let back: () -> Void
    let chosen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: back) {
                    Label("Back", systemImage: "chevron.left")
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    model.nearby.start()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(model.nearby.isBusy)
                .help("Search again")
            }
            .buttonStyle(.borderless)
            .overlay { Text("Mosques near you").font(.headline) }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                NearbyMosqueList(maxHeight: 380, onChosen: chosen)
                Text("Nearby mosques come from Apple Maps. Not every mosque is on Mawaqit, and matching is done by name and website.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
        .onAppear {
            if model.nearby.phase == .idle {
                model.nearby.start()
            }
        }
    }
}
