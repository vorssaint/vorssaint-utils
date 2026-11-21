// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

extension MenuBarIconAnimation {
    private var frameCount: Int {
        switch self {
        case .cat, .dog, .slime, .drop, .newtonCradle, .mochi: return 5
        case .coffee, .engine: return 10
        }
    }

    /// Some runners revisit frames within a loop in RunCat Neo.
    var frameOrder: [Int] {
        switch self {
        case .slime: return [0, 1, 2, 3, 4, 4, 3, 2, 1]
        case .newtonCradle: return [0, 1, 2, 1, 0, 3, 4, 3]
        case .mochi: return [0, 1, 2, 3, 4, 3, 2, 1]
        case .cat, .dog, .drop, .coffee, .engine: return Array(0..<frameCount)
        }
    }

    var frames: [NSImage] { Self.framesByAnimation[self] ?? [] }

    private static let framesByAnimation = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0, $0.loadFrames()) }
    )

    private func loadFrames() -> [NSImage] {
        let frames = (0..<frameCount).compactMap { index -> NSImage? in
            guard let url = Bundle.main.url(forResource: "\(rawValue)-frame-\(index)",
                                            withExtension: "png", subdirectory: "MenuBarRunners"),
                  let source = NSImage(contentsOf: url),
                  source.size.width > 0, source.size.height > 0 else { return nil }

            let canvas = BlackHoleGlyph.pointSize
            let scale = min((canvas.width - 2) / source.size.width,
                            (canvas.height - 2) / source.size.height)
            let width = source.size.width * scale
            let height = source.size.height * scale
            let image = NSImage(size: canvas, flipped: false) { rect in
                source.draw(in: NSRect(x: rect.midX - width / 2, y: rect.midY - height / 2,
                                       width: width, height: height))
                return true
            }
            image.isTemplate = true
            return image
        }
        guard frames.count == frameCount else { return [] }
        return frameOrder.map { frames[$0] }
    }

    /// CPU usage is a fraction of the whole machine. Keep motion visible at
    /// idle and limit status-bar redraws even when all cores are busy.
    static func frameInterval(cpuUsage: Double?) -> TimeInterval {
        let usage = cpuUsage ?? 0
        let load = usage.isFinite ? min(max(usage, 0), 1) : 0
        return 1 / (4 + 10 * load)
    }
}
