import CoreLocation

enum RouteOptimizer {
    /// Reorders only untimed runs between fixed appointments. For each next
    /// stop, use walking directions when available and fall back to distance.
    @MainActor static func optimizedOrder(for stops: [Stop]) async -> [Stop] {
        await optimizedOrder(for: stops) { from, to in
            await DirectionsService.walkingLeg(from: from.coordinate, to: to.coordinate)?.time
        }
    }

    @MainActor static func optimizedOrder(
        for stops: [Stop],
        travelTime: @MainActor (Stop, Stop) async -> TimeInterval?
    ) async -> [Stop] {
        var result: [Stop] = []
        var index = 0

        while index < stops.count {
            if stops[index].plannedTime != nil {
                result.append(stops[index])
                index += 1
                continue
            }

            let end = stops[index...].firstIndex { $0.plannedTime != nil } ?? stops.endIndex
            var remaining = Array(stops[index..<end].filter(\.hasCoordinate))
            let unlocated = stops[index..<end].filter { !$0.hasCoordinate }
            var current = result.last

            // Without a preceding stop, keep the first place as the day's start.
            if current == nil, !remaining.isEmpty {
                let first = remaining.removeFirst()
                current = first
                result.append(first)
            }

            while let from = current, !remaining.isEmpty {
                var nearestIndex = 0
                var shortest = TimeInterval.infinity
                for candidateIndex in remaining.indices {
                    let candidate = remaining[candidateIndex]
                    let time = await travelTime(from, candidate)
                        ?? walkingTime(from: from, to: candidate) ?? .infinity
                    if time < shortest {
                        shortest = time
                        nearestIndex = candidateIndex
                    }
                }
                let next = remaining.remove(at: nearestIndex)
                current = next
                result.append(next)
            }

            result.append(contentsOf: unlocated)
            index = end
        }

        return result
    }

    /// Approximate walking time between two stops, assuming ~1.4 m/s (5 km/h).
    static func walkingTime(from: Stop, to: Stop) -> TimeInterval? {
        guard from.hasCoordinate, to.hasCoordinate else { return nil }
        let distance = from.location.distance(from: to.location)
        return distance / 1.4
    }
}
