// swift-tools-version:5.9
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import PackageDescription

let package = Package(
    name: "Vorssaint",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "HIDEventSystem",
            path: "Sources/HIDEventSystem"
        ),
        .systemLibrary(
            name: "VMStatisticsCompat",
            path: "Sources/VMStatisticsCompat"
        ),
        .target(
            name: "RecorderGIFCodec",
            path: "Sources/RecorderGIFCodec",
            sources: ["RecorderGIFCodec.c", "vendor/cgif/cgif_raw.c"]
        ),
        .executableTarget(
            name: "Vorssaint",
            dependencies: ["VMStatisticsCompat", "HIDEventSystem", "RecorderGIFCodec"],
            path: "Sources/Vorssaint"
        )
    ]
)
