# Road Trip Weather (iOS)

Native SwiftUI port of [Road Trip Weather Map](https://github.com/keggman12/roadtrip-weather-app):
plan a drive, pick a route and a vehicle range, and get a weather briefing for the
**forecast at your estimated arrival time** at every stop, with NWS alerts matched to
each ETA, temperature-coloured route segments, wind relative to travel, and Buc-ee's /
Love's / rest-area layers — all viewable offline once generated.

**No backend.** The app talks only to Apple frameworks (MapKit, WeatherKit, SwiftData with
optional iCloud) and public sources (api.weather.gov, OpenStreetMap Overpass, the chains'
public locators) directly from the device. No API keys ship in the bundle; the optional
Open Charge Map key is entered in Settings and kept in the Keychain.

## Layout

```
project.yml                 XcodeGen manifest (generates RoadTripWeather.xcodeproj)
RoadTripWeather/            SwiftUI app target (iOS 18+, Observation, SwiftData)
RoadTripWeatherTests/       app-level tests (mappers, services with stubbed URLs)
Packages/RoadTripCore/      Foundation-only Swift package: models + all pure logic, unit tested
tools/poi-snapshot/         Mac-side tool that regenerates the bundled POI snapshot
docs/                       feature map, gaps report, data model, phase 1 tasks
```

## Build on the Mac

```bash
git pull
brew install xcodegen
xcodegen generate
open RoadTripWeather.xcodeproj
```

In Xcode: Signing & Capabilities → choose your Team. In the developer portal, enable
**WeatherKit** for the App ID (both the *Capabilities* and *App Services* tabs); it can take
up to ~30 minutes to activate. iCloud/CloudKit is optional — delete the entitlement keys in
`project.yml` if you don't want sync.

Run the pure-logic tests without Xcode:

```bash
cd Packages/RoadTripCore && swift test
```

## Regenerate the POI snapshot

```bash
cd tools/poi-snapshot
swift run poi-snapshot --out ../../RoadTripWeather/Resources/pois-snapshot.json
```

Sources are the same as the web app's `server/seed-pois.js`: buc-ees.com JSON-LD, the
loves.com locator API (Travel Stops only), and a nationwide Overpass query for rest areas,
with Overpass exact-tag fallbacks for the brands. Sanity checks (≥ 30 Buc-ee's, ≥ 300
Love's) protect the existing file: on failure nothing is overwritten.

## Documents

- [`docs/feature-map.md`](docs/feature-map.md) — web → Swift feature map and code-vs-README discrepancies
- [`docs/gaps.md`](docs/gaps.md) — what MapKit / WeatherKit / on-device NWS can't do, with workarounds
- [`docs/data-model.md`](docs/data-model.md) — SwiftData schema
- [`docs/phase1-tasks.md`](docs/phase1-tasks.md) — MVP task list with acceptance criteria

## Status

Phase 1 in progress. `RoadTripCore` (85 tests, verified green with the Swift 6.1 Linux toolchain; run `swift test` on the Mac too) and the app target are written; first Xcode build and on-device verification happen on the Mac. The bundled POI snapshot is real data (57 Buc-ee's, 619 Love's, 3,622 rest areas) harvested 2026-10-07.
