import CoreLocation
import Foundation
import SwiftData

enum StopCategory: String, Codable, CaseIterable, Identifiable {
    case food
    case sight
    case activity

    var id: String { rawValue }
}

@Model
final class Stop {
    #Unique<Stop>([\.id])
    #Index<Stop>([\.sortOrder])

    var id: UUID
    var name: String
    var category: StopCategory
    var latitude: Double
    var longitude: Double
    var plannedTime: Date?
    var durationEstimate: TimeInterval
    var notes: String
    var isBackup: Bool
    var sortOrder: Int

    var day: Day?

    init(
        name: String,
        category: StopCategory,
        latitude: Double,
        longitude: Double,
        plannedTime: Date? = nil,
        durationEstimate: TimeInterval = 3600,
        notes: String = "",
        isBackup: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.plannedTime = plannedTime
        self.durationEstimate = durationEstimate
        self.notes = notes
        self.isBackup = isBackup
        self.sortOrder = sortOrder
    }

    var hasCoordinate: Bool {
        latitude != 0 || longitude != 0
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}
