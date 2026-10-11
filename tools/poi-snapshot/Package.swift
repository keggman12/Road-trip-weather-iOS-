// swift-tools-version: 6.0
import PackageDescription

// Dev-time tool (not shipped): regenerates RoadTripWeather/Resources/pois-snapshot.json
// from the same sources as the web app's server/seed-pois.js, using RoadTripCore's
// parsers so the app and the tool can never disagree about the data shape.
let package = Package(
    name: "poi-snapshot",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/RoadTripCore"),
    ],
    targets: [
        .executableTarget(
            name: "poi-snapshot",
            dependencies: [.product(name: "RoadTripCore", package: "RoadTripCore")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
