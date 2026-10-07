# Phase 1 (MVP) task list with acceptance criteria

Order is roughly dependency order. "Core" = `Packages/RoadTripCore`. Each task ends in a
commit on the working branch.

## 1. Repository scaffold
- `project.yml` (XcodeGen), `.gitignore`, README, `docs/`.
- **AC:** `brew install xcodegen && xcodegen generate` on the Mac produces `RoadTripWeather.xcodeproj` with app, app-tests and Core package targets; the app builds for iOS 18 simulator after setting the Team. `swift test` in Core passes.

## 2. RoadTripCore pure logic
Modules: `Geo`, `WaypointSampler`, `ETACalculator`, `Wind`, `TemperatureScale`, `ConditionCategory`, `AlertMatcher`/`AlertDeduper`, `TripScorer`, `DepartureCandidates`, `POINormalizer`, `CorridorFilter`, `BuceesJSONLDParser`, `LovesStoresParser`, `StopEditReplayer`, `RecentLocations`.
- **AC:** every public function has at least one test whose expected value is derived from the web code (constants listed in `docs/feature-map.md`); Swift 6 language mode, no force unwraps, Foundation only; builds on Linux and macOS.

## 3. Service protocols and mocks
`RoutingService`, `GeocodingService`, `TimeZoneService`, `WeatherService`, `AlertService`, `POIService`, `ChargerService`; `Mocks/` with deterministic fakes.
- **AC:** SwiftUI previews and app tests run with mocks and no network.

## 4. MapKit services
`MapKitGeocodingService` (`MKLocalSearch`), `MapKitRoutingService` (alternates for 2 points; chained legs for vias; direct route for comparison; `departureDate`), `CLTimeZoneService` (reverse geocode, serialized, cached).
- **AC:** Denver → Dallas returns ≥ 1 route (alternates when MapKit has them); Denver → Amarillo → Dallas returns one via route labelled "via Amarillo" plus "Direct"; every stop in a briefing has a `timeZoneID`; no weather call is made during Find Routes.

## 5. WeatherKit service
Hourly window around ETA, daily fallback, horizon state, condition mapping, attribution.
- **AC:** for an ETA 30 h out the snapshot's `recordDate` is within 30 min of the ETA and `kind == .hourly`; for an ETA 12 days out `horizon == .beyondHorizon` and no crash; attribution view visible on the briefing screen.

## 6. NWS alert service
- **AC:** every request carries the User-Agent (asserted with a `URLProtocol` stub); an alert with `ends` 3 h before the ETA is filtered, one ending 1 h before is kept (buffer); a 429 is retried; a network error yields `[]`.

## 7. Plan screen
Origin, destination, via-points (add/remove/reorder), departure (`DatePicker` in the origin's zone, default next full hour), vehicle picker with garage editor, range field (clamped 20…800, switching to "Custom" when edited), recents.
- **AC:** Find Routes disabled until origin and destination resolve; recents update only after successful geocoding; call counter shows 0 WeatherKit calls after Find Routes.

## 8. Routes screen and Generate Briefing
Route cards (fastest tag, +delta), map preview, selected route; "Generate Weather Briefing" briefs the selected route; "Brief all routes" option.
- **AC:** progress shows n/N stops; a failed stop shows "Weather unavailable" without failing the briefing; the briefing is persisted as a `CachedBriefing` with all stops before the UI shows it.

## 9. Briefing map
Temperature-coloured segments, dimmed alternates when all routes are briefed, stop annotations (temp, condition icon, wind arrow, ☾, alert ring), POI pins.
- **AC:** segment colours equal `TemperatureScale.color(for: avg)`; changing bands in Settings recolours without any network call; dark map style.

## 10. Stop list
Cards with tag, ETA in stop zone with abbreviation, hourly/daily chip, condition badge, wind with head/tail/cross chip, feels-like, humidity, precip, leg chip with ⚠ when leg > range, dwell stepper, overnight toggle, remove.
- **AC:** changing dwell at stop 3 shifts ETAs of stops 4…N by the delta and marks them stale when drift > 30 min; the stale banner's Refresh refetches only weather and alerts and clears the flags.

## 11. Precipitation timeline
Swift Charts bar chart.
- **AC:** hidden when fewer than two stops have precip data; bar is red for thunderstorm/severe/snow, amber for ≥ 50 %, value labels from 15 %.

## 12. POI layers
Bundled snapshot import, per-kind toggles, corridor filter (8000 m brands, 4000 m rest), pin callout with nearest-stop forecast and "Add as fuel stop" / "Add as stop".
- **AC:** with airplane mode on and a cached briefing open, toggling Buc-ee's shows pins within the corridor; adding one inserts a stop snapped to the route with `poiKind` set and the default 15-min dwell, then fetches its forecast when online.

## 13. Saved trips and offline cache
Save (default name "Origin → Dest"), list, load (re-find routes, reselect, replay stop edits), delete; open cached briefing offline.
- **AC:** in airplane mode a saved trip opens its last briefing with stops, ETAs, forecasts, alerts, POIs and route overlay; the header shows "generated 3 h ago"; forecasts older than the stale threshold are labelled.

## 14. Settings and Data Sources screen
Temperature bands editor (monotonic fix-up, reset), vehicle garage, NWS contact email; Data Sources lists MapKit, WeatherKit, NWS, Buc-ee's, Love's, rest areas, Overpass, OCM with last success, count, last error.
- **AC:** each row updates after the corresponding call; OCM row shows "disabled — add a key" when no key is stored.

## 15. tools/poi-snapshot
Swift executable using Core parsers.
- **AC:** `swift run poi-snapshot --out ../../RoadTripWeather/Resources/pois-snapshot.json` writes a snapshot with ≥ 30 Buc-ee's, ≥ 300 Love's and > 0 rest areas; a source failure prints the reason and leaves the existing file untouched.
