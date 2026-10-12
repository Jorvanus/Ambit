import Foundation

struct TimingConflict {
    let lateBy: TimeInterval
}

enum DaySchedule {
    /// Follows the displayed stop order from the first fixed time onward.
    /// Untimed stops consume their duration, and each leg adds its walking time.
    static func conflicts(
        for stops: [Stop],
        on date: Date,
        walkingLegs: [StopLegID: WalkingLeg],
        calendar: Calendar = .current
    ) -> [UUID: TimingConflict] {
        var conflicts: [UUID: TimingConflict] = [:]
        var previousEnd: Date?

        for (index, stop) in stops.enumerated() {
            let arrival: Date?
            if let previousEnd, index > 0 {
                let previous = stops[index - 1]
                let leg = walkingLegs[StopLegID(from: previous, to: stop)]
                let travelTime = leg?.time ?? RouteOptimizer.walkingTime(from: previous, to: stop) ?? 0
                arrival = previousEnd.addingTimeInterval(travelTime)
            } else {
                arrival = nil
            }

            let fixedStart: Date? = stop.plannedTime.flatMap { plannedTime -> Date? in
                let components = calendar.dateComponents([.hour, .minute], from: plannedTime)
                guard let hour = components.hour, let minute = components.minute else { return nil }
                return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
            }

            if let fixedStart, let arrival, arrival > fixedStart {
                conflicts[stop.id] = TimingConflict(lateBy: arrival.timeIntervalSince(fixedStart))
            }

            if let start = [fixedStart, arrival].compactMap({ $0 }).max() {
                previousEnd = start.addingTimeInterval(stop.durationEstimate)
            } else {
                previousEnd = nil
            }
        }

        return conflicts
    }
}
