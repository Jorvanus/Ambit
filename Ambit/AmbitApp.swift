import SwiftUI
import SwiftData

@main
struct AmbitApp: App {
    var sharedModelContainer: ModelContainer = Self.makeModelContainer()

    var body: some Scene {
        WindowGroup {
            TripListView()
        }
        .modelContainer(sharedModelContainer)
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: AmbitSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AmbitMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            // A migration failed in a way AmbitMigrationPlan didn't handle.
            // The app has no shipped users yet, so recover by discarding the
            // local store rather than leaving the app unable to launch —
            // once this ships, replace this with real recovery (e.g.
            // surfacing the error, attempting a backup/export) instead of
            // dropping data.
            assertionFailure("SwiftData migration failed, resetting local store: \(error)")
            try? FileManager.default.removeItem(at: configuration.url)
            return (try? ModelContainer(
                for: schema,
                migrationPlan: AmbitMigrationPlan.self,
                configurations: [configuration]
            )) ?? {
                fatalError("Could not create ModelContainer even after resetting the store: \(error)")
            }()
        }
    }
}
