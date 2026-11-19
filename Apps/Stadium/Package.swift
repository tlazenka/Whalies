// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Stadium",
    platforms: [.macOS(.v15), .iOS(.v18), .macCatalyst(.v18)],
    products: [
        .library(name: "StadiumCore", targets: ["StadiumCore"]),
        .library(name: "WhaleKartCore", targets: ["WhaleKartCore"]),
        .library(name: "CrowdCore", targets: ["CrowdCore"]),
        .library(name: "BallgameCore", targets: ["BallgameCore"]),
        .library(name: "StadiumGame", targets: ["StadiumGame"]),
        .library(name: "StadiumKit", targets: ["StadiumKit"]),
        .executable(name: "whalekart", targets: ["WhaleKartCLI"]),
        .executable(name: "stadium", targets: ["StadiumCLI"]),
    ],
    dependencies: [.package(name: "Muttniks", path: "../..")],
    targets: [
        .target(name: "StadiumCore"),
        .target(name: "WhaleKartCore", dependencies: ["StadiumCore"]),
        .target(name: "CrowdCore", dependencies: ["StadiumCore"]),
        .target(name: "BallgameCore", dependencies: ["StadiumCore"]),
        .target(name: "StadiumGame", dependencies: ["StadiumCore", "WhaleKartCore", "CrowdCore"]),
        .target(name: "StadiumKit", dependencies: [
            "StadiumCore", "WhaleKartCore", "CrowdCore", "StadiumGame",
            .product(name: "JSONViewKit", package: "Muttniks"),
            .product(name: "WhaleyCore", package: "Muttniks", condition: .when(platforms: [.iOS, .macCatalyst])),
            .product(name: "WhaleyHost", package: "Muttniks", condition: .when(platforms: [.iOS, .macCatalyst])),
            .product(name: "SQLiteJSONBlaster", package: "Muttniks", condition: .when(platforms: [.iOS, .macCatalyst])),
        ], resources: [.copy("Resources/WaterLens.metal")]),
        .executableTarget(name: "WhaleKartCLI", dependencies: ["WhaleKartCore"]),
        .executableTarget(name: "StadiumCLI", dependencies: ["StadiumGame"]),
        .testTarget(name: "StadiumCoreTests", dependencies: ["StadiumCore"]),
        .testTarget(name: "WhaleKartCoreTests", dependencies: ["WhaleKartCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "CrowdCoreTests", dependencies: ["CrowdCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "BallgameCoreTests", dependencies: ["BallgameCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "StadiumGameTests", dependencies: ["StadiumGame"], resources: [.copy("Fixtures")]),
        .testTarget(name: "StadiumKitTests", dependencies: [
            "StadiumKit", "StadiumGame", "StadiumCore", "CrowdCore",
            .product(name: "JSONViewKit", package: "Muttniks"),
        ]),
    ],
    swiftLanguageModes: [.v5]
)
