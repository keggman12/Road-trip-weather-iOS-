# Resources

`pois-snapshot.json` is the bundled POI snapshot the app imports on first launch
(format: `RoadTripCore.POISnapshot`). The committed file was harvested with
`tools/poi-snapshot` on 2026-10-07 from the same sources as the web app's
`server/seed-pois.js`:

| Kind | Count | Source |
|---|---|---|
| Buc-ee's | 57 | buc-ees.com/locations JSON-LD (official) |
| Love's Travel Stops | 619 | loves.com/api/fetch_stores (official; Country Stores and Speedco excluded) |
| Rest areas / service plazas | 3,622 | OpenStreetMap via Overpass (branded plazas excluded) |

Regenerate on your Mac:

```bash
cd tools/poi-snapshot
swift run poi-snapshot --out ../../RoadTripWeather/Resources/pois-snapshot.json
```

A kind whose sources all fail keeps its rows from the existing file; if nothing can be
harvested the file is left untouched. The app re-imports a kind when `generatedAt` changes
and that kind has not since been refreshed from a live source in-app.

`Assets.xcassets` is created by Xcode on first open if missing; add an `AppIcon` and an
`AccentColor` there.
