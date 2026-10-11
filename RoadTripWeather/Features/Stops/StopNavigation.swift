import MapKit
import RoadTripCore
import SwiftUI
import UIKit

/// Hands a stop to Apple Maps or Waze for turn-by-turn directions.
@MainActor
enum StopNavigator {
    static func mapItem(for stop: Stop) -> MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate.clLocationCoordinate))
        item.name = stop.label
        return item
    }

    static func openInAppleMaps(_ stop: Stop) {
        mapItem(for: stop).openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    /// The Waze app when installed (`waze` is in LSApplicationQueriesSchemes),
    /// else the web link, which also opens the app or the App Store page.
    static func wazeURL(for stop: Stop, wazeInstalled: Bool) -> URL? {
        wazeInstalled ? NavigationLinks.wazeApp(stop.coordinate) : NavigationLinks.wazeWeb(stop.coordinate)
    }

    static var wazeInstalled: Bool {
        NavigationLinks.wazeApp(Coordinate(lat: 0, lon: 0)).map { UIApplication.shared.canOpenURL($0) } ?? false
    }
}

/// "Navigate" menu on a stop card.
struct NavigateMenu: View {
    let stop: Stop
    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            Button { StopNavigator.openInAppleMaps(stop) } label: { Label("Apple Maps", systemImage: "map") }
            Button {
                if let url = StopNavigator.wazeURL(for: stop, wazeInstalled: StopNavigator.wazeInstalled) { openURL(url) }
            } label: { Label("Waze", systemImage: "car") }
        } label: {
            Image(systemName: "arrow.triangle.turn.up.right.circle")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("Navigate to \(stop.label)")
        }
    }
}
