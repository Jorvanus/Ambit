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
    @State private var isConfirmingRemovedDays = false
    @State private var saveError: String?

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
                    Button("Save") { requestSave() }
                        .buttonStyle(.glassProminent)
                        .disabled(name.isEmpty || destination.isEmpty)
                }
            }
            .confirmationDialog(
                "Move stops from removed days?",
                isPresented: $isConfirmingRemovedDays,
                titleVisibility: .visible
            ) {
                Button("Move Stops and Save") { save() }
            } message: {
                Text("\(excludedStopCount) stops on days outside the new dates will move to Places to Visit. Their booking details and expenses will stay attached.")
            }
            .alert("Could Not Save Trip", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var excludedStopCount: Int {
        guard let existingTrip else { return 0 }
        return TripDateChangeService.excludedDays(in: existingTrip, start: startDate, end: endDate)
            .reduce(0) { $0 + $1.stops.count }
    }

    private func requestSave() {
        if excludedStopCount > 0 {
            isConfirmingRemovedDays = true
        } else {
            save()
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
        do {
            if existingTrip == nil { modelContext.insert(trip) }
            try TripDateChangeService.apply(
                to: trip,
                start: startDate,
                end: endDate,
                name: name,
                destination: destination,
                pace: pace,
                budget: Double(budgetText),
                in: modelContext
            )
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
        }
    }
}

#Preview {
    TripFormView()
        .modelContainer(for: [Trip.self, Day.self, Stop.self, Expense.self], inMemory: true)
}
