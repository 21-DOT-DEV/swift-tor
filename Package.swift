// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "swift-tor",
    products: [
        .library(name: "libtor", targets: ["libtor"]),
        .library(name: "Tor", targets: ["Tor"])
    ],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-plugin-subtree.git", exact: "0.0.7")
    ],
    targets: [
        .target(
            name: "libtor",
            cSettings: [
                // C settings will be configured after analyzing Tor's build system
            ]
        ),
        .target(
            name: "Tor",
            dependencies: ["libtor"]
        )
    ],
    swiftLanguageModes: [.v6]
)
