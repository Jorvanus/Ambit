import CoreLocation
import MapKit
import SwiftUI
import SwiftData

struct StopFormView: View {
    @Bindable var day: Day
    var existingStop: Stop?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: StopCategory
    @State private var hasPlannedTime: Bool
    @State private var plannedTime: Date
    @State private var durationMinutes: Double
    @State private var notes: String

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var isLocating = false
    @State private var locationNotFound = false

    init(day: Day, existingStop: Stop? = nil) {
        self.day = day
        self.existingStop = existingStop
        _name = State(initialValue: existingStop?.name ?? "")
        _category = State(initialValue: existingStop?.category ?? .sight)
        _hasPlannedTime = State(initialValue: existingStop?.plannedTime != nil)
        _plannedTime = State(initialValue: existingStop?.plannedTime ?? Date())
        _durationMinutes = State(initialValue: (existingStop?.durationEstimate ?? 3600) / 60)
        _notes = State(initialValue: existingStop?.notes ?? "")
        _coordinate = State(initialValue: existingStop?.hasCoordinate == true ? existingStop?.coordinate : nil)
    }

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
                if existingStop != nil {
                    Section {
                        Button("Delete Stop", role: .destructive) { delete() }
                    }
                }
            }
            .navigationTitle(existingStop == nil ? "New Stop" : "Edit Stop")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingStop == nil ? "Add" : "Save") {
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
        if let existingStop {
            existingStop.name = name
            existingStop.category = category
            existingStop.plannedTime = hasPlannedTime ? plannedTime : nil
            existingStop.durationEstimate = durationMinutes * 60
            existingStop.notes = notes
            existingStop.latitude = coordinate?.latitude ?? 0
            existingStop.longitude = coordinate?.longitude ?? 0
        } else {
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
        }
        dismiss()
    }

    private func delete() {
        if let existingStop {
            modelContext.delete(existingStop)
        }
        dismiss()
    }
}

#Preview {
    StopFormView(day: Day(date: .now))
        .modelContainer(for: [Trip.self, Day.self, Stop.self], inMemory: true)
}
