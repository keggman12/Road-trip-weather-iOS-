# HANDOFF — Road Trip Weather (iOS)

Originally written 2026-10-08 by a cloud session with no Xcode; **updated 2026-10-08 after the
first Mac session**, which built, signed, tested and ran the app. Branch:
`claude/quirky-mccarthy-wnet9m`. Owner: keggman12. Reference web app:
`github.com/keggman12/roadtrip-weather-app` (read-only; cloned next to this repo as
`../roadtrip-weather-app` for parity checks).

## 1. Where things stand

| Area | State | Verified how |
|---|---|---|
| `docs/` (feature map, gaps, data model, phase-1 tasks) | done | reviewed by owner |
| `Packages/RoadTripCore` (models + all pure logic) | done, 85 tests | `swift test` green on Linux **and macOS** (Swift 6.4) |
| `tools/poi-snapshot` (Mac harvester) | done | run for real: 57 Buc-ee's, 619 Love's, 3,622 rest areas |
| `RoadTripWeather/Resources/pois-snapshot.json` | real data, 1.2 MB | counts above |
| `project.yml` (XcodeGen) | generates cleanly | Xcode 27.0, team `D69L37WPA3` set |
| App target (SwiftUI, SwiftData, MapKit, WeatherKit, NWS) | builds with zero warnings, runs | iPhone 17 simulator + signed device build |
| Signing / capabilities | done | App ID `com.keggman12.RoadTripWeather`: WeatherKit (Capabilities + App Services), iCloud/CloudKit, Push; container `iCloud.com.keggman12.RoadTripWeather`; live WeatherKit calls succeed |
| App tests (`RoadTripWeatherTests/`) | 38 tests, green | `xcodebuild test` (see §2) |

### Phase-1 tasks (`docs/phase1-tasks.md`)

| Task | Status | Evidence |
|---|---|---|
| 1 Scaffold | ✅ | builds after `xcodegen generate`; asset catalog added |
| 2 Core logic | ✅ | 85 Core tests |
| 3 Protocols + mocks | ✅ | coordinator tests run on mocks, no network |
| 4 MapKit services | ✅ | `LiveRoutingTests` (live MapKit) |
| 5 WeatherKit | ✅ | `LiveWeatherKitTests` (live); attribution persisted with the briefing |
| 6 NWS alerts | ✅ | `NWSAlertServiceTests` (`URLProtocol` stub) |
| 7 Plan screen | ◐ | range clamp 20…800 + keyboard Done added; recents verified by hand; no automated test of "Find Routes disabled until resolved" |
| 8 Routes + briefing persistence | ✅ | `SessionPersistenceTests`: draft written before the UI sees it; restored on relaunch |
| 9–13 Map, stops, precip, POIs, saved trips | ✅ | `BriefingAcceptanceTests` (offline fakes with an airplane-mode switch) |
| 14 Settings + Data Sources | ✅ | `SettingsDataSourcesTests`: every row (MapKit, WeatherKit, NWS, Overpass, brands, rest, snapshot, OCM) updates after its call; bands fix-up/persist/reset; garage rules |
| 15 `tools/poi-snapshot` | ✅ | ran on Linux; not yet re-run on the Mac |

## 2. Build and test on the Mac

```bash
xcodegen generate                                         # after any project.yml change
swift test --package-path Packages/RoadTripCore           # 85 tests
xcodebuild -project RoadTripWeather.xcodeproj -scheme RoadTripWeather \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -collect-test-diagnostics never test                    # 38 app + 85 Core tests
```

- **`-collect-test-diagnostics never` matters**: without it, a failing test leaves xcodebuild
  stuck in `simctl diagnose` for 10+ minutes.
- Tests tagged `.live` (`LiveRoutingTests`, `LiveWeatherKitTests`) hit real MapKit/WeatherKit
  and fail offline. Everything else is deterministic and offline.
- There is no iPhone 16 simulator on this Mac; use iPhone 17.
- The app's `Tag` view clashes with Swift Testing's `Tag`: write `Testing.Tag` in tests.
- Swift Testing filters: `-only-testing:RoadTripWeatherTests` works; per-function filters on
  free `@Test` functions didn't match.

## 3. Things learned the hard way (first Mac session)

- The predicted compile failures in the old §3 mostly didn't happen. The only compile error was
  a captured `var request` in `NWSAlertService` (Swift 6 sendability).
- The test bundle needs `GENERATE_INFOPLIST_FILE: YES` (in `project.yml`).
- The first launch after a cold simulator boot shows ~5 s of black — that is the simulator, not
  the app. Measured: the app's launch path is 275 ms on a fresh install; the bundled POI import
  (~215 ms) now runs on a background `@ModelActor` (`POISnapshotImporter`).
- Two plain `Button`s in one `Form` row both fire on any tap (Apply also ran Reset); use
  `.buttonStyle(.borderless)` for multi-button rows.
- `DataSourceStatusStore.status(_:)` and `POIStore.meta(for:)` are read-only on purpose so rendering can't insert rows or race the
  importer into duplicates (no unique constraints under CloudKit).

## 4. Decisions already made with the owner (don't re-ask)

- Paid Apple Developer Program: enrolled → WeatherKit (500k calls/month included).
  Team ID `D69L37WPA3` lives in `project.yml` (setting it in Xcode is lost on regenerate).
- Bundle ID stays `com.keggman12.RoadTripWeather` (registered; owner's other apps use
  `com.davekegley.*`, deliberately not matched).
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
- NWS retries only 429, 5xx and transient network errors (the web never retried).

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
- **Session persistence**: briefings are built off-screen, written as *draft*
  `CachedBriefingRecord`s (`trip == nil`, via `TripStore.replaceDrafts`), then published. Every
  stop mutation, refresh, save and load rewrites the drafts; the plan behind them is
  `AppSettings.session` (UserDefaults). `BriefingCoordinator.init` restores it. Saved trips keep
  their own cached briefings; drafts never appear in the Trips list.
- Cached-only sessions pad un-briefed route indices with empty `RouteGeometry` placeholders;
  `RoutesView` skips them (`realRoutes`).
- Screens: Plan → Routes → Briefing (map, summary, alerts, precip chart, stop cards), Trips,
  Settings (bands, garage, NWS contact, OCM key), Data sources & freshness.

## 6. What's next

1. Task 7 leftovers: automated test that Find Routes stays disabled until both fields are set
   and that recents only update after successful geocoding.
2. Phase 2 (optimizer UI, manual stop entry, GPX, Waze links, Supercharger lookup): the Core
   pieces exist (`DepartureCandidates`, `TripScorer`, `Geo.projectOntoRoute`, `StopEditReplayer`).
3. Polish noticed in the simulator, not yet done: the Find Routes button sits under the floating
   tab bar until you scroll; the overnight toggle on stop cards has no visible label; wind text
   truncates on stop cards.

## 7. Conventions

- Swift 6 language mode, strict concurrency, no force unwraps, Observation (`@Observable`),
  SwiftData only. Services are `Sendable` structs or actors; stores are `@MainActor`.
- Small commits with clear messages; keep `RoadTripCore` free of UI/Apple-only frameworks so
  `swift test` keeps working on Linux.
- Never ship fabricated POI data; regenerate the snapshot only with `tools/poi-snapshot`.
- Be polite to third parties: NWS/Overpass identified by User-Agent, Overpass serialized with
  30 s cooldown on 429/406, brand refresh manual + at most weekly.
