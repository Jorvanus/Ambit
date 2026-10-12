import MapKit
import SwiftUI

private struct MapRoutePair: Identifiable {
    let from: Stop
    let to: Stop

    var id: StopLegID { StopLegID(from: from, to: to) }
}

struct TripMapView: View {
    let trip: Trip
    @Binding var selectedDayID: UUID?
    @Binding var selectedStopID: UUID?

    @State private var position: MapCameraPosition = .automatic
    @State private var walkingRoutes: [StopLegID: WalkingLeg] = [:]

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

    private func routePairs(for day: Day) -> [MapRoutePair] {
        let stops = day.stops.sorted { $0.sortOrder < $1.sortOrder }
        return zip(stops, stops.dropFirst()).compactMap { from, to in
            guard from.hasCoordinate, to.hasCoordinate else { return nil }
            return MapRoutePair(from: from, to: to)
        }
    }

    private var visibleRoutePairs: [MapRoutePair] {
        visibleDays.flatMap(routePairs)
    }

    private var routeSignature: [String] {
        [selectedDayID?.uuidString ?? "all"] + visibleDays.flatMap { day in
            [day.id.uuidString] + day.stops.sorted { $0.sortOrder < $1.sortOrder }.map {
                "\($0.id)|\($0.latitude)|\($0.longitude)"
            }
        }
    }

    private var hasAnyLocation: Bool {
        days.contains { !located($0).isEmpty } || !trip.savedPlaces.filter(\.hasCoordinate).isEmpty
    }

    var body: some View {
        Map(position: $position, selection: $selectedStopID) {
            ForEach(visibleDays) { day in
                ForEach(routePairs(for: day).filter { walkingRoutes[$0.id]?.path.isEmpty == false }) { pair in
                    if let route = walkingRoutes[pair.id] {
                        MapPolyline(coordinates: route.path.map(\.coordinate))
                            .stroke(color(for: day), lineWidth: 4)
                    }
                }
                ForEach(routePairs(for: day).filter { walkingRoutes[$0.id]?.path.isEmpty != false }) { pair in
                    MapPolyline(coordinates: [pair.from.coordinate, pair.to.coordinate])
                        .stroke(color(for: day).opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                }
                ForEach(Array(day.stops.sorted { $0.sortOrder < $1.sortOrder }.enumerated()), id: \.element.id) { index, stop in
                    if stop.hasCoordinate {
                        Annotation(stop.name, coordinate: stop.coordinate) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: selectedStopID == stop.id ? 34 : 26, height: selectedStopID == stop.id ? 34 : 26)
                                .background(selectedStopID == stop.id ? Color.accentColor : color(for: day), in: .circle)
                                .overlay(Circle().stroke(.white, lineWidth: selectedStopID == stop.id ? 4 : 2))
                                .shadow(color: selectedStopID == stop.id ? .black.opacity(0.25) : .clear, radius: 5, y: 2)
                        }
                        .tag(stop.id)
                    }
                }
            }
            ForEach(savedPlaces) { place in
                Marker(place.name, systemImage: "bookmark.fill", coordinate: place.coordinate)
                    .tint(.gray)
                    .tag(place.id)
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
            ScrollView(.horizontal) {
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
            .scrollIndicators(.hidden, axes: .horizontal)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if visibleRoutePairs.contains(where: { walkingRoutes[$0.id]?.path.isEmpty != false }) {
                Text("Dashed lines are approximate while walking routes load or are unavailable.")
                    .font(.caption)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
            }
        }
        .task(id: routeSignature) {
            await refreshWalkingRoutes()
        }
        .onChange(of: selectedDayID) {
            position = .automatic
        }
    }

    private func refreshWalkingRoutes() async {
        walkingRoutes = [:]
        for pair in visibleRoutePairs {
            let route = await DirectionsService.walkingLeg(from: pair.from.coordinate, to: pair.to.coordinate)
            guard !Task.isCancelled else { return }
            if let route {
                walkingRoutes[pair.id] = route
            }
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
