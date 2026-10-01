// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Icons at Launchpad Classic's tile size, cached the same way
/// `CommandBarIconCache` caches Command Bar's smaller ones — full-size
/// `NSWorkspace` icons are expensive and disk-backed, so every tile would
/// otherwise re-read them on every redraw.
enum LaunchpadIconCache {
    private static let side: CGFloat = 128
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    static func icon(forPath path: String) -> NSImage {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        let full = NSWorkspace.shared.icon(forFile: path)
        let sized = downsampled(full)
        cache.setObject(sized, forKey: path as NSString, cost: Int(side * side * 4))
        return sized
    }

    private static func downsampled(_ image: NSImage) -> NSImage {
        let result = NSImage(size: NSSize(width: side, height: side))
        result.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: .zero, operation: .copy, fraction: 1)
        result.unlockFocus()
        return result
    }
}

/// The live installed-app scan Launchpad Classic's grid reads from.
/// Re-scanned each time the panel opens (see `LaunchpadService.show()`),
/// never persisted — only the user's arrangement of it is (`LaunchpadLayoutStore`).
final class LaunchpadAppCatalog: ObservableObject {
    static let shared = LaunchpadAppCatalog()

    @Published private(set) var apps: [LaunchpadApp] = []

    private init() {}

    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let installed = InstalledApps.installedApplications(includeSystemApplications: true)
            let apps = LaunchpadAppSupport.apps(from: installed)
            DispatchQueue.main.async { self?.apps = apps }
        }
    }
}
