import MapKit
import SwiftUI

struct TripMapView: View {
    let trip: Trip

    @State private var selectedDayID: UUID?
    @State private var position: MapCameraPosition = .automatic

    private static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .red, .indigo]

    private var days: [Day] {
        trip.days.sorted { $0.date < $1.date }
    }

    private var visibleDays: [Day] {
        selectedDayID == nil ? days : days.filter { $0.id == selectedDayID }
    }

    private var savedPlaces: [Stop] {
        selectedDayID == nil ? trip.savedPlaces.filter(\.hasCoordinate) : []
    }

    private func color(for day: Day) -> Color {
        let index = days.firstIndex { $0.id == day.id } ?? 0
        return Self.palette[index % Self.palette.count]
    }

    private func located(_ day: Day) -> [Stop] {
        day.stops.sorted { $0.sortOrder < $1.sortOrder }.filter(\.hasCoordinate)
    }

    private var hasAnyLocation: Bool {
        days.contains { !located($0).isEmpty } || !trip.savedPlaces.filter(\.hasCoordinate).isEmpty
    }

    var body: some View {
        Map(position: $position) {
            ForEach(visibleDays) { day in
                if located(day).count > 1 {
                    MapPolyline(coordinates: located(day).map(\.coordinate))
                        .stroke(color(for: day), lineWidth: 4)
                }
                ForEach(Array(located(day).enumerated()), id: \.element.id) { index, stop in
                    Annotation(stop.name, coordinate: stop.coordinate) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(color(for: day), in: .circle)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            ForEach(savedPlaces) { place in
                Marker(place.name, systemImage: "bookmark.fill", coordinate: place.coordinate)
                    .tint(.gray)
            }
        }
        .overlay {
            if !hasAnyLocation {
                ContentUnavailableView(
                    "Nothing on the map yet",
                    systemImage: "map",
                    description: Text("Stops appear here once they've been found on the map.")
                )
                .background(.regularMaterial)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer {
                    HStack(spacing: 8) {
                        chip("All", dayID: nil, tint: .accentColor)
                        ForEach(days) { day in
                            chip(
                                day.date.formatted(.dateTime.month(.abbreviated).day()),
                                dayID: day.id,
                                tint: color(for: day)
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
        }
        .onChange(of: selectedDayID) {
            position = .automatic
        }
    }

    @ViewBuilder
    private func chip(_ title: String, dayID: UUID?, tint: Color) -> some View {
        Button(title) { selectedDayID = dayID }
            .buttonStyle(.glass)
            .tint(selectedDayID == dayID ? tint : nil)
            .font(.subheadline.weight(selectedDayID == dayID ? .bold : .regular))
    }
}
