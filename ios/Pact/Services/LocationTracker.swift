import Foundation
import CoreLocation

/// What a finished tracking session actually measured — the real trail
/// walked or run, not a suggested route to a venue (that's
/// `RouteService`/`Challenge.routeCoordinates`'s job for the map preview).
struct TrackedSession {
    let coordinates: [CLLocationCoordinate2D]
    let distanceMiles: Double
    let duration: TimeInterval
    let classification: ActivityClassification
}

/// A walk vs. a run, decided from how fast the phone was actually moving —
/// not from which button someone tapped. `unknown` covers a session too
/// short or too GPS-poor to have a confident average speed.
enum ActivityClassification: String {
    case walking = "Walking"
    case running = "Running"
    case unknown = "Tracking"

    var icon: String {
        switch self {
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .unknown: "location.fill"
        }
    }

    /// Meters/second a sustained pace has to clear to count as a run —
    /// roughly a 13:30/mile jog. Below this, even a brisk walk still reads
    /// as walking.
    static let runningThreshold = 2.2
}

/// Records a real GPS trail while a challenge is being worked, live —
/// distance, duration, and a walking/running call, all derived from actual
/// `CLLocation` samples rather than typed in. Only usable on a real device
/// in motion: the Simulator can feed it a canned or manually-dragged
/// location, but nothing here fakes movement on its own.
@MainActor
@Observable
final class LocationTracker: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var isTracking = false
    private(set) var coordinates: [CLLocationCoordinate2D] = []
    private(set) var distanceMiles: Double = 0
    private(set) var classification: ActivityClassification = .unknown

    private var lastLocation: CLLocation?
    private var recentSpeeds: [Double] = []
    private(set) var startDate: Date?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Redraws the trail every ~10 meters instead of on every tiny GPS
        // jitter — smoother polyline, far fewer wasted updates.
        manager.distanceFilter = 10
    }

    func requestPermission() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    var canTrack: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    func start() {
        guard canTrack, !isTracking else { return }
        coordinates = []
        distanceMiles = 0
        classification = .unknown
        lastLocation = nil
        recentSpeeds = []
        startDate = Date()
        isTracking = true
        manager.startUpdatingLocation()
    }

    @discardableResult
    func stop() -> TrackedSession {
        manager.stopUpdatingLocation()
        isTracking = false
        let duration = startDate.map { Date().timeIntervalSince($0) } ?? 0
        return TrackedSession(coordinates: coordinates, distanceMiles: distanceMiles, duration: duration, classification: classification)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorizationStatus = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                // Accuracy worse than 30m (a bad urban-canyon or indoor fix)
                // would put a visible kink in the polyline and a bogus
                // instant-speed spike — skip it rather than plot it.
                guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 30 else { continue }
                if let last = lastLocation {
                    distanceMiles += location.distance(from: last) / 1609.344
                }
                if location.speed >= 0 {
                    recentSpeeds.append(location.speed)
                    if recentSpeeds.count > 8 { recentSpeeds.removeFirst() }
                    let avg = recentSpeeds.reduce(0, +) / Double(recentSpeeds.count)
                    // Needs a few real samples before it'll call it either
                    // way — one fast GPS blip right after start shouldn't
                    // flip the badge to "Running".
                    if recentSpeeds.count >= 3 {
                        classification = avg >= ActivityClassification.runningThreshold ? .running : .walking
                    }
                }
                coordinates.append(location.coordinate)
                lastLocation = location
            }
        }
    }
}
