import CoreLocation

enum RouteOptimizer {
    /// Orders stops to approximately minimize total straight-line travel distance
    /// using a nearest-neighbor heuristic, starting from the first stop.
    /// Stops without a resolved coordinate are left in place at the end, in their
    /// original relative order, since distance to them is unknown.
    static func optimizedOrder(for stops: [Stop]) -> [Stop] {
        let locatable = stops.filter { $0.hasCoordinate }
        let unlocatable = stops.filter { !$0.hasCoordinate }
        guard locatable.count > 1 else { return stops }

        var remaining = locatable
        var route = [remaining.removeFirst()]

        while !remaining.isEmpty {
            let current = route[route.count - 1].location
            let nearestIndex = remaining.indices.min { a, b in
                current.distance(from: remaining[a].location) < current.distance(from: remaining[b].location)
            }!
            route.append(remaining.remove(at: nearestIndex))
        }

        return route + unlocatable
    }

    /// Approximate walking time between two stops, assuming ~1.4 m/s (5 km/h).
    static func walkingTime(from: Stop, to: Stop) -> TimeInterval? {
        guard from.hasCoordinate, to.hasCoordinate else { return nil }
        let distance = from.location.distance(from: to.location)
        return distance / 1.4
    }
}
