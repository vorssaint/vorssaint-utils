// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ScreenCaptureKit

/// Reading pixels off a display or a window through ScreenCaptureKit, for the
/// features that look at the screen without being a capture tool themselves
/// (Watch in the island) and for the screenshot tool's frozen frame.
enum ScreenRegionCapture {
    /// An area of one display, resolved once when it is chosen.
    struct Region: Equatable {
        let displayID: CGDirectDisplayID
        /// Set only when the area is a whole window.
        let windowID: CGWindowID?
        /// Top-left origin, in the display's pixels.
        let pixelRect: CGRect
        /// The same area in Cocoa global points.
        let anchorRect: CGRect
        /// Pixels per point of the source display.
        let scale: CGFloat
    }

    /// One prepared capture that can be read again and again: resolving the
    /// shareable windows for every reading adds latency.
    final class RegionCapture: @unchecked Sendable {
        private let filter: SCContentFilter
        private let configuration: SCStreamConfiguration

        init(filter: SCContentFilter, configuration: SCStreamConfiguration) {
            self.filter = filter
            self.configuration = configuration
        }

        func image() async -> CGImage? {
            try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                       configuration: configuration)
        }
    }

    /// A part of one display with every window of this app left out, so a
    /// reading never sees the app's own surfaces change.
    static func prepareDisplayRegion(displayID: CGDirectDisplayID,
                                     pixelRect: CGRect) async -> RegionCapture? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true),
            let display = content.displays.first(where: { $0.displayID == displayID })
        else { return nil }
        let scale = screenScale(for: displayID)
        let displayPixels = CGRect(x: 0, y: 0,
                                   width: CGFloat(display.width) * scale,
                                   height: CGFloat(display.height) * scale)
        let clamped = pixelRect.intersection(displayPixels).integral
        guard !clamped.isNull, !clamped.isEmpty else { return nil }
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: clamped.minX / scale,
                                          y: clamped.minY / scale,
                                          width: clamped.width / scale,
                                          height: clamped.height / scale)
        configuration.width = max(1, Int(clamped.width))
        configuration.height = max(1, Int(clamped.height))
        configuration.showsCursor = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        return RegionCapture(filter: filter, configuration: configuration)
    }

    /// Every display at full resolution, exactly as it looks, keyed by display
    /// id. A display that fails is absent.
    static func captureAllDisplays(includePointer: Bool) async -> [CGDirectDisplayID: CGImage] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        else { return [:] }
        var result: [CGDirectDisplayID: CGImage] = [:]
        for screen in NSScreen.screens {
            let id = screen.displayID
            guard id != 0, let display = content.displays.first(where: { $0.displayID == id })
            else { continue }
            let scale = screen.backingScaleFactor
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int((CGFloat(display.width) * scale).rounded()))
            configuration.height = max(1, Int((CGFloat(display.height) * scale).rounded()))
            configuration.showsCursor = includePointer
            configuration.colorSpaceName = CGColorSpace.sRGB
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                      configuration: configuration) {
                result[id] = image
            }
        }
        return result
    }

    /// The window drawn on its own, whole wherever it sits.
    static func captureIndependentWindow(_ windowID: CGWindowID, scale: CGFloat) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true),
            let window = content.windows.first(where: { $0.windowID == windowID })
        else { return nil }
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((window.frame.width * scale).rounded()))
        configuration.height = max(1, Int((window.frame.height * scale).rounded()))
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// Other apps' ordinary on-screen windows, front to back, in the window
    /// server's global top-left coordinates.
    static func otherAppWindows() -> [(id: CGWindowID, bounds: CGRect)] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let ownPID = Int32(ProcessInfo.processInfo.processIdentifier)
        return info.compactMap { entry in
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat]
            else { return nil }
            let bounds = CGRect(x: boundsDict["X"] ?? 0,
                                y: boundsDict["Y"] ?? 0,
                                width: boundsDict["Width"] ?? 0,
                                height: boundsDict["Height"] ?? 0)
            guard bounds.width >= 40, bounds.height >= 40 else { return nil }
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { return nil }
            return (id: id, bounds: bounds)
        }
    }

    private static func screenScale(for displayID: CGDirectDisplayID) -> CGFloat {
        NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
    }
}

extension NSScreen {
    /// The CoreGraphics display id behind this screen; 0 when missing, which
    /// callers treat as not capturable.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
