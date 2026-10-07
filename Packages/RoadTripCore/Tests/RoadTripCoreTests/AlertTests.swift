import Foundation
import Testing
@testable import RoadTripCore

@Suite("Alerts (web getAlertsAt / dedupeAlerts)")
struct AlertTests {
    let eta = Date(timeIntervalSince1970: 1_781_100_000)
    let h: TimeInterval = 3600

    func alert(_ id: String, onset: TimeInterval?, ends: TimeInterval?, severity: AlertSeverity = .unknown) -> WeatherAlert {
        WeatherAlert(id: id, event: id, severity: severity, onset: onset.map { eta.addingTimeInterval($0) }, ends: ends.map { eta.addingTimeInterval($0) })
    }

    @Test func bufferIsTwoHoursEachSide() {
        let alerts = [
            alert("expired-3h-ago", onset: -10 * h, ends: -3 * h),      // dropped
            alert("expired-1h-ago", onset: -10 * h, ends: -1 * h),      // kept (within 2 h slack)
            alert("ends-exactly-2h-before", onset: -10 * h, ends: -2 * h), // kept (>=)
            alert("starts-in-3h", onset: 3 * h, ends: 6 * h),           // dropped
            alert("starts-in-2h", onset: 2 * h, ends: 6 * h),           // kept (<=)
            alert("starts-in-1h", onset: 1 * h, ends: 6 * h),           // kept
            alert("open-ended", onset: nil, ends: nil),                 // kept
            alert("no-end", onset: -1 * h, ends: nil),                  // kept
        ]
        let kept = AlertMatcher.inEffect(alerts, at: eta).map(\.id)
        #expect(kept == ["expired-1h-ago", "ends-exactly-2h-before", "starts-in-2h", "starts-in-1h", "open-ended", "no-end"])
    }

    @Test func nilETAKeepsEverything() {
        let alerts = [alert("a", onset: -10 * h, ends: -9 * h)]
        #expect(AlertMatcher.inEffect(alerts, at: nil).count == 1)
    }

    @Test func dedupeOrdersBySeverityAndKeepsFirst() {
        let s1 = Stop(kind: .origin, label: "a", coordinate: Coordinate(lat: 0, lon: 0), routeIndex: 0, distanceMi: 0, alerts: [
            alert("minor", onset: nil, ends: nil, severity: .minor),
            alert("severe", onset: nil, ends: nil, severity: .severe),
        ])
        let s2 = Stop(kind: .destination, label: "b", coordinate: Coordinate(lat: 1, lon: 1), routeIndex: 1, distanceMi: 10, alerts: [
            alert("severe", onset: nil, ends: nil, severity: .severe),   // duplicate id
            alert("extreme", onset: nil, ends: nil, severity: .extreme),
            alert("mystery", onset: nil, ends: nil, severity: .unknown),
            alert("moderate", onset: nil, ends: nil, severity: .moderate),
        ])
        let out = AlertDeduper.dedupe(stops: [s1, s2])
        #expect(out.map(\.id) == ["extreme", "severe", "moderate", "minor", "mystery"])
    }

    @Test func severityParsingIsLenient() {
        #expect(AlertSeverity(nwsString: "Severe") == .severe)
        #expect(AlertSeverity(nwsString: "Bananas") == .unknown)
        #expect(AlertSeverity(nwsString: nil) == .unknown)
        #expect(AlertSeverity.extreme < AlertSeverity.minor)
    }

    @Test func nwsResponseDecodesLikeWeb() throws {
        let data = Fixtures.data("nws-alerts-sample.json")
        let resp = try NWSAlertsResponse.decode(data)
        let alerts = resp.alerts()
        #expect(alerts.count == 3)

        let a = try #require(alerts.first { $0.id.hasSuffix("tornado-watch") })
        #expect(a.event == "Tornado Watch")
        #expect(a.severity == .severe)
        #expect(a.areaDescription.contains("Potter"))
        // onset preferred over effective; ends preferred over expires.
        #expect(a.onset == NWSAlertsResponse.parseDate("2026-06-10T15:00:00-05:00"))
        #expect(a.ends == NWSAlertsResponse.parseDate("2026-06-10T22:00:00-05:00"))

        let b = try #require(alerts.first { $0.id.hasSuffix("heat-advisory") })
        // No onset → effective; no ends → expires; event missing → "Alert"? (event present here)
        #expect(b.onset == NWSAlertsResponse.parseDate("2026-06-10T10:00:00-05:00"))
        #expect(b.ends == NWSAlertsResponse.parseDate("2026-06-11T00:00:00-05:00"))
        #expect(b.severity == .moderate)

        let c = try #require(alerts.first { $0.id == "feature-level-id" })
        #expect(c.event == "Alert")            // missing event
        #expect(c.severity == .unknown)        // unrecognised severity
        #expect(c.onset == nil && c.ends == nil)
    }

    @Test func nwsDateParsing() {
        #expect(NWSAlertsResponse.parseDate("2026-06-10T15:00:00-05:00")?.timeIntervalSince1970 == 1_781_121_600)
        #expect(NWSAlertsResponse.parseDate("2026-06-10T20:00:00Z")?.timeIntervalSince1970 == 1_781_121_600)
        #expect(NWSAlertsResponse.parseDate("garbage") == nil)
        #expect(NWSAlertsResponse.parseDate(nil) == nil)
        #expect(NWSAlertsResponse.parseDate("") == nil)
    }

    @Test func emptyFeatureCollection() throws {
        let resp = try NWSAlertsResponse.decode(Data(#"{"type":"FeatureCollection"}"#.utf8))
        #expect(resp.alerts().isEmpty)
    }
}
