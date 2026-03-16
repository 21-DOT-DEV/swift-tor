// swift-tools-version: 6.1

// MARK: - Release Build Optimizations (Future)
// Link-Time Optimization (LTO) - Can reduce binary size 10-20%:
//   .unsafeFlags(["-flto=thin"], .when(configuration: .release))
// Strip Debug Symbols - Further reduces release binary size:
//   .unsafeFlags(["-Xlinker", "-dead_strip"], .when(configuration: .release))
// Note: unsafeFlags prevent use as a dependency; consider for app targets only

import PackageDescription

let package = Package(
    name: "swift-tor",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
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
            dependencies: [
                .product(name: "libcrypto", package: "swift-openssl"),
                .product(name: "libssl", package: "swift-openssl"),
                .product(name: "libevent", package: "swift-event"),
            ],
            exclude: [
                "src/ext/ed25519/donna/test-internals.c",  // Included inline by ed25519_tor.c
                "src/ext/strlcpy.c",                       // Included inline by compat_string.c
                "src/ext/strlcat.c",                       // Included inline by compat_string.c
            ],
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("."),
                .headerSearchPath("src"),
                .headerSearchPath("src/ext"),
                .headerSearchPath("src/ext/trunnel"),
                .headerSearchPath("src/ext/equix/include"),
                .headerSearchPath("src/ext/equix/hashx/include"),
                .headerSearchPath("src/ext/equix/hashx/src"),
                .define("HAVE_CONFIG_H"),
                .define("HAVE_MODULE_POW"),  // Enable PoW module (equix already extracted)
                .define("ED25519_SUFFIX", to: "_donna"),  // Required for curve25519 symbol names
                .define("_SYS_BUF_H_"),  // Prevents conflict with system sys/buf.h
                .define("FALLTHROUGH", to: "__attribute__((fallthrough))"),
                .define("SHARE_DATADIR", to: "\"/usr/local/share\""),  // Required: default GeoIP path (overridden at runtime)
                .define("LOCALSTATEDIR", to: "\"/usr/local/var\""),  // Required: fallback DataDirectory (never used - always set programmatically)
                // Linux: Enable GNU extensions (memmem, etc.)
                .define("_GNU_SOURCE", .when(platforms: [.linux])),
            ],
            linkerSettings: [
                .linkedLibrary("z"), // zlib => -lz
            ]
        ),
        .target(
            name: "Tor",
            dependencies: ["libtor"]
        ),
        .testTarget(
            name: "TorTests",
            dependencies: ["Tor", "libtor"]
        ),
        .executableTarget(
            name: "TorDemo",
            dependencies: ["Tor", "libtor"],
            path: "Sources/TorDemo"
        )
    ],
    swiftLanguageModes: [.v6]
)
