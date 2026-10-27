// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// A Launchpad icon for the Dock. Vorssaint lives in the menu bar, so the
/// icon is a small app of its own in ~/Applications whose only job is to
/// open the app's launchpad link and quit. It is written by the app rather
/// than shipped, so it needs no signing of its own and always points at the
/// build (official or Developer) that made it.
enum LaunchpadDockIcon {
    static var bundleIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "com.vorssaint.utils") + ".launchpad"
    }

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Launchpad.app", isDirectory: true)
    }

    /// The first URL scheme the running build declares, so the Developer
    /// build's icon opens the Developer build.
    static var scheme: String {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        return (types?.first?["CFBundleURLSchemes"] as? [String])?.first ?? "vorssaint"
    }

    /// Writes (or refreshes) the helper app and pins it to the Dock once.
    @discardableResult
    static func install() -> Bool {
        guard write() else { return false }
        return addToDock()
    }

    /// A full uninstall takes the icon off the Dock and moves the helper to
    /// the Trash, but only a helper this build wrote: the identifier is checked
    /// so an app someone else named Launchpad is never touched.
    static func uninstall() {
        guard Bundle(url: url)?.bundleIdentifier == bundleIdentifier else { return }
        let domain = "com.apple.dock" as CFString
        let key = "persistent-apps" as CFString
        let tiles = CFPreferencesCopyAppValue(key, domain) as? [[String: Any]] ?? []
        let kept = tiles.filter { tileURL($0) != url.standardizedFileURL }
        if kept.count != tiles.count {
            CFPreferencesSetAppValue(key, kept as CFArray, domain)
            if CFPreferencesAppSynchronize(domain) { Shell.run("/usr/bin/killall", ["Dock"]) }
        }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    private static func tileURL(_ tile: [String: Any]) -> URL? {
        let file = (tile["tile-data"] as? [String: Any])?["file-data"] as? [String: Any]
        return (file?["_CFURLString"] as? String).flatMap(URL.init(string:))?.standardizedFileURL
    }

    private static func write() -> Bool {
        let fm = FileManager.default
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)
        let info: [String: Any] = [
            "CFBundleExecutable": "Launchpad",
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": FeatureStrings.launchpad(L10n.shared.language).pageTitle,
            "CFBundlePackageType": "APPL",
            "CFBundleIconFile": "AppIcon",
            // The compiled glass icon, when the build made one; the icns otherwise.
            "CFBundleIconName": "AppIcon",
            "CFBundleShortVersionString": "1.0",
            // No menu bar and no running dot: the script is gone in a blink.
            "LSUIElement": true,
        ]
        let script = "#!/bin/sh\nexec /usr/bin/open -g '\(scheme)://launchpad'\n"
        do {
            try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try plist.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
            let executable = macOS.appendingPathComponent("Launchpad")
            try Data(script.utf8).write(to: executable, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            guard writeIcon(into: resources) else { return false }
        } catch {
            return false
        }
        // Finder and the Dock cache icons by bundle; tell them this one changed.
        LSRegisterURL(url as CFURL, true)
        NSWorkspace.shared.noteFileSystemChanged(url.path)
        return true
    }

    /// The Dock keeps its pinned apps in its own preferences and only reads
    /// them when it starts, so adding one means writing there and restarting
    /// it, which the system does at once.
    private static func addToDock() -> Bool {
        let domain = "com.apple.dock" as CFString
        let key = "persistent-apps" as CFString
        var tiles = CFPreferencesCopyAppValue(key, domain) as? [[String: Any]] ?? []
        let target = url.standardizedFileURL
        guard !tiles.contains(where: { tileURL($0) == target }) else { return true }
        tiles.append([
            "tile-type": "file-tile",
            "tile-data": ["file-data": ["_CFURLString": target.absoluteString, "_CFURLStringType": 15]],
        ])
        CFPreferencesSetAppValue(key, tiles as CFArray, domain)
        guard CFPreferencesAppSynchronize(domain) else { return false }
        return Shell.run("/usr/bin/killall", ["Dock"]).status == 0
    }

    // MARK: - Icon

    /// The build compiles the icon from its Icon Composer file in
    /// Resources/Brand; a build without Xcode's icon compiler draws one.
    private static func writeIcon(into resources: URL) -> Bool {
        let fm = FileManager.default
        let icns = resources.appendingPathComponent("AppIcon.icns")
        let car = resources.appendingPathComponent("Assets.car")
        try? fm.removeItem(at: icns)
        try? fm.removeItem(at: car)
        if let compiledCar = Bundle.main.url(forResource: "LaunchpadIcon", withExtension: "car"),
           let compiledIcns = Bundle.main.url(forResource: "LaunchpadIcon", withExtension: "icns"),
           (try? fm.copyItem(at: compiledCar, to: car)) != nil,
           (try? fm.copyItem(at: compiledIcns, to: icns)) != nil {
            return true
        }
        try? fm.removeItem(at: car)
        guard let target = CGImageDestinationCreateWithURL(icns as CFURL, UTType.icns.identifier as CFString,
                                                           6, nil) else { return false }
        for side in [16, 32, 128, 256, 512, 1024] {
            guard let image = drawIcon(side: side) else { return false }
            CGImageDestinationAddImage(target, image, nil)
        }
        return CGImageDestinationFinalize(target)
    }

    /// A soft white squircle holding a three-by-three grid of black tiles:
    /// the old Launchpad's idea in Vorssaint's own look.
    private static func drawIcon(side: Int) -> CGImage? {
        let size = CGFloat(side)
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let inset = size * 0.1
        let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let squircle = CGPath(roundedRect: body, cornerWidth: body.width * 0.225, cornerHeight: body.width * 0.225,
                              transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.03,
                          color: CGColor(gray: 0, alpha: 0.35))
        context.addPath(squircle)
        context.setFillColor(CGColor(gray: 0.96, alpha: 1))
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(squircle)
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
            CGColor(gray: 1, alpha: 1), CGColor(gray: 0.93, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY),
                                   options: [])
        context.restoreGState()
        // The tiles cast the same soft shadow as the brand mark.
        context.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.025,
                          color: CGColor(gray: 0, alpha: 0.3))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        let tile = body.width * 0.14
        let gap = body.width * 0.075
        let start = body.midX - (tile * 3 + gap * 2) / 2
        for index in 0..<9 {
            let rect = CGRect(x: start + CGFloat(index % 3) * (tile + gap),
                              y: body.midY + (tile * 3 + gap * 2) / 2 - CGFloat(index / 3 + 1) * tile - CGFloat(index / 3) * gap,
                              width: tile, height: tile)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: tile * 0.28, cornerHeight: tile * 0.28, transform: nil))
        }
        context.fillPath()
        return context.makeImage()
    }
}
