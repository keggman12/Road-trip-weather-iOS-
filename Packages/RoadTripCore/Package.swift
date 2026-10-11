// swift-tools-version: 6.0
import PackageDescription

// RoadTripCore — models and pure logic for Road Trip Weather.
// Foundation only: no UI, MapKit, WeatherKit or CoreLocation, so it builds
// on Linux and macOS as well as iOS and is shared by the app and tools/.
let package = Package(
    name: "RoadTripCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "RoadTripCore", targets: ["RoadTripCore"]),
    ],
    targets: [
        .target(
            name: "RoadTripCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RoadTripCoreTests",
            dependencies: ["RoadTripCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
