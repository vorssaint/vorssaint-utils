// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Darwin
import Foundation

enum DockPreviewTests {
    static func run(expect: (Bool, String) -> Void) {
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            expect(!(abs(actual - expected) > tol), "\(label): got \(actual), expected \(expected)")
        }

        let registeredDefaults = Defaults.registeredDefaults
        let visibleDockCard = CGRect(x: 0, y: 25, width: 120, height: 80)
        for eventType: NSEvent.EventType in [.leftMouseDown, .rightMouseDown, .otherMouseDown, .otherMouseUp, .mouseMoved] {
            for button in [0, 1, 2, 3, 4] {
                let handles = DockPreviewSupport.handlesMiddleClick(eventType: eventType,
                    buttonNumber: button, point: CGPoint(x: 60, y: 50),
                    visibleRect: visibleDockCard, isHidden: false)
                expect(handles == (button == 2 && (eventType == .otherMouseDown || eventType == .otherMouseUp)),
                       "Dock preview reserves only middle-button presses and releases")
            }
        }
        for point in [CGPoint(x: 60, y: 10), CGPoint(x: 130, y: 50), CGPoint(x: 60, y: 110)] {
            expect(!DockPreviewSupport.handlesMiddleClick(eventType: .otherMouseDown,
                buttonNumber: 2, point: point, visibleRect: visibleDockCard, isHidden: false),
                   "clipped and off-card preview areas cannot close a window")
        }
        expect(!DockPreviewSupport.handlesMiddleClick(eventType: .otherMouseDown,
            buttonNumber: 2, point: CGPoint(x: 60, y: 50), visibleRect: visibleDockCard, isHidden: true),
               "hidden preview cards cannot close a window")
        expect(registeredDefaults[DefaultsKey.dockPreviewEnabled] as? Bool == false,
               "Dock Preview is opt-in for clean installs")
        expect(registeredDefaults[DefaultsKey.dockPreviewBackgroundOpacity] as? Double == 1.0,
               "the Dock Preview panel starts fully solid")
        expect(registeredDefaults[DefaultsKey.dockPreviewQuitAppOnClose] as? Bool == false,
               "the Dock Preview close button closes one window by default")
        expect(DockPreviewSupport.closeAction(quitAppOnClose: false) == .closeWindow
                && DockPreviewSupport.closeAction(quitAppOnClose: true) == .quitApp,
               "the Dock Preview close preference selects exactly one close action")
        var dockPreviewQuitRequests = 0
        var dockPreviewWindowCloseRequests = 0
        DockPreviewSupport.performCloseAction(
            quitAppOnClose: false,
            requestQuit: {
                dockPreviewQuitRequests += 1
                return true
            },
            closeWindow: { dockPreviewWindowCloseRequests += 1 }
        )
        DockPreviewSupport.performCloseAction(
            quitAppOnClose: true,
            requestQuit: {
                dockPreviewQuitRequests += 1
                return true
            },
            closeWindow: { dockPreviewWindowCloseRequests += 1 }
        )
        DockPreviewSupport.performCloseAction(
            quitAppOnClose: true,
            requestQuit: {
                dockPreviewQuitRequests += 1
                return false
            },
            closeWindow: { dockPreviewWindowCloseRequests += 1 }
        )
        expect(dockPreviewQuitRequests == 2 && dockPreviewWindowCloseRequests == 2,
               "Dock Preview closes a window normally, waits after an accepted quit, and falls back after refusal")
        expect(registeredDefaults[DefaultsKey.dockClickHide] as? Bool == false,
               "hiding the active app from its Dock icon is opt-in")
        expect(DockPreviewSupport.sanitizedBackgroundOpacity(0.7) == 0.7,
               "a Dock Preview background opacity inside the range is kept")
        // A card is dragged for the same reason whatever state its window is in:
        // the user wants that window here. Minimized and parked-on-another-Space
        // used to refuse the gesture, which read as the drag doing nothing --
        // releasing then counted as a click and the window went back to its own
        // old place instead of the drop point.
        expect(DockPreviewSupport.canDragToPlace(hasWindowID: true, isFullscreen: false),
               "an ordinary preview card can be dragged out of the panel")
        expect(DockPreviewSupport.canDragToPlace(hasWindowID: true, isFullscreen: false),
               "a minimized or parked window is dragged like any other")
        expect(!DockPreviewSupport.canDragToPlace(hasWindowID: true, isFullscreen: true),
               "a fullscreen window owns its Space and ignores a dropped position")
        expect(!DockPreviewSupport.canDragToPlace(hasWindowID: false, isFullscreen: false),
               "an entry without a window has nothing to move")
        // The preview size setting sizes the thumbnail, not the writing around
        // it. Both halves of that are checked across every size on offer: the
        // picture tracks the setting exactly, and the chrome does not move at
        // all — a title band that scaled with the card once left a 12pt line
        // adrift in 31pt of nothing at the largest setting.
        let previewScales = Defaults.allowedPreviewSizes.map { PreviewSizing.scale(for: $0) }
        expect(previewScales.count == 4 && previewScales.contains(1.0),
               "every preview size on offer has a scale, including the unscaled one")
        expect(previewScales.allSatisfy { scale in
                   let thumbnail = DockPreviewSupport.cardThumbnailSize(scale: scale)
                   let base = DockPreviewSupport.cardThumbnailSize(scale: 1)
                   return abs(thumbnail.width - base.width * scale) < 0.0001
                       && abs(thumbnail.height - base.height * scale) < 0.0001
               },
               "a Dock Preview thumbnail is exactly the chosen preview size")
        expect(previewScales.allSatisfy { scale in
                   let card = DockPreviewSupport.cardSize(scale: scale)
                   let thumbnail = DockPreviewSupport.cardThumbnailSize(scale: scale)
                   return card.height - thumbnail.height - 13 * scale >= DockPreviewSupport.cardTitleHeight
               },
               "a card keeps a full title band at every preview size, never a scaled-down one")
        expect(DockPreviewSupport.cardTitleHeight >= 20,
               "the title band holds one line of 12pt semibold beside two 16pt controls")
        // The well is cut to the shape of the screen the capture came from, so
        // a full-height window fills it instead of sitting between two bars.
        expect(previewScales.allSatisfy { scale in
                   let picture = DockPreviewSupport.cardPictureSize(scale: scale)
                   return abs(picture.width / picture.height - 1.6) < 0.001
               },
               "the picture inside a thumbnail is 16:10 at every preview size")
        expect(previewScales.allSatisfy { scale in
                   let picture = DockPreviewSupport.cardPictureSize(scale: scale)
                   let thumbnail = DockPreviewSupport.cardThumbnailSize(scale: scale)
                   return picture.width < thumbnail.width && picture.height < thumbnail.height
               },
               "the picture keeps its inset inside the thumbnail well at every size")
        expect(previewScales.allSatisfy {
                   DockPreviewSupport.cardFallbackIconSize(scale: $0)
                       < DockPreviewSupport.cardThumbnailSize(scale: $0).height
               },
               "the stand-in app icon stays inside the thumbnail it stands in for at every size")
        // Every window takes the same steps on a drop, whatever state it was
        // in. A branch on `isMinimized` made that drop feel like a different
        // gesture from an ordinary one -- which is the thing being fixed, so a
        // branch is what this guards against.
        let placeSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Switcher/WindowActivator.swift",
            encoding: .utf8)) ?? ""
        let placeBody = (placeSource.components(separatedBy: "static func place(_ item: SwitcherItem")
            .last ?? "").components(separatedBy: "\n    @discardableResult").first ?? ""
        let placeCode = placeBody
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(!placeCode.isEmpty && !placeCode.contains("isMinimized"),
               "a drop takes the same steps for a minimized window as for any other")
        // The thumbnail is derived from the card, so a constant changed on its
        // own must not silently eat into it or leave the card short.
        expectClose(Double(DockPreviewSupport.cardThumbnailHeight
                            + DockPreviewSupport.cardPadding * 2
                            + DockPreviewSupport.cardTitleSpacing
                            + DockPreviewSupport.cardTitleHeight),
                    Double(DockPreviewSupport.cardHeight),
                    "a Dock Preview card's chrome and thumbnail add up to the card")
        expect(DockPreviewSupport.cardThumbnailHeight
                > DockPreviewSupport.cardHeight * 0.7,
               "the thumbnail keeps most of the Dock Preview card")

        // The card used to draw the app icon on every thumbnail and the window
        // title both over the thumbnail and under it. In a panel every card
        // belongs to one app, so both said the same thing once per window.
        let dockPreviewCardSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Switcher/DockPreviewPanelView.swift",
            encoding: .utf8)) ?? ""
        let dockPreviewCardCode = dockPreviewCardSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(dockPreviewCardCode.components(separatedBy: "window.displayTitle").count - 1 == 1,
               "a Dock Preview card names its window once")
        // Nothing is drawn on top of the picture any more. The close and
        // minimize buttons sat in a 28pt capsule in its top-right corner --
        // over a third of its height -- and the pinned badge sat beside them.
        expect(!dockPreviewCardCode.contains("previewControlBar"),
               "no control bar floats over a Dock Preview thumbnail")
        let titleBandBody = dockPreviewCardCode
            .components(separatedBy: "private var titleBand: some View {").last ?? ""
        let bandDeclaration = titleBandBody.components(separatedBy: "private var").first ?? ""
        expect(bandDeclaration.contains("closeButton") && bandDeclaration.contains("minimizeButton"),
               "both window controls sit in the title band, beside the name")
        expect(!DockPreviewSupport.showsCardControls(isHovering: false, isSelected: false),
               "a card with no pointer on it and no selection draws no window controls")
        expect(DockPreviewSupport.showsCardControls(isHovering: true, isSelected: false),
               "the pointer summons a card's window controls")
        let contextMenuBody = dockPreviewCardCode
            .components(separatedBy: "private var cardContextMenu: some View {").last ?? ""
        expect((contextMenuBody.components(separatedBy: "private var").first ?? "")
                   .contains("dockPreviewPinPanel"),
               "pinning is offered by name in the card menu, not by a bare pushpin")
        expect(DockPreviewSupport.showsCardAppBadge(hasPreview: true),
               "a card with a capture badges it with the app's icon, as the App Switcher does")
        expect(!DockPreviewSupport.showsCardAppBadge(hasPreview: false),
               "a card without one already shows that icon as its watermark, so it takes no badge")
        expect(dockPreviewCardSource.contains("window.isOnHiddenSpace"),
               "a Dock Preview card badges a window that lives on another desktop")

        let dockDropScreen = CGRect(x: -1440, y: 24, width: 1440, height: 876)
        expect(DockPreviewSupport.dragOrigin(pointer: CGPoint(x: -700, y: 500),
                                             windowSize: CGSize(width: 600, height: 400),
                                             visibleFrame: dockDropScreen)
               == CGPoint(x: -700, y: 500),
               "a Dock Preview drop inside the screen keeps the pointer origin")
        expect(DockPreviewSupport.dragOrigin(pointer: CGPoint(x: -20, y: 100),
                                             windowSize: CGSize(width: 600, height: 400),
                                             visibleFrame: dockDropScreen)
               == CGPoint(x: -600, y: 424),
               "a Dock Preview edge drop keeps the whole window reachable")
        expect(DockPreviewSupport.dragOrigin(pointer: CGPoint(x: -700, y: 500),
                                             windowSize: CGSize(width: 1800, height: 1000),
                                             visibleFrame: dockDropScreen)
               == CGPoint(x: -1440, y: 900),
               "an oversized dropped window keeps its title bar on the destination screen")
        expect(DockPreviewSupport.sanitizedBackgroundOpacity(0)
               == DockPreviewSupport.backgroundOpacityRange.lowerBound
               && DockPreviewSupport.sanitizedBackgroundOpacity(-3)
               == DockPreviewSupport.backgroundOpacityRange.lowerBound,
               "the Dock Preview panel never fades past the floor that keeps it looking like a panel")
        expect(DockPreviewSupport.sanitizedBackgroundOpacity(4) == 1.0
               && DockPreviewSupport.sanitizedBackgroundOpacity(.nan) == 1.0
               && DockPreviewSupport.sanitizedBackgroundOpacity(.infinity) == 1.0,
               "a broken stored Dock Preview opacity falls back to solid")
        expect(registeredDefaults[DefaultsKey.dockPreviewOpenDelay] as? Int
               == DockPreviewSupport.defaultOpenDelayMilliseconds,
               "a clean install waits the default before opening a Dock Preview")
        expect(DockPreviewSupport.openDelayMillisecondsRange
               .contains(DockPreviewSupport.defaultOpenDelayMilliseconds),
               "the default Dock Preview delay is one the field accepts")
        expect(DockPreviewSupport.sanitizedOpenDelay(milliseconds: 350) == 350,
               "a typed Dock Preview delay inside the range is kept")
        expect(DockPreviewSupport.sanitizedOpenDelay(milliseconds: -1)
               == DockPreviewSupport.openDelayMillisecondsRange.lowerBound
               && DockPreviewSupport.sanitizedOpenDelay(milliseconds: 9_000)
               == DockPreviewSupport.openDelayMillisecondsRange.upperBound,
               "a Dock Preview delay outside the range is clamped to it")
        expect(DockPreviewSupport.sanitizedOpenDelay(milliseconds: 0)
               >= DockPreviewSupport.openDelayMillisecondsRange.lowerBound,
               "an unset or zeroed Dock Preview delay cannot disarm the wait entirely")
        expectClose(DockPreviewSupport.openDelay(milliseconds: 250), 0.25,
                    "the stored milliseconds drive the timer in seconds")
        let openDelays = DockPreviewSupport.openDelayMillisecondsRange
            .map { DockPreviewSupport.openDelay(milliseconds: $0) }
        expect(openDelays.allSatisfy { DockPreviewSupport.switchDelay <= $0 },
               "no chosen delay makes switching slower than opening")
        expect(openDelays.allSatisfy { DockPreviewSupport.prefetchDelay(openDelay: $0) <= $0 },
               "the window list is never read after the panel it is read for has opened")
        expect(openDelays.allSatisfy {
                   $0 - DockPreviewSupport.prefetchDelay(openDelay: $0)
                       <= DockPreviewSupport.prefetchLead + 0.0001
               },
               "the window list is never read further ahead than the lead, so what opens is still true")
        expectClose(DockPreviewSupport.prefetchDelay(
                        openDelay: DockPreviewSupport.openDelay(
                            milliseconds: DockPreviewSupport.defaultOpenDelayMilliseconds)),
                    0.1,
                    "at the default the window list is read halfway through the wait")
        expect(openDelays.allSatisfy {
                   DockPreviewSupport.prefetchDelay(openDelay: $0) >= DockPreviewSupport.prefetchLead
               },
               "no setting reads the window list before the cursor has held still")
        expect(DockPreviewSupport.switchDelay + 0.06
               < DockPreviewSupport.openDelay(
                   milliseconds: DockPreviewSupport.openDelayMillisecondsRange.lowerBound),
               "a switch, reading its window list inline, still lands before the shortest fresh open")
    }

    static func runGeometry(expect: (Bool, String) -> Void) {
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            expect(!(abs(actual - expected) > tol), "\(label): got \(actual), expected \(expected)")
        }

        let dockPreviewCardSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Switcher/DockPreviewPanelView.swift",
            encoding: .utf8)) ?? ""
        // MARK: Dock Preview helpers

        let dockPrefs = DockPreviewPreferences.sanitized(orientation: "left",
                                                         autohide: true,
                                                         tileSize: 81,
                                                         magnification: false,
                                                         magnifiedTileSize: 100)
        expect(dockPrefs == DockPreviewPreferences(orientation: .left,
                                                   autohide: true,
                                                   tileSize: 81,
                                                   magnification: false,
                                                   magnifiedTileSize: 100),
               "Dock Preview preferences preserve valid Dock values")
        let fallbackDockPrefs = DockPreviewPreferences.sanitized(orientation: "bad",
                                                                 autohide: nil,
                                                                 tileSize: 999,
                                                                 magnification: nil,
                                                                 magnifiedTileSize: nil)
        expect(fallbackDockPrefs == DockPreviewPreferences(orientation: .bottom,
                                                           autohide: false,
                                                           tileSize: 256,
                                                           magnification: false,
                                                           magnifiedTileSize: 128),
               "Dock Preview preferences sanitize missing and out-of-range values")
        expect(DockPreviewSupport.availability(enabled: false,
                                               hasAccessibility: true,
                                               hasScreenRecording: true,
                                               preferences: dockPrefs)
               == DockPreviewAvailability(canRun: false, blockedReason: nil),
               "disabled Dock Preview does not report an error")
        expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: false,
                                               hasScreenRecording: true,
                                               preferences: dockPrefs).blockedReason == .missingAccessibility,
               "Dock Preview requires Accessibility")
        expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: true,
                                               hasScreenRecording: false,
                                               preferences: dockPrefs).blockedReason == .missingScreenRecording,
               "Dock Preview requires Screen Recording")
        let magnifiedPrefs = DockPreviewPreferences(orientation: .bottom,
                                                    autohide: false,
                                                    tileSize: 64,
                                                    magnification: true,
                                                    magnifiedTileSize: 128)
        expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: true,
                                               hasScreenRecording: true,
                                               preferences: magnifiedPrefs).canRun,
               "Dock Preview runs with Dock magnification enabled")
        expect(magnifiedPrefs.hoverTileSize == 128,
               "hover tile size follows the magnified size while magnification is on")
        expect(dockPrefs.hoverTileSize == 81,
               "hover tile size stays at the resting size while magnification is off")
        expect(DockPreviewSupport.dockProximityBand(tileSize: magnifiedPrefs.hoverTileSize)
               > magnifiedPrefs.magnifiedTileSize,
               "Dock proximity band covers a fully magnified icon")
        expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: true,
                                               hasScreenRecording: true,
                                               preferences: dockPrefs).canRun,
               "Dock Preview can run when enabled and permitted")

        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let iconBottom = CGRect(x: 660, y: 0, width: 80, height: 80)
        let panelSize = CGSize(width: 400, height: 160)
        let bottomFrame = DockPreviewSupport.panelFrame(anchor: iconBottom,
                                                        panelSize: panelSize,
                                                        screenVisibleFrame: screen,
                                                        orientation: .bottom)
        expectClose(Double(bottomFrame.midX), Double(iconBottom.midX), "Dock Preview bottom panel centers on icon")
        expect(bottomFrame.minY > iconBottom.maxY,
               "Dock Preview bottom panel sits above the Dock icon")
        let leftFrame = DockPreviewSupport.panelFrame(anchor: CGRect(x: 0, y: 380, width: 80, height: 80),
                                                      panelSize: panelSize,
                                                      screenVisibleFrame: screen,
                                                      orientation: .left)
        expect(leftFrame.minX > 80,
               "Dock Preview left panel sits to the right of the Dock")
        let rightFrame = DockPreviewSupport.panelFrame(anchor: CGRect(x: 1360, y: 380, width: 80, height: 80),
                                                       panelSize: panelSize,
                                                       screenVisibleFrame: screen,
                                                       orientation: .right)
        expect(rightFrame.maxX < 1360,
               "Dock Preview right panel sits to the left of the Dock")
        let hiddenLeftFrame = DockPreviewSupport.panelFrameWhenDockHidden(
            leftFrame, screenVisibleFrame: screen, orientation: .left)
        expect(hiddenLeftFrame.minX == screen.minX + DockPreviewSupport.edgePadding
               && hiddenLeftFrame.minY == leftFrame.minY,
               "Dock Preview fills a left auto-hidden Dock's vacated edge without jumping vertically")
        let hiddenRightFrame = DockPreviewSupport.panelFrameWhenDockHidden(
            rightFrame, screenVisibleFrame: screen, orientation: .right)
        expect(hiddenRightFrame.maxX == screen.maxX - DockPreviewSupport.edgePadding
               && hiddenRightFrame.minY == rightFrame.minY,
               "Dock Preview fills a right auto-hidden Dock's vacated edge without jumping vertically")
        let hiddenBottomFrame = DockPreviewSupport.panelFrameWhenDockHidden(
            bottomFrame, screenVisibleFrame: screen, orientation: .bottom)
        expect(hiddenBottomFrame.minY == screen.minY + DockPreviewSupport.edgePadding
               && hiddenBottomFrame.minX == bottomFrame.minX,
               "Dock Preview fills a bottom auto-hidden Dock's vacated edge without jumping horizontally")
        let resizedDockFrame = DockPreviewSupport.panelFrame(
            anchor: iconBottom,
            panelSize: DockPreviewSupport.panelSize(itemCount: 1,
                                                    screenVisibleFrame: screen,
                                                    isPinned: false),
            screenVisibleFrame: screen,
            orientation: .bottom
        )
        let expectedResizedEdgeFrame = DockPreviewSupport.panelFrameWhenDockHidden(
            resizedDockFrame, screenVisibleFrame: screen, orientation: .bottom)
        expect(DockPreviewSupport.resizedPanelFrame(
                resizedDockFrame,
                didReattachForSession: true,
                screenVisibleFrame: screen,
                orientation: .bottom) == expectedResizedEdgeFrame,
               "resizing a reattached Dock Preview keeps it at the vacated screen edge")
        expect(!DockPreviewSupport.shouldStartDockVisibilityTimer(
                hasActiveTimer: false,
                didReattachForSession: true,
                autohide: true),
               "a reattached Dock Preview does not re-arm its visibility watcher")
        // Both complements, so neither helper can be mutated into a constant
        // and stay green: an always-edge frame would strand a panel that was
        // never reattached, and an always-false watcher would never fire once.
        expect(DockPreviewSupport.resizedPanelFrame(
                resizedDockFrame,
                didReattachForSession: false,
                screenVisibleFrame: screen,
                orientation: .bottom) == resizedDockFrame,
               "a preview that never reattached keeps resizing to the Dock-anchored frame")
        expect(DockPreviewSupport.shouldStartDockVisibilityTimer(
                hasActiveTimer: false,
                didReattachForSession: false,
                autohide: true),
               "an auto-hiding Dock still arms the visibility watcher the first time")
        let dockPreviewServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/DockPreview/DockPreviewService.swift",
            encoding: .utf8)) ?? ""
        let dockPreviewServiceCode = dockPreviewServiceSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(dockPreviewServiceCode.contains("startDockVisibilityTimerIfNeeded()")
               && dockPreviewServiceCode.contains("CGWindowListCopyWindowInfo(.optionOnScreenOnly")
               && dockPreviewServiceCode.contains("DockPreviewSupport.panelFrameWhenDockHidden("),
               "an entered auto-hide Dock Preview follows the Dock's live window to the vacated edge")
        expect(dockPreviewServiceCode.contains("if accepted { self?.endSession() }")
                && dockPreviewServiceCode.contains("if accepted { self?.closePreviewPanel() }"),
               "an accepted app quit closes both hover and pinned previews immediately")
        // The jump is the Dock's thickness, an order of magnitude past
        // panelStayMargin, so a pointer that never moved would otherwise read as
        // outside the panel on its next twitch and dismiss the preview.
        expect(dockPreviewServiceCode.contains("reattachGraceFrame = frame")
               && dockPreviewServiceCode.contains("reattachGraceFrame?.insetBy("),
               "the frame a reattached Dock Preview left behind keeps counting until the pointer reaches the new one")
        // The tap this service owns is served by the main run loop, so an
        // animated setFrame would queue every mouse event behind the slide.
        expect(!dockPreviewServiceCode.contains("setFrame(edgeFrame, display: true, animate: true)")
               && dockPreviewServiceCode.contains("clampedPanelFrame(DockPreviewSupport.panelFrameWhenDockHidden("),
               "a reattached Dock Preview lands clamped, without animating the main run loop")
        let corridor = DockPreviewSupport.hoverCorridor(iconFrame: iconBottom,
                                                        panelFrame: bottomFrame,
                                                        orientation: .bottom)
        expect(corridor.contains(CGPoint(x: iconBottom.midX, y: (iconBottom.maxY + bottomFrame.minY) / 2)),
               "Dock Preview corridor keeps the path from Dock icon to panel alive")
        // A neighbouring Dock icon, one tile to the side, must fall OUTSIDE the
        // corridor; otherwise returning to the Dock can never hand the session to
        // another app and the panel stays stuck on the previous one.
        let neighborIcon = CGRect(x: iconBottom.maxX + 8, y: 0, width: 80, height: 80)
        expect(!corridor.contains(CGPoint(x: neighborIcon.midX, y: neighborIcon.midY)),
               "Dock Preview corridor excludes the neighbouring Dock icon so app switching works")
        expect(DockPreviewSupport.dockProximityBand(tileSize: 64) >= 160,
               "Dock proximity band covers a default-size Dock")
        expect(DockPreviewSupport.dockProximityBand(tileSize: 200)
               > DockPreviewSupport.dockProximityBand(tileSize: 64),
               "Dock proximity band grows with the Dock tile size")
        let onePreviewSize = DockPreviewSupport.panelSize(itemCount: 1, screenVisibleFrame: screen,
                                                          isPinned: false)
        let twoPreviewSize = DockPreviewSupport.panelSize(itemCount: 2, screenVisibleFrame: screen,
                                                          isPinned: false)
        expect(twoPreviewSize.width > onePreviewSize.width,
               "Dock Preview panel size shrinks when a card is removed")
        // The header carries the window counter and the steppers that move
        // between windows, so one window leaves it with nothing to say. It used
        // to name the app instead, back at a pointer resting on that app's Dock
        // icon. A pinned panel keeps it: there it is the drag handle, and the
        // only way to unpin or close.
        // A long name is clipped at rest and scrolled under the pointer. The
        // measurement runs off the font rather than a layout pass, so it holds
        // before the band has ever been drawn.
        let bandWidth = DockPreviewSupport.cardTitleTextWidth
        expect(bandWidth > 0 && bandWidth < DockPreviewSupport.cardThumbnailWidth,
               "the name's room is the band less the two controls beside it")
        expect(!SwitcherSupport.titleOverflows("Mail", width: bandWidth),
               "a short window name is not scrolled")
        expect(SwitcherSupport.titleOverflows(String(repeating: "measurement ", count: 8),
                                              width: bandWidth),
               "a name longer than the band is")
        expect(!SwitcherSupport.titleOverflows("anything", width: 0),
               "a band with no room to measure against scrolls nothing")
        expect(SwitcherSupport.titleWidth("Preferences", weight: .semibold)
               > SwitcherSupport.titleWidth("Preferences", weight: .regular),
               "the selected card's heavier name is measured as the heavier name")
        // Both panels show windows of the same kind, so a name too long for its
        // room behaves the same in each. One view, two callers, two widths.
        let scrollingTitleSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Switcher/ScrollingTitle.swift",
            encoding: .utf8)) ?? ""
        expect(scrollingTitleSource.contains("struct ScrollingTitle: View"),
               "the scrolling name is one view, not a copy in each panel")
        let switcherCardSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Switcher/SwitcherView.swift",
            encoding: .utf8)) ?? ""
        expect(switcherCardSource.contains("ScrollingTitle(")
               && dockPreviewCardSource.contains("ScrollingTitle("),
               "the App Switcher and the Dock preview both draw their name through it")
        // One view, hung differently by each panel. Pinning it to the leading
        // edge in both left a grid card's name and the app name under it on two
        // different axes, which reads as a broken card rather than a choice.
        expect(scrollingTitleSource.contains(".frame(width: width, alignment: alignment)"),
               "the shared name view is told where to sit instead of always taking the leading edge")
        expect(sourceBody(of: switcherCardSource, from: "ScrollingTitle(", to: "scrolls:")
                .contains("alignment: .center"),
               "a grid card centres the window's name over the app name under it")
        expect(sourceBody(of: dockPreviewCardSource, from: "ScrollingTitle(", to: "scrolls:")
                .contains("alignment: .leading"),
               "a Dock preview card keeps the name on the leading edge, beside its two buttons")
        expect(!DockPreviewSupport.showsPanelHeader(isPinned: false),
               "a hovered panel draws no header, whatever it is showing")
        expect(DockPreviewSupport.showsPanelHeader(isPinned: true),
               "a pinned panel keeps the header that names it and moves it")
        // Cards run along the Dock's own edge. A row beside a side Dock grew
        // away from it across the screen, which is the one direction the
        // pointer is not coming from.
        expect(!DockPreviewSupport.stacksVertically(orientation: .bottom, isPinned: false),
               "a Dock at the bottom gets a row of cards")
        expect(DockPreviewSupport.stacksVertically(orientation: .left, isPinned: false)
               && DockPreviewSupport.stacksVertically(orientation: .right, isPinned: false),
               "a Dock at either side gets a column of cards")
        expect(!DockPreviewSupport.stacksVertically(orientation: .right, isPinned: true),
               "a pinned panel is detached from the Dock, so it keeps the row")
        let sideSize = DockPreviewSupport.panelSize(itemCount: 3, screenVisibleFrame: screen,
                                                    isPinned: false, orientation: .right)
        let bottomSize = DockPreviewSupport.panelSize(itemCount: 3, screenVisibleFrame: screen,
                                                      isPinned: false, orientation: .bottom)
        expect(sideSize.width == DockPreviewSupport.cardWidth + DockPreviewSupport.panelPadding * 2,
               "a side Dock's panel is one card wide however many windows it holds")
        expect(sideSize.height > bottomSize.height && sideSize.width < bottomSize.width,
               "the same three windows make a tall narrow panel beside a side Dock")
        expect(DockPreviewSupport.visibleCardCount(itemCount: 99, screenVisibleFrame: screen,
                                                   orientation: .bottom, isPinned: false) < 99,
               "the panel reports how many cards it can show before it has to scroll")
        expect(DockPreviewSupport.visibleCardCount(itemCount: 2, screenVisibleFrame: screen,
                                                   orientation: .bottom, isPinned: false) == 2,
               "two cards that fit are both counted, so the panel does not scroll for them")
        expect(onePreviewSize.height == DockPreviewSupport.cardHeight
               + DockPreviewSupport.panelPadding * 2,
               "a headerless panel is the card and the padding, nothing more")
        expect(DockPreviewSupport.panelSize(itemCount: 1, screenVisibleFrame: screen, isPinned: true).height
               == onePreviewSize.height + DockPreviewSupport.panelHeaderHeight,
               "the header is the whole difference a pinned panel makes to the height")
        expect(DockPreviewSupport.windowPositionText(selectedWindowID: nil, windowIDs: [11]) == nil,
               "Dock Preview hides the window counter for a single window")
        expect(DockPreviewSupport.windowPositionText(selectedWindowID: nil, windowIDs: [11, 22, 33]) == "3",
               "Dock Preview header shows the window count before a card is selected")
        expect(DockPreviewSupport.windowPositionText(selectedWindowID: 22, windowIDs: [11, 22, 33]) == "2/3",
               "Dock Preview header shows selected window position")
        let iconRowLayout = SwitcherIconRowLayout.compute(count: 6, screenVisibleFrame: screen)
        expect(iconRowLayout.visibleIconCount == 6,
               "App Switcher icon-row mode can show all icons when they fit")
        expect(iconRowLayout.panelSize.width <= screen.width * 0.96 + SwitcherIconRowLayout.padding * 2,
               "App Switcher icon-row mode stays within the visible screen")
        expect(iconRowLayout.panelSize.height
               == SwitcherIconRowLayout.previewHeight
               + SwitcherIconRowLayout.previewGap
               + SwitcherIconRowLayout.rowHeight
               + SwitcherIconRowLayout.hintGap
               + SwitcherIconRowLayout.hintHeight
               + SwitcherIconRowLayout.padding * 2,
               "App Switcher icon-row mode reserves preview, icon row and shortcut hint height")
        expect(iconRowLayout.simplePanelSize.height
               == SwitcherIconRowLayout.simpleTitleHeight
               + SwitcherIconRowLayout.simpleTitleGap
               + SwitcherIconRowLayout.rowHeight
               + SwitcherIconRowLayout.hintGap
               + SwitcherIconRowLayout.hintHeight
               + SwitcherIconRowLayout.padding * 2,
               "App Switcher simple mode replaces previews with a compact title rail")
        expect(iconRowLayout.simplePanelSize.width
               == max(iconRowLayout.appRowSurfaceWidth,
                      iconRowLayout.simpleTitleSurfaceWidth,
                      SwitcherIconRowLayout.hintBarWidth)
               + SwitcherIconRowLayout.padding * 2,
               "App Switcher simple mode fits its app row, title rail and shortcut hints")
        let compactIconRowLayout = SwitcherIconRowLayout.compute(
            appCount: 1,
            selectedWindowCount: 1,
            screenVisibleFrame: screen,
            showsShortcutHints: false
        )
        expect(compactIconRowLayout.panelSize.height
               == iconRowLayout.panelSize.height
               - SwitcherIconRowLayout.hintGap
               - SwitcherIconRowLayout.hintHeight,
               "App Switcher removes the shortcut hint bar and its vertical space")
        expect(compactIconRowLayout.simplePanelSize.width
               == max(compactIconRowLayout.appRowSurfaceWidth,
                      compactIconRowLayout.simpleTitleSurfaceWidth)
                    + SwitcherIconRowLayout.padding * 2,
               "App Switcher without shortcut hints still fits its title rail")
        // Two apps leave the icon row narrower than the hint bar, the case that
        // used to lay rows out against a width the panel was never sized for.
        let twoAppLayout = SwitcherIconRowLayout.compute(appCount: 2,
                                                         selectedWindowCount: 1,
                                                         screenVisibleFrame: screen,
                                                         showsShortcutHints: false)
        expect(twoAppLayout.appRowSurfaceWidth < SwitcherIconRowLayout.hintBarWidth
               && twoAppLayout.contentWidth(simpleMode: true, windowRow: false)
                    == twoAppLayout.simplePanelSize.width - SwitcherIconRowLayout.padding * 2
               && twoAppLayout.contentWidth(simpleMode: true, windowRow: true)
                    == twoAppLayout.simpleWindowPanelSize.width - SwitcherIconRowLayout.padding * 2,
               "App Switcher rows fit the panel with fewer apps than the hint bar is wide")
        expect(SwitcherSupport.gridColumnCount(itemCount: 10, maxColumns: 8) == 5,
               "App Switcher wrapping splits ten windows across two even rows")
        expect(SwitcherSupport.gridColumnCount(itemCount: 9, maxColumns: 8) == 5,
               "App Switcher wrapping keeps nine windows on five plus four")
        expect(SwitcherSupport.gridColumnCount(itemCount: 17, maxColumns: 8) == 6,
               "App Switcher wrapping balances three rows instead of leaving one leftover")
        expect(SwitcherSupport.gridColumnCount(itemCount: 8, maxColumns: 8) == 8,
               "App Switcher keeps a single full row when everything fits")
        expect(SwitcherSupport.gridColumnCount(itemCount: 3, maxColumns: 8) == 3,
               "App Switcher width still follows the window count on one row")
        expect(SwitcherSupport.gridColumnCount(itemCount: 16, maxColumns: 8) == 8,
               "App Switcher keeps the packed width when two rows are already even")
        expect(SwitcherSupport.gridSelectionIndex(after: 1,
                                                   itemCount: 8,
                                                   columns: 5,
                                                   movingDown: true) == 6,
               "App Switcher down navigation keeps the same column when it exists")
        expect(SwitcherSupport.gridSelectionIndex(after: 4,
                                                   itemCount: 8,
                                                   columns: 5,
                                                   movingDown: true) == 7,
               "App Switcher down navigation lands on the last item of a shorter row")
        expect(SwitcherSupport.gridSelectionIndex(after: 7,
                                                   itemCount: 8,
                                                   columns: 5,
                                                   movingDown: true) == 7,
               "App Switcher down navigation stays put on the final row")
        expect(SwitcherSupport.gridSelectionIndex(after: 6,
                                                   itemCount: 8,
                                                   columns: 5,
                                                   movingDown: false) == 1,
               "App Switcher up navigation keeps its existing column behavior")
        let previousPreviewSize = UserDefaults.standard.object(forKey: DefaultsKey.previewSize)
        UserDefaults.standard.set("small", forKey: DefaultsKey.previewSize)
        expectClose(Double(PreviewSizing.scale), 0.75,
                    "Preview sizing accepts the Small option")
        expectClose(Double(SwitcherIconRowLayout.scale), 0.75,
                    "App Switcher icon-row mode honors the Small option")
        expectClose(Double(SwitcherIconRowLayout.appEntryIconSize), 49.5,
                    "App Switcher Small keeps a windowless app icon inside its preview")
        let selectedIconTileHeight = SwitcherIconRowLayout.selectedIconSize
            + SwitcherIconRowLayout.iconTileSpacing
            + SwitcherIconRowLayout.iconTitleHeight
            + SwitcherIconRowLayout.iconTileVerticalPadding * 2
        expectClose(Double(SwitcherIconRowLayout.rowHeight - selectedIconTileHeight),
                    Double(SwitcherIconRowLayout.iconTileVerticalMargin * 2),
                    "App Switcher Small keeps the selection outline inside its icon row")
        expectClose(Double(DockPreviewSupport.cardSpacing), 6,
                    "Dock Preview Small previews tighten card spacing")
        expectClose(Double(DockPreviewSupport.panelPadding),
                    Double(DockPreviewSupport.cardPadding),
                    "Dock Preview Small previews tighten panel padding with the card's")
        // The grid card's chrome is two lines of text that do not change with
        // the preview size. The card does, so the thumbnail has to take every
        // point the chrome leaves, at whichever size is stored.
        let smallGridScale = PreviewSizing.scale
        let smallGridCardHeight = SwitcherGridCard.height
        let smallGridCardChrome = smallGridCardHeight - SwitcherGridCard.thumbnailHeight
        expect(SwitcherGridCard.fallbackIconSize < SwitcherGridCard.thumbnailHeight,
               "App Switcher Small keeps the stand-in app icon inside its grid card thumbnail")
        UserDefaults.standard.set("xlarge", forKey: DefaultsKey.previewSize)
        expectClose(Double(SwitcherGridCard.height / smallGridCardHeight),
                    Double(PreviewSizing.scale / smallGridScale),
                    "an App Switcher grid card's height follows the preview size")
        expectClose(Double(SwitcherGridCard.height - SwitcherGridCard.thumbnailHeight),
                    Double(smallGridCardChrome),
                    "an App Switcher grid card spends the same chrome at every preview size")
        expectClose(Double(smallGridCardChrome),
                    Double(SwitcherGridCard.padding * 2
                            + SwitcherGridCard.titleSpacing
                            + SwitcherGridCard.titleHeight),
                    "the grid card's chrome is exactly the parts it is made of, not a number standing in for them")
        expect(SwitcherGridCard.titleHeight >= 31,
               "the grid card title band holds a 13pt line over a 10.5pt line without clipping")
        expect(SwitcherGridCard.fallbackIconSize < SwitcherGridCard.thumbnailHeight,
               "App Switcher Extra Large keeps the stand-in app icon inside its grid card thumbnail")
        let xlargeIconRowLayout = SwitcherIconRowLayout.compute(appCount: 6,
                                                                 selectedWindowCount: 1,
                                                                 screenVisibleFrame: screen)
        expect(SwitcherIconRowLayout.scale <= 1.15,
               "App Switcher icon-row mode caps Extra High preview scaling")
        expect(xlargeIconRowLayout.panelSize.height < 540,
               "App Switcher icon-row mode stays compact with Extra High previews")
        expect(xlargeIconRowLayout.panelSize.width < 950,
               "App Switcher icon-row mode avoids a giant empty backdrop with six apps")
        let xlargeSingleWindowLayout = SwitcherIconRowLayout.compute(appCount: 1,
                                                                     selectedWindowCount: 1,
                                                                     screenVisibleFrame: screen)
        expectClose(Double(xlargeSingleWindowLayout.previewContentWidth),
                    Double(SwitcherIconRowLayout.previewCardWidth),
                    "App Switcher icon-row mode keeps a one-window preview card compact")
        expectClose(Double(xlargeSingleWindowLayout.previewSurfaceWidth),
                    Double(SwitcherIconRowLayout.previewCardWidth + SwitcherIconRowLayout.previewPanelPadding * 2),
                    "App Switcher icon-row mode keeps padding around a one-window preview card")
        expect(xlargeSingleWindowLayout.panelSize.width < 430,
               "App Switcher icon-row mode avoids a giant horizontal panel for one app with one window")
        if let previousPreviewSize {
            UserDefaults.standard.set(previousPreviewSize, forKey: DefaultsKey.previewSize)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.previewSize)
        }
        let defaultSwitcherHints = SwitcherSupport.shortcutHints(for: .switcherDefault,
                                                                 windowShortcut: .switcherWindowDefault)
        // Grave and J print the cap the active keyboard layout carries, not the
        // US one: that is what #1047 changed. Pinning "⌘ `" and "⌘J" here made
        // the check fail on Turkish QWERTY and every other layout that moves
        // them. Ask the layout, and keep the rule the hint depends on: a lone
        // symbol takes a space after the modifiers, a letter does not.
        let commandKeyHint: (String, Int64, String) -> String = { modifiers, keyCode, ansiCap in
            let cap = GlobalShortcut.layoutKeyLabel(for: keyCode, usesCommand: true) ?? ansiCap
            let needsSeparator = cap.count == 1
                && cap.rangeOfCharacter(from: .alphanumerics) == nil
            return modifiers + (needsSeparator ? " " : "") + cap
        }
        expect(defaultSwitcherHints.apps == "⌘Tab"
                && defaultSwitcherHints.windows == commandKeyHint("⌘", Int64(kVK_ANSI_Grave), "`"),
               "App Switcher icon-row hints describe default app and window shortcuts")
        let customSwitcherHints = SwitcherSupport.shortcutHints(
            for: GlobalShortcut(keyCode: Int64(kVK_Tab), modifiers: [.option]),
            windowShortcut: GlobalShortcut(keyCode: Int64(kVK_ANSI_J), modifiers: [.command])
        )
        expect(customSwitcherHints.apps == "⌥Tab"
                && customSwitcherHints.windows == commandKeyHint("⌘", Int64(kVK_ANSI_J), "J"),
               "App Switcher icon-row hints show custom app and window shortcuts independently")
        expect(SwitcherSupport.shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: true,
                                                                  wasShiftHeld: false,
                                                                  isShiftHeld: true),
               "App Switcher shift-only back navigation fires when Shift is pressed")
        expect(!SwitcherSupport.shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: true,
                                                                   wasShiftHeld: true,
                                                                   isShiftHeld: true),
               "App Switcher shift-only back navigation does not repeat while Shift is held")
        expect(!SwitcherSupport.shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: true,
                                                                   wasShiftHeld: true,
                                                                   isShiftHeld: false),
               "App Switcher shift-only back navigation does not fire on Shift release")
        expect(!SwitcherSupport.shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: false,
                                                                   wasShiftHeld: false,
                                                                   isShiftHeld: true),
               "App Switcher shift-only back navigation stays off when Shift belongs to the shortcut")

        func syntheticCapture(_ draw: (CGContext, CGSize) -> Void) -> CGImage? {
            let size = CGSize(width: 320, height: 200)
            guard let context = CGContext(data: nil,
                                          width: Int(size.width),
                                          height: Int(size.height),
                                          bitsPerComponent: 8,
                                          bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            draw(context, size)
            return context.makeImage()
        }
        let opaqueCapture = syntheticCapture { context, size in
            context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
        }
        let roundedCapture = syntheticCapture { context, size in
            let path = CGPath(roundedRect: CGRect(origin: .zero, size: size),
                              cornerWidth: 12, cornerHeight: 12, transform: nil)
            context.addPath(path)
            context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
            context.fillPath()
        }
        let shearedCapture = syntheticCapture { context, size in
            context.translateBy(x: size.width * 0.35, y: size.height * 0.3)
            context.concatenate(CGAffineTransform(a: 0.35, b: 0.12, c: -0.18, d: 0.35, tx: 0, ty: 0))
            context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
        }
        // A sheared capture whose bounding box hugs the artwork: only the two
        // corners outside the parallelogram stay transparent.
        let tightShearCapture = syntheticCapture { context, size in
            context.move(to: CGPoint(x: size.width * 0.25, y: 0))
            context.addLine(to: CGPoint(x: size.width, y: 0))
            context.addLine(to: CGPoint(x: size.width * 0.75, y: size.height))
            context.addLine(to: CGPoint(x: 0, y: size.height))
            context.closePath()
            context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            context.fillPath()
        }
        if let opaqueCapture, let grid = SwitcherSupport.alphaGrid(of: opaqueCapture) {
            expect(!SwitcherSupport.captureLooksTransformed(alphaGrid: grid),
                   "switcher keeps captures of fully opaque windows")
        } else {
            expect(false, "switcher alpha grid renders an opaque synthetic capture")
        }
        if let roundedCapture, let grid = SwitcherSupport.alphaGrid(of: roundedCapture) {
            expect(!SwitcherSupport.captureLooksTransformed(alphaGrid: grid),
                   "switcher keeps captures of windows with rounded corners")
        } else {
            expect(false, "switcher alpha grid renders a rounded synthetic capture")
        }
        if let shearedCapture, let grid = SwitcherSupport.alphaGrid(of: shearedCapture) {
            expect(SwitcherSupport.captureLooksTransformed(alphaGrid: grid),
                   "switcher rejects the small sheared snapshot Stage Manager renders for parked windows")
        } else {
            expect(false, "switcher alpha grid renders a sheared synthetic capture")
        }
        if let tightShearCapture, let grid = SwitcherSupport.alphaGrid(of: tightShearCapture) {
            expect(SwitcherSupport.captureLooksTransformed(alphaGrid: grid),
                   "switcher rejects sheared captures even when the bounding box hugs the artwork")
        } else {
            expect(false, "switcher alpha grid renders a tight sheared synthetic capture")
        }
        expect(!SwitcherSupport.captureLooksTransformed(alphaGrid: [], gridSize: 8),
               "switcher capture classifier tolerates a malformed alpha grid")

        // Pixel counts measured on a 620 by 452 point window: whole on screen,
        // hanging over the bottom edge, and hanging past the side edge.
        let probeWindow = CGSize(width: 620, height: 452)
        expect(SwitcherSupport.captureCoversWindow(imageWidth: 1240, imageHeight: 904,
                                                   windowSize: probeWindow),
               "switcher keeps a capture that covers the whole window")
        expect(!SwitcherSupport.captureCoversWindow(imageWidth: 1240, imageHeight: 144,
                                                    windowSize: probeWindow),
               "switcher rejects the band captured for a window hanging over the bottom edge")
        expect(!SwitcherSupport.captureCoversWindow(imageWidth: 120, imageHeight: 904,
                                                    windowSize: probeWindow),
               "switcher rejects the band captured for a window hanging past the side edge")
        expect(SwitcherSupport.captureCoversWindow(imageWidth: 620, imageHeight: 452,
                                                   windowSize: probeWindow),
               "switcher coverage check ignores the display scale, so a plain screen passes")
        expect(SwitcherSupport.captureCoversWindow(imageWidth: 2200, imageHeight: 424,
                                                   windowSize: CGSize(width: 1100, height: 212)),
               "switcher keeps the capture of a window that really is that wide")
        expect(SwitcherSupport.captureCoversWindow(imageWidth: 1240, imageHeight: 144,
                                                   windowSize: .zero),
               "switcher coverage check passes when the window size says nothing")
        expect(SwitcherSupport.captureCoversWindow(imageWidth: 0, imageHeight: 904,
                                                   windowSize: probeWindow),
               "switcher coverage check passes when a capture reports no pixels")

        expect(SwitcherSupport.staleCacheVictims(ids: [1, 2, 3], active: [], lastTouched: [:], limit: 3).isEmpty,
               "switcher preview cache keeps everything under the limit")
        expect(SwitcherSupport.staleCacheVictims(ids: [1, 2, 3, 4],
                                                 active: [1],
                                                 lastTouched: [2: 10, 3: 5, 4: 20],
                                                 limit: 3) == [3],
               "switcher preview cache evicts the least recently used entry beyond the limit")
        expect(SwitcherSupport.staleCacheVictims(ids: [1, 2, 3, 4],
                                                 active: [3],
                                                 lastTouched: [1: 1, 2: 2, 4: 4],
                                                 limit: 2) == [1, 2],
               "switcher preview cache never evicts entries being refreshed right now")
        expect(SwitcherSupport.cacheByteBudgetVictims(sizes: [1: 30, 2: 30],
                                                      active: [],
                                                      lastTouched: [1: 1, 2: 2],
                                                      budget: 100).isEmpty,
               "preview byte budget keeps everything while under budget")
        expect(SwitcherSupport.cacheByteBudgetVictims(sizes: [1: 60, 2: 60, 3: 60],
                                                      active: [],
                                                      lastTouched: [1: 1, 2: 2, 3: 3],
                                                      budget: 100) == [1, 2],
               "preview byte budget evicts least recently used entries until the bytes fit")
        expect(SwitcherSupport.cacheByteBudgetVictims(sizes: [1: 60, 2: 60, 3: 60],
                                                      active: [1],
                                                      lastTouched: [1: 1, 2: 2, 3: 3],
                                                      budget: 100) == [2, 3],
               "preview byte budget never evicts entries being refreshed right now")

        // Sheared alpha mask (rows shift right going down): corner detection
        // must find the parallelogram's extremes so rectification can undo it.
        let quadWidth = 120, quadHeight = 100
        var shearAlpha = [UInt8](repeating: 0, count: quadWidth * quadHeight)
        for y in 0..<quadHeight {
            let shift = y * 20 / quadHeight
            for x in shift..<(80 + shift) {
                shearAlpha[y * quadWidth + x] = 255
            }
        }
        if let corners = SwitcherSupport.opaqueQuadCorners(alpha: shearAlpha,
                                                           width: quadWidth,
                                                           height: quadHeight) {
            expect(corners.topLeft == CGPoint(x: 0, y: 0)
                   && corners.topRight == CGPoint(x: 79, y: 0)
                   && corners.bottomRight == CGPoint(x: 98, y: 99)
                   && corners.bottomLeft == CGPoint(x: 19, y: 99),
                   "switcher quad corners land on the sheared mask extremes")
        } else {
            expect(false, "switcher quad corners resolve for a sheared mask")
        }
        expect(SwitcherSupport.opaqueQuadCorners(alpha: [UInt8](repeating: 0, count: quadWidth * quadHeight),
                                                 width: quadWidth,
                                                 height: quadHeight) == nil,
               "switcher quad corners reject an empty capture")
    }
}
