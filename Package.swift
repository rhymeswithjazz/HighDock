// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HighDock",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "HighDock", targets: ["HighDock"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.5")],
    targets: [
        .target(name: "HighDockCore"),
        .target(name: "HighDockPlatform", dependencies: ["HighDockCore"]),
        .executableTarget(name: "HighDockProbe", dependencies: ["HighDockCore", "HighDockPlatform"]),
        .executableTarget(name: "HighDock", dependencies: ["HighDockCore", "HighDockPlatform", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "HighDockCoreTests", dependencies: ["HighDockCore"]),
        .testTarget(name: "HighDockPlatformTests", dependencies: ["HighDockPlatform", "HighDockCore"]),
        .testTarget(name: "HighDockTests", dependencies: ["HighDock", "HighDockPlatform", "HighDockCore"])
    ]
)
