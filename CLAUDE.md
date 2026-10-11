# Road Trip Weather (iOS) — project instructions

Start with `HANDOFF.md` (current state, first jobs, likely compile failures) and `docs/`.

- Targets: iOS 18+, SwiftUI, Observation, SwiftData, Swift 6 strict concurrency, no force unwraps.
- `Packages/RoadTripCore` must stay Foundation-only (builds on Linux). Run its tests with
  `swift test --package-path Packages/RoadTripCore`; expected values come from the web app's
  JavaScript via `tools/web-reference/gen.mjs` — change the fixture only by regenerating it.
- The Xcode project is generated: edit `project.yml`, run `xcodegen generate`; never commit
  `*.xcodeproj`.
- No backend of ours, no API keys in the bundle. Optional keys go to the Keychain via Settings.
- POI data comes only from `tools/poi-snapshot` or the in-app refresh; never hand-edit
  `RoadTripWeather/Resources/pois-snapshot.json`.
- Decisions already settled with the owner are listed in `HANDOFF.md` §4; don't re-ask them.
- Commit in small steps with descriptive messages.
