// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Emulist",
    platforms: [.macOS("14.2")],
    products: [
        .executable(name: "Emulist", targets: ["Emulist"]),
        .executable(name: "emulist-cli", targets: ["emulist-cli"]),
        .library(name: "EmulistCore", targets: ["EmulistCore"]),
    ],
    targets: [
        // Color science, film model, Metal pipeline, video I/O and project model. No UI.
        .target(name: "EmulistCore"),
        // The SwiftUI application.
        .executableTarget(name: "Emulist", dependencies: ["EmulistCore"]),
        // Headless renderer used for look development, test charts and batch export.
        .executableTarget(name: "emulist-cli", dependencies: ["EmulistCore"]),
        .testTarget(name: "EmulistCoreTests", dependencies: ["EmulistCore"]),
    ]
)
