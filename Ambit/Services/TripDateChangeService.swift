import Foundation
import SwiftData

@MainActor
enum TripDateChangeService {
    static func excludedDays(in trip: Trip, start: Date, end: Date, calendar: Calendar = .current) -> [Day] {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        return trip.days.filter {
            let date = calendar.startOfDay(for: $0.date)
            return date < first || date > last
        }
    }

    static func apply(
        to trip: Trip,
        start: Date,
        end: Date,
        name: String,
        destination: String,
        pace: Pace,
        budget: Double?,
        in context: ModelContext,
        calendar: Calendar = .current
    ) throws {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        guard first <= last else { throw TripDateError.invalidRange }

        var dates: [Date] = []
        var date = first
        while date <= last {
            dates.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else {
                throw TripDateError.invalidRange
            }
            date = next
        }

        let excluded = excludedDays(in: trip, start: start, end: end, calendar: calendar)
        let remainingDates = Set(trip.days.filter { day in
            !excluded.contains { $0.id == day.id }
        }.map { calendar.startOfDay(for: $0.date) })
        var nextOrder = (trip.savedPlaces.map(\.sortOrder).max() ?? -1) + 1

        try context.transaction {
            for day in excluded {
                for stop in day.stops.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                    stop.day = nil
                    stop.poolTrip = trip
                    stop.sortOrder = nextOrder
                    nextOrder += 1
                }
                context.delete(day)
            }
            for date in dates where !remainingDates.contains(date) {
                let day = Day(date: date)
                day.trip = trip
                context.insert(day)
            }
            trip.startDate = start
            trip.endDate = end
            trip.name = name
            trip.destination = destination
            trip.pace = pace
            trip.budget = budget
        }
    }
}

enum TripDateError: LocalizedError {
    case invalidRange

    var errorDescription: String? { "The trip end date must be on or after its start date." }
}
