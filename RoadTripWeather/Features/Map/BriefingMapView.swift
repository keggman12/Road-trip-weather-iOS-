import MapKit
import RoadTripCore
import SwiftUI

/// Temperature-coloured route segments, weather pins (temp, icon, wind
/// arrow, ☾, alert ring), dimmed alternates and POI pins (web
/// `drawAllBriefings` + `makeMarker` + POI layers).
struct BriefingMapView: View {
    let briefing: Briefing
    let dimmed: [Briefing]
    let scale: TemperatureScale
    let pois: [POIKind: [POI]]
    let onPOITap: (POI) -> Void

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(dimmed, id: \.id) { alt in
                ForEach(segments(of: alt), id: \.index) { seg in
                    MapPolyline(coordinates: seg.coords.map(\.clLocationCoordinate))
                        .stroke(seg.color.opacity(0.5), style: StrokeStyle(lineWidth: 4, dash: [2, 6]))
                }
            }
            ForEach(segments(of: briefing), id: \.index) { seg in
                MapPolyline(coordinates: seg.coords.map(\.clLocationCoordinate))
                    .stroke(seg.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
            ForEach(pois.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { kind in
                ForEach(pois[kind] ?? []) { poi in
                    Annotation(poi.name, coordinate: poi.coordinate.clLocationCoordinate, anchor: .center) {
                        Button { onPOITap(poi) } label: {
                            Text(kind.pinLetter)
                                .font(.caption2.weight(.heavy))
                                .frame(width: 18, height: 18)
                                .background(Theme.poiColor(kind), in: Circle())
                                .foregroundStyle(.black)
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
            ForEach(Array(briefing.stops.enumerated()), id: \.element.id) { i, stop in
                Annotation(stop.label, coordinate: stop.coordinate.clLocationCoordinate, anchor: .bottom) {
                    StopPin(stop: stop, isEndpoint: i == 0 || i == briefing.stops.count - 1, scale: scale)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
    }

    struct Segment {
        var index: Int
        var coords: [Coordinate]
        var color: Color
    }

    /// Web `drawColoredRoute`.
    func segments(of b: Briefing) -> [Segment] {
        zip(b.stops, b.stops.dropFirst()).enumerated().map { i, pair in
            let (a, c) = pair
            let avg = TemperatureScale.segmentTemperature(a.weather.map { Double($0.temperatureF) }, c.weather.map { Double($0.temperatureF) })
            return Segment(index: i, coords: BriefingMapper.segmentCoordinates(b.geometry.coordinates, from: a, to: c), color: Color(hex: scale.colorHex(forTemperatureF: avg)))
        }
    }
}

struct StopPin: View {
    let stop: Stop
    let isEndpoint: Bool
    let scale: TemperatureScale

    var body: some View {
        let color = Color(hex: scale.colorHex(forTemperatureF: stop.weather.map { Double($0.temperatureF) }))
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                Image(systemName: stop.weather?.category.symbolName ?? "questionmark")
                    .font(.caption2)
                Text(stop.weather.map { "\($0.temperatureF)°" } ?? "n/a")
                    .font(.caption.monospacedDigit().weight(.bold))
                if let deg = stop.weather?.windFromDegrees {
                    Image(systemName: "arrow.down")
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(Double(Wind.arrowRotation(windFrom: deg))))
                        .foregroundStyle(Theme.accent)
                }
                if stop.isOvernight { Text("☾").font(.caption2) }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Theme.surface, in: Capsule())
            .overlay(Capsule().stroke(stop.alerts.isEmpty ? color : Theme.danger, lineWidth: stop.alerts.isEmpty ? 1.5 : 2.5))
            .overlay(alignment: .topTrailing) {
                if !stop.alerts.isEmpty {
                    Circle().fill(Theme.danger).frame(width: 8, height: 8).offset(x: 3, y: -3)
                }
            }
            Triangle().fill(color).frame(width: 8, height: 5)
        }
        .foregroundStyle(Theme.text)
        .scaleEffect(isEndpoint ? 1.1 : 1)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
