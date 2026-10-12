import SwiftUI
import SwiftData
import UIKit

private enum TripTab: String, CaseIterable, Identifiable {
    case itinerary = "Itinerary"
    case map = "Map"
    case budget = "Budget"

    var id: String { rawValue }
}

private enum TripSheet: Identifiable {
    case newStop(Day?)
    case editStop(Stop)

    var id: String {
        switch self {
        case .newStop(let day): return "new-\(day?.id.uuidString ?? "pool")"
        case .editStop(let stop): return "edit-\(stop.id.uuidString)"
        }
    }
}

enum TripDaySelection {
    static func preferredDayID(
        in days: [Day],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> UUID? {
        let ordered = days.sorted { $0.date < $1.date }
        let today = calendar.startOfDay(for: now)
        return ordered.first { calendar.isDate($0.date, inSameDayAs: now) }?.id
            ?? ordered.first { calendar.startOfDay(for: $0.date) > today }?.id
            ?? ordered.last?.id
    }
}

struct TripDetailView: View {
    @Bindable var trip: Trip

    @State private var tab: TripTab = .itinerary
    @State private var selectedDayID: UUID?
    @State private var isPresentingEditTrip = false
    // Sheets live here, not on the list sections: a sheet attached inside a
    // List row is dismissed whenever that row re-renders (e.g. when walking
    // times arrive), which would wipe a half-filled form.
    @State private var sheet: TripSheet?

    private var sortedDays: [Day] {
        trip.days.sorted { $0.date < $1.date }
    }

    private var selectedDay: Day? {
        sortedDays.first { $0.id == selectedDayID }
    }

    init(trip: Trip) {
        self.trip = trip
        _selectedDayID = State(initialValue: TripDaySelection.preferredDayID(in: trip.days))
    }

    var body: some View {
        Group {
            switch tab {
            case .itinerary:
                List {
                    if let selectedDay {
                        DaySection(
                            day: selectedDay,
                            onAdd: { sheet = .newStop(selectedDay) },
                            onEdit: { sheet = .editStop($0) }
                        )
                        PlacesSection(
                            trip: trip,
                            onAdd: { sheet = .newStop(nil) },
                            onEdit: { sheet = .editStop($0) }
                        )
                    } else {
                        PlacesSection(
                            trip: trip,
                            onAdd: { sheet = .newStop(nil) },
                            onEdit: { sheet = .editStop($0) }
                        )
                        ForEach(sortedDays) { day in
                            DaySection(
                                day: day,
                                onAdd: { sheet = .newStop(day) },
                                onEdit: { sheet = .editStop($0) }
                            )
                        }
                    }
                }
            case .map:
                TripMapView(trip: trip, selectedDayID: $selectedDayID)
            case .budget:
                TripBudgetView(trip: trip)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                Picker("Section", selection: $tab) {
                    ForEach(TripTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                if tab == .itinerary, !sortedDays.isEmpty {
                    TripDayPicker(days: sortedDays, selectedDayID: $selectedDayID)
                }
            }
            .background(.regularMaterial)
        }
        .onChange(of: sortedDays.map(\.id)) { _, dayIDs in
            if let selectedDayID, !dayIDs.contains(selectedDayID) {
                self.selectedDayID = TripDaySelection.preferredDayID(in: sortedDays)
            }
        }
        .navigationTitle(trip.name)
        .navigationSubtitle(trip.destination)
        .navigationBarTitleDisplayMode(.inline)
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
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .newStop(let day):
                StopFormView(trip: trip, day: day)
            case .editStop(let stop):
                StopFormView(trip: trip, day: stop.day, existingStop: stop)
            }
        }
    }
}

private enum TripDayPickerID: Hashable {
    case all
    case day(UUID)
}

private struct TripDayPicker: View {
    let days: [Day]
    @Binding var selectedDayID: UUID?

    private var selectedPickerID: TripDayPickerID {
        selectedDayID.map(TripDayPickerID.day) ?? .all
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Button {
                        selectedDayID = nil
                    } label: {
                        dateLabel(top: "All", bottom: "days", isSelected: selectedDayID == nil)
                    }
                    .buttonStyle(.glass)
                    .tint(selectedDayID == nil ? .accentColor : nil)
                    .accessibilityLabel("All days")
                    .accessibilityAddTraits(selectedDayID == nil ? .isSelected : [])
                    .id(TripDayPickerID.all)

                    ForEach(days) { day in
                        let isSelected = selectedDayID == day.id
                        Button {
                            selectedDayID = day.id
                        } label: {
                            dateLabel(
                                top: Calendar.current.isDateInToday(day.date)
                                    ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)),
                                bottom: day.date.formatted(.dateTime.month(.abbreviated).day()),
                                isSelected: isSelected
                            )
                        }
                        .buttonStyle(.glass)
                        .tint(isSelected ? .accentColor : nil)
                        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(TripDayPickerID.day(day.id))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden, axes: .horizontal)
            .onAppear { proxy.scrollTo(selectedPickerID, anchor: .center) }
            .onChange(of: selectedDayID) { _, _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(selectedPickerID, anchor: .center)
                }
            }
        }
    }

    private func dateLabel(top: String, bottom: String, isSelected: Bool) -> some View {
        VStack(spacing: 2) {
            Text(top).font(.caption.weight(isSelected ? .bold : .medium))
            Text(bottom).font(.subheadline.weight(isSelected ? .semibold : .regular))
        }
        .frame(minWidth: 62)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct PlacesSection: View {
    @Bindable var trip: Trip
    let onAdd: () -> Void
    let onEdit: (Stop) -> Void

    @Environment(\.modelContext) private var modelContext

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
                    StopRow(stop: place, walkingTimeToNext: nil, timingConflict: nil) {
                        onEdit(place)
                    }
                }
                .onDelete { offsets in
                    for place in offsets.map({ places[$0] }) {
                        modelContext.delete(place)
                    }
                }
            }
            Button(action: onAdd) {
                Label("Add Place", systemImage: "plus")
            }
        } header: {
            Label("Places to visit", systemImage: "bookmark")
        }
    }
}

private struct DaySection: View {
    @Bindable var day: Day
    let onAdd: () -> Void
    let onEdit: (Stop) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var legs: [StopLegID: WalkingLeg] = [:]
    @State private var isOptimizing = false

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
        return legs[StopLegID(from: stop, to: stops[index + 1])]?.time
            ?? RouteOptimizer.walkingTime(from: stop, to: stops[index + 1])
    }

    private func isWalkingEstimate(after index: Int) -> Bool {
        guard index < stops.count - 1,
              stops[index].hasCoordinate, stops[index + 1].hasCoordinate else { return false }
        return legs[StopLegID(from: stops[index], to: stops[index + 1])] == nil
    }

    private var timingConflicts: [UUID: TimingConflict] {
        DaySchedule.conflicts(for: stops, on: day.date, walkingLegs: legs)
    }

    private var walkingSummary: String {
        if stops.isEmpty { return "No walking planned" }
        if stops.count == 1 { return "No walk between stops" }
        var time: TimeInterval = 0
        var distance: Double = 0
        var hasLegs = false
        var hasEstimatedLeg = false
        for index in 0..<max(0, stops.count - 1) {
            let from = stops[index]
            let to = stops[index + 1]
            guard from.hasCoordinate, to.hasCoordinate else { continue }
            hasLegs = true
            if let leg = legs[StopLegID(from: from, to: to)] {
                time += leg.time
                distance += leg.distance
            } else {
                hasEstimatedLeg = true
                time += RouteOptimizer.walkingTime(from: from, to: to) ?? 0
                distance += from.location.distance(from: to.location)
            }
        }
        guard hasLegs else { return "Walking time unavailable" }
        let estimate = hasEstimatedLeg ? "About " : ""
        let minutes = Int((time / 60).rounded())
        return "\(estimate)\(minutes) min walking · \(String(format: "%.1f km", distance / 1000))"
    }

    private var bookingSummary: String {
        let count = stops.filter { $0.bookingStatus != .none }.count
        let required = stops.filter { $0.bookingStatus == .required }.count
        guard count > 0 else { return "No bookings" }
        let bookings = "\(count) \(count == 1 ? "booking" : "bookings")"
        return required > 0 ? "\(bookings), \(required) to book" : bookings
    }

    private var conflictSummary: String {
        let count = timingConflicts.count
        guard count > 0 else { return "No timing conflicts" }
        return "\(count) timing \(count == 1 ? "conflict" : "conflicts")"
    }

    var body: some View {
        Section {
            if stops.isEmpty {
                Text("No stops yet").foregroundStyle(.secondary)
            } else {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    StopRow(
                        stop: stop,
                        walkingTimeToNext: walkingTime(after: index),
                        isWalkingEstimate: isWalkingEstimate(after: index),
                        timingConflict: timingConflicts[stop.id]
                    ) {
                        onEdit(stop)
                    }
                }
                .onDelete(perform: deleteStops)
                .onMove(perform: moveStops)
            }
            HStack {
                Button(action: onAdd) {
                    Label("Add Stop", systemImage: "plus")
                }
                Spacer()
                if canOptimize {
                    Button {
                        Task { await optimizeOrder() }
                    } label: {
                        if isOptimizing {
                            ProgressView()
                                .accessibilityLabel("Optimizing walking order")
                        } else {
                            Label("Optimize untimed", systemImage: "arrow.triangle.swap")
                        }
                    }
                    .font(.caption)
                    .disabled(isOptimizing)
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 10) {
                Text(day.date.formatted(date: .complete, time: .omitted))
                    .font(.headline)
                    .textCase(nil)
                    .foregroundStyle(.primary)
                LazyVGrid(
                    columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    dayMetric("\(stops.count) \(stops.count == 1 ? "stop" : "stops")", systemImage: "mappin.and.ellipse")
                    dayMetric(walkingSummary, systemImage: "figure.walk")
                    dayMetric(bookingSummary, systemImage: "ticket")
                    dayMetric(
                        conflictSummary,
                        systemImage: timingConflicts.isEmpty ? "checkmark.circle" : "exclamationmark.triangle.fill",
                        color: timingConflicts.isEmpty ? .secondary : .orange
                    )
                }
                .font(.subheadline)
                .textCase(nil)
            }
            .padding(.vertical, 6)
        }
        .headerProminence(.increased)
        .task(id: routeSignature) {
            await refreshLegs()
        }
    }

    private func dayMetric(_ title: String, systemImage: String, color: Color = .primary) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
        }

    private func refreshLegs() async {
        let currentStops = stops
        legs = [:]
        var results: [StopLegID: WalkingLeg] = [:]
        for index in 0..<max(0, currentStops.count - 1) {
            let from = currentStops[index]
            let to = currentStops[index + 1]
            guard from.hasCoordinate, to.hasCoordinate else { continue }
            if let leg = await DirectionsService.walkingLeg(from: from.coordinate, to: to.coordinate) {
                results[StopLegID(from: from, to: to)] = leg
            }
        }
        if !Task.isCancelled {
            legs = results
        }
    }

    private var canOptimize: Bool {
        var untimedCount = 0
        for stop in stops {
            if stop.plannedTime != nil {
                if untimedCount > 1 { return true }
                untimedCount = 0
            } else if stop.hasCoordinate {
                untimedCount += 1
            }
        }
        return untimedCount > 1
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

    private func optimizeOrder() async {
        let original = stops
        isOptimizing = true
        defer { isOptimizing = false }
        let optimized = await RouteOptimizer.optimizedOrder(for: original)
        let current = stops
        guard current.count == original.count,
              zip(current, original).allSatisfy({ now, before in
                  now.id == before.id && now.plannedTime == before.plannedTime
                      && now.latitude == before.latitude && now.longitude == before.longitude
              }) else { return }
        for (index, stop) in optimized.enumerated() {
            stop.sortOrder = index
        }
    }
}

private struct StopRow: View {
    let stop: Stop
    let walkingTimeToNext: TimeInterval?
    var isWalkingEstimate = false
    let timingConflict: TimingConflict?
    let onEdit: () -> Void

    private var bookingLink: URL? {
        guard let url = stop.bookingURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: onEdit) {
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
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(stop.name)")
                if stop.bookingStatus != .none {
                    Menu {
                        Text(stop.bookingStatus.label)
                        if let confirmation = stop.confirmationNumber, !confirmation.isEmpty {
                            Button("Copy confirmation number", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = confirmation
                            }
                            Text("Confirmation: \(confirmation)")
                        }
                        if let bookingLink {
                            Link(destination: bookingLink) {
                                Label("Open booking", systemImage: "arrow.up.forward.app")
                            }
                        }
                        Button("Edit booking", systemImage: "pencil", action: onEdit)
                    } label: {
                        Label("Booking", systemImage: stop.bookingStatus.icon)
                            .labelStyle(.iconOnly)
                            .foregroundStyle(bookingColor(for: stop.bookingStatus))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Booking for \(stop.name): \(stop.bookingStatus.label)")
                }
            }
            if let timingConflict {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Timing conflict: may be \(max(1, Int(ceil(timingConflict.lateBy / 60)))) min late")
                        .foregroundStyle(.primary)
                }
                .font(.footnote.weight(.medium))
                .padding(.leading, 36)
                .accessibilityElement(children: .combine)
            }
            if let walkingTimeToNext {
                Label("\(isWalkingEstimate ? "About " : "")\(Int((walkingTimeToNext / 60).rounded())) min walk to next stop", systemImage: "figure.walk")
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
