import Foundation
import CoreLocation
import CoreMotion

/// What a finished tracking session actually measured — the real trail
/// walked or run, not a suggested route to a venue (that's
/// `RouteService`/`Challenge.routeCoordinates`'s job for the map preview).
struct TrackedSession {
    let coordinates: [CLLocationCoordinate2D]
    let distanceMiles: Double
    let steps: Int
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

/// Records a real trail while a challenge is being worked, live — distance,
/// steps, duration, and a walking/running call. One shared instance (not
/// per-screen) so closing `LiveTrackingView` doesn't kill an in-progress
/// recording — only an explicit "Finish" does.
///
/// Distance/route come from `CLLocationManager`; step count comes
/// separately from `CMPedometer`, because GPS alone is a poor way to
/// measure short, low-displacement movement — pacing around a small area
/// or a handful of steps barely moves the GPS fix at all, while the
/// pedometer's motion-coprocessor reading still counts every one of them.
/// Only usable on a real device in motion: the Simulator can feed
/// `CLLocationManager` a canned or manually-dragged location, and
/// `CMPedometer` has no hardware step data to report at all.
@MainActor
@Observable
final class LocationTracker: NSObject, CLLocationManagerDelegate {
    static let shared = LocationTracker()

    private let manager = CLLocationManager()
    private let pedometer = CMPedometer()

    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var isTracking = false
    private(set) var coordinates: [CLLocationCoordinate2D] = []
    private(set) var distanceMiles: Double = 0
    private(set) var steps: Int = 0
    private(set) var classification: ActivityClassification = .unknown
    /// Which challenge this session belongs to — set by whichever
    /// `LiveTrackingView` started it, read by a later one reattaching to
    /// an already-running session after the screen was closed and reopened.
    private(set) var challengeID: UUID?

    private var lastLocation: CLLocation?
    private var recentSpeeds: [Double] = []
    private(set) var startDate: Date?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // 3m instead of a coarser filter — short walks or someone mostly
        // pacing in place need every small real displacement plotted, not
        // just the big ones a wider filter would keep.
        manager.distanceFilter = 3
    }

    func requestPermission() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    var canTrack: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    func start(for challengeID: UUID) {
        guard canTrack, !isTracking else { return }
        self.challengeID = challengeID
        coordinates = []
        distanceMiles = 0
        steps = 0
        classification = .unknown
        lastLocation = nil
        recentSpeeds = []
        startDate = Date()
        isTracking = true
        manager.startUpdatingLocation()
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let data else { return }
                let count = data.numberOfSteps.intValue
                Task { @MainActor in self?.steps = count }
            }
        }
    }

    @discardableResult
    func stop() -> TrackedSession {
        manager.stopUpdatingLocation()
        pedometer.stopUpdates()
        isTracking = false
        let duration = startDate.map { Date().timeIntervalSince($0) } ?? 0
        let session = TrackedSession(coordinates: coordinates, distanceMiles: distanceMiles, steps: steps, duration: duration, classification: classification)
        challengeID = nil
        return session
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
