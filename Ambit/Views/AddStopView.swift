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

    var body: some View {
        NavigationStack {
            Form {
                Section("Stop") {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(StopCategory.allCases) { category in
                            Text(category.rawValue.capitalized).tag(category)
                        }
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
                    Button("Add") { save() }
                        .buttonStyle(.glassProminent)
                        .disabled(name.isEmpty)
                }
            }
        }
    }

    private func save() {
        let stop = Stop(
            name: name,
            category: category,
            latitude: 0,
            longitude: 0,
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
