import CoreLocation
import MapKit

struct WalkingLeg: Sendable {
    let time: TimeInterval
    let distance: CLLocationDistance
}

enum DirectionsService {
    /// Real walking route between two coordinates via MKDirections.
    /// Returns nil if no route could be calculated (e.g. offline, or the
    /// points aren't walkable), so callers can fall back to an estimate.
    static func walkingLeg(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async -> WalkingLeg? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return nil }
            return WalkingLeg(time: route.expectedTravelTime, distance: route.distance)
        } catch {
            return nil
        }
    }
}
