// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import ScreenCaptureKit

/// Raw pixel acquisition for the screenshot tool. Displays go through
/// ScreenCaptureKit; a clicked window prefers the window server so the result
/// is the window's own crisp buffer (rounded corners, no neighbors bleeding
/// in), with ScreenCaptureKit as the fallback. The windows the screenshot
/// workflow puts on screen are always excluded so captures never contain the
/// tool taking them; the rest of the app follows the visibility preference.
enum ScreenshotCaptureEngine {

    /// Full-resolution capture of one display.
    static func captureDisplay(_ displayID: CGDirectDisplayID,
                               includePointer: Bool,
                               hideVorssaintWindows: Bool,
                               protectedWindowIDs: Set<CGWindowID>) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        else { return nil }
        guard let display = content.displays.first(where: { $0.displayID == displayID })
        else { return nil }

        let ownWindows = excludedOwnWindows(in: content,
                                            hideVorssaintWindows: hideVorssaintWindows,
                                            protectedWindowIDs: protectedWindowIDs)
        return await captureDisplay(display,
                                    scale: screenScale(for: displayID),
                                    excluding: ownWindows,
                                    includePointer: includePointer)
    }

    static func captureDisplayRegion(displayID: CGDirectDisplayID,
                                     pixelRect: CGRect,
                                     includePointer: Bool,
                                     hideVorssaintWindows: Bool,
                                     protectedWindowIDs: Set<CGWindowID>) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true),
            let display = content.displays.first(where: { $0.displayID == displayID })
        else { return nil }
        let scale = screenScale(for: displayID)
        let displayPixels = CGRect(x: 0, y: 0,
                                   width: CGFloat(display.width) * scale,
                                   height: CGFloat(display.height) * scale)
        let clamped = ScreenshotSupport.clamp(pixelRect, to: displayPixels).integral
        guard !clamped.isEmpty else { return nil }
        let ownWindows = excludedOwnWindows(in: content,
                                            hideVorssaintWindows: hideVorssaintWindows,
                                            protectedWindowIDs: protectedWindowIDs)
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: clamped.minX / scale,
                                          y: clamped.minY / scale,
                                          width: clamped.width / scale,
                                          height: clamped.height / scale)
        configuration.width = max(1, Int(clamped.width))
        configuration.height = max(1, Int(clamped.height))
        configuration.showsCursor = includePointer
        configuration.colorSpaceName = CGColorSpace.sRGB
        return try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                           configuration: configuration)
    }

    /// Captures every given screen, keyed by display id. Screens that fail
    /// are simply absent; the caller decides how to degrade.
    static func captureAllDisplays(includePointer: Bool,
                                   hideVorssaintWindows: Bool,
                                   protectedWindowIDs: Set<CGWindowID>) async -> [CGDirectDisplayID: CGImage] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        else { return [:] }
        let ownWindows = excludedOwnWindows(in: content,
                                            hideVorssaintWindows: hideVorssaintWindows,
                                            protectedWindowIDs: protectedWindowIDs)
        var result: [CGDirectDisplayID: CGImage] = [:]
        for screen in NSScreen.screens {
            let id = screen.displayID
            guard id != 0,
                  let display = content.displays.first(where: { $0.displayID == id })
            else { continue }
            if let image = await captureDisplay(display,
                                                scale: screen.backingScaleFactor,
                                                excluding: ownWindows,
                                                includePointer: includePointer) {
                result[id] = image
            }
        }
        return result
    }

    /// The app's own windows a display capture must leave out, resolved
    /// against the same shareable-content snapshot the capture will use.
    private static func excludedOwnWindows(in content: SCShareableContent,
                                           hideVorssaintWindows: Bool,
                                           protectedWindowIDs: Set<CGWindowID>) -> [SCWindow] {
        let ownWindowIDs = Set(content.windows.compactMap { window in
            window.owningApplication?.processID == getpid() ? window.windowID : nil
        })
        let excludedIDs = ScreenshotCapturePolicy.excludedWindowIDs(
            hideVorssaintWindows: hideVorssaintWindows,
            ownWindowIDs: ownWindowIDs,
            protectedWindowIDs: protectedWindowIDs)
        return content.windows.filter { excludedIDs.contains($0.windowID) }
    }

    private static func captureDisplay(_ display: SCDisplay,
                                       scale: CGFloat,
                                       excluding ownWindows: [SCWindow],
                                       includePointer: Bool) async -> CGImage? {
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((CGFloat(display.width) * scale).rounded()))
        configuration.height = max(1, Int((CGFloat(display.height) * scale).rounded()))
        configuration.showsCursor = includePointer
        configuration.colorSpaceName = CGColorSpace.sRGB
        return try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                           configuration: configuration)
    }

    /// The window's own buffer via the window server (same capture the
    /// switcher thumbnails use), full resolution, falling back to
    /// ScreenCaptureKit when the private route is unavailable or when it
    /// returns only the visible slice of a window that runs off the screen.
    static func captureWindow(_ windowID: CGWindowID, scale: CGFloat) async -> CGImage? {
        // A sheet or dialog the app stacked on the window is a window of its
        // own, and neither single-window route draws it (issue #1098). The
        // window list answers this without waiting on shareable content, so
        // the ordinary capture keeps the faster route.
        let onScreen = onScreenWindows()
        if let target = onScreen.first(where: { $0.id == windowID }),
           let geometricPlan = ScreenshotCapturePolicy.attachedCapturePlan(
               target: target, frontToBack: onScreen) {
            var plan: ScreenshotCapturePolicy.AttachedCapturePlan? = geometricPlan
            if Permissions.shared.accessibility {
                let confirmedIDs = accessibilityAttachedWindowIDs(
                    targetWindowID: target.id,
                    ownerPID: target.ownerPID,
                    candidateWindowIDs: Array(geometricPlan.windowIDs.dropFirst()))
                plan = ScreenshotCapturePolicy.confirmedAttachment(
                    geometricPlan, confirmedIDs: confirmedIDs)
            }
            if let plan,
               let composited = await captureAttached(plan) {
                return composited
            }
        }
        var clippedFallback: CGImage?
        if let image = WindowPreviewProvider.captureViaWindowServer(windowID) {
            let bounds = windowBounds(windowID)
            if bounds.map({ SwitcherSupport.captureCoversWindow(imageWidth: image.width,
                                                                imageHeight: image.height,
                                                                windowSize: $0.size) }) ?? true {
                return image
            }
            clippedFallback = image
        }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true),
            let window = content.windows.first(where: { $0.windowID == windowID })
        else { return clippedFallback }
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((window.frame.width * scale).rounded()))
        configuration.height = max(1, Int((window.frame.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let capture = try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                  configuration: configuration)
        return capture ?? clippedFallback
    }

    /// On-screen windows front to back, as the attached-window decision needs
    /// them. Ordinary layer-zero windows only, so a menu or the Dock cannot
    /// read as something stacked on the clicked window.
    private static func onScreenWindows() -> [ScreenshotCapturePolicy.CaptureWindow] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return info.compactMap { entry in
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat]
            else { return nil }
            if let alpha = entry[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { return nil }
            return ScreenshotCapturePolicy.CaptureWindow(
                id: id,
                ownerPID: pid,
                frame: CGRect(x: boundsDict["X"] ?? 0,
                              y: boundsDict["Y"] ?? 0,
                              width: boundsDict["Width"] ?? 0,
                              height: boundsDict["Height"] ?? 0))
        }
    }

    /// The geometric candidates Accessibility does not positively identify as
    /// standard windows. `nil` means the app did not provide a window map that
    /// names the target.
    private static func accessibilityAttachedWindowIDs(
        targetWindowID: CGWindowID,
        ownerPID: pid_t,
        candidateWindowIDs: [CGWindowID]) -> Set<CGWindowID>? {
        guard AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(ownerPID)
        guard let windows = accessibilityElements(application, kAXWindowsAttribute as CFString)
        else { return nil }

        var elementsByID: [CGWindowID: AXUIElement] = [:]
        for window in windows {
            if let id = AXWindowResolver.windowID(for: window) {
                elementsByID[id] = window
            }
        }
        guard !elementsByID.isEmpty,
              elementsByID[targetWindowID] != nil
        else { return nil }

        var confirmed: Set<CGWindowID> = []
        for candidateID in candidateWindowIDs {
            guard let element = elementsByID[candidateID] else {
                // AX had no answer for this one — only a window AX positively identifies as standard is filtered out.
                confirmed.insert(candidateID)
                continue
            }
            // The standard set matches what the auto-quit and enumeration paths already read.
            if let subrole = accessibilityString(element, kAXSubroleAttribute as CFString),
               subrole == (kAXStandardWindowSubrole as String) || subrole == "AXFullScreenWindow" {
                continue
            }
            confirmed.insert(candidateID)
        }
        return confirmed
    }

    private static func accessibilityElements(_ element: AXUIElement,
                                              _ attribute: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let elements = value as? [AXUIElement]
        else { return nil }
        return elements
    }

    private static func accessibilityString(_ element: AXUIElement,
                                            _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success
        else { return nil }
        return value as? String
    }

    /// Draws the clicked window together with what the app stacked on it.
    /// ScreenCaptureKit is the only route that takes more than one window. It
    /// captures their composited display, then crops it to the area they cover.
    /// `nil` leaves the single-window routes to answer.
    private static func captureAttached(
        _ plan: ScreenshotCapturePolicy.AttachedCapturePlan) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        else { return nil }
        let windows = plan.windowIDs.compactMap { id in
            content.windows.first { $0.windowID == id }
        }
        let hits = content.displays.filter { $0.frame.intersects(plan.bounds) }
        // A window straddling two displays has no single display to crop from,
        // while one hanging off a lone display's edge still does: the crop
        // clamps the part that is on screen.
        guard windows.count == plan.windowIDs.count,
              hits.count == 1,
              let display = hits.first,
              let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }),
              let mainScreen = NSScreen.screens.first
        else { return nil }
        let filter = SCContentFilter(display: display, including: windows)
        let configuration = SCStreamConfiguration()
        let pixelScale = CGFloat(filter.pointPixelScale)
        configuration.width = max(1, Int((CGFloat(display.width) * pixelScale).rounded()))
        configuration.height = max(1, Int((CGFloat(display.height) * pixelScale).rounded()))
        configuration.showsCursor = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                      configuration: configuration)
        else { return nil }
        let cocoaBounds = ScreenshotSupport.cocoaRect(fromWindowServer: plan.bounds,
                                                      mainScreenHeight: mainScreen.frame.height)
        let viewBounds = ScreenshotSupport.flippedViewRect(fromCocoa: cocoaBounds,
                                                           screenFrame: screen.frame)
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let pixelBounds = ScreenshotSupport.imagePixelRect(
            fromView: viewBounds,
            viewSize: screen.frame.size,
            imageSize: imageBounds.size)
        let cropBounds = ScreenshotSupport.clamp(pixelBounds, to: imageBounds)
        guard !cropBounds.isEmpty else { return nil }
        return image.cropping(to: cropBounds)
    }

    /// The window's size as the window server knows it, used to tell a whole
    /// window capture from one clipped to the part inside a display.
    private static func windowBounds(_ windowID: CGWindowID) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let dict = info.first?[kCGWindowBounds as String] as? [String: CGFloat]
        else { return nil }
        let bounds = CGRect(x: dict["X"] ?? 0, y: dict["Y"] ?? 0,
                            width: dict["Width"] ?? 0, height: dict["Height"] ?? 0)
        return bounds.width > 1 && bounds.height > 1 ? bounds : nil
    }

    /// On-screen windows a click can capture, front to back, in the window
    /// server's global top-left coordinates. Ordinary layer-zero windows from
    /// this process follow the visibility preference, except for capture UI.
    static func pickableWindows(hideVorssaintWindows: Bool,
                                protectedWindowIDs: Set<CGWindowID>)
        -> [(id: CGWindowID, bounds: CGRect)] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let ownPID = Int32(ProcessInfo.processInfo.processIdentifier)
        return info.compactMap { entry in
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat]
            else { return nil }
            guard ScreenshotCapturePolicy.canPickWindow(
                id,
                isOwnWindow: pid == ownPID,
                hideVorssaintWindows: hideVorssaintWindows,
                protectedWindowIDs: protectedWindowIDs)
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
