import SwiftUI
import SwiftData

struct TripDetailView: View {
    @Bindable var trip: Trip

    private var sortedDays: [Day] {
        trip.days.sorted { $0.date < $1.date }
    }

    var body: some View {
        List {
            ForEach(sortedDays) { day in
                DaySection(day: day)
            }
        }
        .navigationTitle(trip.name)
        .navigationSubtitle(trip.destination)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
        }
    }
}

private struct DaySection: View {
    @Bindable var day: Day

    @Environment(\.modelContext) private var modelContext
    @State private var isPresentingAddStop = false

    private var stops: [Stop] {
        day.stops.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Section {
            if stops.isEmpty {
                Text("No stops yet").foregroundStyle(.secondary)
            } else {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    StopRow(
                        stop: stop,
                        walkingTimeToNext: index < stops.count - 1
                            ? RouteOptimizer.walkingTime(from: stop, to: stops[index + 1])
                            : nil
                    )
                }
                .onDelete(perform: deleteStops)
                .onMove(perform: moveStops)
            }
            HStack {
                Button {
                    isPresentingAddStop = true
                } label: {
                    Label("Add Stop", systemImage: "plus")
                }
                Spacer()
                if locatableStopCount > 1 {
                    Button {
                        optimizeOrder()
                    } label: {
                        Label("Optimize", systemImage: "arrow.triangle.swap")
                    }
                    .font(.caption)
                }
            }
        } header: {
            Text(day.date.formatted(date: .abbreviated, time: .omitted))
        }
        .sheet(isPresented: $isPresentingAddStop) {
            AddStopView(day: day)
        }
    }

    private var locatableStopCount: Int {
        stops.filter { $0.hasCoordinate }.count
    }

    private func deleteStops(at offsets: IndexSet) {
        let stopsToDelete = offsets.map { stops[$0] }
        for stop in stopsToDelete {
            modelContext.delete(stop)
        }
        reindexSortOrder()
    }

    private func moveStops(from source: IndexSet, to destination: Int) {
        var reordered = stops
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, stop) in reordered.enumerated() {
            stop.sortOrder = index
        }
    }

    private func reindexSortOrder() {
        for (index, stop) in stops.enumerated() {
            stop.sortOrder = index
        }
    }

    private func optimizeOrder() {
        let optimized = RouteOptimizer.optimizedOrder(for: stops)
        for (index, stop) in optimized.enumerated() {
            stop.sortOrder = index
        }
    }
}

private struct StopRow: View {
    let stop: Stop
    let walkingTimeToNext: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon(for: stop.category))
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.interactive(), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.name).font(.body)
                    if let time = stop.plannedTime {
                        Text(time.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let walkingTimeToNext {
                Label("\(Int((walkingTimeToNext / 60).rounded())) min walk to next stop", systemImage: "figure.walk")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 36)
            }
        }
    }

    private func icon(for category: StopCategory) -> String {
        switch category {
        case .food: return "fork.knife"
        case .sight: return "camera"
        case .activity: return "figure.walk"
        }
    }
}
