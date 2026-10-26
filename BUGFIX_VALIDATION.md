# Weather and itinerary fixes — 2026-10-26

Branch: `codex/bugfix-weather-itinerary`.
The repository was clean on `main` before these edits.

## Revalidated findings and changes

1. Failed refreshes cleared cached forecasts, stamped new forecast times, and always reported success. Cached weather, its forecast time and the briefing freshness time now survive failure. Partial failures report attempted failures even when cached values remain. Successful stops update normally; alerts are fetched independently. A fully successful refresh advances the briefing freshness time.
2. Missing weather could outrank severe weather, and alerts without weather were skipped by scoring. Incomplete/stale route weather has no comparison score. Incomplete departures sort after complete candidates and cannot receive the Best badge or recommendation. Alert penalties count even without a forecast.
3. Manually added stops now retain actual destination coordinates. Route index, along-route mileage and off-route distance come from projection for ordering. Weather, navigation and export use the destination. This does not reroute the road geometry or add detour driving time.
4. Overnight stops reached before the local resume time can resume that morning, with at least six elapsed hours of rest; later arrivals resume the next day. This matches Android, including stop-local time zones. Tests cover spring and autumn DST transitions.
5. The weekly POI setting now triggers refresh checks on launch, foreground entry and setting changes. Buc-ee's and Love's are refreshed serially only when due. Attempts (including failures) are throttled for a week, duplicate concurrent refreshes are prevented, and failures retain existing data. Rest areas remain snapshot-only. This is foreground refresh, not a guaranteed background scheduler.
6. Regeneration and adopting another departure reuse existing edited itineraries. Dwell times, overnight choices, manual stops, removals and stop IDs survive. The optimizer uses those stops but fetches fresh weather for each candidate. Pending saved-trip edits are applied before fetching all forecasts, so downstream shifted ETAs are included.

## Automated verification

- `swift test --package-path Packages/RoadTripCore`: 115 tests passed.
- Xcode simulator build and deterministic suite: 69 app tests plus 115 core tests passed on iPhone 18 Pro / iOS 27.0.
- Full suite including live providers: the existing `LiveRoutingTests.viaRatonAlsoOffersTheEasternRoute` failed because MapKit did not supply the expected eastern alternate (two assertions). Routing code was not changed. No test assertion or fixture was relaxed to hide that result.
- Final deterministic Xcode command:

```sh
xcodebuild test -project RoadTripWeather.xcodeproj -scheme RoadTripWeather \
  -destination 'platform=iOS Simulator,id=B24D502D-1353-4DC3-8521-37165AC0384B' \
  -derivedDataPath /tmp/rtw-ios-derived \
  -skip-testing:RoadTripWeatherTests/LiveRoutingTests \
  -skip-testing:RoadTripWeatherTests/LiveWeatherKitTests \
  CODE_SIGNING_ALLOWED=NO
```

## Try it in Xcode

1. Open `RoadTripWeather.xcodeproj` inside `/Users/dkegley/Developer/Road-trip-weather-iOS-/Road-trip-weather-iOS-` (the nested folder).
2. Choose the `RoadTripWeather` scheme and an iPhone simulator in the toolbar. Press Command-R to build and run, or Command-U to run tests. The normal scheme includes live-provider tests, which can fail because of service responses or WeatherKit authorization.
3. For a physical iPhone, select it as the destination and choose your Apple development team under the app target's Signing & Capabilities. Keep WeatherKit enabled. The mocked regression tests do not require working live WeatherKit access; live forecasts on a device do.
4. Generate a briefing, change a stop's dwell, mark another overnight, remove a stop and add an off-road address. Regenerate and adopt another departure. Confirm those edits remain and navigation targets the address.
5. After caching weather, disable networking and refresh. Cached values should remain and the status should report failure. Re-enable networking and refresh successfully. A departure with missing forecasts must not receive a Best badge.
6. To check overnight timing, use an arrival before 8 AM: 1:30 AM can resume at 8 AM, while 7:30 AM resumes at 1:30 PM because of the six-hour minimum. Times use the stop's zone.
7. Enable the weekly POI setting and bring the app to the foreground. Data Sources shows refresh attempts/results. Returning to the app again within a week should not repeat an automatic attempt; Refresh now still works manually. The app must be opened/active for the automatic check.

No project regeneration, commit, push, archive or TestFlight upload is required to try these changes. Existing cached stops whose original address coordinates were already discarded cannot recover that address automatically; re-add such a stop to get the correct destination.
