// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

extension MenuBarIconAnimation {
    var frameCount: Int {
        switch self {
        case .cat: return 5
        case .coffee: return 10
        }
    }

    var frames: [NSImage] {
        switch self {
        case .cat: return Self.catFrames
        case .coffee: return Self.coffeeFrames
        }
    }

    private static let catFrames = Self.cat.loadFrames()
    private static let coffeeFrames = Self.coffee.loadFrames()

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
        return frames.count == frameCount ? frames : []
    }

    /// CPU usage is a fraction of the whole machine. Keep motion visible at
    /// idle and limit status-bar redraws even when all cores are busy.
    static func frameInterval(cpuUsage: Double?) -> TimeInterval {
        let usage = cpuUsage ?? 0
        let load = usage.isFinite ? min(max(usage, 0), 1) : 0
        return 1 / (4 + 10 * load)
    }
}
