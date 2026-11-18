// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The moon wallpaper: its still frame, drawn for the display macOS shows
/// the lock screen on and set as that display's desktop picture, and the
/// rule for when the lock screen may lay its live layer over it.
///
/// The live layer only adds what moves, so it shows only while the desktop
/// picture is the frame drawn for that display's present size; any other
/// picture would show through around it.
enum NotchLockWallpaper {
    /// The display macOS draws the clock and the password field on.
    static var lockScreen: NSScreen? {
        let main = CGMainDisplayID()
        return NSScreen.screens.first(where: { $0.notchDisplayID == main }) ?? NSScreen.screens.first
    }

    static func scene(for screen: NSScreen) -> NotchLockWallpaperScene {
        NotchLockWallpaperScene(width: Double(screen.frame.width), height: Double(screen.frame.height),
                                scale: Double(screen.backingScaleFactor))
    }

    static var folder: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("LockWallpaper", isDirectory: true)
    }

    /// One file per scene and display size, so a frame is never redrawn
    /// under a desktop picture that already shows it.
    static func frameURL(for scene: NotchLockWallpaperScene) -> URL? {
        folder?.appendingPathComponent(
            "moon-v\(NotchLockWallpaperScene.version)-\(scene.pixelWidth)x\(scene.pixelHeight).png", isDirectory: false)
    }

    /// The live layer's scene, while the lock screen's display shows the
    /// still frame drawn for it.
    static func liveScene(in defaults: UserDefaults = .standard) -> (scene: NotchLockWallpaperScene, frame: CGRect)? {
        guard NotchLockScreenSupport.showsWallpaper(in: defaults), let screen = lockScreen else { return nil }
        let scene = scene(for: screen)
        guard let url = frameURL(for: scene),
              NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL == url.standardizedFileURL,
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return (scene, screen.frame)
    }

    private static let queue = DispatchQueue(label: "com.vorssaint.lock-wallpaper", qos: .userInitiated)

    /// Draws the still frame for the lock screen's display, when it has not
    /// been drawn yet, and sets it as that display's desktop picture.
    static func apply(completion: ((Bool) -> Void)? = nil) {
        guard let screen = lockScreen else { completion?(false); return }
        let scene = scene(for: screen)
        guard let folder, let url = frameURL(for: scene) else { completion?(false); return }
        let displayID = screen.notchDisplayID
        queue.async {
            var ready = FileManager.default.fileExists(atPath: url.path)
            if !ready, PrivateFileStore.createDirectory(at: folder), let image = scene.renderFrame(),
               let data = png(image) {
                ready = PrivateFileStore.write(data, to: url)
            }
            DispatchQueue.main.async {
                // The display may have gone while the frame was drawn.
                guard ready, let screen = NSScreen.screens.first(where: { $0.notchDisplayID == displayID }) else {
                    completion?(false)
                    return
                }
                let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true,
                ]
                let set = (try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)) != nil
                if set { removeUnused(keeping: url) }
                completion?(set)
            }
        }
    }

    /// Frames for other sizes or older scenes that no display shows.
    private static func removeUnused(keeping current: URL) {
        guard let folder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return }
        let shown = Set(NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0)?.standardizedFileURL })
            .union([current.standardizedFileURL])
        for file in files where file.pathExtension == "png" && !shown.contains(file.standardizedFileURL) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
