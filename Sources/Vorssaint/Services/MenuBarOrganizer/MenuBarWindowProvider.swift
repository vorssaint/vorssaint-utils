// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

final class MenuBarWindowProvider {
    func records() -> [MenuBarOrganizerWindowRecord] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        CGGetActiveDisplayList(UInt32(displays.count), &displays, &displayCount)
        let topEdges = displays.prefix(Int(displayCount)).flatMap {
            let bounds = CGDisplayBounds($0)
            return [bounds.minY, bounds.maxY]
        }

        return raw.compactMap { dictionary -> MenuBarOrganizerWindowRecord? in
            guard let idNumber = dictionary[kCGWindowNumber as String] as? NSNumber,
                  let pidNumber = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
                  let layerNumber = dictionary[kCGWindowLayer as String] as? NSNumber,
                  let bounds = dictionary[kCGWindowBounds as String] as? NSDictionary,
                  let fallbackFrame = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            let windowID = CGWindowID(idNumber.uint32Value)
            let pid = pid_t(pidNumber.int32Value)
            let application = NSRunningApplication(processIdentifier: pid)
            let ownerName = (dictionary[kCGWindowOwnerName as String] as? String)
                ?? application?.localizedName
                ?? ""
            let title = dictionary[kCGWindowName as String] as? String ?? ""
            let frame = DynamicMenuBarAPI.shared.frame(for: windowID) ?? fallbackFrame
            let record = MenuBarOrganizerWindowRecord(
                windowID: windowID,
                ownerPID: pid,
                ownerName: ownerName,
                bundleIdentifier: application?.bundleIdentifier ?? "",
                title: title,
                frame: frame,
                layer: layerNumber.intValue,
                alpha: (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
            return MenuBarOrganizerSupport.isLikelyMenuBarWindow(
                record, statusLevel: statusLevel, screenTopEdges: topEdges) ? record : nil
        }
    }

    func image(for windowID: CGWindowID) async -> NSImage? {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false),
              let window = content.windows.first(where: { $0.windowID == windowID })
        else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(window.frame.width * 2), 1)
        configuration.height = max(Int(window.frame.height * 2), 1)
        configuration.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: configuration)
        else { return nil }
        return NSImage(cgImage: image, size: window.frame.size)
    }
}
