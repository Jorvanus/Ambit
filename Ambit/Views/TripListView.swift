import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TripListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.startDate) private var trips: [Trip]

    @State private var isPresentingNewTrip = false
    @State private var backupDocument: TripBackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isConfirmingImport = false
    @State private var pendingImport: Data?
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(trips) { trip in
                    NavigationLink(value: trip) {
                        VStack(alignment: .leading) {
                            Text(trip.name).font(.headline)
                            Text(trip.destination).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteTrips)
            }
            .navigationTitle("Trips")
            .navigationSubtitle(trips.isEmpty ? "" : "\(trips.count) planned")
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip)
            }
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button("Export Trip Backup", systemImage: "square.and.arrow.up") { exportBackup() }
                        Button("Restore Trip Backup", systemImage: "square.and.arrow.down") { isImporting = true }
                    } label: {
                        Label("Backup", systemImage: "archivebox")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { isPresentingNewTrip = true }) {
                        Label("New Trip", systemImage: "plus")
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .sheet(isPresented: $isPresentingNewTrip) {
                TripFormView()
            }
            .fileExporter(
                isPresented: $isExporting,
                document: backupDocument,
                contentType: .json,
                defaultFilename: "Ambit Trips Backup"
            ) { result in
                if case .failure(let error) = result { statusMessage = error.localizedDescription }
                backupDocument = nil
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    pendingImport = try Data(contentsOf: url)
                    isConfirmingImport = true
                } catch {
                    statusMessage = error.localizedDescription
                }
            }
            .confirmationDialog(
                "Restore trips from backup?",
                isPresented: $isConfirmingImport,
                titleVisibility: .visible
            ) {
                Button("Add Trips from Backup") { restoreBackup() }
            } message: {
                Text("Ambit checks the entire backup before importing. Trips are added as new copies; your current trips stay in place. Repeating this import will add another copy.")
            }
            .alert("Trip Backup", isPresented: Binding(
                get: { statusMessage != nil },
                set: { if !$0 { statusMessage = nil } }
            )) {
                Button("OK", role: .cancel) { statusMessage = nil }
            } message: {
                Text(statusMessage ?? "")
            }
            .overlay {
                if trips.isEmpty {
                    ContentUnavailableView(
                        "No Trips Yet",
                        systemImage: "airplane.departure",
                        description: Text("Tap + to plan your first trip.")
                    )
                }
            }
        }
    }

    private func deleteTrips(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(trips[index])
        }
    }

    private func exportBackup() {
        do {
            backupDocument = TripBackupDocument(data: try TripBackupService.export(from: modelContext))
            isExporting = true
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func restoreBackup() {
        guard let pendingImport else { return }
        self.pendingImport = nil
        do {
            let count = try TripBackupService.restore(pendingImport, into: modelContext)
            statusMessage = "Restored \(count) trip\(count == 1 ? "" : "s") as new copies."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

#Preview {
    TripListView()
        .modelContainer(for: [Trip.self, Day.self, Stop.self, Expense.self], inMemory: true)
}
