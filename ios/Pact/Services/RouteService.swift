import Foundation
import MapKit

/// Builds a real, walkable route for a challenge's venue using MapKit's
/// actual directions API — `MKDirections` calculates a path along real
/// streets/paths between two real landmarks, instead of the one hardcoded,
/// made-up loop near La Jolla that every distance challenge used to get
/// pasted with regardless of where it was actually happening (a Coronado
/// challenge showed a "route" near La Jolla Shores).
///
/// The landmark pairs below are real, named places near each venue this
/// app already grounds its content in — MKDirections fills in the actual
/// walkable path between them, so the route is both geographically
/// plausible (real start/end points) and geometrically real (an actual
/// street-following polyline, not a hand-drawn shape).
@MainActor
final class RouteService {
    static let shared = RouteService()
    private var cache: [String: [CLLocationCoordinate2D]] = [:]

    private struct Landmarks {
        let match: (String) -> Bool
        let start: CLLocationCoordinate2D
        let end: CLLocationCoordinate2D
    }

    private static let venues: [Landmarks] = [
        Landmarks(match: { $0.contains("la jolla") },
                  start: .init(latitude: 32.8567, longitude: -117.2570), // La Jolla Shores Park
                  end: .init(latitude: 32.8669, longitude: -117.2571)),  // Scripps Pier
        Landmarks(match: { $0.contains("balboa") },
                  start: .init(latitude: 32.7314, longitude: -117.1467), // Balboa Park Visitors Center
                  end: .init(latitude: 32.7353, longitude: -117.1490)),  // San Diego Zoo entrance
        Landmarks(match: { $0.contains("coronado") },
                  start: .init(latitude: 32.6859, longitude: -117.1745), // Coronado Ferry Landing
                  end: .init(latitude: 32.6810, longitude: -117.1836)),  // Hotel del Coronado
        Landmarks(match: { $0.contains("gaslamp") || $0.contains("petco") },
                  start: .init(latitude: 32.7073, longitude: -117.1566), // Petco Park
                  end: .init(latitude: 32.7115, longitude: -117.1611)),  // 5th & Market, Gaslamp Quarter
        Landmarks(match: { $0.contains("mission bay") },
                  start: .init(latitude: 32.7757, longitude: -117.2264), // Mission Bay Park
                  end: .init(latitude: 32.7644, longitude: -117.2266)),  // SeaWorld San Diego
    ]

    private static let defaultLandmarks = (
        start: CLLocationCoordinate2D(latitude: 32.7157, longitude: -117.1611), // Santa Fe Depot
        end: CLLocationCoordinate2D(latitude: 32.7202, longitude: -117.1706)    // Waterfront Park
    )

    /// The real walking path for a venue, computed once via `MKDirections`
    /// and cached for the rest of this launch. Falls back to a straight
    /// line between the two real landmarks if the routing request fails
    /// (offline, rate-limited) — still two real, correctly-located places,
    /// just not snapped to actual streets.
    func route(for venue: String) async -> [CLLocationCoordinate2D] {
        if let cached = cache[venue] { return cached }
        let v = venue.lowercased()
        let pair = Self.venues.first { $0.match(v) }
        let start = pair?.start ?? Self.defaultLandmarks.start
        let end = pair?.end ?? Self.defaultLandmarks.end

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
        request.transportType = .walking

        let coordinates: [CLLocationCoordinate2D]
        if let response = try? await MKDirections(request: request).calculate(), let route = response.routes.first {
            coordinates = route.polyline.coordinates
        } else {
            coordinates = [start, end]
        }
        cache[venue] = coordinates
        return coordinates
    }
}

private extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
