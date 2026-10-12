# TestFlight upload

One-time: an app record for `com.keggman12.RoadTripWeather` must exist in App Store Connect.

```bash
# bump the build number every upload
xcodegen generate
xcodebuild -project RoadTripWeather.xcodeproj -scheme RoadTripWeather -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/RoadTripWeather.xcarchive \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION=<N> archive
xcodebuild -exportArchive -archivePath build/RoadTripWeather.xcarchive \
  -exportOptionsPlist tools/testflight/ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates
```

`ExportOptions.plist` uploads straight to App Store Connect. Builds can go to internal and
external testers (`testFlightInternalTestingOnly` is `false` from build 4). A build uploaded as
internal-only can never be added to an external group.
