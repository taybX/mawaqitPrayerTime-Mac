import CoreLocation
import Foundation
import MapKit
import MawaqitKit
import Observation

/// "Find mosques near me": Apple Maps for the list, then a check of which ones have a Mawaqit page.
@Observable
final class NearbyMosqueSearch {
    enum Phase: Equatable {
        case idle, locating, searching, done
        case failed(String)
    }

    enum Status {
        case unchecked, checking, notFound
        case found(MawaqitPageFinder.Match)
    }

    struct Place: Identifiable {
        let id = UUID()
        let candidate: MosqueCandidate
        /// Metres from the user.
        let distance: Double
        var status: Status
    }

    private(set) var phase: Phase = .idle
    private(set) var places: [Place] = []
    private(set) var locationDenied = false

    @ObservationIgnored private lazy var locator = LocationProvider()
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    private let finder = MawaqitPageFinder()

    /// Search radius around the user.
    static let radius: CLLocationDistance = 15_000
    /// How many of the nearest results get checked against Mawaqit straight away.
    static let checkedUpFront = 10
    /// Checks run a few at a time to go easy on mawaqit.net and the mosques' websites.
    static let checksAtOnce = 3

    var isBusy: Bool { phase == .locating || phase == .searching }

    func start() {
        searchTask?.cancel()
        searchTask = Task {
            locationDenied = false
            places = []
            phase = .locating
            do {
                let here = try await locator.currentCoordinate()
                await search(around: here)
            } catch LocationError.denied {
                locationDenied = true
                phase = .failed(LocationError.denied.localizedDescription)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Lists mosques around a point and checks the nearest ones against Mawaqit.
    func search(around coordinate: CLLocationCoordinate2D) async {
        phase = .searching
        do {
            places = try await Self.mapSearch(around: coordinate)
                .map { Place(candidate: $0.candidate, distance: $0.distance, status: .unchecked) }
            phase = .done
        } catch {
            phase = .failed("Apple Maps search failed: \(error.localizedDescription)")
            return
        }

        let ids = places.prefix(Self.checkedUpFront).map(\.id)
        for start in stride(from: 0, to: ids.count, by: Self.checksAtOnce) {
            guard !Task.isCancelled else { return }
            let batch = ids[start..<min(start + Self.checksAtOnce, ids.count)]
            await withTaskGroup(of: Void.self) { group in
                for id in batch {
                    group.addTask { _ = await self.check(id) }
                }
            }
        }
    }

    /// Finds the Mawaqit page for one place, reusing an earlier result.
    func check(_ id: Place.ID) async -> MawaqitPageFinder.Match? {
        guard let index = places.firstIndex(where: { $0.id == id }) else { return nil }
        switch places[index].status {
        case .found(let match): return match
        case .notFound, .checking: return nil
        case .unchecked: break
        }
        places[index].status = .checking
        let match = await finder.findPage(for: places[index].candidate)
        // A new search may have replaced the list while this one was running.
        if let index = places.firstIndex(where: { $0.id == id }) {
            places[index].status = match.map(Status.found) ?? .notFound
        }
        return match
    }

    /// A web search limited to mawaqit.net, for mosques the app couldn't match itself.
    static func webSearchURL(for candidate: MosqueCandidate) -> URL {
        var components = URLComponents(string: "https://www.google.com/search")!
        let query = ["site:mawaqit.net", candidate.name, candidate.city ?? ""].joined(separator: " ")
        components.queryItems = [URLQueryItem(name: "q", value: query.trimmingCharacters(in: .whitespaces))]
        return components.url!
    }

    // MARK: - Apple Maps

    private static let queries = ["mosque", "masjid"]

    private static func mapSearch(around center: CLLocationCoordinate2D) async throws -> [(candidate: MosqueCandidate, distance: Double)] {
        var results: [(candidate: MosqueCandidate, distance: Double)] = []
        var seen: Set<String> = []
        var lastError: Error?

        for query in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
            request.resultTypes = .pointOfInterest

            let items: [MKMapItem]
            do {
                items = try await MKLocalSearch(request: request).start().mapItems
            } catch {
                lastError = error  // "no results" for one query is fine if another finds some
                continue
            }

            for item in items {
                guard let candidate = candidate(from: item) else { continue }
                let distance = MawaqitPageFinder.distance(
                    center.latitude, center.longitude, candidate.latitude, candidate.longitude
                )
                let key = "\(candidate.name.lowercased())|\(Int(candidate.latitude * 1000))|\(Int(candidate.longitude * 1000))"
                guard distance <= radius, seen.insert(key).inserted else { continue }
                results.append((candidate, distance))
            }
        }

        if results.isEmpty, let lastError, (lastError as? MKError)?.code != .placemarkNotFound {
            throw lastError
        }
        return results.sorted { $0.distance < $1.distance }
    }

    private static func candidate(from item: MKMapItem) -> MosqueCandidate? {
        guard let name = item.name, !name.isEmpty else { return nil }
        let coordinate: CLLocationCoordinate2D
        let city: String?
        if #available(macOS 26, *) {
            coordinate = item.location.coordinate
            city = item.addressRepresentations?.cityName
        } else {
            coordinate = item.placemark.coordinate
            city = item.placemark.locality
        }
        return MosqueCandidate(
            name: name, city: city,
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            website: item.url
        )
    }
}
