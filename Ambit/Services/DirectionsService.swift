import CoreLocation
import MapKit

enum DirectionsService {
    /// Real walking travel time between two coordinates via MKDirections.
    /// Returns nil if no route could be calculated (e.g. offline, or the
    /// points aren't walkable), so callers can fall back to an estimate.
    static func walkingTravelTime(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            return response.routes.first?.expectedTravelTime
        } catch {
            return nil
        }
    }
}
