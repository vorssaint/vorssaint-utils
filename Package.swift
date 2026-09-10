// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import PackageDescription

let package = Package(
    name: "Vorssaint",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VorssaintWebPEncoder", targets: ["VorssaintWebPEncoder"]),
    ],
    dependencies: [
        .package(url: "https://github.com/the-swift-collective/libwebp.git", exact: "1.4.0"),
    ],
    targets: [
        .systemLibrary(
            name: "HIDEventSystem",
            path: "Sources/HIDEventSystem"
        ),
        .systemLibrary(
            name: "VMStatisticsCompat",
            path: "Sources/VMStatisticsCompat"
        ),
        .executableTarget(
            name: "Vorssaint",
            dependencies: ["VMStatisticsCompat", "HIDEventSystem"],
            path: "Sources/Vorssaint"
        ),
        .executableTarget(
            name: "VorssaintWebPEncoder",
            dependencies: [.product(name: "WebP", package: "libwebp")],
            path: "Sources/WebPEncoder"
        )
    ]
)
