// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The production panel class is compiled here. Creating it deferred neither
/// shows a window nor needs a running application; the sheet check orders a
/// fully transparent panel in off screen, since a sheet brings its parent in.
enum NotchPanelTests {
    static func run(expect: (Bool, String) -> Void) {
        trace("notch-panel", "started")
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 40),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        expect(panel.accessibilitySubrole() == .unknown,
               "the island describes itself as an undescribed borderless overlay, so window managers skip it "
               + "instead of listing a ghost window of this app on the current space")
        expect(panel.accessibilityRole() == .window && panel.isAccessibilityElement(),
               "the island stays an accessible window for assistive technology")
        expect(!panel.isMovableByWindowBackground,
               "holding the island cannot move its rectangular window frame")
        panel.collectionBehavior = NotchPanel.overlayCollectionBehavior
        expect(panel.collectionBehavior.contains([.canJoinAllSpaces, .fullScreenAuxiliary])
               && panel.collectionBehavior.intersection([.managed, .stationary, .transient]) == .stationary,
               "the island stays in place when the desktop is revealed, with no conflicting window motion policy")
        expect(NotchPanel.fullscreenLevel.rawValue > NSWindow.Level.normal.rawValue
               && NotchPanel.fullscreenLevel.rawValue < NSWindow.Level.mainMenu.rawValue,
               "the simulated full-screen cutout stays over app content but yields to the revealed menu bar")
        trace("notch-panel.surface-button-routing", "started")
        surfaceButtonRouting(expect: expect)
        trace("notch-panel.surface-button-routing", "finished")
        trace("notch-panel.sheet-contracts", "started")
        sheetContracts(expect: expect)
        trace("notch-panel.sheet-contracts", "finished")
        trace("notch-panel.active-glass", "started")
        activeGlass(expect: expect)
        trace("notch-panel.active-glass", "finished")
        trace("notch-panel.side-fade-removed", "started")
        sideFadeRemoved(expect: expect)
        trace("notch-panel.side-fade-removed", "finished")
        trace("notch-panel", "finished")
    }

    private static func trace(_ name: String, _ state: String) {
        FileHandle.standardError.write(Data("\(name) \(state)\n".utf8))
    }

    private static func sideFadeRemoved(expect: (Bool, String) -> Void) {
        let source = try? String(contentsOfFile: "Sources/Vorssaint/Services/Notch/NotchWindowHost.swift",
                                 encoding: .utf8)
        expect(source?.contains("private let silhouette = CAShapeLayer()") == true
               && source?.contains("silhouette.mask") == false
               && source?.contains("menuBarFade") == false,
               "the island silhouette stays fully opaque at its left and right edges")
    }

    private static func surfaceButtonRouting(expect: (Bool, String) -> Void) {
        final class Counter { var clicks = 0 }
        let counter = Counter()
        let panel = NSPanel(contentRect: CGRect(x: -4000, y: -4000, width: 120, height: 40),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        panel.contentView = NSHostingView(rootView: AnyView(
            ZStack {
                Button { counter.clicks += 1 } label: {
                    Text("Activity").frame(width: 120, height: 40)
                }
            }
            .frame(width: 120, height: 40)
            .contentShape(Rectangle())
            .modifier(NotchSurfaceTapGesture())
        ))
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        let location = CGPoint(x: 60, y: 20)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
                                      timestamp: 0, windowNumber: panel.windowNumber, context: nil,
                                      eventNumber: 1, clickCount: 1, pressure: 1)
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [],
                                    timestamp: 0.1, windowNumber: panel.windowNumber, context: nil,
                                    eventNumber: 1, clickCount: 1, pressure: 0)
        if let down { panel.sendEvent(down) }
        if let up { panel.sendEvent(up) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        expect(down != nil && up != nil && counter.clicks == 1,
               "a child activity button still receives its click when the empty surface keeps taps in the island")
    }

    /// Liquid Glass draws a dull stand-in in a window that looks inactive. The
    /// island never takes key focus when hover opens it, yet its glass must
    /// render as in a window that holds focus. Neither panel is ordered in.
    private static func activeGlass(expect: (Bool, String) -> Void) {
#if compiler(>=6.2)
        guard #available(macOS 26, *) else { return }
        _ = NSApplication.shared
        func rendered(in panel: NSPanel) -> [String] {
            let host = NSHostingView(rootView: Color.clear.glassEffect(.clear, in: Rectangle()).frame(width: 200, height: 100))
            host.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
            panel.contentView = host
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            CATransaction.flush()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            var lines: [String] = []
            func walk(_ layer: CALayer, depth: Int) {
                var line = "\(depth) \(type(of: layer)) \(layer.opacity) \(layer.isHidden)"
                for case let filter as NSObject in layer.filters ?? [] {
                    line += " \(filter.value(forKey: "name") ?? "")"
                    let keys = filter.responds(to: NSSelectorFromString("inputKeys"))
                        ? filter.value(forKey: "inputKeys") as? [String] ?? [] : []
                    for key in keys.sorted() {
                        if let number = filter.value(forKey: key) as? NSNumber { line += " \(key)=\(number)" }
                    }
                }
                lines.append(line)
                layer.sublayers?.forEach { walk($0, depth: depth + 1) }
            }
            if let layer = host.layer { walk(layer, depth: 0) }
            return lines
        }
        let frame = CGRect(x: -4000, y: -4000, width: 200, height: 100)
        let island = NotchPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let focused = NotchPanelFocusReference(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                               backing: .buffered, defer: false)
        island.isReleasedWhenClosed = false
        focused.isReleasedWhenClosed = false
        defer { island.close(); focused.close() }
        let islandGlass = rendered(in: island)
        expect(!island.isKeyWindow && !islandGlass.isEmpty && islandGlass == rendered(in: focused),
               "the island's Liquid Glass renders as in a focused window from the moment it opens, "
               + "without taking key focus from the app in front")
#endif
    }

    private static func sheetContracts(expect: (Bool, String) -> Void) {
        _ = NSApplication.shared
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.prohibited)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        let island = NotchPanel(contentRect: CGRect(x: -4000, y: -4000, width: 300, height: 120),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        island.isReleasedWhenClosed = false
        island.alphaValue = 0
        let dialog = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 80),
                             styleMask: [.titled], backing: .buffered, defer: false)
        dialog.isReleasedWhenClosed = false
        dialog.alphaValue = 0
        defer { island.close(); dialog.close() }
        var response: NSApplication.ModalResponse?
        island.beginSheet(dialog) { response = $0 }
        var deadline = Date().addingTimeInterval(2)
        while island.attachedSheet == nil, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        expect(island.attachedSheet === dialog, "a dialog attaches to the island as its sheet")
        island.orderOut(nil)
        deadline = Date().addingTimeInterval(2)
        while response == nil, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        expect(response == .cancel && island.attachedSheet == nil && !dialog.isVisible,
               "hiding the island ends an attached sheet through its completion, so a dialog opened inside it "
               + "is never dropped silently by a lock, sleep or teardown, leaving its caller waiting")
        island.orderOut(nil)
        expect(!island.isVisible, "ordering out without a sheet stays an ordinary hide")
    }
}

/// A window that answers every appearance question as one holding focus does.
private final class NotchPanelFocusReference: NSPanel {
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    @objc func hasKeyAppearance() -> Bool { true }
    @objc func hasMainAppearance() -> Bool { true }
}
