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

    @Relationship(deleteRule: .cascade, inverse: \Day.trip)
    var days: [Day] = []

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
}
