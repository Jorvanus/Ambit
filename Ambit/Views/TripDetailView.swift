import SwiftUI
import SwiftData
import UIKit
import MapKit

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
    @State private var selectedStopID: UUID?
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
                ScrollViewReader { proxy in
                    List {
                        if let selectedDay {
                            DaySection(
                                day: selectedDay,
                                selectedStopID: $selectedStopID,
                                showsMapPreview: true,
                                onOpenMap: { tab = .map },
                                onAdd: { sheet = .newStop(selectedDay) },
                                onAddIdea: { sheet = .newStop(nil) },
                                onEdit: { sheet = .editStop($0) }
                            )
                            PlacesSection(
                                trip: trip,
                                selectedStopID: $selectedStopID,
                                showsEmptyAction: false,
                                onAdd: { sheet = .newStop(nil) },
                                onEdit: { sheet = .editStop($0) }
                            )
                        } else {
                            PlacesSection(
                                trip: trip,
                                selectedStopID: $selectedStopID,
                                showsEmptyAction: true,
                                onAdd: { sheet = .newStop(nil) },
                                onEdit: { sheet = .editStop($0) }
                            )
                            ForEach(sortedDays) { day in
                                DaySection(
                                    day: day,
                                    selectedStopID: $selectedStopID,
                                    showsMapPreview: false,
                                    onOpenMap: {},
                                    onAdd: { sheet = .newStop(day) },
                                    onAddIdea: { sheet = .newStop(nil) },
                                    onEdit: { sheet = .editStop($0) }
                                )
                            }
                        }
                    }
                    .onChange(of: selectedStopID) { _, stopID in
                        guard let stopID else { return }
                        withAnimation(.snappy) {
                            proxy.scrollTo(stopID, anchor: .center)
                        }
                    }
                    .onAppear {
                        if let selectedStopID {
                            proxy.scrollTo(selectedStopID, anchor: .center)
                        }
                    }
                }
            case .map:
                TripMapView(
                    trip: trip,
                    selectedDayID: $selectedDayID,
                    selectedStopID: $selectedStopID
                )
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
        .onChange(of: selectedDayID) {
            selectedStopID = nil
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
                HStack(spacing: 6) {
                    Button {
                        selectedDayID = nil
                    } label: {
                        dateLabel(top: "All", bottom: "days", isSelected: selectedDayID == nil)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
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
                        .controlSize(.small)
                        .tint(isSelected ? .accentColor : nil)
                        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(TripDayPickerID.day(day.id))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 2)
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
        VStack(spacing: 0) {
            Text(top).font(.caption2.weight(isSelected ? .bold : .medium))
            Text(bottom).font(.caption.weight(isSelected ? .semibold : .regular))
        }
        .frame(minWidth: 40)
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }
}

private struct DayMapPreview: View {
    let day: Day
    let selectedStopID: UUID?
    let onOpenMap: () -> Void

    @State private var position: MapCameraPosition = .automatic

    private var stops: [Stop] {
        day.stops.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var routeSignature: [String] {
        stops.map { "\($0.id)|\($0.latitude)|\($0.longitude)" }
    }

    private var hasMappedStops: Bool {
        stops.contains(where: \.hasCoordinate)
    }

    var body: some View {
        Button(action: onOpenMap) {
            ZStack(alignment: .bottomTrailing) {
                Map(position: $position) {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        if stop.hasCoordinate {
                            Annotation(stop.name, coordinate: stop.coordinate) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(
                                        selectedStopID == stop.id ? Color.accentColor : Color.blue,
                                        in: Circle()
                                    )
                                    .overlay(Circle().stroke(.white, lineWidth: selectedStopID == stop.id ? 4 : 2))
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                }
                .allowsHitTesting(false)

                if !hasMappedStops {
                    Label("No mapped stops yet", systemImage: "map")
                        .font(.subheadline.weight(.medium))
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.regularMaterial)
                }

                Label("Open full map", systemImage: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 142)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map preview for \(day.date.formatted(date: .complete, time: .omitted))")
        .accessibilityHint("Opens the full map for this day")
        .onChange(of: routeSignature) { _, _ in position = .automatic }
    }
}

private struct PlacesSection: View {
    @Bindable var trip: Trip
    @Binding var selectedStopID: UUID?
    let showsEmptyAction: Bool
    let onAdd: () -> Void
    let onEdit: (Stop) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var isExpanded = true

    private var places: [Stop] {
        trip.savedPlaces.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        if places.isEmpty && !showsEmptyAction {
            EmptyView()
        } else {
            Section {
                if places.isEmpty {
                    Button(action: onAdd) {
                        Label("Add idea", systemImage: "plus")
                    }
                } else if isExpanded {
                ForEach(Array(places.enumerated()), id: \.element.id) { _, place in
                    HStack(spacing: 10) {
                        StopRow(
                            number: nil,
                            stop: place,
                            timingConflict: nil,
                            isHighlighted: selectedStopID == place.id,
                            onEdit: { onEdit(place) }
                        )
                        Menu {
                            ForEach(trip.days.sorted { $0.date < $1.date }) { day in
                                Button(day.date.formatted(date: .abbreviated, time: .omitted)) {
                                    move(place, to: day)
                                }
                            }
                        } label: {
                            Label("Add to day", systemImage: "calendar.badge.plus")
                                .font(.caption.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .fixedSize()
                        }
                        .accessibilityHint("Choose a day for this saved place")
                    }
                    .id(place.id)
                }
                .onDelete { offsets in
                    for place in offsets.map({ places[$0] }) {
                        modelContext.delete(place)
                    }
                }
                    Button(action: onAdd) {
                        Label("Add idea", systemImage: "plus")
                    }
                }
            }
            header: {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack {
                        Label("Ideas", systemImage: "lightbulb")
                        Text("\(places.count)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            }
        }
    }

    private func move(_ place: Stop, to day: Day) {
        place.poolTrip = nil
        place.sortOrder = (day.stops.map(\.sortOrder).max() ?? -1) + 1
        place.day = day
    }
}

private struct DaySection: View {
    @Bindable var day: Day
    @Binding var selectedStopID: UUID?
    let showsMapPreview: Bool
    let onOpenMap: () -> Void
    let onAdd: () -> Void
    let onAddIdea: () -> Void
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
            if showsMapPreview {
                DayMapPreview(day: day, selectedStopID: selectedStopID, onOpenMap: onOpenMap)
                    .id("map-preview-\(day.id)")
            }
            if stops.isEmpty {
                Text("No stops yet").foregroundStyle(.secondary)
            } else {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    VStack(spacing: 0) {
                        StopRow(
                            number: index + 1,
                            stop: stop,
                            timingConflict: timingConflicts[stop.id],
                            isHighlighted: selectedStopID == stop.id,
                            onEdit: { onEdit(stop) }
                        )
                        .id(stop.id)
                        if index < stops.count - 1 {
                            WalkingLegRow(
                                from: stop,
                                to: stops[index + 1],
                                walkingTime: walkingTime(after: index),
                                isEstimate: isWalkingEstimate(after: index)
                            )
                            .padding(.top, 10)
                        }
                    }
                }
                .onDelete(perform: deleteStops)
                .onMove(perform: moveStops)
            }
            HStack {
                Button(action: onAdd) {
                    Label("Add Stop", systemImage: "plus")
                }
                Button(action: onAddIdea) {
                    Label("Add idea", systemImage: "lightbulb")
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
    let number: Int?
    let stop: Stop
    let timingConflict: TimingConflict?
    var isHighlighted = false
    let onEdit: () -> Void

    private var bookingLink: URL? {
        guard let url = stop.bookingURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let number {
                    Text("\(number)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor, in: Circle())
                        .accessibilityLabel("Stop \(number)")
                } else {
                    Image(systemName: icon(for: stop.category))
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular, in: .circle)
                        .accessibilityHidden(true)
                }

                Button(action: onEdit) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stop.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let plannedTime = stop.plannedTime {
                            Label(plannedTime.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                                .font(.subheadline)
                        } else if number != nil {
                            Label("Time not set", systemImage: "clock")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Label("Saved place", systemImage: "bookmark")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(stop.name)")
            }

            HStack(spacing: 8) {
                bookingStatusMenu
                Spacer(minLength: 8)
                bookingAction
            }

            if let timingConflict {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Timing conflict: may be \(max(1, Int(ceil(timingConflict.lateBy / 60)))) min late")
                        .foregroundStyle(.primary)
                }
                .font(.footnote.weight(.medium))
                .padding(.leading, 44)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(isHighlighted ? 8 : 0)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                    }
            }
        }
    }

    private var bookingStatusMenu: some View {
        Menu {
            Text(stop.bookingStatus.label)
            if let confirmation = stop.confirmationNumber, !confirmation.isEmpty {
                Button("Copy confirmation number", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = confirmation
                }
                Text("Confirmation: \(confirmation)")
            }
            Button("Edit booking details", systemImage: "pencil", action: onEdit)
        } label: {
            Label(bookingStatusTitle, systemImage: stop.bookingStatus.icon.isEmpty ? "calendar" : stop.bookingStatus.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(bookingColor(for: stop.bookingStatus))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(bookingColor(for: stop.bookingStatus).opacity(0.12), in: Capsule())
        }
        .accessibilityLabel("Booking status for \(stop.name): \(bookingStatusTitle)")
    }

    @ViewBuilder
    private var bookingAction: some View {
        if let bookingLink {
            Link(destination: bookingLink) {
                Label("Open booking", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button(action: onEdit) {
                Label(bookingActionTitle, systemImage: "ticket")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var bookingStatusTitle: String {
        stop.bookingStatus == .none ? "No booking" : stop.bookingStatus.label
    }

    private var bookingActionTitle: String {
        switch stop.bookingStatus {
        case .none: return "Add booking"
        case .required: return "Add booking details"
        case .booked, .confirmed: return "Booking details"
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
        case .none: return .secondary
        case .required: return .orange
        case .booked: return .blue
        case .confirmed: return .green
        }
    }
}

private struct WalkingLegRow: View {
    let from: Stop
    let to: Stop
    let walkingTime: TimeInterval?
    let isEstimate: Bool

    private var directionsURL: URL? {
        guard from.hasCoordinate, to.hasCoordinate else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.queryItems = [
            URLQueryItem(name: "saddr", value: "\(from.latitude),\(from.longitude)"),
            URLQueryItem(name: "daddr", value: "\(to.latitude),\(to.longitude)"),
            URLQueryItem(name: "dirflg", value: "w")
        ]
        return components.url
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(.quaternary)
                .frame(width: 2, height: 30)
                .padding(.leading, 14)

            Label(walkingTitle, systemImage: "figure.walk")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            if let directionsURL {
                Link(destination: directionsURL) {
                    Label("Directions", systemImage: "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Walking directions from \(from.name) to \(to.name)")
            }
        }
        .padding(.vertical, 3)
    }

    private var walkingTitle: String {
        guard let walkingTime else { return "Walking time unavailable" }
        let estimate = isEstimate ? "About " : ""
        return "\(estimate)\(Int((walkingTime / 60).rounded())) min walk"
    }
}
