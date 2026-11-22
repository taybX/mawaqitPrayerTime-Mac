import CoreLocation

enum LocationError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied: "Location access is off for Mawaqit Prayer Time."
        case .unavailable: "Your Mac couldn't work out where it is. Check that Wi-Fi is on and try again."
        }
    }
}

/// Gets the Mac's location once, asking for permission the first time.
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocationCoordinate2D, Error>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentCoordinate() async throws -> CLLocationCoordinate2D {
        try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
            proceed()
        }
    }

    private func proceed() {
        guard !waiting.isEmpty else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()  // the answer arrives in locationManagerDidChangeAuthorization
        case .denied, .restricted:
            finish(.failure(LocationError.denied))
        default:
            manager.requestLocation()
        }
    }

    private func finish(_ result: Result<CLLocationCoordinate2D, Error>) {
        let pending = waiting
        waiting = []
        for continuation in pending {
            continuation.resume(with: result)
        }
    }

    // CLLocationManager calls its delegate on the thread that created it: the main thread.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { proceed() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        MainActor.assumeIsolated { finish(.success(coordinate)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        MainActor.assumeIsolated { finish(.failure(denied ? LocationError.denied : LocationError.unavailable)) }
    }
}
