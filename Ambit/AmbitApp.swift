import SwiftUI
import SwiftData

@main
struct AmbitApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Trip.self, Day.self, Stop.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    var body: some Scene {
        WindowGroup {
            TripListView()
        }
        .modelContainer(sharedModelContainer)
    }
}
