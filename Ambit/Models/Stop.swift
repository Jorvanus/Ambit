import CoreLocation
import Foundation
import SwiftData

enum StopCategory: String, Codable, CaseIterable, Identifiable {
    case food
    case sight
    case activity

    var id: String { rawValue }
}

enum BookingStatus: String, Codable, CaseIterable, Identifiable {
    case none
    case required
    case booked
    case confirmed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "No Booking Needed"
        case .required: return "Booking Required"
        case .booked: return "Booked"
        case .confirmed: return "Confirmed"
        }
    }

    var icon: String {
        switch self {
        case .none: return ""
        case .required: return "exclamationmark.circle.fill"
        case .booked: return "ticket.fill"
        case .confirmed: return "checkmark.circle.fill"
        }
    }
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
    var bookingStatus: BookingStatus = BookingStatus.none
    var confirmationNumber: String?
    var bookingURLString: String?

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
        sortOrder: Int = 0,
        bookingStatus: BookingStatus = .none,
        confirmationNumber: String? = nil,
        bookingURLString: String? = nil
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
        self.bookingStatus = bookingStatus
        self.confirmationNumber = confirmationNumber
        self.bookingURLString = bookingURLString
    }

    var bookingURL: URL? {
        bookingURLString.flatMap { URL(string: $0) }
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
