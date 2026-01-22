// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-tor",
    products: [
        .library(name: "libtor", targets: ["libtor"]),
        .library(name: "Tor", targets: ["Tor"])
    ],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-plugin-subtree.git", exact: "0.0.7"),
        .package(url: "https://github.com/21-DOT-DEV/swift-openssl.git", branch: "main"),
        .package(url: "https://github.com/21-DOT-DEV/swift-event.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "libtor",
            cSettings: [
                // C settings will be configured after analyzing Tor's build system
            ],
            linkerSettings: [
                .linkedLibrary("z") // zlib => -lz
            ]
        ),
        .target(
            name: "Tor",
            dependencies: ["libtor"]
        )
    ],
    swiftLanguageModes: [.v6]
)
