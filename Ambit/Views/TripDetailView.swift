import SwiftUI
import SwiftData

private enum TripTab: String, CaseIterable, Identifiable {
    case itinerary = "Itinerary"
    case map = "Map"
    case budget = "Budget"

    var id: String { rawValue }
}

struct TripDetailView: View {
    @Bindable var trip: Trip

    @State private var tab: TripTab = .itinerary
    @State private var isPresentingEditTrip = false

    private var sortedDays: [Day] {
        trip.days.sorted { $0.date < $1.date }
    }

    var body: some View {
        Group {
            switch tab {
            case .itinerary:
                List {
                    PlacesSection(trip: trip)
                    ForEach(sortedDays) { day in
                        DaySection(trip: trip, day: day)
                    }
                }
            case .map:
                TripMapView(trip: trip)
            case .budget:
                TripBudgetView(trip: trip)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Section", selection: $tab) {
                ForEach(TripTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle(trip.name)
        .navigationSubtitle(trip.destination)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingEditTrip = true
                } label: {
                    Label("Edit Trip", systemImage: "pencil")
                }
            }
            if tab == .itinerary {
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $isPresentingEditTrip) {
            TripFormView(existingTrip: trip)
        }
    }
}

private struct PlacesSection: View {
    @Bindable var trip: Trip

    @Environment(\.modelContext) private var modelContext
    @State private var isPresentingAdd = false
    @State private var editingStop: Stop?

    private var places: [Stop] {
        trip.savedPlaces.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Section {
            if places.isEmpty {
                Text("Save places now, schedule them on a day later.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(places) { place in
                    StopRow(stop: place, walkingTimeToNext: nil)
                        .contentShape(Rectangle())
                        .onTapGesture { editingStop = place }
                }
                .onDelete { offsets in
                    for place in offsets.map({ places[$0] }) {
                        modelContext.delete(place)
                    }
                }
            }
            Button {
                isPresentingAdd = true
            } label: {
                Label("Add Place", systemImage: "plus")
            }
        } header: {
            Label("Places to visit", systemImage: "bookmark")
        }
        .sheet(isPresented: $isPresentingAdd) {
            StopFormView(trip: trip)
        }
        .sheet(item: $editingStop) { place in
            StopFormView(trip: trip, existingStop: place)
        }
    }
}

private struct DaySection: View {
    let trip: Trip
    @Bindable var day: Day

    @Environment(\.modelContext) private var modelContext
    @State private var isPresentingAddStop = false
    @State private var editingStop: Stop?
    @State private var legs: [UUID: WalkingLeg] = [:]

    private var stops: [Stop] {
        day.stops.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Identifies the current stop order + coordinates, so walking times
    /// are refetched when either changes but not on every unrelated redraw.
    private var routeSignature: [String] {
        stops.map { "\($0.id)|\($0.latitude)|\($0.longitude)" }
    }

    private func walkingTime(after index: Int) -> TimeInterval? {
        guard index < stops.count - 1 else { return nil }
        let stop = stops[index]
        return legs[stop.id]?.time ?? RouteOptimizer.walkingTime(from: stop, to: stops[index + 1])
    }

    private var summary: String {
        var parts = ["\(stops.count) \(stops.count == 1 ? "stop" : "stops")"]
        var time: TimeInterval = 0
        var distance: Double = 0
        var hasLegs = false
        for index in 0..<max(0, stops.count - 1) {
            let from = stops[index]
            let to = stops[index + 1]
            guard from.hasCoordinate, to.hasCoordinate else { continue }
            hasLegs = true
            if let leg = legs[from.id] {
                time += leg.time
                distance += leg.distance
            } else {
                time += RouteOptimizer.walkingTime(from: from, to: to) ?? 0
                distance += from.location.distance(from: to.location)
            }
        }
        if hasLegs {
            parts.append("\(Int((time / 60).rounded())) min walking")
            parts.append(String(format: "%.1f km", distance / 1000))
        }
        let toBook = stops.filter { $0.bookingStatus == .required }.count
        if toBook > 0 {
            parts.append("\(toBook) to book")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Section {
            if stops.isEmpty {
                Text("No stops yet").foregroundStyle(.secondary)
            } else {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    StopRow(stop: stop, walkingTimeToNext: walkingTime(after: index))
                        .contentShape(Rectangle())
                        .onTapGesture { editingStop = stop }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(day.date.formatted(date: .abbreviated, time: .omitted))
                if !stops.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $isPresentingAddStop) {
            StopFormView(trip: trip, day: day)
        }
        .sheet(item: $editingStop) { stop in
            StopFormView(trip: trip, day: day, existingStop: stop)
        }
        .task(id: routeSignature) {
            await refreshLegs()
        }
    }

    private func refreshLegs() async {
        let currentStops = stops
        var results: [UUID: WalkingLeg] = [:]
        for index in 0..<max(0, currentStops.count - 1) {
            let from = currentStops[index]
            let to = currentStops[index + 1]
            guard from.hasCoordinate, to.hasCoordinate else { continue }
            if let leg = await DirectionsService.walkingLeg(from: from.coordinate, to: to.coordinate) {
                results[from.id] = leg
            }
        }
        legs = results
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
                Spacer()
                if stop.bookingStatus != .none {
                    Image(systemName: stop.bookingStatus.icon)
                        .foregroundStyle(bookingColor(for: stop.bookingStatus))
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

    private func bookingColor(for status: BookingStatus) -> Color {
        switch status {
        case .none: return .clear
        case .required: return .orange
        case .booked: return .blue
        case .confirmed: return .green
        }
    }
}
