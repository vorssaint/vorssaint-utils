// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT
import AppKit
import SwiftUI
import QuartzCore

/// Exercises the production window host without touching preferences, files,
/// clipboard, keyboard input or hardware controls. The test window is invisible.
enum NotchPresentationProbe {
    static func runAndExit() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.main else { print("NOTCH PROBE FAILED: no display"); exit(1) }
        let geometry = NotchGeometry(screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                                     cameraWidth: screen.safeAreaInsets.top > 0 ? 210 : 0)
        let host = NotchWindowHost(content: AnyView(Color.black), geometry: geometry, size: geometry.collapsed)
        host.panel.alphaValue = 0
        host.panel.ignoresMouseEvents = true
        host.panel.orderFrontRegardless()
        var failures: [String] = []
        if host.panel.level.rawValue <= NSWindow.Level.statusBar.rawValue
            || host.panel.level.rawValue >= NSWindow.Level.popUpMenu.rawValue {
            failures.append("top-edge activation must outrank status items while leaving native menus above the island")
        }
        if geometry.isNotched, let mask = host.panel.contentView?.layer?.mask as? CAShapeLayer,
           let path = mask.path {
            if !path.contains(CGPoint(x: 12, y: 1))
                || path.contains(CGPoint(x: 12, y: geometry.collapsed.height - 1)) {
                failures.append("physical silhouette is inverted")
            }
        }
        var nativeResizes = 0
        let resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
                                                                     object: host.panel, queue: nil) { _ in
            nativeResizes += 1
        }
        defer { NotificationCenter.default.removeObserver(resizeObserver) }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var samples = 0
        var maxAnchorError: CGFloat = 0
        var maxContentError: CGFloat = 0
        var canvasChangedSize = false
        var noticeHeightLimit: CGFloat?
        var lostStationaryHover = false
        var hoverHosts = [host]
        let stationaryPointer = CGPoint(x: screen.frame.midX - geometry.cameraWidth / 4, y: screen.frame.maxY)
        func sample() {
            samples += 1
            if host.contentCanvasSize != host.panel.frame.size { canvasChangedSize = true }
            maxAnchorError = max(maxAnchorError, abs(host.panel.frame.maxY - (screen.frame.maxY - geometry.topInset)))
            maxContentError = max(maxContentError, abs(host.contentTopOnScreen - host.panel.frame.maxY))
            if abs(host.visibleFrame.maxY - host.panel.frame.maxY) > 0.5 {
                failures.append("visible silhouette detached from window top")
            }
            if !host.panel.frame.insetBy(dx: -0.5, dy: -0.5).contains(host.visibleFrame) {
                failures.append("visible silhouette exceeded its backing area")
            }
            if let noticeHeightLimit, host.visibleFrame.height > noticeHeightLimit + 0.5 {
                failures.append("horizontal feedback grew below the menu bar")
            }
            if !lostStationaryHover, hoverHosts.contains(where: { $0.panel.isVisible && !$0.containsHover(stationaryPointer) }) {
                lostStationaryHover = true
                failures.append("animation reported a stationary pointer at the screen top as outside the island")
            }
        }
        func advance(_ seconds: TimeInterval) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                RunLoop.current.run(until: min(end, Date().addingTimeInterval(0.008)))
                sample()
            }
        }
        host.present(size: geometry.expanded, geometry: geometry, animated: true, transitionContent: .reveal)
        if !reduceMotion, host.panel.contentView?.layer?.sublayers?.first(where: { $0.name == "notch.contentCover" })?.animation(forKey: "notch.opacity") == nil {
            failures.append("opening content has no reveal transition")
        }
        advance(0.09)
        let intermediate = host.visibleFrame
        if intermediate.height <= geometry.collapsed.height || intermediate.height >= geometry.expanded.height {
            if !reduceMotion { failures.append("opening has no intermediate frames") }
        }
        if !reduceMotion {
            if host.panel.frame.size != geometry.expanded { failures.append("opening did not reserve its backing area") }
            let outside = CGPoint(x: host.panel.frame.minX + 12, y: host.panel.frame.minY + 4)
            if host.contains(outside) { failures.append("transparent transition area accepted an interaction") }
            if let canvas = host.panel.contentView {
                let point = host.panel.convertPoint(fromScreen: outside)
                if canvas.hitTest(point) != nil { failures.append("native hit testing escaped the animated silhouette") }
                let inside = CGPoint(x: intermediate.midX, y: intermediate.midY)
                if !host.contains(inside) || canvas.hitTest(host.panel.convertPoint(fromScreen: inside)) == nil {
                    failures.append("visible transition content could not receive an interaction")
                }
            }
        }
        var updatedGeometry = geometry
        updatedGeometry.compactSideRoom = 140
        let beforeMeasurement = host.resizeCount
        host.present(size: geometry.expanded, geometry: updatedGeometry, animated: true)
        if host.resizeCount != beforeMeasurement { failures.append("menu measurement restarted an unchanged presentation") }
        advance(0.52)
        if nativeResizes > 2 { failures.append("opening resized its native window every frame: \(nativeResizes)") }
        let openingResizes = nativeResizes
        host.present(size: geometry.notice, geometry: geometry, animated: true, transitionContent: .dismiss)
        var completedActions = 0
        host.whenSettled { completedActions += 1 }
        if !reduceMotion, completedActions != 0 { failures.append("screen action ran before the closing transition finished") }
        let beforeBurst = host.resizeCount
        for _ in 0..<1000 { host.present(size: geometry.notice, geometry: geometry, animated: true) }
        if host.resizeCount != beforeBurst { failures.append("value burst restarted the resize") }
        advance(0.08)
        if !reduceMotion, (host.panel.contentView?.layer?.sublayers?.first(where: { $0.name == "notch.contentCover" })?.presentation()?.opacity ?? 0) < 0.99 {
            failures.append("closing left content visible under the moving clip")
        }
        if host.panel.contentView?.subviews.first?.alphaValue != 1 {
            failures.append("closing disabled the hosting view's interaction frame")
        }
        advance(0.52)
        if host.panel.frame != geometry.frame(for: geometry.notice) { failures.append("notice did not settle") }
        if host.panel.contentView?.layer?.sublayers?.first(where: { $0.name == "notch.contentCover" })?.opacity != 0 {
            failures.append("settled content remained hidden")
        }
        if completedActions != 1 { failures.append("transition completion did not run exactly once") }
        let beforeContentTransition = nativeResizes
        host.present(size: geometry.notice, geometry: geometry, animated: true, transitionContent: .replace)
        if !reduceMotion, host.panel.contentView?.subviews.first?.layer?.animation(forKey: kCATransition) == nil {
            failures.append("same-size content changes have no transition")
        }
        if nativeResizes != beforeContentTransition { failures.append("content transition resized the window") }
        for _ in 0..<6 {
            host.present(size: geometry.expanded, geometry: geometry, animated: true)
            advance(0.04)
            let beforeReverse = host.visibleFrame
            host.present(size: geometry.collapsed, geometry: geometry, animated: true)
            if !reduceMotion, abs(beforeReverse.height - host.visibleFrame.height) > 0.5 {
                failures.append("reversing the animation jumped to an endpoint")
            }
            advance(0.04)
        }
        advance(0.60)
        if host.panel.frame != geometry.frame(for: geometry.collapsed) { failures.append("interrupted motion did not settle") }
        noticeHeightLimit = geometry.menuBarHeight
        for notification in [false, true] {
            let size = geometry.noticeSize(notification: notification)
            host.present(size: size, geometry: geometry, animated: true, transitionContent: .reveal)
            advance(0.09)
            if !reduceMotion, host.visibleFrame.width <= geometry.collapsed.width || host.visibleFrame.width >= size.width {
                failures.append("horizontal reveal has no intermediate width")
            }
            let beforeUpdates = host.resizeCount
            for _ in 0..<1000 { host.present(size: size, geometry: geometry, animated: true) }
            if host.resizeCount != beforeUpdates { failures.append("horizontal value updates restarted the resize") }
            advance(0.55)
            if host.panel.frame != geometry.frame(for: size) { failures.append("horizontal feedback did not settle") }
            host.present(size: geometry.collapsed, geometry: geometry, animated: true, transitionContent: .dismiss)
            advance(0.55)
        }
        noticeHeightLimit = nil
        if maxAnchorError > 0.5 { failures.append("window detached from top: \(maxAnchorError)") }
        if canvasChangedSize { failures.append("content canvas escaped its stable native backing area") }
        if maxContentError > 0.5 { failures.append("content detached from window top: \(maxContentError)") }
        let pasteboard = NSPasteboard.withUniqueName()
        let fixture = URL(fileURLWithPath: "/tmp/notch-presentation-probe.txt")
        pasteboard.writeObjects([fixture as NSURL])
        if host.beginProbeDrop(pasteboard) != [] { failures.append("disabled file target accepted a drop") }
        var entered = 0
        var accepted = 0
        host.setFileDropActions(NotchFileDropActions(
            canAccept: { $0.availableType(from: [.fileURL]) != nil },
            enter: { entered += 1; host.present(size: geometry.expanded, geometry: geometry, animated: true) },
            accept: { board in
                guard board.string(forType: .fileURL) == fixture.absoluteString else { return false }
                accepted += 1
                return true
            }, exit: {}))
        if host.beginProbeDrop(pasteboard, localSource: true) != [] { failures.append("file target stole an internal reorder") }
        if host.beginProbeDrop(pasteboard) != .copy { failures.append("file URL was refused") }
        advance(0.07)
        if !host.finishProbeDrop(pasteboard) || accepted != 1 || entered != 1 {
            failures.append("drop was lost while the native window expanded")
        }
        if host.finishProbeDrop(pasteboard) { failures.append("one drag was accepted twice") }
        host.setFileDropActions(nil)
        if host.beginProbeDrop(pasteboard) != [] { failures.append("disabled target retained its drop handler") }
        pasteboard.releaseGlobally()
        host.present(size: geometry.peek, geometry: geometry, animated: false)
        if host.panel.frame != geometry.frame(for: geometry.peek)
            || host.panel.contentView?.layer?.mask?.animation(forKey: "notch.resize") != nil {
            failures.append("immediate presentation retained an animation")
        }
        host.present(size: geometry.expanded, geometry: geometry, animated: true)
        advance(0.04)
        host.panel.contentView?.layer?.mask?.removeAnimation(forKey: "notch.resize")
        advance(0.04)
        if host.panel.frame != geometry.frame(for: geometry.expanded) {
            failures.append("an externally cancelled animation retained its reserved frame")
        }
        var activationCount = 0
        for size in [geometry.collapsed, geometry.expanded, geometry.collapsed] {
            let hasHeader = size == geometry.expanded
            host.present(size: size, geometry: geometry, animated: false)
            host.setActivationArea(geometry.activationArea(in: size, hasHeader: hasHeader, compactActivity: false),
                                   title: "Toggle", willPress: {}, activate: { activationCount += 1 })
            advance(0.02)
            for inset: CGFloat in [0, 0.5, 1] {
                let point = CGPoint(x: host.panel.frame.width / 2, y: host.panel.frame.height - inset)
                guard let button = host.panel.contentView?.hitTest(point) as? NSButton else {
                    failures.append("top activation failed at inset \(inset), size \(size), silhouette \(host.contains(host.panel.convertPoint(toScreen: point)))")
                    continue
                }
                if !button.acceptsFirstMouse(for: nil) { failures.append("the native activation target requires an initial focus click") }
                button.performClick(nil)
                if hasHeader {
                    let controls = CGPoint(x: point.x, y: host.panel.frame.height - geometry.safeContentTop - 10)
                    if host.panel.contentView?.hitTest(controls) === button { failures.append("top activation covered the content controls") }
                }
            }
            if host.panel.contentView?.trackingAreas.count != 1 { failures.append("main hover tracking duplicated during resizing") }
        }
        if activationCount != 9 { failures.append("native activation did not run once per click across opening and closing") }
        host.setActivationArea(.zero, title: "", willPress: {}, activate: {})
        host.present(size: geometry.expanded, geometry: geometry, animated: true)
        host.whenSettled { completedActions += 1 }
        host.close()
        advance(0.02)
        if completedActions != 2 || host.panel.isVisible { failures.append("closing the host lost a pending action or reopened the window") }
        let dropBounds = CGRect(x: 0, y: 0, width: 200, height: 160)
        for phase: CGFloat in [0.25, 0.5, 0.72, 0.9, 1] {
            for side in NotchQuickAccessSide.allCases {
                let path = NotchQuickAccessDrop(progress: phase, index: 0, edge: 86, top: 55, side: side).path(in: dropBounds)
                let center = NotchQuickAccessLayout.center(index: 0, progress: phase, edge: 86, top: 55, side: side)
                let insideConnection = side == .bottom ? CGPoint(x: center.x, y: center.y - 10)
                    : CGPoint(x: center.x + (side == .left ? 10 : -10), y: center.y)
                if !path.contains(center) || !path.contains(insideConnection) {
                    failures.append("the liquid connection cut a hole into its drop")
                }
            }
        }
        if !NotchQuickAccessDrop(progress: 0, index: 0, edge: 86, top: 55, side: .left).path(in: dropBounds).isEmpty {
            failures.append("a withdrawn drop left a painted fragment")
        }
        let bubbles = NotchWindowHost(content: AnyView(Color.black), geometry: geometry, size: geometry.collapsed,
                                      quickAccess: { AnyView(NotchQuickAccessView(service: .shared, motion: $0)) })
        bubbles.panel.alphaValue = 0
        bubbles.panel.ignoresMouseEvents = true
        bubbles.panel.orderFrontRegardless()
        hoverHosts.append(bubbles)
        for side in NotchQuickAccessSide.allCases {
            let configuration = NotchQuickAccessConfiguration(side: side, actions: [.explore, .settings, .module(.timer)])
            bubbles.present(size: geometry.expanded, geometry: geometry, animated: false, quickAccess: configuration)
            advance(0.04)
            if bubbles.panel.frame.width != geometry.expanded.width + NotchQuickAccessLayout.gutter * 2
                || bubbles.contentCanvasSize.width != geometry.expanded.width
                || !screen.frame.contains(bubbles.panel.frame) {
                failures.append("floating controls changed the notch content width or escaped the display")
            }
            if abs(bubbles.contentTopOnScreen - bubbles.panel.frame.maxY) > 0.5 {
                failures.append("floating controls displaced the content below the top anchor")
            }
            if !bubbles.quickAccessProbeInteractive || bubbles.quickAccessProbeCenters.count != 3 {
                failures.append("settled floating controls did not become accessible")
            }
            if bubbles.quickAccessProbeTrackingAreas != 1 {
                failures.append("floating controls did not create exactly one hover corridor")
            }
            for point in bubbles.quickAccessProbeCenters {
                let local = bubbles.panel.convertPoint(fromScreen: point)
                if !bubbles.contains(point) || bubbles.panel.contentView?.hitTest(local) == nil {
                    failures.append("a floating control could not receive a click")
                }
                let gap = side == .bottom ? CGPoint(x: point.x, y: point.y + 28)
                    : CGPoint(x: point.x + (side == .left ? 28 : -28), y: point.y)
                if bubbles.contains(gap) || bubbles.panel.contentView?.hitTest(bubbles.panel.convertPoint(fromScreen: gap)) != nil {
                    failures.append("the transparent gap beside a floating control accepted a click")
                }
                let overshoot = side == .bottom ? CGPoint(x: point.x, y: point.y - 34)
                    : CGPoint(x: point.x + (side == .left ? -34 : 34), y: point.y)
                if !bubbles.containsHover(gap) || !bubbles.containsHover(overshoot) || bubbles.contains(overshoot) {
                    failures.append("hover did not forgive travel around floating controls independently of clicks")
                }
            }
            bubbles.present(size: geometry.collapsed, geometry: geometry, animated: true)
            if bubbles.quickAccessProbeInteractive { failures.append("departing floating controls still accepted input") }
            if bubbles.quickAccessProbeTrackingAreas != 0 { failures.append("departing controls retained hover tracking") }
            advance(0.06)
            if !reduceMotion, abs(bubbles.visibleFrame.width - geometry.expanded.width) > 0.5 {
                failures.append("the notch withdrew before its floating controls could rejoin it")
            }
            advance(0.95)
            if bubbles.panel.frame != geometry.frame(for: geometry.collapsed) {
                failures.append("closing retained transparent space for the floating controls")
            }
            for _ in 0..<3 {
                bubbles.present(size: geometry.expanded, geometry: geometry, animated: true, quickAccess: configuration)
                advance(0.06)
                bubbles.present(size: geometry.collapsed, geometry: geometry, animated: true)
                advance(0.04)
            }
            bubbles.present(size: geometry.expanded, geometry: geometry, animated: true, quickAccess: configuration)
            advance(1.05)
            if !bubbles.quickAccessProbeInteractive || bubbles.quickAccessProbeTrackingAreas != 1
                || !bubbles.quickAccessProbeCenters.allSatisfy(bubbles.contains) {
                failures.append("reversing the floating animation lost its final hit targets")
            }
        }
        let mixed = NotchQuickAccessConfiguration(buttons: NotchQuickAccessSide.allCases.flatMap { side in
            [NotchQuickAction.explore, .settings, .pin].map { NotchQuickButton(action: $0, side: side) }
        })
        bubbles.present(size: geometry.expanded, geometry: geometry, animated: false, quickAccess: mixed)
        advance(0.04)
        if bubbles.quickAccessProbeCenters.count != 9 || bubbles.quickAccessProbeTrackingAreas != 3
            || !bubbles.quickAccessProbeCenters.allSatisfy(bubbles.contains)
            || !screen.frame.contains(bubbles.panel.frame) {
            failures.append("simultaneous left, right and bottom shortcuts lost geometry or hit targets")
        }
        bubbles.close()
        advance(0.05)
        if bubbles.panel.isVisible || bubbles.quickAccessProbeInteractive || bubbles.quickAccessProbeTrackingAreas != 0 {
            failures.append("closing left a floating control alive")
        }
        print("NOTCH PROBE \(failures.isEmpty ? "OK" : "FAILED") samples=\(samples) openingNativeResizes=\(openingResizes) repeatedUpdates=1000 fileDrops=\(accepted) topError=\(maxAnchorError) contentError=\(maxContentError)")
        failures.forEach { print($0) }
        exit(failures.isEmpty ? 0 : 1)
    }
}
#endif
