import CoreLocation
import MapKit

struct WalkingLeg: Sendable {
    let time: TimeInterval
    let distance: CLLocationDistance
    let path: [RouteCoordinate]
}

struct RouteCoordinate: Sendable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct StopLegID: Hashable, Sendable {
    let from: UUID
    let to: UUID

    init(from: Stop, to: Stop) {
        self.from = from.id
        self.to = to.id
    }
}

private struct WalkingRouteKey: Hashable, Sendable {
    let fromLatitude: UInt64
    let fromLongitude: UInt64
    let toLatitude: UInt64
    let toLongitude: UInt64

    init(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) {
        fromLatitude = from.latitude.bitPattern
        fromLongitude = from.longitude.bitPattern
        toLatitude = to.latitude.bitPattern
        toLongitude = to.longitude.bitPattern
    }
}

private actor WalkingRouteCache {
    private var legs: [WalkingRouteKey: WalkingLeg] = [:]

    func leg(for key: WalkingRouteKey) -> WalkingLeg? { legs[key] }
    func store(_ leg: WalkingLeg, for key: WalkingRouteKey) { legs[key] = leg }
}

enum DirectionsService {
    private static let cache = WalkingRouteCache()

    /// Real walking route between two coordinates via MKDirections.
    /// Returns nil if no route could be calculated (e.g. offline, or the
    /// points aren't walkable), so callers can fall back to an estimate.
    static func walkingLeg(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async -> WalkingLeg? {
        let key = WalkingRouteKey(from: from, to: to)
        if let cached = await cache.leg(for: key) { return cached }

        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return nil }
            let points = route.polyline.points()
            let path = (0..<route.polyline.pointCount).map { index in
                let coordinate = points[index].coordinate
                return RouteCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
            let leg = WalkingLeg(time: route.expectedTravelTime, distance: route.distance, path: path)
            await cache.store(leg, for: key)
            return leg
        } catch {
            return nil
        }
    }
}
