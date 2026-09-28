// swift-tools-version: 6.2
import CompilerPluginSupport
import PackageDescription

/// The app's Swift settings, mirrored from Piru.xcodeproj so a shared file means the same
/// thing here as in the app: MainActor default isolation, approachable concurrency, and
/// member-import visibility.
let appSwiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

/// Platforms without Apple's frameworks, where the stand-ins below take their place.
let portable: [Platform] = [.android, .linux]

let package = Package(
    name: "PiruCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Piru", targets: ["Piru"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0"),
    ],
    targets: [
        // Named `Piru` so module-qualified names (`Piru.SourceFacet`) resolve as they do in the app.
        // Sources are symlinks into the app tree: one copy of every file, compiled by both.
        .target(
            name: "Piru",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .target(name: "os", condition: .when(platforms: portable)),
                .target(name: "OSLog", condition: .when(platforms: portable)),
                .target(name: "CryptoKit", condition: .when(platforms: portable)),
                .target(name: "CoreLocation", condition: .when(platforms: portable)),
                .target(name: "SwiftData", condition: .when(platforms: portable)),
            ],
            // Apple's Foundation re-exports Observation, so shared files write `@Observable`
            // under `import Foundation` alone; the implicit import reproduces that re-export.
            swiftSettings: appSwiftSettings + [
                .unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "Observation"], .when(platforms: portable)),
            ],
        ),

        // Stand-ins, each named for the Apple module it replaces so `import X` compiles unchanged.
        .target(name: "os"),
        .target(name: "OSLog", dependencies: ["os"]),
        // swift-crypto is Apple's API-compatible open-source build of CryptoKit.
        .target(name: "CryptoKit", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
        .target(name: "CoreLocation"),
        .target(name: "SwiftData", dependencies: ["PortableData"]),

        // SwiftData's API over SQLite. Named apart from SwiftData so it builds, and is tested, on macOS too.
        .target(
            name: "PortableData",
            dependencies: ["PortableDataMacros", .product(name: "GRDB", package: "GRDB.swift")],
        ),
        .macro(
            name: "PortableDataMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
        ),
        // The core reads its identity from Info.plist, as the app's bundle provides it. On macOS the
        // plist is linked into the binary; elsewhere it ships beside it as piru-smoke.resources/.
        .executableTarget(
            name: "piru-smoke",
            dependencies: ["Piru"],
            exclude: ["Info.plist"],
            swiftSettings: appSwiftSettings,
            linkerSettings: [
                .unsafeFlags(
                    [
                        "-Xlinker",
                        "-sectcreate",
                        "-Xlinker",
                        "__TEXT",
                        "-Xlinker",
                        "__info_plist",
                        "-Xlinker",
                        "Sources/piru-smoke/Info.plist",
                    ],
                    .when(platforms: [.macOS]),
                ),
            ],
        ),
        .testTarget(name: "PortableDataTests", dependencies: ["PortableData"], swiftSettings: appSwiftSettings),
    ],
)
