// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MailroomDeck",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "MailroomCore", targets: ["MailroomCore"]),
        .library(name: "MailroomFeatures", targets: ["MailroomFeatures"]),
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
        // ViewModel / Store / View 层：可被测试与 Preview 直接引用
        .target(
            name: "MailroomFeatures",
            dependencies: ["MailroomCore"]
        ),
        // 仅保留 @main 组装入口
        .executableTarget(
            name: "MailroomApp",
            dependencies: ["MailroomFeatures"]
        ),
        .executableTarget(
            name: "MailroomBridgeCLI",
            dependencies: ["MailroomCore"]
        ),
        .testTarget(
            name: "MailroomCoreTests",
            dependencies: ["MailroomCore"]
        ),
        .testTarget(
            name: "MailroomFeaturesTests",
            dependencies: ["MailroomFeatures", "MailroomCore"],
            exclude: ["__Goldens__", "__Snapshots__"]
        )
    ]
)
