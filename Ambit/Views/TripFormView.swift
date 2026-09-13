import SwiftUI
import SwiftData

struct TripFormView: View {
    var existingTrip: Trip?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var destination: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var pace: Pace
    @State private var budgetText: String

    init(existingTrip: Trip? = nil) {
        self.existingTrip = existingTrip
        _name = State(initialValue: existingTrip?.name ?? "")
        _destination = State(initialValue: existingTrip?.destination ?? "")
        _startDate = State(initialValue: existingTrip?.startDate ?? Date())
        _endDate = State(initialValue: existingTrip?.endDate ?? Date().addingTimeInterval(60 * 60 * 24 * 3))
        _pace = State(initialValue: existingTrip?.pace ?? .chill)
        _budgetText = State(initialValue: existingTrip?.budget.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") {
                    TextField("Name", text: $name)
                    TextField("Destination", text: $destination)
                }
                Section("Dates") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
                Section("Preferences") {
                    Picker("Pace", selection: $pace) {
                        ForEach(Pace.allCases) { pace in
                            Text(pace.rawValue.capitalized).tag(pace)
                        }
                    }
                    TextField("Budget (optional)", text: $budgetText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle(existingTrip == nil ? "New Trip" : "Edit Trip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .buttonStyle(.glassProminent)
                        .disabled(name.isEmpty || destination.isEmpty)
                }
            }
        }
    }

    private func save() {
        let trip = existingTrip ?? Trip(
            name: name,
            destination: destination,
            startDate: startDate,
            endDate: endDate,
            pace: pace,
            budget: Double(budgetText)
        )
        if existingTrip != nil {
            trip.name = name
            trip.destination = destination
            trip.startDate = startDate
            trip.endDate = endDate
            trip.pace = pace
            trip.budget = Double(budgetText)
        } else {
            modelContext.insert(trip)
        }
        syncDays(for: trip)
        dismiss()
    }

    /// Adds/removes Day objects so they match the trip's current date range,
    /// preserving (and their stops) any day that's still within range.
    private func syncDays(for trip: Trip) {
        let calendar = Calendar.current
        var desiredDates: [Date] = []
        var currentDate = calendar.startOfDay(for: trip.startDate)
        let lastDate = calendar.startOfDay(for: trip.endDate)
        while currentDate <= lastDate {
            desiredDates.append(currentDate)
            guard let next = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = next
        }
        let desiredSet = Set(desiredDates)

        for day in trip.days where !desiredSet.contains(calendar.startOfDay(for: day.date)) {
            modelContext.delete(day)
        }

        let existingDates = Set(trip.days.map { calendar.startOfDay(for: $0.date) })
        for date in desiredDates where !existingDates.contains(date) {
            let day = Day(date: date)
            day.trip = trip
            modelContext.insert(day)
        }
    }
}

#Preview {
    TripFormView()
        .modelContainer(for: [Trip.self, Day.self, Stop.self], inMemory: true)
}
