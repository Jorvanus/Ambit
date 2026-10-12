import CoreLocation
import MapKit
import SwiftData
import SwiftUI

@Observable
@MainActor
private final class ImportModel {
    enum Stage { case input, reading, review }
    enum Source: String, CaseIterable { case text = "Text", link = "Link" }

    var stage = Stage.input
    var source = Source.text
    var text = ""
    var urlText = ""
    var errorMessage: String?
    var draft = ItineraryDraft()
    var startDate = Calendar.current.startOfDay(for: Date())
    private var geocodeTask: Task<Void, Never>?

    func read() {
        errorMessage = nil
        // Pasting a lone link into the text box should just work.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if source == .text, !trimmed.contains(where: \.isWhitespace), trimmed.lowercased().hasPrefix("http") {
            urlText = trimmed
            source = .link
        }

        stage = .reading
        let pastedText = text
        let link = urlText
        let fromLink = source == .link
        Task {
            do {
                draft = fromLink
                    ? try await ItineraryPageImporter.load(link)
                    : await ItineraryExtractor.extract(from: pastedText)
                stage = .review
                locateAll()
            } catch {
                errorMessage = error.localizedDescription
                stage = .input
            }
        }
    }

    func cancel() {
        geocodeTask?.cancel()
    }

    /// Geocodes every stop that isn't already placed. Stops are looked up by id each
    /// time because the user can delete or rename rows while this runs.
    func locateAll(force: Bool = false) {
        geocodeTask?.cancel()
        if force {
            for dayIndex in draft.days.indices {
                for stopIndex in draft.days[dayIndex].stops.indices {
                    draft.days[dayIndex].stops[stopIndex].locateState = .pending
                }
            }
        }
        let targets = draft.days.flatMap(\.stops).filter { $0.locateState != .found }.map(\.id)
        let destination = draft.destination
        geocodeTask = Task {
            for id in targets {
                guard !Task.isCancelled else { return }
                guard let name = stop(id)?.name else { continue }
                update(id) { $0.locateState = .locating }
                let coordinate = await StopGeocoder.geocode(name: name, near: destination)
                guard !Task.isCancelled else { return }
                update(id) {
                    $0.latitude = coordinate?.latitude
                    $0.longitude = coordinate?.longitude
                    $0.locateState = coordinate == nil ? .notFound : .found
                }
            }
            flagOutliers()
        }
    }

    func relocate(_ id: UUID) {
        let destination = draft.destination
        guard let name = stop(id)?.name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        update(id) { $0.locateState = .locating }
        Task {
            let coordinate = await StopGeocoder.geocode(name: name, near: destination)
            update(id) {
                $0.latitude = coordinate?.latitude
                $0.longitude = coordinate?.longitude
                $0.locateState = coordinate == nil ? .notFound : .found
            }
            flagOutliers()
        }
    }

    func stop(_ id: UUID) -> DraftStop? {
        draft.days.lazy.flatMap(\.stops).first { $0.id == id }
    }

    func update(_ id: UUID, _ change: (inout DraftStop) -> Void) {
        for dayIndex in draft.days.indices {
            if let stopIndex = draft.days[dayIndex].stops.firstIndex(where: { $0.id == id }) {
                change(&draft.days[dayIndex].stops[stopIndex])
                return
            }
        }
    }

    func remove(_ ids: [UUID]) {
        for dayIndex in draft.days.indices {
            draft.days[dayIndex].stops.removeAll { ids.contains($0.id) }
        }
        flagOutliers()
    }

    /// Geocoding can land a same-named place in a distant suburb. Flag anything far
    /// from the middle of the other stops so the user checks it.
    private func flagOutliers() {
        let located = draft.days.flatMap(\.stops).compactMap { stop -> (UUID, CLLocation)? in
            guard let lat = stop.latitude, let lon = stop.longitude else { return nil }
            return (stop.id, CLLocation(latitude: lat, longitude: lon))
        }
        let center = located.count >= 3
            ? CLLocation(
                latitude: located.map { $0.1.coordinate.latitude }.sorted()[located.count / 2],
                longitude: located.map { $0.1.coordinate.longitude }.sorted()[located.count / 2]
            )
            : nil
        let far = Set(located.filter { center != nil && $0.1.distance(from: center!) > 40_000 }.map(\.0))
        for dayIndex in draft.days.indices {
            for stopIndex in draft.days[dayIndex].stops.indices {
                let id = draft.days[dayIndex].stops[stopIndex].id
                draft.days[dayIndex].stops[stopIndex].isFarFromOthers = far.contains(id)
            }
        }
    }

    @discardableResult
    func makeTrip(in context: ModelContext, calendar: Calendar = .current) -> Trip {
        let first = calendar.startOfDay(for: startDate)
        let dayCount = max(draft.days.count, 1)
        let last = calendar.date(byAdding: .day, value: dayCount - 1, to: first) ?? first
        let trip = Trip(
            name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
            destination: draft.destination.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: first,
            endDate: last
        )
        context.insert(trip)

        for (dayIndex, draftDay) in draft.days.enumerated() {
            let date = calendar.date(byAdding: .day, value: dayIndex, to: first) ?? first
            let day = Day(date: date)
            context.insert(day)
            day.trip = trip

            for (order, draftStop) in draftDay.stops.enumerated() {
                var plannedTime: Date?
                if let hour = draftStop.hour, let minute = draftStop.minute {
                    plannedTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)
                }
                let stop = Stop(
                    name: draftStop.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    category: draftStop.category,
                    latitude: draftStop.latitude ?? 0,
                    longitude: draftStop.longitude ?? 0,
                    plannedTime: plannedTime,
                    notes: draftStop.notes,
                    sortOrder: order
                )
                context.insert(stop)
                stop.day = day
            }
        }
        return trip
    }
}

struct ImportItineraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var model = ImportModel()
    @State private var mapPosition: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            Group {
                switch model.stage {
                case .input: inputStage
                case .reading: readingStage
                case .review: reviewStage
                }
            }
            .navigationTitle("Import Itinerary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancel()
                        dismiss()
                    }
                }
                if model.stage == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create Trip") {
                            model.cancel()
                            model.makeTrip(in: modelContext)
                            dismiss()
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(
                            model.draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                                || model.draft.stopCount == 0
                        )
                    }
                }
            }
        }
    }

    // MARK: Stages

    private var inputStage: some View {
        Form {
            Section {
                Picker("Source", selection: $model.source) {
                    ForEach(ImportModel.Source.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if model.source == .text {
                Section {
                    TextEditor(text: $model.text)
                        .frame(minHeight: 220)
                        .overlay(alignment: .topLeading) {
                            if model.text.isEmpty {
                                Text("Paste an itinerary, e.g.\nDay 1\n9:00 Story Bridge\n12:30 Lunch at Howard Smith Wharves")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    PasteButton(payloadType: String.self) { strings in
                        if let pasted = strings.first { model.text = pasted }
                    }
                } header: {
                    Text("Itinerary text")
                } footer: {
                    Text("Text is read on this device. You'll review every stop before anything is saved.")
                }
            } else {
                Section {
                    TextField("https://example.com/3-days-in-lisbon", text: $model.urlText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { strings in
                        if let pasted = strings.first { model.urlText = pasted.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                } header: {
                    Text("Web page")
                } footer: {
                    Text("Ambit downloads the page without sending any cookies or account details, then reads it on this device. Pages that need a login or load their content with JavaScript can't be read; paste the text instead.")
                }
            }

            if let error = model.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(model.source == .link ? "Fetch & Read Page" : "Read Itinerary") { model.read() }
                    .disabled(readDisabled)
            }
        }
    }

    private var readDisabled: Bool {
        let value = model.source == .link ? model.urlText : model.text
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var readingStage: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(model.source == .link ? "Fetching and reading the page…" : "Reading your itinerary…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reviewStage: some View {
        Form {
            Section("Trip") {
                TextField("Name", text: $model.draft.name)
                TextField("Destination", text: $model.draft.destination)
                DatePicker("Starts", selection: $model.startDate, displayedComponents: .date)
                Button("Find places again near destination") { model.locateAll(force: true) }
                    .disabled(model.draft.stopCount == 0)
            }

            if let host = model.draft.sourceHost {
                Section {
                    Label("From \(host). Check each stop before creating the trip.", systemImage: "link")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let note = model.draft.note {
                Section {
                    Label(note, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            if model.draft.stopCount == 0 {
                Section {
                    ContentUnavailableView(
                        "No stops found",
                        systemImage: "text.magnifyingglass",
                        description: Text("Go back and try text with one stop per line, grouped under Day 1, Day 2…")
                    )
                }
            } else {
                Section("Map check") { reviewMap }
            }

            ForEach($model.draft.days) { $day in
                Section(day.title) {
                    ForEach(day.stops) { stop in
                        row(for: stop.id)
                    }
                    .onDelete { offsets in
                        model.remove(offsets.map { day.stops[$0].id })
                    }
                }
            }
        }
    }

    private var reviewMap: some View {
        let located = model.draft.days.flatMap(\.stops).filter { $0.latitude != nil }
        return Map(position: $mapPosition) {
            ForEach(located) { stop in
                Marker(
                    stop.name,
                    coordinate: CLLocationCoordinate2D(latitude: stop.latitude ?? 0, longitude: stop.longitude ?? 0)
                )
                .tint(stop.isFarFromOthers ? .red : .blue)
            }
        }
        .frame(height: 200)
        .listRowInsets(EdgeInsets())
        // The map is built before geocoding finishes, so refit as pins arrive.
        .onChange(of: located.count) { fitMap(to: located) }
        .onAppear { fitMap(to: located) }
    }

    private func fitMap(to stops: [DraftStop]) {
        let points = stops.compactMap { stop -> MKMapPoint? in
            guard let lat = stop.latitude, let lon = stop.longitude else { return nil }
            return MKMapPoint(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        guard let first = points.first else { return }
        let rect = points.dropFirst().reduce(MKMapRect(origin: first, size: MKMapSize(width: 0, height: 0))) {
            $0.union(MKMapRect(origin: $1, size: MKMapSize(width: 0, height: 0)))
        }
        // Pad so edge pins aren't clipped, with a floor so a single stop isn't zoomed in absurdly far.
        let padded = rect.insetBy(dx: -max(rect.width * 0.25, 4000), dy: -max(rect.height * 0.25, 4000))
        mapPosition = .rect(padded)
    }

    private func row(for id: UUID) -> some View {
        let binding = Binding<String>(
            get: { model.stop(id)?.name ?? "" },
            set: { newValue in model.update(id) { $0.name = newValue } }
        )
        let stop = model.stop(id)
        return VStack(alignment: .leading, spacing: 4) {
            TextField("Stop name", text: binding)
                .onSubmit { model.relocate(id) }
            HStack(spacing: 8) {
                if let time = stop?.timeLabel {
                    Label(time, systemImage: "clock")
                }
                switch stop?.locateState {
                case .locating, .pending:
                    ProgressView().controlSize(.mini)
                case .found:
                    if stop?.isFarFromOthers == true {
                        Label("Far from the other stops, check it", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    } else {
                        Label("Located", systemImage: "mappin.circle.fill").foregroundStyle(.green)
                    }
                case .notFound:
                    Label("Not found", systemImage: "questionmark.circle").foregroundStyle(.orange)
                case nil:
                    EmptyView()
                }
                if let notes = stop?.notes, !notes.isEmpty {
                    Text(notes).lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
