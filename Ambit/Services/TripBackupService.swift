import CryptoKit
import Foundation
import SwiftData
import UniformTypeIdentifiers
import SwiftUI

enum TripBackupError: LocalizedError {
    case unsupportedVersion
    case invalidArchive
    case damagedArchive
    case incompleteStore

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "This backup was made by a newer version of Ambit."
        case .invalidArchive: "The backup has invalid or missing trip data. Nothing was imported."
        case .damagedArchive: "The backup failed its integrity check. Nothing was imported."
        case .incompleteStore: "Some trip records could not be included in the backup. The export was cancelled."
        }
    }
}

@MainActor
enum TripBackupService {
    private static let formatVersion = 1

    static func export(from context: ModelContext) throws -> Data {
        let trips = try context.fetch(FetchDescriptor<Trip>())
        let snapshots = trips.sorted { $0.id.uuidString < $1.id.uuidString }.map(TripRecord.init)
        let payload = Payload(trips: snapshots)
        try validate(payload)
        guard Set(snapshots.flatMap(\.days).map(\.id)) == Set(try context.fetch(FetchDescriptor<Day>()).map(\.id)),
              Set(snapshots.flatMap { $0.days.flatMap(\.stops) + $0.savedPlaces }.map(\.id))
                == Set(try context.fetch(FetchDescriptor<Stop>()).map(\.id)),
              Set(snapshots.flatMap(\.expenses).map(\.id))
                == Set(try context.fetch(FetchDescriptor<Expense>()).map(\.id)) else {
            throw TripBackupError.incompleteStore
        }
        let payloadData = try encoder.encode(payload)
        let archive = Archive(version: formatVersion, digest: digest(payloadData), payload: payload)
        return try encoder.encode(archive)
    }

    /// Imports new copies so existing trips are never replaced or deleted.
    @discardableResult
    static func restore(_ data: Data, into context: ModelContext) throws -> Int {
        let archive = try decoder.decode(Archive.self, from: data)
        guard archive.version == formatVersion else { throw TripBackupError.unsupportedVersion }
        let payloadData = try encoder.encode(archive.payload)
        guard digest(payloadData) == archive.digest else { throw TripBackupError.damagedArchive }
        try validate(archive.payload)

        do {
            try context.transaction {
                for record in archive.payload.trips {
                    let trip = Trip(
                        name: record.name,
                        destination: record.destination,
                        startDate: record.startDate,
                        endDate: record.endDate,
                        pace: record.pace,
                        budget: record.budget
                    )
                    trip.destinationLatitude = record.destinationLatitude
                    trip.destinationLongitude = record.destinationLongitude
                    context.insert(trip)
                    var stopsByOriginalID: [UUID: Stop] = [:]

                    for dayRecord in record.days {
                        let day = Day(date: dayRecord.date)
                        day.trip = trip
                        context.insert(day)
                        for stopRecord in dayRecord.stops {
                            let stop = stopRecord.makeStop()
                            stop.day = day
                            context.insert(stop)
                            stopsByOriginalID[stopRecord.id] = stop
                        }
                    }
                    for stopRecord in record.savedPlaces {
                        let stop = stopRecord.makeStop()
                        stop.poolTrip = trip
                        context.insert(stop)
                        stopsByOriginalID[stopRecord.id] = stop
                    }
                    for expenseRecord in record.expenses {
                        let expense = Expense(
                            title: expenseRecord.title,
                            amount: expenseRecord.amount,
                            date: expenseRecord.date
                        )
                        expense.trip = trip
                        expense.stop = expenseRecord.stopID.flatMap { stopsByOriginalID[$0] }
                        context.insert(expense)
                    }
                }
            }
            try context.save()
            return archive.payload.trips.count
        } catch {
            context.rollback()
            throw error
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func validate(_ payload: Payload) throws {
        var tripIDs = Set<UUID>()
        var dayIDs = Set<UUID>()
        var stopIDs = Set<UUID>()
        var expenseIDs = Set<UUID>()

        for trip in payload.trips {
            let first = Calendar.current.startOfDay(for: trip.startDate)
            let last = Calendar.current.startOfDay(for: trip.endDate)
            guard tripIDs.insert(trip.id).inserted,
                  !trip.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !trip.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  first <= last,
                  trip.budget?.isFinite ?? true else { throw TripBackupError.invalidArchive }

            var tripStopIDs = Set<UUID>()
            for day in trip.days {
                guard dayIDs.insert(day.id).inserted,
                      Calendar.current.startOfDay(for: day.date) >= first,
                      Calendar.current.startOfDay(for: day.date) <= last else {
                    throw TripBackupError.invalidArchive
                }
                for stop in day.stops { try validate(stop, globalIDs: &stopIDs, tripIDs: &tripStopIDs) }
            }
            for stop in trip.savedPlaces { try validate(stop, globalIDs: &stopIDs, tripIDs: &tripStopIDs) }
            for expense in trip.expenses {
                guard expenseIDs.insert(expense.id).inserted,
                      !expense.title.isEmpty,
                      expense.amount.isFinite,
                      expense.stopID.map({ tripStopIDs.contains($0) }) ?? true else {
                    throw TripBackupError.invalidArchive
                }
            }
        }
    }

    private static func validate(_ stop: StopRecord, globalIDs: inout Set<UUID>, tripIDs: inout Set<UUID>) throws {
        guard globalIDs.insert(stop.id).inserted,
              tripIDs.insert(stop.id).inserted,
              !stop.name.isEmpty,
              stop.latitude.isFinite, (-90...90).contains(stop.latitude),
              stop.longitude.isFinite, (-180...180).contains(stop.longitude),
              stop.durationEstimate.isFinite, stop.durationEstimate >= 0 else {
            throw TripBackupError.invalidArchive
        }
    }

    private struct Archive: Codable {
        let version: Int
        let digest: String
        let payload: Payload
    }

    private struct Payload: Codable {
        let trips: [TripRecord]
    }

    private struct TripRecord: Codable {
        let id: UUID
        let name: String
        let destination: String
        let startDate: Date
        let endDate: Date
        let pace: Pace
        let budget: Double?
        let destinationLatitude: Double?
        let destinationLongitude: Double?
        let days: [DayRecord]
        let savedPlaces: [StopRecord]
        let expenses: [ExpenseRecord]

        init(_ trip: Trip) {
            id = trip.id
            name = trip.name
            destination = trip.destination
            startDate = trip.startDate
            endDate = trip.endDate
            pace = trip.pace
            budget = trip.budget
            destinationLatitude = trip.destinationLatitude
            destinationLongitude = trip.destinationLongitude
            days = trip.days.sorted { $0.date < $1.date }.map(DayRecord.init)
            savedPlaces = trip.savedPlaces.sorted { $0.sortOrder < $1.sortOrder }.map(StopRecord.init)
            expenses = trip.expenses.sorted { $0.id.uuidString < $1.id.uuidString }.map(ExpenseRecord.init)
        }
    }

    private struct DayRecord: Codable {
        let id: UUID
        let date: Date
        let stops: [StopRecord]

        init(_ day: Day) {
            id = day.id
            date = day.date
            stops = day.stops.sorted { $0.sortOrder < $1.sortOrder }.map(StopRecord.init)
        }
    }

    private struct StopRecord: Codable {
        let id: UUID
        let name: String
        let category: StopCategory
        let latitude: Double
        let longitude: Double
        let plannedTime: Date?
        let durationEstimate: TimeInterval
        let notes: String
        let isBackup: Bool
        let sortOrder: Int
        let bookingStatus: BookingStatus
        let confirmationNumber: String?
        let bookingURLString: String?

        init(_ stop: Stop) {
            id = stop.id
            name = stop.name
            category = stop.category
            latitude = stop.latitude
            longitude = stop.longitude
            plannedTime = stop.plannedTime
            durationEstimate = stop.durationEstimate
            notes = stop.notes
            isBackup = stop.isBackup
            sortOrder = stop.sortOrder
            bookingStatus = stop.bookingStatus
            confirmationNumber = stop.confirmationNumber
            bookingURLString = stop.bookingURLString
        }

        func makeStop() -> Stop {
            Stop(
                name: name, category: category, latitude: latitude, longitude: longitude,
                plannedTime: plannedTime, durationEstimate: durationEstimate, notes: notes,
                isBackup: isBackup, sortOrder: sortOrder, bookingStatus: bookingStatus,
                confirmationNumber: confirmationNumber, bookingURLString: bookingURLString
            )
        }
    }

    private struct ExpenseRecord: Codable {
        let id: UUID
        let title: String
        let amount: Double
        let date: Date
        let stopID: UUID?

        init(_ expense: Expense) {
            id = expense.id
            title = expense.title
            amount = expense.amount
            date = expense.date
            stopID = expense.stop?.id
        }
    }
}

@Observable
final class TripBackupDocument: WritableDocument {
    static let writableContentTypes: [UTType] = [.json]
    let data: Data

    init(data: Data) { self.data = data }

    func writer(configuration: sending WriteConfiguration) -> sending FileWrapperDocumentWriter<Data> {
        FileWrapperDocumentWriter(configuration) { data, _ in
            FileWrapper(regularFileWithContents: data)
        }
    }

    @MainActor
    func snapshot(contentType: UTType) async throws -> sending Data { data }
}
