# SwiftData model design

Two layers:

1. **`RoadTripCore` value types** (`Codable`, `Sendable`, Foundation-only) — what every
   algorithm and every view works with: `Briefing`, `Stop`, `WeatherSnapshot`,
   `WeatherAlert`, `POI`, `Vehicle`, `RouteGeometry`.
2. **SwiftData `@Model` classes** in the app target (`RoadTripWeather/Persistence`) — what
   is stored and optionally synced with CloudKit. `Persistence/Mappers` converts in both
   directions.

## CloudKit rules applied everywhere

- No `@Attribute(.unique)`. Identity fields (`POI.kind + sourceID`, `Alert.nwsID`) are
  enforced in code by the repositories.
- Every scalar has a default; every relationship is optional with an explicit `inverse`.
- Delete rules are `.cascade` or `.nullify`, never `.deny`.
- Session-only values (API call counters) live in memory, not in the store.

## Models

### Vehicle
| Field | Type | Default / note |
|---|---|---|
| id | UUID | `UUID()` |
| name | String | "" |
| rangeMi | Double | 300; clamped 20…800 on save |
| isEV | Bool | false |
| sortOrder | Int | 0 |
| isBuiltIn | Bool | false — the three seeded defaults |
| createdAt | Date | now |
| trips | [Trip]? | inverse `Trip.vehicle`, `.nullify` |

Seeded on first launch: Automobile 300, Motorcycle 180, Tesla 250 (EV).

### Trip
| Field | Type | Default / note |
|---|---|---|
| id | UUID | |
| name | String | "" |
| originQuery, originLabel | String | typed text and resolved label |
| originLat, originLon | Double | 0 |
| originTimeZoneID | String? | from `MKMapItem.timeZone` |
| destQuery, destLabel, destLat, destLon, destTimeZoneID | same shape | |
| viasData | Data | JSON `[PlacePoint]` (`query, label, lat, lon, timeZoneID`) |
| departureDate | Date | |
| departureTimeZoneID | String? | origin's zone; the picker edits in this zone |
| vehicle | Vehicle? | `.nullify` |
| rangeMiSnapshot | Double | 300 — the range used, even if the vehicle changes later |
| multiDayEnabled | Bool | false |
| maxDriveHours | Double | 10 (2…20) |
| resumeTime | String | "08:00" |
| selectedRouteIndex | Int | 0 |
| stopEditsData | Data? | JSON `StopEdits { manualStops: [ManualStopEdit], removedMi: [Int] }` |
| createdAt, updatedAt | Date | |
| briefings | [CachedBriefing]? | inverse `CachedBriefing.trip`, `.cascade` |

### CachedBriefing
One per briefed route per generation. The newest per route is shown; older ones are pruned to a small number.

| Field | Type | Note |
|---|---|---|
| id | UUID | |
| trip | Trip? | |
| routeIndex | Int | position in the route list at generation time |
| routeLabel | String | "Direct", "via Amarillo", "Route 2" |
| generatedAt | Date | drives "data age" and stale labels |
| departureDate | Date | |
| distanceMi, durationSec, totalMi | Double | `totalMi` is the sampled polyline length used for ETA |
| polylineData | Data | packed `[Float64]` lat,lon pairs (route geometry) |
| legBoundaryIndices | [Int] | polyline indices where via-point legs join |
| weatherAttributionURL | String? | WeatherKit legal link |
| briefedAllRoutes | Bool | false |
| schemaVersion | Int | 1 |
| stops | [Stop]? | inverse `Stop.briefing`, `.cascade` |
| segments | [RouteSegment]? | inverse `RouteSegment.briefing`, `.cascade` |
| shownPOIData | Data? | JSON `[POIKind: [sourceID]]` — the pins visible when saved, so they render offline |

### Stop
| Field | Type | Note |
|---|---|---|
| id | UUID | |
| briefing | CachedBriefing? | |
| index | Int | order after sorting by `distanceMi` |
| kindRaw | String | origin / destination / sampled / manual / poi |
| label | String | |
| lat, lon | Double | snapped position |
| routeIndex | Int | polyline segment index |
| distanceMi, legMi | Double | |
| etaDate | Date | |
| dwellMin | Int | 15, 0 at endpoints |
| manualOvernight, autoOvernight | Bool | false |
| resumeDate | Date? | |
| travelBearing | Double? | |
| timeZoneID | String? | |
| poiKindRaw | String? | bucees / loves / rest |
| poiSourceID | String? | |
| offRouteMi | Double? | manual stops |
| weather | WeatherSnapshot? | inverse `WeatherSnapshot.stop`, `.cascade` |
| alerts | [Alert]? | many-to-many, inverse `Alert.stops` |
| chargersData | Data? | JSON `[Charger]` (Phase 2) |

### WeatherSnapshot
| Field | Type | Note |
|---|---|---|
| id | UUID | |
| stop | Stop? | |
| forecastForDate | Date | the ETA the forecast was fetched for (web `weatherForEpoch`) |
| recordDate | Date | timestamp of the chosen hourly/daily record |
| fetchedAt | Date | |
| tempF, feelsLikeF | Double | rounded like the web |
| humidityPct | Int? | |
| windMph | Int | rounded |
| windDeg | Double? | direction the wind comes from |
| cloudPct | Int? | |
| conditionRaw | String | `WeatherCondition` raw value |
| conditionText | String | human description |
| categoryRaw | String | clear / partly-cloudy / mostly-cloudy / rain / thunderstorm / severe / snow |
| precipChance | Double? | 0–1 |
| kindRaw | String | hourly / daily |
| horizonRaw | String | ok / beyondHorizon / failed |
| source | String | "weatherkit" |

### Alert
| Field | Type | Note |
|---|---|---|
| id | UUID | |
| nwsID | String | identity, deduped in code |
| event, severity, headline, areaDesc | String | |
| onset, ends | Date? | `onset ∥ effective`, `ends ∥ expires` |
| fetchedAt | Date | |
| stops | [Stop]? | |

### RouteSegment
| Field | Type | Note |
|---|---|---|
| id | UUID | |
| briefing | CachedBriefing? | |
| index, fromStopIndex, toStopIndex | Int | |
| coordsData | Data | packed `[Float64]` of the slice between the two stops (stop positions included) |
| avgTempF | Double? | mean of the two stop temps or whichever exists; colour is derived at render time from the current `TemperatureScale` |

### POI
| Field | Type | Note |
|---|---|---|
| kindRaw | String | bucees / loves / rest |
| sourceID | String | `bucees/57`, `loves/312`, `node/123` |
| name | String | |
| detail | String? | street, `I-35 · Exit 212`, "Rest area" / "Service plaza" |
| lat, lon | Double | |
| sourceRaw | String | bundled / official / osm / import |
| updatedAt | Date | |

### POIMeta
| Field | Type | Note |
|---|---|---|
| kindRaw | String | one row per kind |
| lastUpdated | Date? | last successful replace |
| count | Int | |
| sourceRaw | String | |
| lastAttemptAt | Date? | |
| lastError | String? | |
| snapshotVersion | String | bundled snapshot date the row came from |

### DataSourceStatus
| Field | Type | Note |
|---|---|---|
| sourceRaw | String | mapkit / weatherkit / nws / overpass / ocm / bucees / loves / rest |
| lastSuccessAt | Date? | |
| recordCount | Int | |
| lastErrorAt | Date? | |
| lastError | String? | |

Session call counts are kept in an `@Observable` `CallCounter`, not persisted.

## Not in SwiftData

- `TemperatureScale` — `@AppStorage` JSON (small, device-local like the web's `localStorage`).
- Recent locations (12, MRU) — `@AppStorage` JSON.
- NWS contact email — `@AppStorage`.
- Open Charge Map key — Keychain (`KeychainStore`).
- Bundled POI snapshot — `Resources/pois-snapshot.json`, imported into `POI` rows on first launch or when `snapshotVersion` changes and the kind has never been refreshed.

## Mapping rules

- `CachedBriefing` ⇄ `RoadTripCore.Briefing`; `Stop` ⇄ `RoadTripCore.Stop`; etc. Mappers are pure functions, tested in the app test target.
- Replacing a POI kind is one `ModelContext` transaction: delete rows of that kind, insert the new rows, update `POIMeta`. If parsing or sanity checks fail nothing is written.
