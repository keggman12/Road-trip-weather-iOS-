# HANDOFF — Road Trip Weather (iOS)

Written 2026-10-08 by a cloud Claude Code session that had **no Xcode**. Read this first in a
session running on the Mac. Branch: `claude/quirky-mccarthy-wnet9m` (11 commits on top of the
initial README). Owner: keggman12. Reference web app: `github.com/keggman12/roadtrip-weather-app`
(read-only; clone it next to this repo as `../roadtrip-weather-app` for parity checks).

## 1. Where things stand

| Area | State | Verified how |
|---|---|---|
| `docs/` (feature map, gaps, data model, phase-1 tasks) | done | reviewed by owner |
| `Packages/RoadTripCore` (models + all pure logic) | done, 85 tests | `swift test` green on Swift 6.1 **Linux**; never run on macOS yet |
| `tools/poi-snapshot` (Mac harvester) | done | built on Linux and **run for real**: 57 Buc-ee's, 619 Love's, 3,622 rest areas |
| `RoadTripWeather/Resources/pois-snapshot.json` | real data, 1.2 MB | counts above |
| `project.yml` (XcodeGen) | written | **never generated** |
| `RoadTripWeather/` app target (SwiftUI, SwiftData, MapKit, WeatherKit, NWS) | written | **never compiled** — expect a round of fixes |
| `RoadTripWeatherTests/MapperTests.swift` | written | never run |

## 2. First job on the Mac — do this in order

```bash
git pull
brew install xcodegen                 # once
xcodegen generate                     # produces RoadTripWeather.xcodeproj (gitignored)
swift test --package-path Packages/RoadTripCore          # expect 85 passed
xcodebuild -project RoadTripWeather.xcodeproj -scheme RoadTripWeather \
  -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | grep -E "error|warning: unre" 
xcodebuild -project RoadTripWeather.xcodeproj -scheme RoadTripWeather \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

Fix compile errors in place; keep fixes minimal and commit them as "App target: first Xcode build
fixes". Then in Xcode: Signing & Capabilities → Team. In the developer portal enable
**WeatherKit** on the App ID (both *Capabilities* and *App Services* tabs; up to ~30 min to
activate). iCloud/CloudKit entitlement is present but sync is off by default (Settings toggle).

If `xcodegen generate` complains about `Assets.xcassets` or `AppIcon`, create an empty asset
catalog at `RoadTripWeather/Resources/Assets.xcassets` with `AppIcon` and `AccentColor`.

## 3. Places most likely to fail the first compile (check these first)

- `Services/WeatherKit/WeatherKitService.swift`: `WeatherCondition` case list in `category(for:)`
  (34 cases listed; any renamed case is a compile error — there is an `@unknown default`, so
  just delete a bad case). `wind.direction.converted(to: .degrees)`, `h.condition.description`.
- `Services/MapKit/MapKitServices.swift`: `MKMapItem(placemark:)` / `item.placemark` are
  deprecated on the iOS 26 SDK (warnings only on iOS 18 target). `MKMultiPoint.coordinates` helper.
- `Persistence/Schema.swift`: SwiftData `@Relationship(inverse:)` pairs; `AlertRecord.stops`
  many-to-many with `StopRecord.alerts`. If SwiftData rejects the inverse on the array side,
  move `@Relationship` to the other side.
- `Persistence/POIStore.swift`: `context.transaction {}` and `context.delete(model:where:)`.
- `Features/Briefing/BriefingCoordinator.swift`: `withTaskGroup` body mutates `phase` (MainActor
  isolated); if Swift 6 complains, hoist progress updates outside the group.
- `App/AppEnvironment.swift`: `Box<T>: @unchecked Sendable` used to wire the NWS status callback.
- `Features/Settings/SettingsView.swift`: `Bindable(v).name` on a `@Model`; `Color.hexString` via UIKit.
- Name clash: our protocol `WeatherService` vs `WeatherKit.WeatherService` — the adapter is
  declared as `RoadTripWeather.WeatherService` on purpose. Keep the module name `RoadTripWeather`.

## 4. Decisions already made with the owner (don't re-ask)

- Paid Apple Developer Program: enrolled → WeatherKit (500k calls/month included).
- Distribution: personal / TestFlight only → device-side brand-site refresh + public Overpass OK.
- Motorcycle default range **180 mi** (web code), not the README's 120.
- Xcode project via **XcodeGen `project.yml`**; `.xcodeproj` is gitignored.
- Brief the **selected route only** by default; "Brief all routes" is an explicit action
  (web briefs all; its README claims otherwise — see docs/feature-map.md discrepancy 4).
- Resume time and departure are evaluated in the **stop's / origin's time zone** (web used the
  browser's; intentional deviation, tested).
- No API keys in the bundle. Open Charge Map key → Keychain via Settings. No server of ours.
- Daily-forecast fallback uses mean(high, low); WeatherKit horizon 10 days → `beyondHorizon`.
- NWS User-Agent = app name + repo URL (+ optional email from Settings).

## 5. Architecture in one minute

- `RoadTripCore` is Foundation-only (own `Coordinate`, no CoreLocation) so it builds on Linux
  and is shared by the app and `tools/poi-snapshot`. All web logic lives here with tests whose
  expected values come from running the web app's JS (`tools/web-reference/gen.mjs` →
  `Tests/.../Fixtures/web-reference.json`). Regenerate with
  `WEB=../roadtrip-weather-app node tools/web-reference/gen.mjs <fixture path>`.
- App: `Services/Protocols/Services.swift` defines Geocoding/Routing/TimeZone/Weather/Alert/POI/
  Charger services; `Services/Mocks` for previews; `AppEnvironment.live()` wires the real ones.
  `BriefingCoordinator` is the two-phase flow (Find Routes = MapKit only; Generate Briefing =
  WeatherKit + NWS). `Persistence/` holds the SwiftData schema (CloudKit-safe: no unique
  attributes, defaults everywhere, optional relationships), mappers, `POIStore`, `TripStore`.
- Screens: Plan → Routes → Briefing (map, summary, alerts, precip chart, stop cards), Trips,
  Settings (bands, garage, NWS contact, OCM key), Data sources & freshness.

## 6. Phase-1 acceptance work after it compiles (docs/phase1-tasks.md has the criteria)

1. Task 4 routing: Denver → Dallas gives alternates; Denver → Amarillo → Dallas gives
   "via Amarillo" + "Direct"; every stop gets a `timeZoneID`; zero WeatherKit calls on Find Routes
   (Data sources screen shows the session counters).
2. Task 5 WeatherKit: 30 h ETA → hourly record within 30 min; 12-day ETA → "beyond horizon".
3. Task 6 NWS: User-Agent present (add a `URLProtocol` stub test), ±2 h filter, 429 retry.
4. Tasks 9–13: map colours, dwell → ETA shift → stale banner → refresh, POI layers offline,
   saved trip opens in airplane mode with data age.
5. Then Phase 2 (optimizer UI, manual stop entry, GPX, Waze links, Supercharger lookup): the Core
   pieces exist (`DepartureCandidates`, `TripScorer`, `Geo.projectOntoRoute`, `StopEditReplayer`).

## 7. Conventions

- Swift 6 language mode, strict concurrency, no force unwraps, Observation (`@Observable`),
  SwiftData only. Services are `Sendable` structs or actors; stores are `@MainActor`.
- Small commits with clear messages; keep `RoadTripCore` free of UI/Apple-only frameworks so
  `swift test` keeps working on Linux.
- Never ship fabricated POI data; regenerate the snapshot only with `tools/poi-snapshot`.
- Be polite to third parties: NWS/Overpass identified by User-Agent, Overpass serialized with
  30 s cooldown on 429/406, brand refresh manual + at most weekly.
