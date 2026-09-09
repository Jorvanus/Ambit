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
                Section(day.date.formatted(date: .abbreviated, time: .omitted)) {
                    let stops = day.stops.sorted { $0.sortOrder < $1.sortOrder }
                    if stops.isEmpty {
                        Text("No stops yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(stops) { stop in
                            StopRow(stop: stop)
                        }
                    }
                }
            }
        }
        .navigationTitle(trip.name)
    }
}

private struct StopRow: View {
    let stop: Stop

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: icon(for: stop.category))
                Text(stop.name).font(.body)
            }
            if let time = stop.plannedTime {
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
