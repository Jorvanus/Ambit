import CoreLocation

enum StopGeocoder {
    static func geocode(name: String, near destination: String) async -> CLLocationCoordinate2D? {
        let query = destination.isEmpty ? name : "\(name), \(destination)"
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.geocodeAddressString(query)
            return placemarks.first?.location?.coordinate
        } catch {
            return nil
        }
    }
}
