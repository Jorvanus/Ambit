import CoreLocation
import MapKit

enum StopGeocoder {
    /// Resolves a place name to a coordinate, preferring matches near the trip's
    /// destination. Address-style geocoding ("name, city") can pick a same-named
    /// place in a distant suburb, so this searches for points of interest within
    /// a region around the destination and takes the closest result.
    static func geocode(name: String, near destination: String) async -> CLLocationCoordinate2D? {
        if let center = await destinationCenter(destination),
           let hit = await search(name, around: center) {
            return hit
        }
        return await addressGeocode(destination.isEmpty ? name : "\(name), \(destination)")
    }

    private static let searchRadius: CLLocationDistance = 30_000

    private static func destinationCenter(_ destination: String) async -> CLLocationCoordinate2D? {
        guard !destination.isEmpty else { return nil }
        return await addressGeocode(destination)
    }

    private static func search(_ name: String, around center: CLLocationCoordinate2D) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: searchRadius * 2,
            longitudinalMeters: searchRadius * 2
        )
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        return response.mapItems
            .map(\.location)
            .filter { $0.distance(from: origin) <= searchRadius }
            .min { $0.distance(from: origin) < $1.distance(from: origin) }?
            .coordinate
    }

    private static func addressGeocode(_ query: String) async -> CLLocationCoordinate2D? {
        guard let request = MKGeocodingRequest(addressString: query),
              let items = try? await request.mapItems else { return nil }
        return items.first?.location.coordinate
    }
}
