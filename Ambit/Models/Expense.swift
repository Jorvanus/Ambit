import Foundation
import SwiftData

@Model
final class Expense {
    #Unique<Expense>([\.id])

    var id: UUID
    var title: String
    var amount: Double
    var date: Date

    var trip: Trip?
    var stop: Stop?

    init(title: String, amount: Double, date: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.amount = amount
        self.date = date
    }
}

extension Double {
    var asCurrency: String {
        formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
}
