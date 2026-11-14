// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MailroomDeck",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MailroomCore", targets: ["MailroomCore"]),
        .executable(name: "MailroomApp", targets: ["MailroomApp"]),
        .executable(name: "mailroom-bridge", targets: ["MailroomBridgeCLI"])
    ],
    targets: [
        .target(
            name: "MailroomCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedLibrary("iconv")
            ]
        ),
        .executableTarget(
            name: "MailroomApp",
            dependencies: ["MailroomCore"]
        ),
        .executableTarget(
            name: "MailroomBridgeCLI",
            dependencies: ["MailroomCore"]
        ),
        .testTarget(
            name: "MailroomCoreTests",
            dependencies: ["MailroomCore"]
        )
    ]
)
