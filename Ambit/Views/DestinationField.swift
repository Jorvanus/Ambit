import CoreLocation
import MapKit
import SwiftUI

/// A destination chosen from Apple Maps: a city or suburb with a coordinate, not free text.
struct ResolvedPlace: Equatable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@MainActor
enum DestinationResolver {
    /// Turns a picked suggestion into a place with a canonical "City, Region" name.
    static func resolve(_ completion: MKLocalSearchCompletion) async -> ResolvedPlace? {
        let request = MKLocalSearch.Request(completion: completion)
        request.resultTypes = .address
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        return place(from: item, fallback: label(for: completion))
    }

    /// Best match for typed or extracted text, e.g. an imported itinerary's destination.
    static func resolve(text: String) async -> ResolvedPlace? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let request = MKGeocodingRequest(addressString: trimmed),
              let item = try? await request.mapItems.first else { return nil }
        return place(from: item, fallback: trimmed)
    }

    private static func place(from item: MKMapItem, fallback: String) -> ResolvedPlace {
        let coordinate = item.location.coordinate
        let context = item.addressRepresentations?.cityWithContext?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (context?.isEmpty == false ? context : nil) ?? fallback
        return ResolvedPlace(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    static func label(for completion: MKLocalSearchCompletion) -> String {
        completion.subtitle.isEmpty ? completion.title : "\(completion.title), \(completion.subtitle)"
    }
}

@MainActor
@Observable
private final class DestinationSearch: NSObject, MKLocalSearchCompleterDelegate {
    var suggestions: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func update(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.count < 2 {
            suggestions = []
            completer.cancel()
        } else {
            completer.queryFragment = trimmed
        }
    }

    func clear() {
        suggestions = []
        completer.cancel()
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Delegate callbacks arrive on the main thread.
        MainActor.assumeIsolated {
            // Address results also include streets and buildings. A city or suburb's subtitle is
            // just region and country ("QLD, Australia"); a street's starts with its suburb
            // ("East Brisbane, QLD, Australia"). Titles with numbers are addresses.
            suggestions = Array(self.completer.results.filter { result in
                !result.title.contains(where: \.isNumber)
                    && result.subtitle.split(separator: ",").count <= 2
            }.prefix(5))
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { suggestions = [] }
    }
}

/// Destination entry that must be completed by choosing a suggested city or suburb.
/// `place` is nil until one is chosen; typing again clears it.
struct DestinationField: View {
    @Binding var place: ResolvedPlace?
    var placeholder = "Destination"

    @State private var text: String
    @State private var search = DestinationSearch()
    @State private var isResolving = false
    @FocusState private var isFocused: Bool

    /// `initialText` seeds the box when there is no resolved place yet (older free-text trips
    /// and imported destinations are resolved by the caller).
    init(place: Binding<ResolvedPlace?>, initialText: String = "", placeholder: String = "Destination") {
        _place = place
        self.placeholder = placeholder
        _text = State(initialValue: place.wrappedValue?.name ?? initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField(placeholder, text: $text)
                    .focused($isFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                if isResolving {
                    ProgressView()
                } else if place != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        .accessibilityLabel("Destination found")
                }
            }

            if place == nil, !text.trimmingCharacters(in: .whitespaces).isEmpty, !isResolving {
                if search.suggestions.isEmpty {
                    if text.trimmingCharacters(in: .whitespaces).count >= 2 {
                        Text("Pick a city or suburb from the suggestions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                } else {
                    ForEach(search.suggestions, id: \.self) { suggestion in
                        Button {
                            choose(suggestion)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(suggestion.title).foregroundStyle(.primary)
                                if !suggestion.subtitle.isEmpty {
                                    Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
        .onChange(of: text) {
            // Editing after a pick means it's no longer the chosen place.
            if let place, text != place.name { self.place = nil }
            if place == nil { search.update(text) }
        }
        .onChange(of: place) {
            if let place, text != place.name { text = place.name }
        }
    }

    private func choose(_ suggestion: MKLocalSearchCompletion) {
        isResolving = true
        search.clear()
        Task {
            let resolved = await DestinationResolver.resolve(suggestion)
            isResolving = false
            if let resolved {
                place = resolved
                text = resolved.name
                isFocused = false
            } else {
                text = DestinationResolver.label(for: suggestion)
                search.update(text)
            }
        }
    }
}
