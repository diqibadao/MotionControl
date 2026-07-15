// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MotionControl",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MotionControl", targets: ["MotionControl"])
    ],
    targets: [
        .executableTarget(
            name: "AXHelper",
            dependencies: [],
            path: "Sources/AXHelper",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/AXHelper/Info.plist"
                ])
            ]
        ),
        .executableTarget(
            name: "MotionControl",
            dependencies: [],
            resources: [.process("Resources")],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/MotionControl/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "MotionControlTests",
            dependencies: ["MotionControl"]
        ),
    ]
)
