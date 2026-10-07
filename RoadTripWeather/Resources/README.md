# Resources

`pois-snapshot.json` is a **placeholder with no POIs**. Real data is harvested on your Mac
(this repo never ships fabricated locations):

```bash
cd tools/poi-snapshot
swift run poi-snapshot --out ../../RoadTripWeather/Resources/pois-snapshot.json
```

The app imports the snapshot on first launch (or when `generatedAt` changes and the kind
has not been refreshed from a live source). Format: `RoadTripCore.POISnapshot`.

`Assets.xcassets` is created by Xcode on first open if missing; add an `AppIcon` and an
`AccentColor` there.
