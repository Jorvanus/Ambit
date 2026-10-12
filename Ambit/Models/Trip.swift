import CoreLocation
import Foundation
import SwiftData

enum Pace: String, Codable, CaseIterable, Identifiable {
    case chill
    case packed

    var id: String { rawValue }
}

@Model
final class Trip {
    #Unique<Trip>([\.id])
    #Index<Trip>([\.startDate])

    var id: UUID
    var name: String
    var destination: String
    var startDate: Date
    var endDate: Date
    var pace: Pace
    var budget: Double?
    /// Centre of the chosen destination. Optional so trips made before destinations were
    /// resolved (free text) keep working.
    var destinationLatitude: Double?
    var destinationLongitude: Double?

    @Relationship(deleteRule: .cascade, inverse: \Day.trip)
    var days: [Day] = []

    @Relationship(deleteRule: .cascade, inverse: \Stop.poolTrip)
    var savedPlaces: [Stop] = []

    @Relationship(deleteRule: .cascade, inverse: \Expense.trip)
    var expenses: [Expense] = []

    init(
        name: String,
        destination: String,
        startDate: Date,
        endDate: Date,
        pace: Pace = .chill,
        budget: Double? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.pace = pace
        self.budget = budget
    }

    var destinationCoordinate: CLLocationCoordinate2D? {
        guard let destinationLatitude, let destinationLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: destinationLatitude, longitude: destinationLongitude)
    }
}
