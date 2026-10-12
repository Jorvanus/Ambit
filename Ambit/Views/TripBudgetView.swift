import SwiftData
import SwiftUI

struct TripBudgetView: View {
    @Bindable var trip: Trip

    @Environment(\.modelContext) private var modelContext
    @State private var isPresentingAdd = false
    @State private var editingExpense: Expense?
    @State private var isPresentingEditTrip = false

    private var expenses: [Expense] {
        trip.expenses.sorted { $0.date > $1.date }
    }

    private var spent: Double {
        trip.expenses.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        List {
            Section {
                if let budget = trip.budget, budget > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(spent.asCurrency).font(.title2.bold())
                            Text("of \(budget.asCurrency)").foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(spent, budget), total: budget)
                            .tint(spent > budget ? .red : .accentColor)
                        if spent > budget {
                            Label("Over budget by \((spent - budget).asCurrency)", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        } else {
                            Text("\((budget - spent).asCurrency) left")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(spent.asCurrency).font(.title2.bold())
                        Text("spent").foregroundStyle(.secondary)
                    }
                    Button("Set a trip budget") { isPresentingEditTrip = true }
                }
            }

            Section("Expenses") {
                if expenses.isEmpty {
                    Text("No expenses yet").foregroundStyle(.secondary)
                } else {
                    ForEach(expenses) { expense in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(expense.title)
                                if let stop = expense.stop {
                                    Label(stop.name, systemImage: "mappin")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(expense.amount.asCurrency)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editingExpense = expense }
                    }
                    .onDelete { offsets in
                        for expense in offsets.map({ expenses[$0] }) {
                            modelContext.delete(expense)
                        }
                    }
                }
                Button {
                    isPresentingAdd = true
                } label: {
                    Label("Add Expense", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            ExpenseFormView(trip: trip)
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseFormView(trip: trip, existingExpense: expense)
        }
        .sheet(isPresented: $isPresentingEditTrip) {
            TripFormView(existingTrip: trip)
        }
    }
}

struct ExpenseFormView: View {
    let trip: Trip
    var existingExpense: Expense?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var amountText: String
    @State private var date: Date
    @State private var stop: Stop?

    init(trip: Trip, existingExpense: Expense? = nil) {
        self.trip = trip
        self.existingExpense = existingExpense
        _title = State(initialValue: existingExpense?.title ?? "")
        _amountText = State(initialValue: existingExpense.map {
            $0.amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
        } ?? "")
        _date = State(initialValue: existingExpense?.date ?? Date())
        _stop = State(initialValue: existingExpense?.stop)
    }

    private var allStops: [Stop] {
        trip.days.sorted { $0.date < $1.date }.flatMap { day in
            day.stops.sorted { $0.sortOrder < $1.sortOrder }
        } + trip.savedPlaces
    }

    private var amount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What was it for?", text: $title)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                Section("Attach to a stop") {
                    Picker("Stop", selection: $stop) {
                        Text("None").tag(Stop?.none)
                        ForEach(allStops) { stop in
                            Text(stop.name).tag(Stop?.some(stop))
                        }
                    }
                }
                if existingExpense != nil {
                    Section {
                        Button("Delete Expense", role: .destructive) {
                            if let existingExpense { modelContext.delete(existingExpense) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existingExpense == nil ? "New Expense" : "Edit Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existingExpense == nil ? "Add" : "Save") { save() }
                        .buttonStyle(.glassProminent)
                        .disabled(title.isEmpty || amount == nil)
                }
            }
        }
    }

    private func save() {
        guard let amount else { return }
        let expense = existingExpense ?? Expense(title: title, amount: amount, date: date)
        if existingExpense == nil {
            modelContext.insert(expense)
            expense.trip = trip
        }
        expense.title = title
        expense.amount = amount
        expense.date = date
        expense.stop = stop
        dismiss()
    }
}
