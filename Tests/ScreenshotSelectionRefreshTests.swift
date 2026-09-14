// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Real selection methods run with controlled capture replies and inert panels.
/// Images carry exclusion identities; no desktop pixels or input events are used.
enum ScreenshotSelectionRefreshContract {
    struct CGImage {
        let excluded: Set<CGWindowID>
        let width = 100
        let height = 100
        func cropping(to: CGRect) -> CGImage? { self }
    }
    enum DefaultsKey {
        static let screenshotFreeze = "freeze", screenshotIncludePointer = "pointer",
            screenshotHideVorssaintWindows = "hide"
    }
    struct ReviewDefaults {
        static var current = ReviewDefaults()
        var values: [String: Bool] = ["freeze": true, "pointer": false, "hide": false]
        func bool(forKey key: String) -> Bool { values[key] ?? false }
    }
    struct NSScreen {
        static let screens = [NSScreen()]
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
    }
    final class View {
        var isCapturePending = false
        var loupeImage: CGImage?
        func captureToolDidChange() {}
        func refreshPointerState() {}
        func updateLoupeImage(_ image: CGImage?) { loupeImage = image }
    }
    final class ScreenshotOverlayPanel {
        let displayID: CGDirectDisplayID
        let screenFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let pixelScale: CGFloat = 1
        var frozenImage: CGImage?
        var windows: [ScreenshotSupport.PickableWindow]
        var overlayView = View()
        var pixelSize: CGSize { screenFrame.size }
        var frozenImageSize: CGSize? { frozenImage == nil ? nil : screenFrame.size }
        init(_ id: CGDirectDisplayID, _ excluded: Set<CGWindowID>) {
            displayID = id
            frozenImage = CGImage(excluded: excluded)
            windows = excluded.contains(11) ? [] : [.init(windowID: 11, frame: screenFrame)]
        }
        func update(frozenImage: CGImage?, windows: [ScreenshotSupport.PickableWindow]) {
            self.frozenImage = frozenImage
            self.windows = windows
        }
    }
    enum RecorderSupport { struct Region { let windowID: CGWindowID? } }
    @MainActor enum ScreenshotCaptureEngine {
        struct Request {
            let excluded: Set<CGWindowID>
            let continuation: CheckedContinuation<[CGDirectDisplayID: CGImage], Never>
        }
        static var requests = [Request]()
        static func captureAllDisplays(
            includePointer: Bool, hideVorssaintWindows: Bool, protectedWindowIDs: Set<CGWindowID>
        ) async -> [CGDirectDisplayID: CGImage] {
            let excluded = ScreenshotCapturePolicy.excludedWindowIDs(
                hideVorssaintWindows: hideVorssaintWindows, ownWindowIDs: [11, 12, 13],
                protectedWindowIDs: protectedWindowIDs)
            return await withCheckedContinuation {
                requests.append(Request(excluded: excluded, continuation: $0))
            }
        }
        static func pickableWindows(hideVorssaintWindows: Bool, protectedWindowIDs: Set<CGWindowID>)
            -> [(id: CGWindowID, bounds: CGRect)]
        {
            ScreenshotCapturePolicy.canPickWindow(
                11, isOwnWindow: true, hideVorssaintWindows: hideVorssaintWindows,
                protectedWindowIDs: protectedWindowIDs)
                ? [(CGWindowID(11), CGRect(x: 0, y: 0, width: 50, height: 50))] : []
        }
        static func captureWindow(_ id: CGWindowID, scale: CGFloat) async -> CGImage? {
            CGImage(excluded: [])
        }
        static func complete(_ index: Int, displays: [CGDirectDisplayID]) {
            let request = requests[index]
            request.continuation.resume(
                returning: Dictionary(
                    uniqueKeysWithValues: displays.map { ($0, CGImage(excluded: request.excluded)) }))
        }
    }
    @MainActor final class Chooser {
        typealias CGImage = ScreenshotSelectionRefreshContract.CGImage
        typealias ScreenshotCaptureEngine = ScreenshotSelectionRefreshContract.ScreenshotCaptureEngine
        typealias DefaultsKey = ScreenshotSelectionRefreshContract.DefaultsKey
        typealias ReviewDefaults = ScreenshotSelectionRefreshContract.ReviewDefaults
        typealias NSScreen = ScreenshotSelectionRefreshContract.NSScreen
        typealias ScreenshotOverlayPanel = ScreenshotSelectionRefreshContract.ScreenshotOverlayPanel
        typealias RecorderSupport = ScreenshotSelectionRefreshContract.RecorderSupport
        typealias QuickToolsSupport = ScreenshotSelectionRefreshContract.QuickToolsSupport
        enum Mode { case image, geometry, color }
        struct Capture {
            let image: CGImage
            let scale: CGFloat
            let anchorRect: CGRect
        }
        enum Outcome {
            case captured(Capture), region(RecorderSupport.Region), scrollingRegion(
                RecorderSupport.Region), color(NSColor), failed, cancelled
        }
        var activeTool: ScreenCaptureTool?
        var activeMode: Mode {
            activeTool == .recording ? .geometry : activeTool == .color ? .color : .image
        }
        var isPickingColor: Bool { activeMode == .color }
        var capturePolicy: ScreenshotSupport.UnifiedCapturePolicy
        var freeze: Bool
        var includePointer: Bool
        var hideVorssaintWindows: Bool
        var sourceRefreshPending = false
        var sourceGeneration = 0, finished = false, scrollingCaptureEnabled = false,
            loupeEnabled = false, selectionInProgress = false
        var panels: [ScreenshotOverlayPanel]
        var outcome: Outcome?
        var captureExcludedWindowIDs: Set<CGWindowID> {
            ScreenshotCapturePolicy.protectedWindowIDs(
                workflowWindowIDs: [12], contentWindowIDs: [11, 13],
                honoursVisibilityPreference: activeTool != nil && activeTool != .recording)
        }
        init(_ tool: ScreenCaptureTool) {
            activeTool = tool
            let d = ReviewDefaults.current
            let p = ScreenshotSupport.unifiedCapturePolicy(
                for: tool, screenshotFreeze: d.bool(forKey: "freeze"),
                screenshotIncludePointer: d.bool(forKey: "pointer"),
                screenshotHideVorssaintWindows: d.bool(forKey: "hide"))
            capturePolicy = p
            freeze = p.freeze
            includePointer = p.includePointer
            hideVorssaintWindows = p.hideVorssaintWindows
            let ids: Set<CGWindowID> = p.keepsContentWindowsOut ? [11, 12, 13] : [12]
            panels = [ScreenshotOverlayPanel(1, ids), ScreenshotOverlayPanel(2, ids)]
        }
        func select(_ tool: ScreenCaptureTool) {
            activeTool = tool
            screenCaptureToolDidChange()
        }
        static var lastRegion: (displayID: CGDirectDisplayID, viewRect: CGRect)?
        func panelUnderMouse() -> ScreenshotOverlayPanel? { panels.first }
        static func pickableWindows(
            _ entries: [(id: CGWindowID, bounds: CGRect)], on screenFrame: CGRect,
            mainScreenHeight: CGFloat
        ) -> [ScreenshotSupport.PickableWindow] {
            entries.map { .init(windowID: $0.id, frame: $0.bounds) }
        }
        func region(fromView: CGRect, on: ScreenshotOverlayPanel, windowID: CGWindowID?)
            -> RecorderSupport.Region
        { .init(windowID: windowID) }
        func finish(_ outcome: Outcome) {
            self.outcome = outcome
            finished = true
        }
        func captureLive(
            displayID: CGDirectDisplayID, pixelRect: CGRect?, scale: CGFloat, anchorRect: CGRect
        ) { finish(.captured(Capture(image: CGImage(excluded: []), scale: scale, anchorRect: anchorRect))) }
    }

    enum QuickToolsSupport {
        static func sampledColor(in image: CGImage, x: Int, y: Int) -> NSColor? {
            image.excluded.contains(11) ? .red : .green
        }
    }
    static func run(_ suite: TestSuite) {
        var completed = false
        Task { @MainActor in
            await checks(suite)
            completed = true
        }
        let deadline = Date().addingTimeInterval(10)
        while !completed && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        suite.expect(completed, "capture selection refresh contracts finish without UI")
    }
    @MainActor static func drain() async { for _ in 0..<20 { await Task.yield() } }
    @MainActor static func checks(_ suite: TestSuite) async {
        func expect(_ condition: Bool, _ message: String) { suite.expect(condition, message) }
        ReviewDefaults.current = ReviewDefaults()
        ScreenshotCaptureEngine.requests = []
        for other in [ScreenCaptureTool.screenshot, .text, .color] {
            for (from, to) in [
                (ScreenCaptureTool.recording, other), (other, ScreenCaptureTool.recording),
            ] {
                let c = Chooser(from)
                let request = ScreenshotCaptureEngine.requests.count
                c.select(to)
                expect(
                    !c.acceptsCaptureInput, "changing tool blocks capture before the refresh task starts")
                c.confirmRegion(CGRect(x: 0, y: 0, width: 20, height: 20), on: c.panels[0])
                c.confirmWindow(11, frame: .zero, on: c.panels[0])
                c.captureFullDisplayUnderMouse()
                Chooser.lastRegion = (1, CGRect(x: 0, y: 0, width: 20, height: 20))
                c.repeatLastRegion()
                c.confirmColor(at: .zero, on: c.panels[0])
                expect(
                    c.outcome == nil,
                    "pending refresh rejects region, window, full-screen, repeat and color confirmations")
                await drain()
                expect(
                    ScreenshotCaptureEngine.requests.count == request + 1,
                    "each changed visibility requests one fresh source")
                ScreenshotCaptureEngine.complete(request, displays: [1, 2])
                await drain()
                expect(c.acceptsCaptureInput, "successful refresh restores capture input")
                expect(
                    c.panels.allSatisfy { $0.frozenImage!.excluded.contains(11) == (to == .recording) },
                    "both displays use the selected tool visibility")
                expect(
                    c.panels.allSatisfy { $0.windows.isEmpty == (to == .recording) },
                    "selectable windows follow the refreshed pixels")
                if to == .color {
                    c.confirmColor(at: .zero, on: c.panels[0])
                } else {
                    c.captureFullDisplayUnderMouse()
                }
                expect(c.outcome != nil, "a ready source can be confirmed normally")
            }
        }
        for available: [CGDirectDisplayID] in [[], [1]] {
            let failed = Chooser(.recording)
            let r = ScreenshotCaptureEngine.requests.count
            failed.select(.screenshot)
            await drain()
            ScreenshotCaptureEngine.complete(r, displays: available)
            await drain()
            if case .failed? = failed.outcome {
                expect(true, "missing refreshed display closes selection safely")
            } else {
                expect(false, "missing refreshed display closes selection safely")
            }
            expect(!failed.acceptsCaptureInput, "a failed refresh never resumes capture on old pixels")
            failed.captureFullDisplayUnderMouse()
            if case .failed? = failed.outcome {
                expect(true, "failed selection cannot subsequently save a stale screenshot")
            } else {
                expect(false, "failed selection cannot subsequently save a stale screenshot")
            }
        }
        let rapid = Chooser(.recording)
        let r3 = ScreenshotCaptureEngine.requests.count
        rapid.select(.screenshot)
        await drain()
        rapid.select(.recording)
        await drain()
        ScreenshotCaptureEngine.complete(r3, displays: [])
        await drain()
        expect(
            !rapid.finished && !rapid.acceptsCaptureInput,
            "outdated failure cannot close or unlock the current refresh")
        ScreenshotCaptureEngine.complete(r3 + 1, displays: [1, 2])
        await drain()
        expect(
            rapid.acceptsCaptureInput
                && rapid.panels.allSatisfy { $0.frozenImage!.excluded.contains(11) && $0.windows.isEmpty },
            "latest source restores input with current visibility")
        let reverse = Chooser(.recording)
        let rr = ScreenshotCaptureEngine.requests.count
        reverse.select(.screenshot)
        await drain()
        reverse.select(.recording)
        await drain()
        ScreenshotCaptureEngine.complete(rr + 1, displays: [1, 2])
        await drain()
        ScreenshotCaptureEngine.complete(rr, displays: [1, 2])
        await drain()
        expect(
            reverse.panels.allSatisfy { $0.frozenImage!.excluded.contains(11) },
            "old success arriving last cannot overwrite current pixels")
        let cancelled = Chooser(.recording)
        let r4 = ScreenshotCaptureEngine.requests.count
        cancelled.select(.screenshot)
        await drain()
        cancelled.finish(.cancelled)
        ScreenshotCaptureEngine.complete(r4, displays: [1, 2])
        await drain()
        expect(
            !cancelled.acceptsCaptureInput && cancelled.panels[0].frozenImage!.excluded.contains(11),
            "cancelled selection ignores delayed refresh")
        let same = Chooser(.screenshot)
        let count = ScreenshotCaptureEngine.requests.count
        same.select(.text)
        same.select(.color)
        await drain()
        expect(
            ScreenshotCaptureEngine.requests.count == count && same.acceptsCaptureInput,
            "equal source tools reuse pixels without pausing capture")
        let follow = Chooser(.screenshot)
        let rf = ScreenshotCaptureEngine.requests.count
        follow.select(.recording)
        await drain()
        ReviewDefaults.current.values["hide"] = true
        follow.select(.text)
        await drain()
        ScreenshotCaptureEngine.complete(rf + 1, displays: [1, 2])
        await drain()
        ScreenshotCaptureEngine.complete(rf, displays: [1, 2])
        await drain()
        expect(
            follow.panels.allSatisfy { $0.frozenImage!.excluded.contains(11) && $0.windows.isEmpty },
            "later preference choice wins over old completion")
        ReviewDefaults.current.values["hide"] = false
        let rshow = ScreenshotCaptureEngine.requests.count
        follow.select(.screenshot)
        await drain()
        ScreenshotCaptureEngine.complete(rshow, displays: [1, 2])
        await drain()
        expect(
            follow.panels.allSatisfy { !$0.frozenImage!.excluded.contains(11) && !$0.windows.isEmpty },
            "showing windows again restores editor visibility")
        let live = Chooser(.recording)
        let rl = ScreenshotCaptureEngine.requests.count
        live.select(.text)
        await drain()
        ReviewDefaults.current.values["freeze"] = false
        live.select(.screenshot)
        expect(
            live.acceptsCaptureInput
                && live.panels.allSatisfy { $0.frozenImage == nil && !$0.windows.isEmpty },
            "switching to live capture resumes with current selectable windows")
        ScreenshotCaptureEngine.complete(rl, displays: [1, 2])
        await drain()
        expect(
            live.panels.allSatisfy { $0.frozenImage == nil },
            "an old frozen result cannot replace live capture")
        let loupe = Chooser(.screenshot)
        let loupeRequest = ScreenshotCaptureEngine.requests.count
        loupe.loadLiveLoupeImages()
        await drain()
        loupe.select(.recording)
        await drain()
        ScreenshotCaptureEngine.complete(loupeRequest + 1, displays: [1, 2])
        await drain()
        ScreenshotCaptureEngine.complete(loupeRequest, displays: [1, 2])
        await drain()
        expect(
            loupe.panels.allSatisfy { $0.overlayView.loupeImage == nil },
            "a previous tool's delayed live loupe cannot replace the current source")

    }
}
