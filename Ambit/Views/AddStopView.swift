import CoreLocation
import MapKit
import SwiftUI
import SwiftData

struct AddStopView: View {
    @Bindable var day: Day

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: StopCategory = .sight
    @State private var hasPlannedTime = false
    @State private var plannedTime = Date()
    @State private var durationMinutes = 60.0
    @State private var notes = ""

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var isLocating = false
    @State private var locationNotFound = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Stop") {
                    TextField("Name", text: $name)
                        .onChange(of: name) { coordinate = nil; locationNotFound = false }
                    Picker("Category", selection: $category) {
                        ForEach(StopCategory.allCases) { category in
                            Text(category.rawValue.capitalized).tag(category)
                        }
                    }
                }
                Section("Location") {
                    Button {
                        Task { await locate() }
                    } label: {
                        if isLocating {
                            ProgressView()
                        } else {
                            Label("Find on Map", systemImage: "location.magnifyingglass")
                        }
                    }
                    .disabled(name.isEmpty || isLocating)

                    if let coordinate {
                        Map(initialPosition: .region(
                            MKCoordinateRegion(
                                center: coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )
                        )) {
                            Marker(name, coordinate: coordinate)
                        }
                        .frame(height: 160)
                        .listRowInsets(EdgeInsets())
                    } else if locationNotFound {
                        Text("Couldn't find that location. It'll be saved without a map position.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Timing") {
                    Toggle("Set a time", isOn: $hasPlannedTime)
                    if hasPlannedTime {
                        DatePicker("Time", selection: $plannedTime, displayedComponents: .hourAndMinute)
                    }
                    Stepper(
                        "Duration: \(Int(durationMinutes)) min",
                        value: $durationMinutes,
                        in: 15...480,
                        step: 15
                    )
                }
                Section("Notes") {
                    TextField("e.g. booking required", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("New Stop")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task { await save() }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(name.isEmpty || isLocating)
                }
            }
        }
    }

    private func locate() async {
        isLocating = true
        locationNotFound = false
        coordinate = await StopGeocoder.geocode(name: name, near: day.trip?.destination ?? "")
        locationNotFound = coordinate == nil
        isLocating = false
    }

    private func save() async {
        if coordinate == nil {
            await locate()
        }
        let stop = Stop(
            name: name,
            category: category,
            latitude: coordinate?.latitude ?? 0,
            longitude: coordinate?.longitude ?? 0,
            plannedTime: hasPlannedTime ? plannedTime : nil,
            durationEstimate: durationMinutes * 60,
            notes: notes,
            sortOrder: day.stops.count
        )
        stop.day = day
        modelContext.insert(stop)
        dismiss()
    }
}

#Preview {
    AddStopView(day: Day(date: .now))
        .modelContainer(for: [Trip.self, Day.self, Stop.self], inMemory: true)
}
