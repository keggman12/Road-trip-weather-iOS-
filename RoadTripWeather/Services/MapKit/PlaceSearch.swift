import CoreLocation
import Foundation
import MapKit
import RoadTripCore

/// Address suggestions while typing (issue #4), from `MKLocalSearchCompleter`:
/// built into iOS, no key and no server of ours. One per location field.
@MainActor
@Observable
final class AddressCompleter: NSObject {
    struct Suggestion: Identifiable {
        let completion: MKLocalSearchCompletion
        var id: ObjectIdentifier { ObjectIdentifier(completion) }
        var title: String { completion.title }
        var subtitle: String { completion.subtitle }
        /// What goes in the field: "Denver International Airport, Denver, CO".
        var text: String { subtitle.isEmpty ? title : "\(title), \(subtitle)" }
    }

    private(set) var suggestions: [Suggestion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    /// Fewer than three characters suggests too much to be useful.
    func update(_ fragment: String) {
        let query = fragment.trimmingCharacters(in: .whitespaces)
        guard query.count >= 3 else { clear(); return }
        completer.queryFragment = query
    }

    func clear() {
        completer.cancel()
        suggestions = []
    }

    /// The exact place behind a suggestion; its `query` is the suggestion text.
    func resolve(_ suggestion: Suggestion) async throws -> PlacePoint {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: suggestion.completion))
        let response = try await search.start()
        guard let item = response.mapItems.first else { throw ServiceError.notFound(suggestion.text) }
        return PlacePoint(item, query: suggestion.text)
    }

    private func publish(_ results: [MKLocalSearchCompletion]) {
        suggestions = results.prefix(5).map(Suggestion.init)
    }
}

extension AddressCompleter: MKLocalSearchCompleterDelegate {
    // MapKit calls the delegate on the main thread.
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { publish(self.completer.results) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated { publish([]) }
    }
}

/// "Use current location" (issue #3): one When-In-Use fix, reverse geocoded
/// to a street address. The query is the address; the label is the town, so
/// trip names read "Thornton → Dallas".
@MainActor
enum CurrentLocation {
    enum Failure: LocalizedError {
        case denied, unavailable

        var errorDescription: String? {
            switch self {
            case .denied: "Location access is off for Road Trip Weather. Turn it on in Settings to use your current location."
            case .unavailable: "Couldn't find your current location. Try again, or type an address."
            }
        }
    }

    static func place(timeout: TimeInterval = 15) async throws -> PlacePoint {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        let location = try await firstFix(timeout: timeout)
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let coordinate = Coordinate(location.coordinate)
        let street = [placemark?.subThoroughfare, placemark?.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let town = [placemark?.locality, placemark?.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let fallback = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        let address = [street, town].filter { !$0.isEmpty }.joined(separator: ", ")
        let query = address.isEmpty ? fallback : address
        return PlacePoint(query: query, label: town.isEmpty ? query : town, coordinate: coordinate, timeZoneID: placemark?.timeZone?.identifier)
    }

    private static func firstFix(timeout: TimeInterval) async throws -> CLLocation {
        let deadline = Date().addingTimeInterval(timeout)
        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location { return location }
            if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                throw Failure.denied
            }
            if Date() > deadline { break }
        }
        throw Failure.unavailable
    }
}
