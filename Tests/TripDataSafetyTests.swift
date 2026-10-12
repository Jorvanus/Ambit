import Foundation
import SwiftData
import Testing
@testable import Ambit

@Suite @MainActor
struct TripDataSafetyTests {
    private func context() throws -> ModelContext {
        let schema = Schema(versionedSchema: AmbitSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: [configuration]))
    }

    private func date(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day))!
    }

    private func populatedTrip(in context: ModelContext) throws -> Trip {
        let trip = Trip(name: "Kyoto", destination: "Japan", startDate: date(12), endDate: date(14), budget: 1000)
        context.insert(trip)
        let first = Day(date: date(12))
        first.trip = trip
        context.insert(first)
        let last = Day(date: date(14))
        last.trip = trip
        context.insert(last)
        let booked = Stop(
            name: "Tea", category: .activity, latitude: 35, longitude: 135,
            plannedTime: date(14).addingTimeInterval(10 * 3600), durationEstimate: 3600,
            notes: "Arrive early", sortOrder: 0, bookingStatus: .confirmed,
            confirmationNumber: "REF123", bookingURLString: "https://example.com/booking"
        )
        booked.day = last
        context.insert(booked)
        let saved = Stop(name: "Temple", category: .sight, latitude: 35.1, longitude: 135.1, sortOrder: 0)
        saved.poolTrip = trip
        context.insert(saved)
        let expense = Expense(
            title: "Tea ticket", amount: 25,
            date: date(14).addingTimeInterval(12_345.123456)
        )
        expense.trip = trip
        expense.stop = booked
        context.insert(expense)
        try context.save()
        return trip
    }

    @Test func shorteningMovesStopsAndKeepsBookingAndExpense() throws {
        let context = try context()
        let trip = try populatedTrip(in: context)
        #expect(TripDateChangeService.excludedDays(in: trip, start: date(12), end: date(13)).count == 1)

        try TripDateChangeService.apply(
            to: trip, start: date(12), end: date(13), name: trip.name,
            destination: trip.destination, pace: trip.pace, budget: trip.budget, in: context
        )
        try context.save()

        let moved = try #require(trip.savedPlaces.first { $0.name == "Tea" })
        #expect(moved.day == nil)
        #expect(moved.poolTrip?.id == trip.id)
        #expect(moved.confirmationNumber == "REF123")
        #expect(trip.expenses.first?.stop?.id == moved.id)
        #expect(trip.days.count == 2)
        #expect(trip.savedPlaces.count == 2)
        let reopened = ModelContext(context.container)
        let storedStops = try reopened.fetch(FetchDescriptor<Stop>())
        #expect(storedStops.count == 2)
        #expect(storedStops.first { $0.name == "Tea" }?.poolTrip != nil)
        #expect(try reopened.fetch(FetchDescriptor<Expense>()).first?.stop?.name == "Tea")
    }

    @Test func backupRoundTripPreservesGraphAndAddsCopies() throws {
        let source = try context()
        _ = try populatedTrip(in: source)
        let data = try TripBackupService.export(from: source)
        let target = try context()
        let existing = Trip(name: "Existing", destination: "Home", startDate: date(12), endDate: date(12))
        target.insert(existing)
        try target.save()

        #expect(try TripBackupService.restore(data, into: target) == 1)
        let trips = try target.fetch(FetchDescriptor<Trip>())
        #expect(trips.count == 2)
        #expect(trips.contains { $0.id == existing.id })
        let restored = try #require(trips.first { $0.name == "Kyoto" })
        let stop = try #require(restored.days.flatMap(\.stops).first { $0.name == "Tea" })
        #expect(restored.budget == 1000)
        #expect(restored.savedPlaces.first?.name == "Temple")
        #expect(stop.bookingStatus == .confirmed)
        #expect(stop.confirmationNumber == "REF123")
        #expect(stop.bookingURLString == "https://example.com/booking")
        #expect(restored.expenses.first?.stop?.id == stop.id)
        #expect(restored.expenses.first?.amount == 25)
        #expect(abs((restored.expenses.first?.date.timeIntervalSince1970 ?? 0) - date(14).addingTimeInterval(12_345.123456).timeIntervalSince1970) < 0.001)
        let reopened = ModelContext(target.container)
        #expect(try reopened.fetch(FetchDescriptor<Trip>()).count == 2)
        #expect(try reopened.fetch(FetchDescriptor<Stop>()).count == 2)
        #expect(try reopened.fetch(FetchDescriptor<Expense>()).first?.stop?.name == "Tea")
    }

    @Test func damagedBackupLeavesExistingTripsUntouched() throws {
        let source = try context()
        _ = try populatedTrip(in: source)
        let data = try TripBackupService.export(from: source)
        var archive = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        archive["digest"] = String(repeating: "0", count: 64)
        let damaged = try JSONSerialization.data(withJSONObject: archive)
        let target = try context()
        let existing = Trip(name: "Existing", destination: "Home", startDate: date(12), endDate: date(12))
        target.insert(existing)
        try target.save()

        #expect(throws: TripBackupError.self) {
            try TripBackupService.restore(damaged, into: target)
        }
        let trips = try target.fetch(FetchDescriptor<Trip>())
        #expect(trips.map(\.id) == [existing.id])
    }
}
