import CoreLocation
import MapKit
import SwiftUI
import SwiftData

struct StopFormView: View {
    let trip: Trip
    var existingStop: Stop?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: StopCategory
    @State private var selectedDayID: UUID?
    @State private var hasPlannedTime: Bool
    @State private var plannedTime: Date
    @State private var durationMinutes: Double
    @State private var notes: String

    @State private var bookingStatus: BookingStatus
    @State private var confirmationNumber: String
    @State private var bookingURLString: String

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var isLocating = false
    @State private var locationNotFound = false

    /// `day` is where a new stop starts out; nil means "Places to visit".
    /// When editing, the stop's own day wins.
    init(trip: Trip, day: Day? = nil, existingStop: Stop? = nil) {
        self.trip = trip
        self.existingStop = existingStop
        _name = State(initialValue: existingStop?.name ?? "")
        _category = State(initialValue: existingStop?.category ?? .sight)
        _selectedDayID = State(initialValue: existingStop != nil ? existingStop?.day?.id : day?.id)
        _hasPlannedTime = State(initialValue: existingStop?.plannedTime != nil)
        _plannedTime = State(initialValue: existingStop?.plannedTime ?? Date())
        _durationMinutes = State(initialValue: (existingStop?.durationEstimate ?? 3600) / 60)
        _notes = State(initialValue: existingStop?.notes ?? "")
        _bookingStatus = State(initialValue: existingStop?.bookingStatus ?? .none)
        _confirmationNumber = State(initialValue: existingStop?.confirmationNumber ?? "")
        _bookingURLString = State(initialValue: existingStop?.bookingURLString ?? "")
        _coordinate = State(initialValue: existingStop?.hasCoordinate == true ? existingStop?.coordinate : nil)
    }

    private var sortedDays: [Day] {
        trip.days.sorted { $0.date < $1.date }
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
                    Picker("Schedule", selection: $selectedDayID) {
                        Text("Places to visit").tag(UUID?.none)
                        ForEach(sortedDays) { day in
                            Text(day.date.formatted(date: .abbreviated, time: .omitted))
                                .tag(UUID?.some(day.id))
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
                Section("Booking") {
                    Picker("Status", selection: $bookingStatus) {
                        ForEach(BookingStatus.allCases) { status in
                            Text(status.label).tag(status)
                        }
                    }
                    if bookingStatus != .none {
                        TextField("Confirmation number", text: $confirmationNumber)
                        TextField("Booking link", text: $bookingURLString)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if let url = URL(string: bookingURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
                           url.scheme?.hasPrefix("http") == true {
                            Link(destination: url) {
                                Label("Open Booking Link", systemImage: "arrow.up.forward.app")
                            }
                        }
                    }
                }
                Section("Notes") {
                    TextField("Add a note", text: $notes, axis: .vertical)
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
        coordinate = await StopGeocoder.geocode(name: name, near: trip.destination)
        locationNotFound = coordinate == nil
        isLocating = false
    }

    private func save() async {
        if coordinate == nil {
            await locate()
        }
        let trimmedConfirmation = confirmationNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = bookingURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetDay = selectedDayID.flatMap { id in trip.days.first { $0.id == id } }

        let stop: Stop
        if let existingStop {
            stop = existingStop
        } else {
            stop = Stop(name: name, category: category, latitude: 0, longitude: 0)
            modelContext.insert(stop)
        }

        stop.name = name
        stop.category = category
        stop.plannedTime = hasPlannedTime ? plannedTime : nil
        stop.durationEstimate = durationMinutes * 60
        stop.notes = notes
        stop.latitude = coordinate?.latitude ?? 0
        stop.longitude = coordinate?.longitude ?? 0
        stop.bookingStatus = bookingStatus
        stop.confirmationNumber = trimmedConfirmation.isEmpty ? nil : trimmedConfirmation
        stop.bookingURLString = trimmedURL.isEmpty ? nil : trimmedURL

        let isNewHome = existingStop == nil
            || stop.day?.id != targetDay?.id
            || (targetDay == nil && stop.poolTrip == nil)
        if isNewHome {
            if let targetDay {
                stop.poolTrip = nil
                stop.sortOrder = Self.nextSortOrder(in: targetDay.stops)
                stop.day = targetDay
            } else {
                stop.day = nil
                stop.sortOrder = Self.nextSortOrder(in: trip.savedPlaces)
                stop.poolTrip = trip
            }
        }
        dismiss()
    }

    /// One past the highest existing order, not `count`: orders can have gaps
    /// (a stop moved or deleted elsewhere), and `count` would then collide.
    private static func nextSortOrder(in stops: [Stop]) -> Int {
        (stops.map(\.sortOrder).max() ?? -1) + 1
    }

    private func delete() {
        if let existingStop {
            let siblings = (existingStop.day?.stops ?? existingStop.poolTrip?.savedPlaces ?? [])
                .filter { $0 !== existingStop }
                .sorted { $0.sortOrder < $1.sortOrder }
            modelContext.delete(existingStop)
            for (index, sibling) in siblings.enumerated() {
                sibling.sortOrder = index
            }
        }
        dismiss()
    }
}
