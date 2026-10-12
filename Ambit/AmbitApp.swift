import SwiftUI
import SwiftData

@main
struct AmbitApp: App {
    @State private var store = StoreState.open()

    var body: some Scene {
        WindowGroup {
            switch store {
            case .ready(let container):
                TripListView()
                    .modelContainer(container)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Trips Could Not Be Opened", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Your trip database has been left untouched. Check available storage and try again. If this continues, keep the app installed so the database can be recovered.\n\n\(message)")
                } actions: {
                    Button("Try Again") { store = StoreState.open() }
                }
            }
        }
    }

    private enum StoreState {
        case ready(ModelContainer)
        case failed(String)

        static func open() -> StoreState {
            let schema = Schema(versionedSchema: AmbitSchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            do {
                return .ready(try ModelContainer(
                    for: schema,
                    migrationPlan: AmbitMigrationPlan.self,
                    configurations: [configuration]
                ))
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }
}
