// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT
import AppKit
import SwiftUI
import QuartzCore

/// Exercises the production window host without touching user preferences, files,
/// clipboard, keyboard input or hardware controls. Tests keep the window
/// invisible; the separate, explicitly requested notice preview is visible.
enum NotchPresentationProbe {
    /// Exercise the production backdrop, including its native glass rendering,
    /// without changing the app's preferences or making the test windows visible.
    private static func surface(_ presentation: NotchBackdropPresentation) -> AnyView {
        AnyView(NotchSurfaceBackground(presentation: presentation, glass: CommandLine.arguments.contains("--glass"))
            .environment(\.colorScheme, .dark))
    }

    /// The glass gradient must follow the visible lip, not the larger reserved
    /// canvas, and content transitions must never cover or fade the backdrop.
    private static func checkBackdrop(_ host: NotchWindowHost, failures: inout [String]) {
        host.synchronizeBackdropProbe()
        let background = host.backdropProbeFrame
        if let silhouette = host.silhouetteProbePath,
           host.backdropProbePath != silhouette {
            failures.append("backdrop contour differs from the animated silhouette")
        }
        let visible = host.visibleFrame.size
        if abs(background.width - visible.width) > 2 || abs(background.height - visible.height) > 2
            || abs(background.minY) > 0.5 {
            failures.append("backdrop detached from the animated silhouette: \(background), visible \(visible)")
        }
        if !host.backdropProbeIndependent {
            failures.append("content transition obscured the backdrop")
        }
    }

    private static func checkHiddenReveal(screen: NSScreen) -> [String] {
        var failures: [String] = []
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for safeArea: CGFloat in [0, 32] {
            let geometry = NotchGeometry(screen: screen.frame, safeAreaTop: safeArea,
                                         cameraWidth: safeArea > 0 ? 210 : 0)
            let host = NotchWindowHost(content: AnyView(Color.clear), geometry: geometry, size: geometry.collapsed, background: surface,
                                      quickAccess: { AnyView(NotchQuickAccessView(service: .shared, motion: $0)) })
            host.panel.alphaValue = 0
            host.panel.ignoresMouseEvents = true
            func advance(_ seconds: TimeInterval) {
                RunLoop.current.run(until: Date().addingTimeInterval(seconds))
            }
            // Reopen at the unchanged size, then interrupt a reveal and reopen
            // at another size. Neither may reuse the concealed, expanded mask.
            for (index, size) in [geometry.expanded, geometry.expanded, geometry.peek].enumerated() {
                host.panel.orderOut(nil)
                host.present(size: size, geometry: geometry, animated: true,
                             quickAccess: .initial, revealFromHidden: true, usesGlass: true)
                if host.quickAccessProbeInteractive && !reduceMotion {
                    failures.append("hidden reveal exposed floating controls before the island")
                }
                host.panel.orderFrontRegardless()
                advance(0.08)
                if !reduceMotion && !(host.visibleFrame.height > 0 && host.visibleFrame.height < size.height) {
                    failures.append("hidden reveal has no intermediate frames (opening \(index), safe area \(safeArea))")
                }
                if abs(host.panel.frame.maxY - screen.frame.maxY) > 0.5
                    || abs(host.contentTopOnScreen - screen.frame.maxY) > 0.5
                    || !host.containsHover(CGPoint(x: screen.frame.midX, y: screen.frame.maxY)) {
                    failures.append("hidden reveal detached from the screen edge or lost stationary hover")
                }
                if !reduceMotion && host.contains(CGPoint(x: screen.frame.midX, y: host.panel.frame.maxY - size.height + 2)) {
                    failures.append("hidden reveal accepted clicks in unrevealed content")
                }
                if index == 1 { continue }
                advance(1)
                if abs(host.visibleFrame.height - size.height) > 0.5 || !host.quickAccessProbeInteractive {
                    failures.append("hidden reveal failed to settle with usable floating controls")
                }
            }
            host.hide(animated: true)
            let closingResizes = host.resizeCount
            for _ in 0..<10 { host.hide(animated: true) }
            if !reduceMotion && host.resizeCount != closingResizes {
                failures.append("repeated hidden refreshes restarted the withdrawal")
            }
            advance(NotchQuickAccessLayout.withdrawalDuration + 0.08)
            checkBackdrop(host, failures: &failures)
            if !reduceMotion && (!host.panel.isVisible || host.visibleFrame.height <= 0
                                  || host.visibleFrame.height >= geometry.peek.height) {
                failures.append("hidden withdrawal has no intermediate frames")
            }
            if host.quickAccessProbeInteractive || !host.panel.ignoresMouseEvents {
                failures.append("departing island or floating controls retained mouse input")
            }
            host.present(size: geometry.expanded, geometry: geometry, animated: true,
                         quickAccess: .initial, revealFromHidden: true, usesGlass: true)
            host.panel.orderFrontRegardless()
            advance(1)
            if !host.panel.isVisible || abs(host.visibleFrame.height - geometry.expanded.height) > 0.5
                || !host.quickAccessProbeInteractive || !host.panel.ignoresMouseEvents {
                failures.append("reopening during withdrawal lost the island, controls or prior mouse policy")
            }
            host.hide(animated: true)
            advance(1)
            if host.panel.isVisible || host.quickAccessProbeInteractive || host.quickAccessProbeTrackingAreas != 0 {
                failures.append("settled withdrawal left a window or floating control active")
            }
            host.present(size: geometry.expanded, geometry: geometry, animated: true,
                         quickAccess: .initial, revealFromHidden: true, usesGlass: true)
            host.panel.orderFrontRegardless()
            advance(0.08)
            host.hide(animated: true)
            advance(1)
            if host.panel.isVisible { failures.append("closing during reveal failed to hide the island") }

            host.panel.orderOut(nil)
            host.present(size: geometry.expanded, geometry: geometry, animated: false, revealFromHidden: true, usesGlass: true)
            host.panel.orderFrontRegardless()
            advance(0.03)
            if host.visibleFrame.size != geometry.expanded {
                failures.append("nonanimated hidden reveal did not present its final size immediately")
            }
            host.panel.orderOut(nil)
            host.present(size: geometry.peek, geometry: geometry, animated: true, usesGlass: true)
            host.panel.orderFrontRegardless()
            advance(0.03)
            if host.visibleFrame.size != geometry.peek {
                failures.append("ordinary first presentation unexpectedly animated from a hidden panel")
            }
            host.hide(animated: true)
            host.hide(animated: false)
            if host.panel.isVisible { failures.append("nonanimated withdrawal did not hide the island immediately") }
            host.close()
        }
        return failures
    }

    /// An explicitly requested preview uses the real notice and animation host,
    /// with no connection, audio adjustment or preference change.
    private static func previewNoticeAndExit(title: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.main else { print("NOTCH PREVIEW FAILED: no display"); exit(1) }
        let cameraWidth = screen.auxiliaryTopRightArea.flatMap { right in
            screen.auxiliaryTopLeftArea.map { max(0, right.minX - $0.maxX) }
        } ?? 0
        var measurements = NotchMenuBarMeasurements()
        let geometry = NotchGeometry(screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            cameraWidth: cameraWidth, menuBarHeight: measurements.height(
                displayID: screen.notchDisplayID, frame: screen.frame, visibleTop: screen.visibleFrame.maxY,
                scale: screen.backingScaleFactor, statusBarThickness: NSStatusBar.system.thickness))
        let notice = NotchNotice(event: .accessory, title: title,
                                detail: FeatureStrings.notchActivities(L10n.shared.language).connected,
                                symbol: NotchAccessorySupport.symbol(for: .audio, name: title))
        let size = geometry.noticeSize(wingWidth: notice.preferredWingWidth)
        let content = NotchNoticeView(notice: notice, geometry: geometry)
            .frame(width: size.width, height: size.height).background(.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        let idle = geometry.restingSize(showsContent: false)
        let host = NotchWindowHost(content: AnyView(content), geometry: geometry, size: idle)
        host.panel.ignoresMouseEvents = true
        host.panel.title = "Connection preview"
        host.panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            host.present(size: size, geometry: geometry, animated: true, transitionContent: .reveal)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1 + NotchEvent.accessory.duration) {
            host.present(size: idle, geometry: geometry, animated: true, transitionContent: .dismiss)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2 + NotchEvent.accessory.duration) {
            host.close()
            print("NOTCH NOTICE PREVIEW OK")
            exit(0)
        }
        app.run()
        exit(1)
    }

    /// Reads the bounds the window server currently shows for a window; while
    /// Mission Control animates a frame change these trail the requested frame.
    private static func serverSize(of window: NSWindow) -> CGSize? {
        guard window.windowNumber > 0,
              let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(window.windowNumber))
                            as? [[String: Any]])?.first,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let width = bounds["Width"], let height = bounds["Height"] else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Opt-in: shows Mission Control on this Mac for a few seconds. Inside it
    /// the window server animates every frame change of a window on screen,
    /// smearing the island's settled pixels over its reserved bounds; the host
    /// must apply its frames there as immediately as it does on the desktop.
    private static func runMissionControlAndExit() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.main else { print("NOTCH MISSION CONTROL PROBE FAILED: no display"); exit(1) }
        var failures: [String] = []
        func advance(_ seconds: TimeInterval) {
            RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        }
        func toggleMissionControl() {
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            launcher.arguments = ["-b", "com.apple.exposelauncher"]
            do { try launcher.run() } catch { failures.append("could not toggle Mission Control: \(error)") }
        }
        let geometry = NotchGeometry(screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                                     cameraWidth: screen.safeAreaInsets.top > 0 ? 210 : 0)
        let host = NotchWindowHost(content: AnyView(Color.clear), geometry: geometry, size: geometry.collapsed, background: surface,
                                  quickAccess: { AnyView(NotchQuickAccessView(service: .shared, motion: $0)) })
        host.panel.alphaValue = 0
        host.panel.ignoresMouseEvents = true
        host.panel.orderFrontRegardless()
        host.present(size: geometry.expanded, geometry: geometry, animated: false, quickAccess: .initial, usesGlass: true)
        // A plain window shows the mode itself: on the desktop its new size
        // reads back at once, in Mission Control the previous size lingers.
        let witness = NSWindow(contentRect: CGRect(x: screen.frame.minX, y: screen.frame.minY, width: 2, height: 2),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        witness.isOpaque = false
        witness.backgroundColor = .clear
        witness.hasShadow = false
        witness.alphaValue = 0
        witness.ignoresMouseEvents = true
        witness.isReleasedWhenClosed = false
        witness.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let witnessContent = NSView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        witnessContent.wantsLayer = true
        witness.contentView = witnessContent
        witness.orderFrontRegardless()
        advance(0.5)
        func witnessLags() -> Bool {
            let side: CGFloat = witness.frame.width > 2 ? 2 : 40
            witness.setFrame(CGRect(x: screen.frame.minX, y: screen.frame.minY, width: side, height: side), display: false)
            witnessContent.layoutSubtreeIfNeeded()
            CATransaction.flush()
            return serverSize(of: witness).map { abs($0.width - side) > 0.5 } ?? false
        }
        if witnessLags() { failures.append("the desktop already animated a plain frame change") }
        toggleMissionControl()
        advance(2)
        guard witnessLags() else {
            print("NOTCH MISSION CONTROL PROBE FAILED: Mission Control did not engage; nothing was verified")
            witness.orderOut(nil)
            host.close()
            exit(1)
        }
        for (size, access) in [(geometry.collapsed, nil), (geometry.expanded, NotchQuickAccessConfiguration.initial),
                               (geometry.collapsed, nil)] {
            let concealedBefore = host.concealedFrameChanges
            host.present(size: size, geometry: geometry, animated: true,
                         transitionContent: access == nil ? .dismiss : .reveal, quickAccess: access, usesGlass: access != nil)
            var settled = false
            host.whenSettled { settled = true }
            // The server must show the reserved frame throughout, and the
            // settled one the moment it is released.
            func smear() -> CGSize? {
                guard let shown = serverSize(of: host.panel),
                      abs(shown.width - host.panel.frame.width) > 0.5 || abs(shown.height - host.panel.frame.height) > 0.5
                else { return nil }
                return shown
            }
            var smeared: CGSize?
            let deadline = Date().addingTimeInterval(3)
            while !settled && smeared == nil && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.008))
                smeared = smear()
            }
            if smeared == nil { smeared = smear() }
            if let smeared {
                failures.append("Mission Control animated the island's frame to \(size): showing \(smeared), reserved \(host.panel.frame.size)")
            } else if !settled {
                failures.append("the island did not settle at \(size) inside Mission Control")
            }
            advance(0.7)
            if let smeared = smear() {
                failures.append("the settled island still shows \(smeared) for a frame of \(host.panel.frame.size)")
            }
            if !host.panel.isVisible { failures.append("the island stayed off screen after settling at \(size)") }
            if host.concealedFrameChanges == concealedBefore {
                failures.append("the host applied the frame change to \(size) on screen inside Mission Control")
            }
        }
        toggleMissionControl()
        advance(1.5)
        witness.orderOut(nil)
        host.close()
        print("NOTCH MISSION CONTROL PROBE \(failures.isEmpty ? "OK" : "FAILED")")
        failures.forEach { print($0) }
        exit(failures.isEmpty ? 0 : 1)
    }

    static func runAndExit() -> Never {
        if CommandLine.arguments.contains("--media-layout") { NotchMediaPresentationProbe.runAndExit() }
        if CommandLine.arguments.contains("--mission-control") { runMissionControlAndExit() }
        if let index = CommandLine.arguments.firstIndex(of: "--preview-notice"),
           CommandLine.arguments.indices.contains(index + 1) {
            previewNoticeAndExit(title: CommandLine.arguments[index + 1])
        }
        if CommandLine.arguments.contains("--profile-only") { runProfileAndExit() }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.main else { print("NOTCH PROBE FAILED: no display"); exit(1) }
        let geometry = NotchGeometry(screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                                     cameraWidth: screen.safeAreaInsets.top > 0 ? 210 : 0)
        let host = NotchWindowHost(content: AnyView(Color.clear), geometry: geometry, size: geometry.collapsed, background: surface)
        host.panel.alphaValue = 0
        host.panel.ignoresMouseEvents = true
        host.panel.orderFrontRegardless()
        var failures = checkHiddenReveal(screen: screen)
        if host.panel.collectionBehavior.intersection([.managed, .transient, .stationary]) != .transient
            || !host.panel.collectionBehavior.contains(.canJoinAllSpaces) {
            failures.append("the island must float across Spaces without following the desktop's window motion")
        }
        if host.panel.level.rawValue <= NSWindow.Level.statusBar.rawValue
            || host.panel.level.rawValue >= NSWindow.Level.popUpMenu.rawValue {
            failures.append("top-edge activation must outrank status items while leaving native menus above the island")
        }
        if let mask = host.panel.contentView?.layer?.mask as? CAShapeLayer,
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
        func matchesNativeFrame(_ actual: CGRect, _ expected: CGRect) -> Bool {
            // AppKit rounds window bounds even when the display's camera safe
            // area is fractional (for example, 37.5 pt). Keep subpoint tolerance.
            abs(actual.minX - expected.minX) <= 0.5 && abs(actual.minY - expected.minY) <= 0.5
                && abs(actual.width - expected.width) <= 0.5 && abs(actual.height - expected.height) <= 0.5
        }
        var samples = 0
        var maxAnchorError: CGFloat = 0
        var maxContentError: CGFloat = 0
        var canvasChangedSize = false
        var noticeHeightLimit: CGFloat?
        var lostStationaryHover = false
        var hoverHosts = [host]
        let stationaryPointer = CGPoint(x: screen.frame.midX - geometry.cameraWidth / 4,
                                        y: screen.frame.maxY)
        func sample() {
            samples += 1
            if host.contentCanvasSize != host.panel.frame.size { canvasChangedSize = true }
            maxAnchorError = max(maxAnchorError, abs(host.panel.frame.maxY - (screen.frame.maxY)))
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
        host.present(size: geometry.expanded, geometry: geometry, animated: true, transitionContent: .reveal, usesGlass: true)
        if !reduceMotion, !host.contentProbeAnimating {
            failures.append("opening content has no reveal transition")
        }
        advance(0.09)
        let intermediate = host.visibleFrame
        if !reduceMotion && host.backdropProbeTicks == 0 {
            failures.append("backdrop display link did not advance during opening")
        }
        checkBackdrop(host, failures: &failures)
        if intermediate.height <= geometry.collapsed.height || intermediate.height >= geometry.expanded.height {
            if !reduceMotion { failures.append("opening has no intermediate frames") }
        }
        if !reduceMotion {
            if !matchesNativeFrame(host.panel.frame, geometry.frame(for: geometry.expanded)) { failures.append("opening did not reserve its backing area") }
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
        host.present(size: geometry.expanded, geometry: updatedGeometry, animated: true, usesGlass: true)
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
        checkBackdrop(host, failures: &failures)
        if !reduceMotion, host.contentProbeOpacity > 0.01 {
            failures.append("closing left content visible under the moving clip")
        }
        if host.contentProbeAlpha != 1 {
            failures.append("closing disabled the hosting view's interaction frame")
        }
        advance(0.52)
        if !matchesNativeFrame(host.panel.frame, geometry.frame(for: geometry.notice)) { failures.append("notice did not settle") }
        if host.backdropProbeUsesGlass || host.backdropProbeScheduled {
            failures.append("compact notice retained glass or its frame scheduler after settling")
        }
        if host.contentProbeOpacity != 1 {
            failures.append("settled content remained hidden")
        }
        if completedActions != 1 { failures.append("transition completion did not run exactly once") }
        // A compact download can exceed 64pt. Its material is a presentation
        // decision, independent of that height and of the animation envelope.
        let crowded = NotchGeometry(screen: screen.frame, safeAreaTop: 38, cameraWidth: 210,
                                    compactSideRoom: 0)
        let downloadHost = NotchWindowHost(content: AnyView(Color.clear), geometry: crowded,
                                          size: crowded.compactActivitySize, background: surface)
        downloadHost.panel.alphaValue = 0
        downloadHost.panel.ignoresMouseEvents = true
        downloadHost.panel.orderFrontRegardless()
        downloadHost.present(size: crowded.compactActivitySize, geometry: crowded, animated: false)
        if crowded.compactActivitySize.height <= 64 || downloadHost.backdropProbeUsesGlass {
            failures.append("tall compact download incorrectly selected glass")
        }
        downloadHost.present(size: crowded.expanded, geometry: crowded, animated: false, usesGlass: true)
        downloadHost.present(size: crowded.compactActivitySize, geometry: crowded, animated: true)
        advance(0.08)
        checkBackdrop(downloadHost, failures: &failures)
        if !reduceMotion && !downloadHost.backdropProbeUsesGlass {
            failures.append("closing dropped the previous glass before settling")
        }
        advance(0.6)
        if downloadHost.backdropProbeUsesGlass || downloadHost.backdropProbeScheduled {
            failures.append("tall compact download retained the expanded material or scheduler")
        }
        downloadHost.present(size: crowded.expanded, geometry: crowded, animated: true, usesGlass: true)
        advance(0.6)
        if downloadHost.backdropProbeScheduled || downloadHost.backdropProbePath != downloadHost.silhouetteProbePath {
            failures.append("settled expanded backdrop kept an intermediate contour or scheduler")
        }
        downloadHost.panel.orderOut(nil)
        let beforeContentTransition = nativeResizes
        host.present(size: geometry.notice, geometry: geometry, animated: true, transitionContent: .replace)
        if !reduceMotion, !host.contentProbeReplacing {
            failures.append("same-size content changes have no transition")
        }
        if nativeResizes != beforeContentTransition { failures.append("content transition resized the window") }
        for _ in 0..<6 {
            host.present(size: geometry.expanded, geometry: geometry, animated: true, usesGlass: true)
            advance(0.04)
            let beforeReverse = host.visibleFrame
            host.present(size: geometry.collapsed, geometry: geometry, animated: true)
            if !reduceMotion, abs(beforeReverse.height - host.visibleFrame.height) > 0.5 {
                failures.append("reversing the animation jumped to an endpoint")
            }
            advance(0.04)
        }
        advance(0.60)
        if !matchesNativeFrame(host.panel.frame, geometry.frame(for: geometry.collapsed)) { failures.append("interrupted motion did not settle") }
        noticeHeightLimit = geometry.notice.height
        for wing in [CGFloat(112), 190, 240] {
            let size = geometry.noticeSize(wingWidth: wing)
            host.present(size: size, geometry: geometry, animated: true, transitionContent: .reveal)
            advance(0.09)
            if !reduceMotion, host.visibleFrame.width <= geometry.collapsed.width || host.visibleFrame.width >= size.width {
                failures.append("horizontal reveal has no intermediate width")
            }
            let beforeUpdates = host.resizeCount
            for _ in 0..<1000 { host.present(size: size, geometry: geometry, animated: true) }
            if host.resizeCount != beforeUpdates { failures.append("horizontal value updates restarted the resize") }
            advance(0.55)
            if !matchesNativeFrame(host.panel.frame, geometry.frame(for: size)) { failures.append("horizontal feedback did not settle") }
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
            enter: { _ in entered += 1; host.present(size: geometry.expanded, geometry: geometry, animated: true, usesGlass: true) },
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
        host.present(size: geometry.peek, geometry: geometry, animated: false, usesGlass: true)
        if !matchesNativeFrame(host.panel.frame, geometry.frame(for: geometry.peek))
            || host.panel.contentView?.layer?.mask?.animation(forKey: "notch.resize") != nil {
            failures.append("immediate presentation retained an animation")
        }
        host.present(size: geometry.expanded, geometry: geometry, animated: true, usesGlass: true)
        advance(0.04)
        host.panel.contentView?.layer?.mask?.removeAnimation(forKey: "notch.resize")
        advance(0.04)
        if !matchesNativeFrame(host.panel.frame, geometry.frame(for: geometry.expanded)) {
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
        host.present(size: geometry.expanded, geometry: geometry, animated: true, usesGlass: true)
        host.whenSettled { completedActions += 1 }
        // The desktop applies frames at once; only Mission Control warrants
        // ordering the island out around a frame change.
        if host.concealedFrameChanges != 0 { failures.append("the desktop concealed the island for \(host.concealedFrameChanges) frame changes") }
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
        let bubbles = NotchWindowHost(content: AnyView(Color.clear), geometry: geometry, size: geometry.collapsed, background: surface,
                                      quickAccess: { AnyView(NotchQuickAccessView(service: .shared, motion: $0)) })
        bubbles.panel.alphaValue = 0
        bubbles.panel.ignoresMouseEvents = true
        bubbles.panel.orderFrontRegardless()
        hoverHosts.append(bubbles)
        for side in NotchQuickAccessSide.allCases {
            let configuration = NotchQuickAccessConfiguration(side: side, actions: [.explore, .settings, .module(.timer)])
            bubbles.present(size: geometry.expanded, geometry: geometry, animated: false, quickAccess: configuration, usesGlass: true)
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
            if !matchesNativeFrame(bubbles.panel.frame, geometry.frame(for: geometry.collapsed)) {
                failures.append("closing retained transparent space for the floating controls")
            }
            for _ in 0..<3 {
                bubbles.present(size: geometry.expanded, geometry: geometry, animated: true, quickAccess: configuration, usesGlass: true)
                advance(0.06)
                bubbles.present(size: geometry.collapsed, geometry: geometry, animated: true)
                advance(0.04)
            }
            bubbles.present(size: geometry.expanded, geometry: geometry, animated: true, quickAccess: configuration, usesGlass: true)
            advance(1.05)
            if !bubbles.quickAccessProbeInteractive || bubbles.quickAccessProbeTrackingAreas != 1
                || !bubbles.quickAccessProbeCenters.allSatisfy(bubbles.contains) {
                failures.append("reversing the floating animation lost its final hit targets")
            }
        }
        for layout: NotchSize in [.compact, .spacious] {
            let shortGeometry = NotchGeometry(screen: screen.frame, safeAreaTop: 32,
                                              cameraWidth: 210, layout: layout)
            let shortSize = shortGeometry.expandedSize(module: .system, systemCards: 3)
            for side: NotchQuickAccessSide in [.left, .right] {
                let access = NotchQuickAccessConfiguration(side: side, actions: [.explore, .settings, .pin])
                bubbles.present(size: shortSize, geometry: shortGeometry, animated: true, quickAccess: access)
                advance(0.8)
                if bubbles.visibleFrame.size != shortSize || bubbles.contentCanvasSize != shortSize {
                    failures.append("reserving space for side buttons enlarged a short page")
                }
                if !bubbles.quickAccessProbeInteractive || bubbles.quickAccessProbeCenters.count != 3 {
                    failures.append("a short page lost its side buttons")
                }
                for point in bubbles.quickAccessProbeCenters {
                    let radius = NotchQuickAccessLayout.diameter / 2
                    let circle = CGRect(x: point.x - radius, y: point.y - radius,
                                        width: radius * 2, height: radius * 2)
                    let lowerEdge = CGPoint(x: point.x, y: point.y - radius + 1)
                    let hoverEdge = CGPoint(x: point.x, y: point.y - radius - NotchQuickAccessLayout.hoverMargin + 1)
                    if !bubbles.panel.frame.contains(circle)
                        || !bubbles.contains(lowerEdge)
                        || bubbles.panel.contentView?.hitTest(bubbles.panel.convertPoint(fromScreen: lowerEdge)) == nil
                        || !bubbles.containsHover(hoverEdge) {
                        failures.append("a side button or its hover margin escaped a short page's backing window")
                    }
                }
                let resizes = bubbles.resizeCount
                bubbles.present(size: shortSize, geometry: shortGeometry, animated: false, quickAccess: access)
                if bubbles.resizeCount != resizes {
                    failures.append("unchanged side-button padding restarted a window resize")
                }
                bubbles.present(size: shortGeometry.collapsed, geometry: shortGeometry, animated: true)
                advance(0.95)
                if !matchesNativeFrame(bubbles.panel.frame, shortGeometry.frame(for: shortGeometry.collapsed))
                    || bubbles.quickAccessProbeInteractive || bubbles.quickAccessProbeTrackingAreas != 0 {
                    failures.append("closing a short page retained side-button space or hover tracking")
                }
            }
        }
        let mixed = NotchQuickAccessConfiguration(buttons: NotchQuickAccessSide.allCases.flatMap { side in
            [NotchQuickAction.explore, .settings, .pin].map { NotchQuickButton(action: $0, side: side) }
        })
        bubbles.present(size: geometry.expanded, geometry: geometry, animated: false, quickAccess: mixed, usesGlass: true)
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
        var timerTransitions = 0
        for barHeight: CGFloat in [32, 40, 64] {
            for downloads in [false, true] {
                var timerGeometry = NotchGeometry(screen: screen.frame, safeAreaTop: 32, cameraWidth: 179,
                                                  menuBarHeight: barHeight, compactSideRoom: 100)
                let initial = timerGeometry.compactTimerGeometry(showsDownloads: downloads)
                let timerHost = NotchWindowHost(content: AnyView(Color.clear), geometry: initial,
                                                size: initial.compactActivitySize, background: surface)
                timerHost.panel.alphaValue = 0
                timerHost.panel.ignoresMouseEvents = true
                timerHost.panel.orderFrontRegardless()
                for room: CGFloat? in [100, 27, nil, 80, 0, 72, 100] {
                    timerGeometry.compactSideRoom = room
                    let next = timerGeometry.compactTimerGeometry(showsDownloads: downloads)
                    timerHost.present(size: next.compactActivitySize, geometry: next, animated: true)
                    let deadline = Date().addingTimeInterval(0.07)
                    while Date() < deadline {
                        RunLoop.current.run(until: Date().addingTimeInterval(0.008))
                        if abs(timerHost.panel.frame.maxY - screen.frame.maxY) > 0.5
                            || abs(timerHost.panel.frame.height - next.stripHeight) > 0.5
                            || abs(timerHost.contentTopOnScreen - screen.frame.maxY) > 0.5 {
                            failures.append("compact timer moved below the camera during a menu-space transition")
                            break
                        }
                    }
                    timerTransitions += 1
                }
                timerHost.close()
            }
        }
        print("NOTCH PROBE \(failures.isEmpty ? "OK" : "FAILED") samples=\(samples) openingNativeResizes=\(openingResizes) repeatedUpdates=1000 fileDrops=\(accepted) topError=\(maxAnchorError) contentError=\(maxContentError) timerTransitions=\(timerTransitions)")
        failures.forEach { print($0) }
        exit(failures.isEmpty ? 0 : 1)
    }

    /// Checks native layout and animation only, without input or screen capture.
    private static func runProfileAndExit() -> Never {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard let screen = NSScreen.main else { print("NOTCH PROFILE PROBE FAILED: no display"); exit(1) }
        var failures = Set<String>()
        var samples = 0
        var transitions = 0
        for barHeight: CGFloat in [16, 22, 24, 32, 40, 64] {
            for physical in [false, true] {
                var geometry = NotchGeometry(screen: screen.frame, safeAreaTop: physical ? 32 : 0, cameraWidth: physical ? 180 : 0,
                                             menuBarHeight: barHeight, compactSideRoom: 64)
                geometry.quickAccessBottomInset = NotchQuickAccessLayout.gutter
                let host = NotchWindowHost(content: AnyView(Color.clear), geometry: geometry, size: geometry.collapsed, background: surface,
                                          quickAccess: { _ in AnyView(Color.clear) })
                host.panel.alphaValue = 0
                host.panel.ignoresMouseEvents = true
                host.panel.orderFrontRegardless()
                let music = geometry.compactMusicGeometry
                let timer = geometry.compactTimerGeometry(showsDownloads: true)
                let states: [(CGSize, Bool)] = [(geometry.collapsed, true), (music.compactActivitySize, true), (geometry.notice, true),
                    (geometry.expanded, false), (geometry.noticeSize(wingWidth: 190), true),
                    (timer.compactActivitySize, true), (geometry.peek, false), (geometry.restingSize(showsContent: false), true)]
                let shortcuts = NotchQuickAccessConfiguration(buttons: [
                    NotchQuickButton(action: .explore, side: .left),
                    NotchQuickButton(action: .settings, side: .right),
                    NotchQuickButton(action: .module(.timer), side: .bottom)])
                var previouslyCompact = true
                for animated in [false, true] {
                    for (size, compact) in states {
                        transitions += 1
                        let access = size == geometry.expanded ? shortcuts : nil
                        host.present(size: size, geometry: geometry, animated: animated, quickAccess: access)
                        var settled = false
                        host.whenSettled { settled = true }
                        let deadline = Date().addingTimeInterval(3)
                        repeat {
                            RunLoop.current.run(until: Date().addingTimeInterval(0.008))
                            samples += 1
                            let visible = host.visibleFrame
                            if !physical && compact && previouslyCompact && visible.height > barHeight + 0.5 {
                                failures.insert("a compact simulated transition grew below the menu bar")
                            }
                            if abs(visible.maxY - screen.frame.maxY) > 0.5 {
                                failures.insert("an opening, feedback or collapse frame detached from the screen edge")
                            }
                            if !screen.frame.insetBy(dx: -0.5, dy: -0.5).contains(host.panel.frame)
                                || !host.panel.frame.insetBy(dx: -0.5, dy: -0.5).contains(visible) {
                                failures.insert("an animated island or its shortcuts escaped the screen or backing window")
                            }
                            if abs(host.contentTopOnScreen - host.panel.frame.maxY) > 0.5
                                || !host.containsHover(CGPoint(x: screen.frame.midX, y: visible.maxY - 1)) {
                                failures.insert("resizing displaced content or lost a stationary pointer inside the notch")
                            }
                        } while !settled && Date() < deadline
                        let gutter = access == nil ? 0 : NotchQuickAccessLayout.gutter
                        let expected = geometry.frame(for: CGSize(width: size.width + gutter * 2,
                                                                   height: size.height + gutter))
                        let actual = host.panel.frame
                        if !settled || host.targetSize != size
                            || abs(actual.midX - expected.midX) > 0.5 || abs(actual.maxY - expected.maxY) > 0.5
                            || abs(actual.width - expected.width) > 1 || abs(actual.height - expected.height) > 1 {
                            failures.insert("a transition did not settle at its requested size and screen-edge position")
                        }
                        let resizes = host.resizeCount
                        for _ in 0..<10 {
                            host.present(size: size, geometry: geometry, animated: false, quickAccess: access)
                        }
                        if host.resizeCount != resizes {
                            failures.insert("pixel alignment caused unchanged presentations to resize repeatedly")
                        }
                        let visible = host.visibleFrame
                        if !physical && compact && visible.minY < screen.frame.maxY - barHeight - 0.5 {
                            failures.insert("a closed or compact simulated notch escaped the actual menu bar")
                        }
                        previouslyCompact = compact
                        let shoulder = min(NotchLayout.shoulder, visible.height * 0.28)
                        if !host.contains(CGPoint(x: visible.minX + shoulder, y: visible.maxY - 0.25))
                            || host.contains(CGPoint(x: visible.minX + shoulder, y: visible.minY + 0.25)) {
                            failures.insert("a physical or simulated notch lost its attached shoulders or rounded lower corners")
                        }
                    }
                }
                let position = host.panel.frame
                host.panel.setFrameOrigin(CGPoint(x: position.minX + 20, y: position.minY - 10))
                host.present(size: geometry.restingSize(showsContent: false), geometry: geometry, animated: false)
                if host.panel.frame != position {
                    failures.insert("an external window move was not restored to the notch's screen-edge position")
                }
                host.close()
                if host.panel.isVisible { failures.insert("closing left the test window visible") }
            }
        }
        print("NOTCH PROFILE PROBE \(failures.isEmpty ? "OK" : "FAILED") samples=\(samples) transitions=\(transitions) menuHeights=6")
        failures.sorted().forEach { print($0) }
        exit(failures.isEmpty ? 0 : 1)
    }
}
#endif
