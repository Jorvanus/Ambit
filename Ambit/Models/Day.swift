import Foundation
import SwiftData

@Model
final class Day {
    #Unique<Day>([\.id])
    #Index<Day>([\.date])

    var id: UUID
    var date: Date

    var trip: Trip?

    @Relationship(deleteRule: .cascade, inverse: \Stop.day)
    var stops: [Stop] = []

    init(date: Date) {
        self.id = UUID()
        self.date = date
    }
}
