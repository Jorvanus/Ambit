import Foundation
import Testing
@testable import Ambit

@Suite @MainActor
struct ItineraryLogicTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
    }

    private func time(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func stop(_ name: String, at plannedTime: Date? = nil, durationMinutes: Double = 30) -> Stop {
        Stop(
            name: name,
            category: .sight,
            latitude: 27,
            longitude: 153,
            plannedTime: plannedTime,
            durationEstimate: durationMinutes * 60
        )
    }

    @Test func walkingTimeCanCreateATimingConflict() {
        let first = stop("First", at: time(9, 0), durationMinutes: 60)
        let second = stop("Second", at: time(10, 15))
        let leg = WalkingLeg(time: 30 * 60, distance: 2_000, path: [])

        let conflicts = DaySchedule.conflicts(
            for: [first, second],
            on: day,
            walkingLegs: [StopLegID(from: first, to: second): leg],
            calendar: calendar
        )

        #expect(conflicts[first.id] == nil)
        #expect(abs((conflicts[second.id]?.lateBy ?? 0) - 900.0) < 0.001)
    }

    @Test func untimedStopsStillConsumeTimeBetweenAppointments() {
        let first = stop("First", at: time(9, 0))
        let middle = stop("Middle")
        let last = stop("Last", at: time(10, 20))
        let leg = WalkingLeg(time: 15 * 60, distance: 1_000, path: [])

        let conflicts = DaySchedule.conflicts(
            for: [first, middle, last],
            on: day,
            walkingLegs: [
                StopLegID(from: first, to: middle): leg,
                StopLegID(from: middle, to: last): leg
            ],
            calendar: calendar
        )

        #expect(abs((conflicts[last.id]?.lateBy ?? 0) - 600.0) < 0.001)
    }

    @Test func optimizationKeepsFixedAppointmentsInPlace() async {
        let first = stop("Fixed start", at: time(9, 0))
        let slow = stop("Slow")
        let fast = stop("Fast")
        let last = stop("Fixed end", at: time(14, 0))

        let optimized = await RouteOptimizer.optimizedOrder(for: [first, slow, fast, last]) { from, to in
            if from.id == first.id, to.id == fast.id { return 5 }
            if from.id == first.id, to.id == slow.id { return 50 }
            return 10
        }

        #expect(optimized.map(\.id) == [first.id, fast.id, slow.id, last.id])
    }

    @Test func daySelectionPrefersTodayThenNearestTripDay() {
        let first = Day(date: day)
        let second = Day(date: calendar.date(byAdding: .day, value: 1, to: day)!)
        let last = Day(date: calendar.date(byAdding: .day, value: 2, to: day)!)
        let days = [last, first, second]

        #expect(TripDaySelection.preferredDayID(in: days, now: time(12, 0), calendar: calendar) == first.id)
        #expect(TripDaySelection.preferredDayID(
            in: days, now: calendar.date(byAdding: .day, value: -2, to: day)!, calendar: calendar
        ) == first.id)
        #expect(TripDaySelection.preferredDayID(
            in: days, now: calendar.date(byAdding: .day, value: 4, to: day)!, calendar: calendar
        ) == last.id)
        #expect(TripDaySelection.preferredDayID(in: [], now: day, calendar: calendar) == nil)
    }
}
