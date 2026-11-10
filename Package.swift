// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sunroom",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Sunroom", targets: ["Sunroom"]),
        .library(name: "SunroomCore", targets: ["SunroomCore"]),
        .library(name: "SunroomKit", targets: ["SunroomKit"]),
    ],
    targets: [
        .target(
            name: "SunroomCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "SunroomKit",
            dependencies: ["SunroomCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Sunroom",
            dependencies: ["SunroomCore", "SunroomKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SunroomRender",
            dependencies: ["SunroomCore", "SunroomKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SunroomCoreTests",
            dependencies: ["SunroomCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
