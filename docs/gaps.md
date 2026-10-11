# Gaps report — what MapKit, WeatherKit and on-device NWS cannot do that the web app does

Each gap names the web behaviour, the platform limitation, and the workaround the iOS
app uses. Items marked **(improvement)** are places where the Apple stack does more than
the web stack.

## Routing and geocoding (MapKit vs OpenRouteService)

| Web behaviour | MapKit reality | Workaround |
|---|---|---|
| One request routes through origin + via-points + destination | `MKDirections.Request` has only `source` and `destination`; no intermediate waypoints | Chain one request per leg (origin→via1, via1→via2, …, →destination), concatenate polylines, sum distance and travel time, record leg boundaries. Alternates are requested only for 2-point trips, which is also what the web app does with ORS. |
| `alternative_routes {target_count 3, weight_factor 1.6, share_factor 0.6}` | `requestsAlternateRoutes = true`; MapKit chooses how many (commonly up to 3) and there is no weight/share tuning | Accept MapKit's set. **(improvement)** No ~100 km cap, so long trips get alternatives without via-points. |
| Route duration is static | `MKDirections.Request.departureDate` | Set from the trip's departure; durations become traffic-aware **(improvement)**. |
| ORS returns a dense GeoJSON line | `MKRoute.polyline` is dense (thousands of points on a long route) | No gap. Sampling, projection and corridor filtering are our own math in `RoadTripCore`. |
| Pelias geocoder returns a label like "Amarillo, TX, USA" | `MKLocalSearch` returns `MKMapItem` with `name`, `placemark` | Build the label from placemark fields; capture `MKMapItem.timeZone` **(improvement, see below)**. |
| OWM response carries the location's IANA timezone, used for every ETA clock | WeatherKit returns no timezone; sampled waypoints have none | `TimeZoneService`: `MKMapItem.timeZone` for geocoded endpoints; `CLGeocoder.reverseGeocodeLocation` for sampled stops (serialized, cached per stop in the briefing); fallback to the origin's zone. Apple throttles `CLGeocoder` (undocumented, roughly one request per second is safe); ≤ 25 lookups per briefing. |
| Unlimited free-tier routing calls counted in the UI | Apple may throttle apps that issue many `MKDirections` requests quickly (no published numbers) | Routing runs once per "Find Routes" (1 + number of legs + 1 for the direct route). Not an issue at this scale. |

## Weather (WeatherKit vs OpenWeatherMap One Call 4.0)

| Web behaviour | WeatherKit reality | Workaround |
|---|---|---|
| Hourly within 47 h, daily beyond, paging the timeline until it covers the ETA | `hourly(startDate:endDate:)` provides data up to **240 h** ahead; `daily` covers **10 days**; nothing beyond | Use hourly for every ETA ≤ 240 h (**improvement**: hourly precision for the whole 10-day window). Daily is only a fallback when the hourly window returns empty near the edge. ETAs more than 10 days out get a `WeatherSnapshot` with `horizon = .beyondHorizon` and the card says "beyond forecast horizon". The web app's daily paging could reach further. |
| Condition by OWM id (`categorize`) | `WeatherCondition` enum, no numeric id | Mapping table in `WeatherKitService`: thunderstorms/isolatedThunderstorms/scatteredThunderstorms/strongStorms → thunderstorm; hurricane/tropicalStorm → severe; rain/drizzle/heavyRain/freezingRain/freezingDrizzle/sunShowers → rain; snow/flurries/heavySnow/sleet/wintryMix/blowingSnow/blizzard → snow; cloudy/foggy/haze/smoky/blowingDust → mostly-cloudy; clear/mostlyClear/hot/frigid/breezy/windy → by cloud cover; partlyCloudy → partly-cloudy; mostlyCloudy → mostly-cloudy. Cloud-cover fallback is the web rule (<15 clear, <50 partly, else mostly). |
| Daily record temperature uses `temp.day` | `DayWeather` has only `highTemperature`/`lowTemperature` | Daily fallback uses the mean of high and low; `kind = .daily` so the card shows the precision tag. |
| `pop` 0–1, humidity %, wind mph, feels-like | `precipitationChance` 0–1, `humidity` 0–1, `wind.speed` as `Measurement`, `apparentTemperature` | Convert once in the adapter; Core stores °F, mph, %, 0–1. |
| No attribution | WeatherKit terms require displaying the Apple Weather attribution (`WeatherService.attribution`) | Attribution mark on the briefing screen and the Data Sources screen. |
| Any key works from any origin | WeatherKit needs the **WeatherKit capability** on the App ID (Capabilities and App Services tabs) and a paid Apple Developer Program membership; 500 000 calls/month included per membership | One `weather(for:including: .hourly(...), .daily)` call per stop ⇒ ≈ 25 calls per briefing, ≤ 300 for a full optimizer matrix. Far inside the quota. |
| No alerts from the weather provider | WeatherKit also exposes `weatherAlerts` | Not used; NWS per spec. Could supplement later for non-US trips. |

## Alerts (NWS from the device)

| Web behaviour | Device reality | Workaround |
|---|---|---|
| `GET api.weather.gov/alerts/active?point=lat,lon` with `Accept: application/geo+json`, no User-Agent (browsers send their own) | NWS rejects requests without a `User-Agent` and asks for app identification plus contact | `NWSAlertService` sends `User-Agent: RoadTripWeather-iOS/<version> (github.com/keggman12/Road-trip-weather-iOS-; <contact>)`; the contact email is an optional Settings field. |
| 25 parallel requests per briefing | Undocumented rate limit (community figures ~5 000/h) | Limit to 4 concurrent requests; retry 429/5xx with backoff; errors yield `[]` so the briefing never fails on alerts (same as web). |
| US only | Same | Outside the US alerts are silently empty, as in the web app. |

## Persistence and offline

| Web behaviour | iOS reality | Workaround |
|---|---|---|
| Trips saved to the Node/SQLite server | SwiftData with optional CloudKit sync. CloudKit forbids `@Attribute(.unique)`, requires every property to be optional or defaulted, every relationship optional with an inverse, and no `.deny` delete rule | Schema designed to those rules; POI identity (kind + sourceID) enforced in code. |
| Map tiles always online | MapKit has no app-controlled offline tile store | Saved briefings open offline with stops, ETAs, forecasts, alerts, POIs and the route overlay; the basemap may be blank where MapKit has nothing cached. Flagged in the UI with a "map tiles unavailable offline" note. |
| Briefing lives in memory | — | `CachedBriefing` stores every stop, snapshot, alert and segment plus `generatedAt`; cards show data age and stale labels. |

## POIs (Overpass and brand locators from the device)

| Web behaviour | Device reality | Workaround |
|---|---|---|
| Nationwide Overpass harvest for rest areas (300 s, 1 GB, 50 000 results) | Unacceptable on a phone | Ship the rest-area snapshot in the bundle; regenerate with `tools/poi-snapshot` on the Mac. Optional corridor query (bbox around the thinned route, 25 s, mirrors, `remark` check) cached per route. |
| Public Overpass from a browser | Public instances expect identification, no parallel bursts, 30 s pause on 429/406, and are "overloaded, do not expect high reliability" | User-Agent, serialized queries, mirrors, cache, manual trigger only. Fine for personal/TestFlight scale. |
| Scraping buc-ees.com and loves.com from a server | Same requests from the device; the chains' terms don't cover automated access | Personal use only; manual button plus at most weekly automatic refresh; browser-style User-Agent like the web script; failures never overwrite. |

## Things the Apple stack does better (no workaround needed)

- Alternates on long routes without via-points.
- Hourly forecast precision for 10 days instead of 2.
- Traffic-aware durations through `departureDate`.
- Per-leg travel times from chained `MKDirections` requests (Phase 1 keeps the web's whole-route proportional ETA for parity; leg-aware ETA is a flagged option).
- Time zone per geocoded place from `MKMapItem.timeZone`.

## Assumptions called out

- Brief the selected route by default; "Brief all routes" is a separate action (web briefs all).
- Alert matching keeps the ±2 h buffer and the `onset ∥ effective` / `ends ∥ expires` rules exactly.
- Daily fallback uses mean(high, low) where the web used `temp.day`.
- NWS contact defaults to the GitHub repo URL until an email is entered in Settings.
