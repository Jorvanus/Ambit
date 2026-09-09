import SwiftUI
import SwiftData

struct NewTripView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var destination = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(60 * 60 * 24 * 3)
    @State private var pace: Pace = .chill
    @State private var budgetText = ""

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
            .navigationTitle("New Trip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || destination.isEmpty)
                }
            }
        }
    }

    private func save() {
        let trip = Trip(
            name: name,
            destination: destination,
            startDate: startDate,
            endDate: endDate,
            pace: pace,
            budget: Double(budgetText)
        )
        modelContext.insert(trip)
        generateDays(for: trip)
        dismiss()
    }

    private func generateDays(for trip: Trip) {
        let calendar = Calendar.current
        var currentDate = trip.startDate
        while currentDate <= trip.endDate {
            let day = Day(date: currentDate)
            day.trip = trip
            modelContext.insert(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = next
        }
    }
}

#Preview {
    NewTripView()
        .modelContainer(for: [Trip.self, Day.self, Stop.self], inMemory: true)
}
