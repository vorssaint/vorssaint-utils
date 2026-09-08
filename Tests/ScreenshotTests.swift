// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Darwin
import Foundation

enum ScreenshotTests {
    static func run(expect: (Bool, String) -> Void) {
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            expect(!(abs(actual - expected) > tol), "\(label): got \(actual), expected \(expected)")
        }

        // MARK: Screenshot tool

        let ownScreenshotWindows: Set<CGWindowID> = [11, 12, 13]
        let protectedScreenshotWindows: Set<CGWindowID> = [12, 99]
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotHideVorssaintWindows]
                as? Bool == true,
               "screenshots hide Vorssaint windows by default")
        expect(SettingsBackupSupport.exportKeys().contains(
            DefaultsKey.screenshotHideVorssaintWindows),
               "the screenshot window visibility preference travels in backups")
        expect(ScreenshotCapturePolicy.excludedWindowIDs(
            hideVorssaintWindows: true,
            ownWindowIDs: ownScreenshotWindows,
            protectedWindowIDs: protectedScreenshotWindows
        ) == ownScreenshotWindows,
        "screenshot hiding Vorssaint excludes every own window")
        expect(ScreenshotCapturePolicy.excludedWindowIDs(
            hideVorssaintWindows: false,
            ownWindowIDs: ownScreenshotWindows,
            protectedWindowIDs: protectedScreenshotWindows
        ) == [12],
        "screenshot keeps protected windows excluded while Vorssaint is visible")
        expect(ScreenshotCapturePolicy.canPickWindow(
            7,
            isOwnWindow: false,
            hideVorssaintWindows: true,
            protectedWindowIDs: protectedScreenshotWindows
        ), "screenshot can always pick an ordinary external window")
        expect(!ScreenshotCapturePolicy.canPickWindow(
            11,
            isOwnWindow: true,
            hideVorssaintWindows: true,
            protectedWindowIDs: protectedScreenshotWindows
        ), "screenshot cannot pick a Vorssaint window while hiding them")
        expect(ScreenshotCapturePolicy.canPickWindow(
            11,
            isOwnWindow: true,
            hideVorssaintWindows: false,
            protectedWindowIDs: protectedScreenshotWindows
        ), "screenshot can pick an ordinary Vorssaint window when visible")
        expect(!ScreenshotCapturePolicy.canPickWindow(
            12,
            isOwnWindow: true,
            hideVorssaintWindows: false,
            protectedWindowIDs: protectedScreenshotWindows
        ), "screenshot cannot pick its own protected capture UI")

        // A sheet or dialog the app stacked on the clicked window is a window
        // of its own, so a single-window capture leaves it out of a shot it is
        // plainly part of (issue #1098). Same app, in front, and lying wholly
        // inside the clicked window is the shape that describes one; anything
        // reaching past its edge is left alone, because drawing a window the
        // person did not choose is worse than leaving a dialog out.
        typealias CaptureWindow = ScreenshotCapturePolicy.CaptureWindow
        let capturedWindow = CaptureWindow(
            id: 1, ownerPID: 500, frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let sheet = CaptureWindow(
            id: 2, ownerPID: 500, frame: CGRect(x: 300, y: 100, width: 400, height: 300))
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [sheet, capturedWindow])
            == ScreenshotCapturePolicy.AttachedCapturePlan(
                windowIDs: [1, 2], bounds: capturedWindow.frame),
               "a sheet on the clicked window joins its capture, the window drawn first")
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [capturedWindow, sheet]) == nil,
               "a window behind the clicked one is not stacked on it")
        let windowOfAnotherApp = CaptureWindow(
            id: 3, ownerPID: 900, frame: CGRect(x: 300, y: 100, width: 400, height: 300))
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [windowOfAnotherApp, capturedWindow]) == nil,
               "another application's window over the clicked one stays out of the shot")
        // The case that decides the rule: a compose or second document window
        // of the same app, in front and overlapping, but reaching past the
        // edge. It is not what was asked for, so the ordinary capture answers.
        let composeWindow = CaptureWindow(
            id: 4, ownerPID: 500, frame: CGRect(x: 700, y: 300, width: 500, height: 400))
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [composeWindow, capturedWindow]) == nil,
               "a same-app window reaching past the clicked window is not drawn into its shot")
        let detachedWindow = CaptureWindow(
            id: 5, ownerPID: 500, frame: CGRect(x: 2_000, y: 100, width: 200, height: 200))
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [detachedWindow, capturedWindow]) == nil,
               "a window of the same app that does not touch the clicked one is not attached")
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [capturedWindow]) == nil,
               "a window with nothing stacked on it keeps the ordinary single-window capture")
        let captureEngineSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/ScreenshotCaptureEngine.swift",
            encoding: .utf8)) ?? ""
        // A sheet is often exactly as wide as the window it drops out of, so
        // the rule has to take one that matches an edge rather than shrink from
        // it.
        let fullWidthSheet = CaptureWindow(
            id: 6, ownerPID: 500, frame: CGRect(x: 100, y: 100, width: 800, height: 200))
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [fullWidthSheet, capturedWindow])?.windowIDs
            == [1, 6],
               "a sheet the full width of its window still joins the capture")
        // Two stacked windows are drawn in the order they are shown.
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow,
            frontToBack: [sheet, fullWidthSheet, capturedWindow])?.windowIDs == [1, 6, 2],
               "what is stacked on the window is drawn back to front")
        // A target the list does not hold cannot have anything in front of it.
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [sheet]) == nil,
               "a window missing from the list does not treat everything as stacked on it")
        expect(captureEngineSource.contains("$0.frame.intersects(plan.bounds)")
                && captureEngineSource.contains("hits.count == 1")
                && !captureEngineSource.contains(".contains(plan.bounds)"),
               "a window straddling two displays falls back to the single-window capture instead of a one-display slice")

        let geometricAttachment = ScreenshotCapturePolicy.AttachedCapturePlan(
            windowIDs: [1, 6, 2], bounds: capturedWindow.frame)
        expect(ScreenshotCapturePolicy.confirmedAttachment(
            geometricAttachment, confirmedIDs: nil) == geometricAttachment,
               "missing Accessibility confirmation leaves the geometric attachment unchanged")
        expect(ScreenshotCapturePolicy.confirmedAttachment(
            geometricAttachment, confirmedIDs: [2])
            == ScreenshotCapturePolicy.AttachedCapturePlan(
                windowIDs: [1, 2], bounds: capturedWindow.frame),
               "Accessibility confirmation keeps its matching attachment in capture order")
        expect(ScreenshotCapturePolicy.confirmedAttachment(
            geometricAttachment, confirmedIDs: []) == nil,
               "Accessibility confirmation with no matching attachment drops the composite plan")

        // The engine is outside the pure-helper test binary. Pin the permission
        // gate before its AX call so window capture never starts an
        // Accessibility round trip merely because geometry found a candidate.
        let screenshotCaptureEngineSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/ScreenshotCaptureEngine.swift",
            encoding: .utf8)) ?? ""
        let captureWindowBody = (screenshotCaptureEngineSource
            .components(separatedBy: "static func captureWindow(").last ?? "")
            .components(separatedBy: "\n    /// On-screen windows").first ?? ""
        let accessibilityGate = captureWindowBody.range(of: "if Permissions.shared.accessibility {")
        let attachmentConfirmation = captureWindowBody.range(
            of: "accessibilityAttachedWindowIDs(")
        expect(accessibilityGate != nil && attachmentConfirmation != nil
               && accessibilityGate!.lowerBound < attachmentConfirmation!.lowerBound,
               "window capture checks its existing Accessibility grant before AX confirmation")
        let accessibilityAttachedWindowIDsBody = (screenshotCaptureEngineSource
            .components(separatedBy: "private static func accessibilityAttachedWindowIDs(").last ?? "")
            .components(separatedBy: "\n    private static func accessibilityElements(").first ?? ""
        let accessibilityAttachedWindowIDsCode = accessibilityAttachedWindowIDsBody
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let unresolvedCandidatePasses = accessibilityAttachedWindowIDsCode.range(of: "guard let element = elementsByID[candidateID] else {\n                confirmed.insert(candidateID)\n                continue\n            }")
        let standardWindowFails = accessibilityAttachedWindowIDsCode.range(of: "if let subrole = accessibilityString(element, kAXSubroleAttribute as CFString),\n               subrole == (kAXStandardWindowSubrole as String) || subrole == \"AXFullScreenWindow\" {\n                continue\n            }\n            confirmed.insert(candidateID)")
        let childrenPassIsAbsent = !accessibilityAttachedWindowIDsCode.contains("kAXChildrenAttribute")
        expect(unresolvedCandidatePasses != nil && standardWindowFails != nil && childrenPassIsAbsent,
               "AX keeps unresolved candidates and excludes only identified standard windows")

        expect(ScreenshotSupport.sanitizedDelay(5) == 5
                && ScreenshotSupport.sanitizedDelay(7) == 0
                && ScreenshotSupport.sanitizedDelay(-3) == 0,
               "capture delay only accepts the offered steps")
        expect(ScreenshotSupport.scrollingCaptureMaximumDuration == 120
                && ScreenshotSupport.scrollingCaptureMaximumFrames == 512
                && ScreenshotSupport.scrollingCaptureMaximumRetainedPixels == 60_000_000
                && ScreenshotSupport.scrollingCaptureMaximumPixels == 60_000_000,
               "manual scrolling screenshots have explicit loop and memory safeguards")

        func scrollingSample(width: Int = 16,
                             height: Int = 120,
                             offset: Int) -> ScreenshotSupport.ScrollingSample {
            var pixels = [UInt8](repeating: 0, count: width * height)
            for row in 0..<height {
                let contentRow = row + offset
                for column in 0..<width {
                    pixels[row * width + column] = UInt8(
                        (contentRow * 17 + column * 31 + (contentRow / 7) * 13) % 251)
                }
            }
            return ScreenshotSupport.ScrollingSample(width: width,
                                                     height: height,
                                                     pixels: pixels)
        }
        let firstScrollSample = scrollingSample(offset: 0)
        let nextScrollSample = scrollingSample(offset: 76)
        let forwardScrollTransition = ScreenshotSupport.scrollingTransition(
            previous: firstScrollSample,
            current: nextScrollSample)
        expect(forwardScrollTransition
                == .advanced(overlap: 44,
                             direction: .forward,
                             contentColumns: 0..<16),
               "scrolling screenshots find the exact shared rows deterministically: \(forwardScrollTransition)")
        let backwardScrollTransition = ScreenshotSupport.scrollingTransition(
            previous: nextScrollSample,
            current: firstScrollSample)
        expect(backwardScrollTransition
                == .advanced(overlap: 44,
                             direction: .backward,
                             contentColumns: 0..<16),
               "scrolling screenshots identify backward movement without duplicating it: \(backwardScrollTransition)")
        expect(ScreenshotSupport.scrollingTransition(previous: nextScrollSample,
                                                     current: nextScrollSample) == .end,
               "an unchanged capture marks the real end of scrolling")
        expect(ScreenshotSupport.scrollingSamplesAreStable(nextScrollSample,
                                                           nextScrollSample),
               "settling recognizes two unchanged scrolling frames")
        let shortFinalScrollSample = scrollingSample(offset: 8)
        expect(ScreenshotSupport.scrollingTransition(previous: firstScrollSample,
                                                     current: shortFinalScrollSample)
                == .advanced(overlap: 112,
                             direction: .forward,
                             contentColumns: 0..<16),
               "a short final scroll is kept instead of failing the whole capture")
        func sampleWithFixedEdges(offset: Int) -> ScreenshotSupport.ScrollingSample {
            let sample = scrollingSample(offset: offset)
            var pixels = sample.pixels
            for row in 0..<12 {
                for column in 0..<sample.width {
                    pixels[row * sample.width + column] = UInt8(row * 5 + column)
                    let bottomRow = sample.height - row - 1
                    pixels[bottomRow * sample.width + column] = UInt8(row * 3 + column)
                }
            }
            return ScreenshotSupport.ScrollingSample(width: sample.width,
                                                     height: sample.height,
                                                     pixels: pixels)
        }
        expect(ScreenshotSupport.scrollingTransition(
            previous: sampleWithFixedEdges(offset: 0),
            current: sampleWithFixedEdges(offset: 50))
                == .advanced(overlap: 70,
                             direction: .forward,
                             contentColumns: 0..<16),
               "fixed page edges do not hide the shared scrolling content")
        func sampleWithFixedBottom(offset: Int,
                                   fixedBottomRows: Int = 18)
            -> ScreenshotSupport.ScrollingSample {
            let sample = scrollingSample(offset: offset)
            var pixels = sample.pixels
            for row in (sample.height - fixedBottomRows)..<sample.height {
                for column in 0..<sample.width {
                    pixels[row * sample.width + column] = UInt8(
                        (row * 29 + column * 11 + 41) % 251)
                }
            }
            return ScreenshotSupport.ScrollingSample(width: sample.width,
                                                     height: sample.height,
                                                     pixels: pixels)
        }
        let fixedBottomStart = sampleWithFixedBottom(offset: 0)
        let fixedBottomNext = sampleWithFixedBottom(offset: 42)
        expect(ScreenshotSupport.scrollingTransition(previous: fixedBottomStart,
                                                     current: fixedBottomNext)
                == .advanced(overlap: 78,
                             direction: .forward,
                             contentColumns: 0..<16),
               "a fixed footer does not hide the moving page overlap")
        expect(ScreenshotSupport.scrollingFixedBottomRows(
            previous: fixedBottomStart,
            current: fixedBottomNext,
            overlap: 78,
            contentColumns: 0..<16) == 18,
               "scrolling capture identifies a fixed footer at the bottom edge")
        expect(ScreenshotSupport.scrollingFixedBottomRows(
            previous: firstScrollSample,
            current: scrollingSample(offset: 42),
            overlap: 78,
            contentColumns: 0..<16) == 0,
               "ordinary moving content is never mistaken for a fixed footer")
        expect(ScreenshotSupport.scrollingNewContentRows(
            imageHeight: 120,
            overlap: 78,
            fixedBottomRows: 18) == 60..<102,
               "new scrolling pixels move above the fixed footer instead of copying it")
        expect(ScreenshotSupport.scrollingNewContentRows(
            imageHeight: 120,
            overlap: 78,
            fixedBottomRows: 0) == 78..<120,
               "captures without a fixed footer keep the original crop geometry")
        var scrollingStressPassed = true
        var scrollingStressFailure: ScreenshotSupport.ScrollingTransition?
        for iteration in 0..<250 {
            let offset = [8, 76][iteration % 2]
            let transition = ScreenshotSupport.scrollingTransition(
                previous: firstScrollSample,
                current: scrollingSample(offset: offset))
            let passed = transition == .advanced(overlap: 120 - offset,
                                                 direction: .forward,
                                                 contentColumns: 0..<16)
            if !passed, scrollingStressFailure == nil { scrollingStressFailure = transition }
            scrollingStressPassed = scrollingStressPassed && passed
        }
        expect(scrollingStressPassed,
               "scroll matching stays deterministic through repeated short and long advances: \(String(describing: scrollingStressFailure))")
        let retinaScrollStart = scrollingSample(width: 32, height: 900, offset: 0)
        let retinaScrollNext = scrollingSample(width: 32, height: 900, offset: 558)
        expect(ScreenshotSupport.scrollingTransition(previous: retinaScrollStart,
                                                     current: retinaScrollNext)
                == .advanced(overlap: 342,
                             direction: .forward,
                             contentColumns: 0..<32),
               "scroll matching handles a full-width sample at a realistic Retina selection height")
        func scrollingSampleWithFixedColumns(offset: Int,
                                             changesAfterScroll: Bool = false)
            -> ScreenshotSupport.ScrollingSample {
            let width = 24
            let height = 120
            var pixels = [UInt8](repeating: 0, count: width * height)
            for row in 0..<height {
                for column in 0..<width {
                    if column < 6 || column >= 18 {
                        pixels[row * width + column] = UInt8(
                            (row * 19 + column * 23 + (row / 5) * 11) % 251)
                    } else if changesAfterScroll && (30..<46).contains(row) {
                        pixels[row * width + column] = UInt8(
                            (row * 61 + column * 7 + 37) % 251)
                    } else {
                        let contentRow = row + offset
                        pixels[row * width + column] = UInt8(
                            (contentRow * 17 + column * 31 + (contentRow / 7) * 13) % 251)
                    }
                }
            }
            return ScreenshotSupport.ScrollingSample(width: width,
                                                     height: height,
                                                     pixels: pixels)
        }
        let fixedColumnsStart = scrollingSampleWithFixedColumns(offset: 0)
        let fixedColumnsNext = scrollingSampleWithFixedColumns(offset: 42)
        expect(ScreenshotSupport.scrollingTransition(previous: fixedColumnsStart,
                                                     current: fixedColumnsNext)
                == .advanced(overlap: 78,
                             direction: .forward,
                             contentColumns: 6..<18),
               "scroll matching isolates moving content from fixed side columns")
        let changedColumnsNext = scrollingSampleWithFixedColumns(
            offset: 42,
            changesAfterScroll: true)
        let changedColumnsTransition = ScreenshotSupport.scrollingTransition(
            previous: fixedColumnsStart,
            current: changedColumnsNext)
        expect(changedColumnsTransition
                == .advanced(overlap: 78,
                             direction: .forward,
                             contentColumns: 6..<18),
               "scroll matching survives a changed block inside moving content: \(changedColumnsTransition)")
        expect(ScreenshotSupport.scrollingPixelRange(sampleColumns: 6..<18,
                                                     sampleWidth: 24,
                                                     imageWidth: 1_920) == 480..<1_440,
               "the moving sample columns map back to the exact captured pixels")
        var unmatchedScrollPixels = [UInt8](repeating: 0, count: 16 * 120)
        for index in unmatchedScrollPixels.indices {
            unmatchedScrollPixels[index] = UInt8((index * 47 + index / 11) % 253)
        }
        let unmatchedScrollSample = ScreenshotSupport.ScrollingSample(
            width: 16, height: 120, pixels: unmatchedScrollPixels)
        expect(ScreenshotSupport.scrollingTransition(previous: firstScrollSample,
                                                     current: unmatchedScrollSample) == .unmatched,
               "ambiguous content fails instead of inventing a seam")
        expectClose(Double(ScreenshotSupport.captureScale(fromDPI: 144) ?? 0), 2,
                    "the cached screenshot restores its Retina scale from PNG metadata")
        expect(ScreenshotSupport.captureScale(fromDPI: nil) == nil
                && ScreenshotSupport.captureScale(fromDPI: 0) == nil
                && ScreenshotSupport.captureScale(fromDPI: .infinity) == nil,
               "missing or broken PNG scale metadata never opens a misleading capture")

        let dragRect = ScreenshotSupport.selectionRect(from: CGPoint(x: 100, y: 80),
                                                       to: CGPoint(x: 40, y: 200))
        expect(dragRect == CGRect(x: 40, y: 80, width: 60, height: 120),
               "a drag in any direction normalizes to a positive rect")
        let squareRect = ScreenshotSupport.selectionRect(from: CGPoint(x: 10, y: 10),
                                                         to: CGPoint(x: 40, y: 90),
                                                         square: true)
        expect(squareRect.width == squareRect.height && squareRect.width == 80,
               "shift constrains the selection to a square")
        let centered = ScreenshotSupport.selectionRect(from: CGPoint(x: 50, y: 50),
                                                       to: CGPoint(x: 70, y: 60),
                                                       fromCenter: true)
        expect(centered == CGRect(x: 30, y: 40, width: 40, height: 20),
               "option grows the selection from the center")
        let cropBounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let cropDraft = CGRect(x: 120, y: 90, width: 400, height: 300)
        expect(ScreenshotSupport.startsNewCropSelection(
                    at: CGPoint(x: 300, y: 250), draft: cropBounds, within: cropBounds),
               "dragging inside the initial full-image crop starts a new selection")
        expect(!ScreenshotSupport.startsNewCropSelection(
                    at: CGPoint(x: 300, y: 250), draft: cropDraft, within: cropBounds),
               "dragging inside an adjusted crop keeps moving it")
        expect(ScreenshotSupport.startsNewCropSelection(
                    at: CGPoint(x: 700, y: 500), draft: cropDraft, within: cropBounds),
               "dragging elsewhere in the image replaces an adjusted crop")
        expect(!ScreenshotSupport.startsNewCropSelection(
                    at: CGPoint(x: 900, y: 700), draft: cropDraft, within: cropBounds),
               "a drag outside the image cannot start a crop")
        expect(ScreenshotSupport.isClick(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 7, y: 8))
                && !ScreenshotSupport.isClick(from: .zero, to: CGPoint(x: 12, y: 0)),
               "a tiny drag is a click, a real drag is not")

        // The crop chrome, the loupe cross and the image applyCrop produces are
        // three drawings of one edge. They agree only while pixelSnappedCropRect
        // is the single thing deciding where that edge is.
        let snapBounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let looseDraft = CGRect(x: 100.4, y: 60.4, width: 100, height: 100)
        let snappedDraft = ScreenshotSupport.pixelSnappedCropRect(looseDraft, within: snapBounds)
        expect(snappedDraft == CGRect(x: 100, y: 60, width: 100, height: 100),
               "a crop draft rounds each edge to the nearest pixel boundary")
        expect(snappedDraft.maxX == 200,
               "a crop draft does not grow outward the way CGRect.integral would")
        expect(ScreenshotSupport.pixelSnappedCropRect(snappedDraft, within: snapBounds)
                == snappedDraft,
               "snapping a crop draft that already sits on pixels changes nothing")
        expect(ScreenshotSupport.pixelSnappedCropRect(
                    CGRect(x: 100.4, y: 60.4, width: 100.2, height: 100.2), within: snapBounds)
                == CGRect(x: 100, y: 60, width: 101, height: 101),
               "a crop edge past the halfway mark rounds to the next boundary")
        let movedDraft = ScreenshotSupport.pixelSnappedCropRect(
            ScreenshotSupport.movedRect(snappedDraft,
                                        by: CGPoint(x: 12.6, y: -4.3),
                                        within: snapBounds),
            within: snapBounds)
        expect(movedDraft.size == snappedDraft.size,
               "moving a crop draft never changes its size")
        expect(ScreenshotSupport.pixelSnappedCropRect(
                    CGRect(x: -40, y: -30, width: 100, height: 100), within: snapBounds)
                == CGRect(x: 0, y: 0, width: 60, height: 70),
               "a snapped crop draft stays inside the image")

        // An even sample side centres the edge only once the edge is whole,
        // which is what the snapping above guarantees.
        let snapImageSize = CGSize(width: 800, height: 600)
        let snappedEdge = ScreenshotSupport.Handle.left.position(in: snappedDraft)
        let snappedSample = ScreenshotSupport.cropLoupeSampleRect(around: snappedEdge,
                                                                  imageSize: snapImageSize,
                                                                  sideLength: 14,
                                                                  centredOnPixel: false)
        expect(snappedSample.midX == snappedEdge.x && snappedSample.midY == snappedEdge.y,
               "the crop loupe centres on the edge it marks once the draft sits on pixels")
        let looseEdge = ScreenshotSupport.Handle.left.position(in: looseDraft)
        let looseSample = ScreenshotSupport.cropLoupeSampleRect(around: looseEdge,
                                                                imageSize: snapImageSize,
                                                                sideLength: 14,
                                                                centredOnPixel: false)
        expect(looseSample.midX != looseEdge.x,
               "an even sample side alone does not centre a fractional crop edge")

        var patternParts = DateComponents()
        patternParts.year = 2026
        patternParts.month = 7
        patternParts.day = 24
        patternParts.hour = 15
        patternParts.minute = 4
        patternParts.second = 9
        if let patternDate = Calendar(identifier: .gregorian).date(from: patternParts) {
            expect(ScreenshotSupport.expandSaveSubfolder("%y-%mo", date: patternDate) == "26-07",
                   "short date tokens expand zero padded")
            expect(ScreenshotSupport.expandSaveSubfolder("%year/%month", date: patternDate)
                   == "2026/July",
                   "long date tokens expand before their short prefixes and nest with slashes")
            expect(ScreenshotSupport.expandSaveSubfolder("", date: patternDate) == "",
                   "an empty subfolder pattern means no subfolder")
            expect(ScreenshotSupport.expandSaveSubfolder("../up//./%y", date: patternDate)
                   == "up/26",
                   "dot, dot-dot and empty components never escape the base folder")
            expect(ScreenshotSupport.expandFileNamePattern("Shot %d at %h.%mi.%s",
                                                           date: patternDate, number: 0)
                   == "Shot 24 at 15.04.09",
                   "file name patterns expand the day and time tokens")
            expect(ScreenshotSupport.expandFileNamePattern("Shot-%#", date: patternDate, number: 7)
                   == "Shot-7",
                   "a single number token renders the sequence unpadded")
            expect(ScreenshotSupport.expandFileNamePattern("%###-%y", date: patternDate, number: 7)
                   == "007-26",
                   "a longer number token zero pads to its length")
            expect(ScreenshotSupport.fileNamePatternUsesNumber("Shot-%#")
                    && !ScreenshotSupport.fileNamePatternUsesNumber("Shot-%y"),
                   "only patterns with the number token consume the sequence")
            expect(ScreenshotSupport.expandFileNamePattern("a/b %h:%mi", date: patternDate, number: 0)
                   == "a-b 15-04",
                   "slashes and colons in a file name pattern become dashes")
        } else {
            expect(false, "gregorian calendar produced the fixed pattern date")
        }

        let cornerFrame = ScreenshotSupport.quickPreviewFrame(
            size: CGSize(width: 310, height: 210),
            anchor: .zero,
            pointer: .zero,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            position: .bottomRight)
        expect(cornerFrame == CGRect(x: 1114, y: 16, width: 310, height: 210),
               "the after-capture confirmation sits inset in the bottom-right corner")
        let previewSize = CGSize(width: 310, height: 210)
        let previewScreen = CGRect(x: -1920, y: 50, width: 1440, height: 900)
        func configuredPreviewFrame(_ position: ScreenshotSupport.QuickPreviewPosition) -> CGRect {
            ScreenshotSupport.quickPreviewFrame(
                size: previewSize,
                anchor: .zero,
                pointer: .zero,
                visibleFrame: previewScreen,
                position: position)
        }
        expect(configuredPreviewFrame(.topLeft)
                == CGRect(x: -1904, y: 724, width: 310, height: 210)
                && configuredPreviewFrame(.topRight)
                == CGRect(x: -806, y: 724, width: 310, height: 210)
                && configuredPreviewFrame(.bottomLeft)
                == CGRect(x: -1904, y: 66, width: 310, height: 210)
                && configuredPreviewFrame(.bottomRight)
                == CGRect(x: -806, y: 66, width: 310, height: 210),
               "every configured preview corner respects the display origin and inset")
        let previewScreens = [
            (frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
             visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055)),
            (frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
             visibleFrame: CGRect(x: 0, y: 40, width: 1440, height: 860)),
            (frame: CGRect(x: 1440, y: 300, width: 1280, height: 1024),
             visibleFrame: CGRect(x: 1440, y: 300, width: 1280, height: 999)),
        ]
        expect(ScreenshotSupport.quickPreviewVisibleFrame(
            anchor: CGRect(x: -900, y: 200, width: 500, height: 400),
            pointer: CGPoint(x: -500, y: 300),
            screens: previewScreens,
            fallback: .zero) == previewScreens[0].visibleFrame,
               "a capture uses the visible frame of its display in a three-display layout")
        expect(ScreenshotSupport.quickPreviewVisibleFrame(
            anchor: CGRect(x: 1300, y: 500, width: 500, height: 500),
            pointer: CGPoint(x: 1700, y: 650),
            screens: previewScreens,
            fallback: .zero) == previewScreens[2].visibleFrame,
               "a capture crossing displays uses the screen containing most of it")
        expect(ScreenshotSupport.quickPreviewVisibleFrame(
            anchor: CGRect(x: 5000, y: 5000, width: 400, height: 300),
            pointer: CGPoint(x: 700, y: 500),
            screens: previewScreens,
            fallback: .zero) == previewScreens[1].visibleFrame,
               "a disconnected capture display falls back to the current pointer display")
        expect(ScreenshotSupport.QuickPreviewPosition.allCases.map(\.rawValue)
                == ["", "topLeft", "topRight", "bottomLeft", "bottomRight"]
                && ScreenshotSupport.QuickPreviewPosition(rawValue: "bogus") == nil,
               "preview positions keep stable storage values and reject unknown values")
        expect(ScreenshotDefaultAction(rawValue: "") == ScreenshotDefaultAction.none
                && ScreenshotDefaultAction(rawValue: "saveAndCopy") == .saveAndCopy
                && ScreenshotDefaultAction(rawValue: "bogus") == nil,
               "after-capture actions decode from their stored raw values")

        // A gesture that ends with more than one release, like a drag made
        // with three fingers, delivers events after the capture is over.
        expect(ScreenshotSupport.selectionAcceptsPointerInput(sessionIsOver: false,
                                                              capturePending: false),
               "a live selection answers the pointer")
        expect(!ScreenshotSupport.selectionAcceptsPointerInput(sessionIsOver: true,
                                                               capturePending: false),
               "a session that is over ignores the tail of a gesture")
        expect(!ScreenshotSupport.selectionAcceptsPointerInput(sessionIsOver: false,
                                                               capturePending: true),
               "a capture already on its way ignores further pointer input")
        expect(!ScreenshotSupport.selectionAcceptsPointerInput(sessionIsOver: true,
                                                               capturePending: true),
               "both at once still ignores the pointer")
        let captureMenuSuite = "com.vorssaint.tests.capture-menu.\(UUID().uuidString)"
        let captureMenuDefaults = UserDefaults(suiteName: captureMenuSuite)!
        defer { captureMenuDefaults.removePersistentDomain(forName: captureMenuSuite) }
        for tool in ScreenCaptureTool.allCases {
            expect(tool.showsCaptureMenu(fromShortcut: true, defaults: captureMenuDefaults),
                   "an existing install keeps the capture menu for \(tool)")
            expect(Defaults.registeredDefaults[tool.showCaptureMenuOnShortcutKey] as? Bool == true
                    && SettingsBackupSupport.exportKeys().contains(tool.showCaptureMenuOnShortcutKey),
                   "capture menu preferences default on and travel with settings backups")
        }
        captureMenuDefaults.register(defaults: Defaults.registeredDefaults)
        for hiddenTool in ScreenCaptureTool.allCases {
            captureMenuDefaults.set(false, forKey: hiddenTool.showCaptureMenuOnShortcutKey)
            let reopenedDefaults = UserDefaults(suiteName: captureMenuSuite)!
            for tool in ScreenCaptureTool.allCases {
                expect(tool.showsCaptureMenu(fromShortcut: true, defaults: reopenedDefaults)
                        == (tool != hiddenTool),
                       "hiding the menu for \(hiddenTool) persists without changing \(tool)'s preference")
                expect(tool.showsCaptureMenu(fromShortcut: false, defaults: reopenedDefaults),
                       "buttons still open the capture menu even when a shortcut hides it")
            }
            captureMenuDefaults.set(true, forKey: hiddenTool.showCaptureMenuOnShortcutKey)
            expect(hiddenTool.showsCaptureMenu(fromShortcut: true, defaults: captureMenuDefaults),
                   "turning the setting back on restores the shortcut menu")
        }
        let recordingOnly: Set<AppFeature> = [.screenRecorder]
        expect(ScreenCaptureTool.available(isAvailable: recordingOnly.contains) == [.recording],
               "the capture chooser hides every uninstalled mode")
        let captureFeatures: Set<AppFeature> = [.screenshot, .screenRecorder,
                                                .screenOCR, .colorPicker]
        expect(ScreenCaptureTool.available(isAvailable: captureFeatures.contains)
                == [.screenshot, .recording, .text, .color],
               "the capture chooser keeps a stable order for every installed mode")
        let captureSettingsSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/ScreenCaptureSettings.swift",
            encoding: .utf8)) ?? ""
        expect(captureSettingsSource.contains("selectedTool")
                && captureSettingsSource.contains(".pickerStyle(.segmented)")
                && captureSettingsSource.contains("ToolShortcutRows(tool: currentTool")
                && captureSettingsSource.contains("RecentCapturesShortcutRows()"),
               "the capture page keeps tool and shared-history shortcuts in the top section")
        let recentCaptureServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/RecentCaptureService.swift",
            encoding: .utf8)) ?? ""
        let featureRuntimeSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/App/FeatureRuntime.swift",
            encoding: .utf8)) ?? ""
        expect(recentCaptureServiceSource.contains("QuickToolHotkey(id: 21)")
                && recentCaptureServiceSource.contains(
                    "hotkey.onPress = { [weak self] in self?.showHistoryWindow() }")
                && featureRuntimeSource.components(separatedBy:
                    "RecentCaptureService.shared.syncWithPreferences()").count == 3,
               "the history shortcut opens its window and follows both capture producers")
        expect(!ScreenshotSupport.captureAvailabilityChanged(
                    activeTools: [.screenshot, .recording],
                    availableTools: [.screenshot, .recording])
                && ScreenshotSupport.captureAvailabilityChanged(
                    activeTools: [.screenshot, .recording],
                    availableTools: [.recording])
                && ScreenshotSupport.captureAvailabilityChanged(
                    activeTools: [.screenshot],
                    availableTools: [.screenshot, .text]),
               "capture countdowns and selectors end whenever installed modes change")
        expect(ScreenshotSupport.captureRouteIsAuthorized(
                    selected: .screenshot,
                    isAvailable: { $0 == .screenshot })
                && !ScreenshotSupport.captureRouteIsAuthorized(
                    selected: .screenshot,
                    isAvailable: { _ in false }),
               "a capture result is routed only while its selected feature remains installed")
        expect(ScreenCaptureTool.allCases.map(\.shortcutKey) == ["1", "2", "3", "4"]
                && ScreenCaptureTool.matchingShortcut("1") == .screenshot
                && ScreenCaptureTool.matchingShortcut("2") == .recording
                && ScreenCaptureTool.matchingShortcut("3") == .text
                && ScreenCaptureTool.matchingShortcut("4") == .color
                && ScreenCaptureTool.matchingShortcut("5") == nil,
               "number keys select the same capture mode shown in the chooser")
        let liveScreenshotPolicy = ScreenshotSupport.unifiedCapturePolicy(
            for: .screenshot,
            screenshotFreeze: false,
            screenshotIncludePointer: true,
            screenshotHideVorssaintWindows: true)
        let recorderPolicy = ScreenshotSupport.unifiedCapturePolicy(
            for: .recording,
            screenshotFreeze: false,
            screenshotIncludePointer: true,
            screenshotHideVorssaintWindows: true)
        let textPolicy = ScreenshotSupport.unifiedCapturePolicy(
            for: .text,
            screenshotFreeze: false,
            screenshotIncludePointer: true,
            screenshotHideVorssaintWindows: true)
        expect(liveScreenshotPolicy == .init(freeze: false, includePointer: true,
                                             hideVorssaintWindows: true,
                                             usesGeometry: false)
                && recorderPolicy == .init(freeze: true, includePointer: false,
                                           hideVorssaintWindows: false,
                                           usesGeometry: true)
                && textPolicy == .init(freeze: true, includePointer: false,
                                       hideVorssaintWindows: true,
                                       usesGeometry: false),
               "switching capture mode rebuilds the frozen frame, pointer and window policy")
        let colorPolicy = ScreenshotSupport.unifiedCapturePolicy(
            for: .color,
            screenshotFreeze: false,
            screenshotIncludePointer: true,
            screenshotHideVorssaintWindows: true)
        expect(textPolicy.sharesSource(with: colorPolicy)
                && !textPolicy.sharesSource(with: recorderPolicy)
                && !textPolicy.sharesSource(with: liveScreenshotPolicy),
               "only freeze, pointer and window policy decide whether a mode needs its own photograph")
        expect(ScreenshotSupport.captureGuideIsVisible(pointerOnDisplay: true,
                                                       selectionInProgress: false,
                                                       capturePending: false)
                && !ScreenshotSupport.captureGuideIsVisible(pointerOnDisplay: true,
                                                            selectionInProgress: true,
                                                            capturePending: false)
                && !ScreenshotSupport.captureGuideIsVisible(pointerOnDisplay: true,
                                                            selectionInProgress: false,
                                                            capturePending: true)
                && !ScreenshotSupport.captureGuideIsVisible(pointerOnDisplay: false,
                                                            selectionInProgress: false,
                                                            capturePending: false),
               "the capture chooser disappears for the whole drag and while capture is pending")
        let captureSelectionSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift",
            encoding: .utf8)) ?? ""
        expect(captureSelectionSource.contains(
            "override func mouseExited(with event: NSEvent) {\n        refreshPointerState()\n        refreshGuideVisibility()"),
               "system chrome cannot hide the capture chooser while the pointer remains on its display")
        expect(captureSelectionSource.contains(
            "screenCaptureOptions?.showsCaptureMenu == false ? 82 : 146")
                && captureSelectionSource.contains(
                    ".opacity(options.selectedTool == .recording ? 1 : 0)"),
               "capture modes reserve the recording controls' height so the chooser never jumps")
        expect(captureSelectionSource.contains("screenCaptureToolDidChange()")
                && captureSelectionSource.contains("!nextPolicy.sharesSource(with: capturePolicy)")
                && captureSelectionSource.contains("adoptCapturePolicy(nextPolicy)")
                && captureSelectionSource.contains("panel.update(frozenImage:")
                && captureSelectionSource.contains("screenCaptureOptions?.onSelectionChange ="),
               "a capture mode that needs other pixels gets them behind the panels, which stay on screen")
        expect(captureSelectionSource.contains("private var pointerIsInside = false")
                && !captureSelectionSource.contains("|| bounds.contains(hoverPoint)"),
               "the capture loupe draws on only the display that owns the current pointer")
        let captureServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/ScreenCaptureService.swift",
            encoding: .utf8)) ?? ""
        expect(!captureServiceSource.contains("replaceSelection"),
               "the capture service does not cancel and recreate selection controllers when changing modes")
        // The preview appears unasked for, so presenting it must not take the
        // keyboard away from whatever the person is typing into. Its shortcuts
        // read a local monitor, which is delivered nothing until the panel is
        // key. Presenting stays silent unless the person opted in, and hover
        // takes nothing either; a click hands the keyboard over in the panel's
        // sendEvent because hosted SwiftUI content answers presses that never
        // reach mouseDown. Comments are stripped so prose naming the API
        // cannot answer for the code.
        let quickPreviewSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift",
            encoding: .utf8)) ?? ""
        expect(!quickPreviewSource.isEmpty, "the screenshot preview source reads back for its shape check")
        let quickPreviewCode = quickPreviewSource.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        // Split at the hosting controller: the hover closure is built above it,
        // so the presentation statements are what remains.
        let presentBody = quickPreviewCode.components(separatedBy: "let host = NSHostingController")
            .dropFirst().first?.components(separatedBy: "private func").first ?? ""
        expect(presentBody.contains("orderFrontRegardless()"),
               "the screenshot preview is presented without activating the app")
        // A click is the hand-off, and it is read in sendEvent because the
        // hosted SwiftUI content answers presses that never reach mouseDown.
        let panelBody = quickPreviewCode.components(separatedBy: "class ScreenshotQuickPreviewPanel")
            .dropFirst().first?.components(separatedBy: "\n}").first ?? ""
        // The opt-in keys the panel only after it is on screen, and the line
        // above the call is the preference check itself, so dropping the guard
        // or keying before ordering front both go red.
        let presentLines = presentBody.components(separatedBy: "\n")
        let orderFrontLine = presentLines.firstIndex { $0.contains("orderFrontRegardless()") } ?? -1
        let makeKeyLine = presentLines.firstIndex { $0.contains("makeKey") } ?? -1
        expect(orderFrontLine >= 0 && makeKeyLine > orderFrontLine
                && presentLines[makeKeyLine - 1].contains("screenshotPreviewTakesFocus"),
               "presenting the screenshot preview takes key focus only behind the opt-in, once the panel is on screen")
        let makeKeyCount = quickPreviewCode.components(separatedBy: "makeKey").count - 1
        let panelMakeKeyCount = panelBody.components(separatedBy: "makeKey").count - 1
        expect(makeKeyCount == panelMakeKeyCount + 1 && panelMakeKeyCount >= 1,
               "hover never takes key focus; only the opted-in presentation and the panel's own click hand-off may")
        expect(panelBody.contains("sendEvent") && panelBody.contains("leftMouseDown")
                && panelBody.contains("makeKey") && panelBody.contains("super.sendEvent"),
               "clicking the screenshot preview takes key focus and still delivers every preview button")

        // Both editors state a size the same way. The recorder wrote
        // "1960x1274" beside a screenshot editor that already read
        // "2940 \u{00D7} 1912 px", and the letter x is the tell.
        let recorderEditorSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Recorder/RecorderEditorView.swift",
            encoding: .utf8)) ?? ""
        expect(!recorderEditorSource.isEmpty, "the recorder editor source reads back for its shape check")
        expect(recorderEditorSource.contains("\\(Int(size.width)) \u{00D7} \\(Int(size.height))"),
               "the recorder states its output size with the multiplication sign")
        // A card that names itself twice reads like filler. The look cards had
        // borrowed the shape, pointer and background labels as subtitles, so
        // two of the three said their own name back in English.
        let inspectorSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Recorder/RecorderInspector.swift",
            encoding: .utf8)) ?? ""
        expect(!inspectorSource.isEmpty, "the recorder inspector source reads back for its shape check")
        expect(!inspectorSource.contains("subtitle"),
               "a look card carries one name, not a label borrowed from another control")
        // A button says what it does. The empty zoom state had borrowed the
        // timeline lane's hint, so the button read "Click here to add a zoom"
        // while being the very thing the reader was already looking at.
        for language in AppLanguage.allCases {
            let recorder = FeatureStrings.recorder(language)
            expect(!recorder.addZoomButton.isEmpty
                    && recorder.addZoomButton != recorder.zoomLaneEmptyHint,
                   "the empty zoom state has its own button label in \(language.rawValue)")
        }
        // A menu row says where the command lives. Every Mac app has a menu
        // named after itself, so the app menu read its own name twice.
        expect(CommandBarMenuPath.crumb(appName: "Notes", path: ["Notes"]) == "Notes",
               "the app menu does not say the app name twice")
        expect(CommandBarMenuPath.crumb(appName: "Notes", path: ["File", "Export"])
                == "Notes \u{203A} File \u{203A} Export",
               "a real trail keeps every step")
        expect(CommandBarMenuPath.crumb(appName: "Notes", path: []) == "Notes",
               "a command straight off the app names only the app")
        expect(CommandBarMenuPath.crumb(appName: "Notes", path: ["", "View"])
                == "Notes \u{203A} View",
               "an empty step leaves no dangling separator")
    }

    static func runEditor(expect: (Bool, String) -> Void) {
        let recordingOnly: Set<AppFeature> = [.screenRecorder]
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            expect(!(abs(actual - expected) > tol), "\(label): got \(actual), expected \(expected)")
        }

        let cocoa = ScreenshotSupport.cocoaRect(fromWindowServer: CGRect(x: 10, y: 30, width: 200, height: 100),
                                                mainScreenHeight: 900)
        expect(cocoa == CGRect(x: 10, y: 770, width: 200, height: 100),
               "window server rects convert to Cocoa coordinates")
        let viewRect = ScreenshotSupport.flippedViewRect(fromCocoa: cocoa,
                                                         screenFrame: CGRect(x: 0, y: 0, width: 1600, height: 900))
        expect(viewRect == CGRect(x: 10, y: 30, width: 200, height: 100),
               "the round trip back to a flipped view restores the window server rect")
        expect(ScreenshotSupport.cocoaRect(fromFlippedView: viewRect,
                                           screenFrame: CGRect(x: 0, y: 0,
                                                               width: 1600, height: 900)) == cocoa,
               "a flipped overlay rect maps back to its Cocoa screen position")
        let pixels = ScreenshotSupport.imagePixelRect(fromView: CGRect(x: 10, y: 20, width: 30, height: 40),
                                                      viewSize: CGSize(width: 100, height: 100),
                                                      imageSize: CGSize(width: 200, height: 200))
        expect(pixels == CGRect(x: 20, y: 40, width: 60, height: 80),
               "view points scale to image pixels")
        expect(ScreenshotSupport.imagePixelRect(fromView: CGRect(x: -20, y: -20, width: 500, height: 500),
                                                viewSize: CGSize(width: 100, height: 100),
                                                imageSize: CGSize(width: 200, height: 200))
                == CGRect(x: 0, y: 0, width: 200, height: 200),
               "pixel rects clamp to the image")
        expect(ScreenshotSupport.imagePixelPoint(fromView: CGPoint(x: 50, y: 25),
                                                 viewSize: CGSize(width: 100, height: 50),
                                                 imageSize: CGSize(width: 200, height: 100))
                == CGPoint(x: 100, y: 50),
               "the capture loupe maps its pointer to the matching source pixel")
        expect(ScreenshotSupport.imagePixelPoint(fromView: CGPoint(x: -10, y: 90),
                                                 viewSize: CGSize(width: 100, height: 50),
                                                 imageSize: CGSize(width: 200, height: 100))
                == CGPoint(x: 0, y: 100),
               "the capture loupe clamps source points at display edges")
        let editorMinimum = ScreenshotSupport.editorMinimumContentSize(
            visibleSize: CGSize(width: 1470, height: 956))
        expect(editorMinimum == CGSize(width: 980, height: 680),
               "the screenshot editor opens on a comfortable canvas")
        let editorSmallDisplay = ScreenshotSupport.editorMinimumContentSize(
            visibleSize: CGSize(width: 700, height: 500))
        expect(editorSmallDisplay == CGSize(width: 700, height: 500),
               "the editor minimum never exceeds a compact display")
        let smallCaptureWindow = ScreenshotSupport.editorContentSize(
            imagePointSize: CGSize(width: 180, height: 100),
            visibleSize: CGSize(width: 1470, height: 956))
        expect(smallCaptureWindow == editorMinimum,
               "a small screenshot still receives the full editing canvas")
        let largeCaptureWindow = ScreenshotSupport.editorContentSize(
            imagePointSize: CGSize(width: 2200, height: 1400),
            visibleSize: CGSize(width: 1470, height: 956))
        expect(largeCaptureWindow.width <= 1470 * 0.90
                && largeCaptureWindow.height <= 956 * 0.88,
               "a large screenshot editor stays inside the visible display")
        expect(ScreenshotSupport.editorOwnsKeyEvent(eventWindowNumber: 42,
                                                    editorWindowNumber: 42,
                                                    editorIsKey: true),
               "screenshot editor owns key events carrying its window number")
        expect(ScreenshotSupport.editorOwnsKeyEvent(eventWindowNumber: 0,
                                                    editorWindowNumber: 42,
                                                    editorIsKey: true),
               "screenshot editor owns windowless menu key equivalents while key")
        expect(!ScreenshotSupport.editorOwnsKeyEvent(eventWindowNumber: 0,
                                                     editorWindowNumber: 42,
                                                     editorIsKey: false),
               "inactive screenshot editor ignores windowless key events")
        expect(!ScreenshotSupport.editorOwnsKeyEvent(eventWindowNumber: 7,
                                                     editorWindowNumber: 42,
                                                     editorIsKey: true),
               "screenshot editor ignores events explicitly owned by another window")
        let previewFrame = ScreenshotSupport.quickPreviewFrame(
            size: CGSize(width: 286, height: 210),
            anchor: CGRect(x: 1100, y: 100, width: 300, height: 300),
            pointer: CGPoint(x: 1300, y: 220),
            visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 956))
        expect(CGRect(x: 10, y: 10, width: 1450, height: 936).contains(previewFrame),
               "the quick capture preview stays fully inside the visible display")

        let pickable = [ScreenshotSupport.PickableWindow(windowID: 1, frame: CGRect(x: 0, y: 0, width: 50, height: 50)),
                        ScreenshotSupport.PickableWindow(windowID: 2, frame: CGRect(x: 0, y: 0, width: 400, height: 400))]
        expect(ScreenshotSupport.window(at: CGPoint(x: 10, y: 10), in: pickable)?.windowID == 1,
               "the frontmost window wins a click")
        expect(ScreenshotSupport.window(at: CGPoint(x: 300, y: 300), in: pickable)?.windowID == 2
                && ScreenshotSupport.window(at: CGPoint(x: 900, y: 900), in: pickable) == nil,
               "clicks outside every window pick nothing")

        let fileDate = Date(timeIntervalSince1970: 1_752_486_065) // 2025-07-14 09:41:05 UTC
        let fileName = ScreenshotSupport.fileName(prefix: "Screenshot", date: fileDate)
        expect(fileName.hasPrefix("Screenshot 20") && fileName.hasSuffix(".png")
                && !fileName.contains(":") && fileName.contains(" at "),
               "file names are dated, colon free and png")
        expect(ScreenshotSupport.uniqueFileName("a.png", exists: { _ in false }) == "a.png",
               "a free name stays untouched")
        expect(ScreenshotSupport.uniqueFileName("a.png", exists: { $0 == "a.png" }) == "a 2.png",
               "a taken name gets the next numbered variant")
        expect(ScreenshotSupport.uniqueFileName("a.png",
                                                exists: { $0 == "a.png" || $0 == "a 2.png" }) == "a 3.png",
               "numbering keeps walking until a free name")
        RecentCaptureStoreTests.run { expect($0, $1) }
        let recentID = UUID()
        expect(ScreenshotSupport.isRecentCaptureCacheFileName("\(recentID.uuidString).png")
                && ScreenshotSupport.isRecentCaptureCacheFileName(
                    "\(recentID.uuidString)-thumbnail.png")
                && !ScreenshotSupport.isRecentCaptureCacheFileName("history.json")
                && !ScreenshotSupport.isRecentCaptureCacheFileName("../\(recentID.uuidString).png"),
               "recent capture cleanup recognizes only app-owned UUID png names")
        let dragRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotDragTests-\(UUID().uuidString)", isDirectory: true)
        let dragData = Data([0x89, 0x50, 0x4E, 0x47])
        let firstDrag = try? ScreenshotSupport.temporaryDragFile(
            data: dragData, name: "Capture.png", directory: dragRoot)
        let secondDrag = try? ScreenshotSupport.temporaryDragFile(
            data: dragData, name: "Capture.png", directory: dragRoot)
        expect(firstDrag?.lastPathComponent == "Capture.png"
                && firstDrag.flatMap { try? Data(contentsOf: $0) } == dragData,
               "a screenshot drag writes the complete payload with its file name")
        expect(firstDrag != nil && secondDrag != nil && firstDrag != secondDrag,
               "simultaneous screenshot drags receive separate temporary files")
        let unrelatedDrag = dragRoot.appendingPathComponent("ScreenshotDrag-not-owned",
                                                            isDirectory: true)
        try? FileManager.default.createDirectory(at: unrelatedDrag,
                                                 withIntermediateDirectories: true)
        ScreenshotSupport.removeTemporaryDragDirectories(directory: dragRoot)
        expect(firstDrag.map { !FileManager.default.fileExists(atPath: $0.path) } == true
                && secondDrag.map { !FileManager.default.fileExists(atPath: $0.path) } == true
                && FileManager.default.fileExists(atPath: unrelatedDrag.path),
               "temporary screenshot cleanup removes only app-owned drag directories")
        try? FileManager.default.removeItem(at: dragRoot)

        let copyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotCopyTests-\(UUID().uuidString)", isDirectory: true)
        let staleCopy = try? ScreenshotSupport.copiedFile(
            data: dragData, name: "Old.png", directory: copyRoot)
        if let staleCopy {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1)],
                ofItemAtPath: staleCopy.path)
        }
        let currentCopy = try? ScreenshotSupport.copiedFile(
            data: dragData, name: "../Capture.png", directory: copyRoot)
        let nextCopy = try? ScreenshotSupport.copiedFile(
            data: dragData, name: "Capture.png", directory: copyRoot)
        if let nextCopy {
            ScreenshotSupport.pruneCopiedFiles(
                in: copyRoot, preserving: nextCopy,
                now: Date(timeIntervalSince1970: 100_000))
        }
        expect(staleCopy.map { !FileManager.default.fileExists(atPath: $0.path) } == true,
               "copying a screenshot removes expired copied files")
        expect(currentCopy?.lastPathComponent == "Capture.png"
                && nextCopy?.lastPathComponent == "Capture 2.png"
                && currentCopy.flatMap { try? Data(contentsOf: $0) } == dragData,
               "copied screenshots stay as unique complete png files")
        expect(currentCopy.map { ScreenshotSupport.isCopiedScreenshot($0, in: copyRoot) } == true,
               "clipboard history recognizes a copied screenshot only inside its private cache")
        expect(currentCopy.map {
            ClipboardHistoryCapturePolicy.isCopiedScreenshot([$0.path], in: copyRoot)
        } == true
                && !ClipboardHistoryCapturePolicy.isCopiedScreenshot(
                    ["/tmp/Other.png"], in: copyRoot),
               "an app-owned screenshot is never retained as a file when image capture rejects it")
        let lateStaleCopy = copyRoot.appendingPathComponent("A.png")
        let publishedCopy = copyRoot.appendingPathComponent("B.png")
        let pruneVictims = ScreenshotSupport.copiedFilePruneVictims(
            [
                .init(url: lateStaleCopy, date: Date(timeIntervalSince1970: 2), bytes: 6),
                .init(url: publishedCopy, date: Date(timeIntervalSince1970: 1), bytes: 6),
            ],
            preserving: publishedCopy,
            maximumCount: 100,
            maximumBytes: 10)
        expect(pruneVictims == [lateStaleCopy],
               "a late stale copy is pruned without evicting the published file")
        let copySymlink = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotCopyLink-\(UUID().uuidString)")
        try? FileManager.default.createSymbolicLink(at: copySymlink,
                                                     withDestinationURL: copyRoot)
        let symlinkCopy = try? ScreenshotSupport.copiedFile(
            data: dragData, name: "Linked.png", directory: copySymlink)
        expect(symlinkCopy == nil
                && currentCopy.map { FileManager.default.fileExists(atPath: $0.path) } == true,
               "copied screenshots reject a symlink cache without touching its target")
        try? FileManager.default.removeItem(at: copySymlink)
        try? FileManager.default.removeItem(at: copyRoot)

        var counterList = [
            ScreenshotSupport.Annotation(tool: .counter, number: 1),
            ScreenshotSupport.Annotation(tool: .arrow),
            ScreenshotSupport.Annotation(tool: .counter, number: 2),
            ScreenshotSupport.Annotation(tool: .counter, number: 3),
        ]
        counterList.remove(at: 0)
        let renumbered = ScreenshotSupport.renumberingCounters(counterList)
        expect(renumbered.filter { $0.tool == .counter }.map(\.number) == [1, 2],
               "deleting a counter renumbers the rest without holes")
        expect(renumbered[0].tool == .arrow || renumbered.count == 3,
               "renumbering never drops annotations")

        let layered = [
            ScreenshotSupport.Annotation(tool: .text),
            ScreenshotSupport.Annotation(tool: .rect),
            ScreenshotSupport.Annotation(tool: .arrow),
        ]
        let sentBack = ScreenshotSupport.reordering(layered, moving: layered[1].id, .backward)
        expect(sentBack.map(\.id) == [layered[1].id, layered[0].id, layered[2].id],
               "sending back swaps an annotation with the one drawn before it")
        let broughtForward = ScreenshotSupport.reordering(layered, moving: layered[1].id, .forward)
        expect(broughtForward.map(\.id) == [layered[0].id, layered[2].id, layered[1].id],
               "bringing forward swaps an annotation with the one drawn after it")
        expect(ScreenshotSupport.reordering(layered, moving: layered[0].id, .backward).map(\.id)
                == layered.map(\.id)
                && ScreenshotSupport.reordering(layered, moving: layered[2].id, .forward).map(\.id)
                == layered.map(\.id),
               "an annotation at either end of the order stays put in that direction")
        expect(ScreenshotSupport.reordering(layered, moving: UUID(), .forward).map(\.id)
                == layered.map(\.id),
               "an unknown annotation leaves the order alone")
        expect(!ScreenshotSupport.canReorder(layered, moving: layered[0].id, .backward)
                && ScreenshotSupport.canReorder(layered, moving: layered[0].id, .forward)
                && !ScreenshotSupport.canReorder(layered, moving: layered[2].id, .forward)
                && ScreenshotSupport.canReorder(layered, moving: layered[2].id, .backward),
               "each direction is offered only while the annotation can still take it")
        expect(!ScreenshotSupport.canReorder(layered, moving: UUID(), .forward)
                && !ScreenshotSupport.canReorder([], moving: layered[0].id, .backward),
               "an annotation that is not there can never be reordered")

        let resized = ScreenshotSupport.resizedRect(CGRect(x: 10, y: 10, width: 100, height: 100),
                                                    dragging: .bottomRight,
                                                    to: CGPoint(x: 50, y: 60))
        expect(resized == CGRect(x: 10, y: 10, width: 40, height: 50),
               "dragging a handle resizes the rect")
        let crossed = ScreenshotSupport.resizedRect(CGRect(x: 10, y: 10, width: 100, height: 100),
                                                    dragging: .right,
                                                    to: CGPoint(x: 0, y: 0))
        expect(crossed.width == 10 && crossed.minX == 0,
               "dragging a handle across the opposite edge flips instead of going negative")
        let movedCrop = ScreenshotSupport.movedRect(
            CGRect(x: 20, y: 30, width: 80, height: 60),
            by: CGPoint(x: 50, y: -100),
            within: CGRect(x: 0, y: 0, width: 120, height: 100))
        expect(movedCrop == CGRect(x: 40, y: 0, width: 80, height: 60),
               "dragging inside a crop moves it without resizing past the image edges")
        expect(ScreenshotSupport.handle(at: CGPoint(x: 10, y: 10),
                                        rect: CGRect(x: 10, y: 10, width: 100, height: 100),
                                        tolerance: 6) == .topLeft,
               "handle hit testing finds the corner")

        let head = ScreenshotSupport.arrowHead(from: CGPoint(x: 0, y: 0),
                                               to: CGPoint(x: 100, y: 0),
                                               strokeWidth: 4)
        expect(head.left.x < 100 && head.right.x < 100 && head.left.y != head.right.y,
               "arrow heads open behind the tip")
        let shortHead = ScreenshotSupport.arrowHead(from: .zero,
                                                    to: CGPoint(x: 10, y: 0),
                                                    strokeWidth: 14)
        expect(shortHead.left.x >= 0 && shortHead.right.x >= 0,
               "a short arrow head never extends behind its tail")
        let arrowPath = ScreenshotSupport.arrowSilhouette(from: CGPoint(x: 100, y: 20),
                                                          to: CGPoint(x: 100, y: 300),
                                                          strokeWidth: 40)
        expect(arrowPath.contains(CGPoint(x: 100, y: 30),
                                  using: .winding,
                                  transform: .identity),
               "the arrow tail stays filled where its cap meets the shaft")
        expect(arrowPath.contains(CGPoint(x: 100, y: 190),
                                  using: .winding,
                                  transform: .identity),
               "the arrow stays filled where its shaft meets the head")
        expect(abs(ScreenshotSupport.distance(from: CGPoint(x: 50, y: 10),
                                              toSegment: CGPoint(x: 0, y: 0),
                                              CGPoint(x: 100, y: 0)) - 10) < 0.001,
               "segment distance measures perpendicular offset")
        expect(ScreenshotSupport.distance(from: CGPoint(x: -30, y: 0),
                                          toSegment: CGPoint(x: 0, y: 0),
                                          CGPoint(x: 100, y: 0)) == 30,
               "segment distance clamps to the endpoints")

        expect(ScreenshotSupport.pixelBlockSize(for: CGSize(width: 5500, height: 3600)) == 65
                && ScreenshotSupport.pixelBlockSize(for: CGSize(width: 200, height: 120)) == 10,
               "pixelation blocks scale with the capture and never get too fine")
        expect(ScreenshotSupport.downscaledSize(pixelSize: CGSize(width: 800, height: 600), scale: 2)
                == CGSize(width: 400, height: 300),
               "the 1x option halves a Retina capture")
        expect(ScreenshotSupport.downscaledSize(pixelSize: CGSize(width: 800, height: 600), scale: 1)
                == CGSize(width: 800, height: 600),
               "a 1x capture never downscales")
        expect(ScreenshotSupport.backdropPadding(for: CGSize(width: 100, height: 100), factor: 0.5) == 24,
               "backdrop padding keeps a floor for tiny captures")
        expect(ScreenshotSupport.backdropPadding(for: CGSize(width: 4000, height: 4000), factor: 1)
                == (4000 * 0.175).rounded(),
               "the margin slider grows the backdrop padding")
        expect(ScreenshotSupport.backdropPadding(for: CGSize(width: 4000, height: 4000), factor: 0)
                == 140,
               "margin zero still keeps a small frame")
        expect(ScreenshotSupport.BackdropID.allCases.filter { $0 != .none }
                .allSatisfy { $0.stops.count == 2 },
               "every backdrop gradient has its two stops")
        expect(ScreenshotSupport.ColorID.sanitized("bogus") == .red
                && ScreenshotSupport.StrokeID.sanitized(nil) == .medium,
               "style choices sanitize to safe defaults")
        expect(ScreenshotSupport.StickerID.sanitized("bogus") == .check
                && ScreenshotSupport.StickerID.allCases.count == 12,
               "stickers keep a safe default and a compact built-in set")
        let stickerRect = ScreenshotSupport.stickerRect(
            centeredAt: CGPoint(x: 5, y: 5),
            side: 40,
            within: CGRect(x: 0, y: 0, width: 100, height: 80))
        expect(stickerRect == CGRect(x: 0, y: 0, width: 40, height: 40),
               "a sticker placed at an edge stays fully inside the image")

        expect(ScreenshotSupport.cardCornerRadius(for: CGSize(width: 1600, height: 900), factor: 0) == 0
                && ScreenshotSupport.cardCornerRadius(for: CGSize(width: 1600, height: 900), factor: 1) == 180
                && ScreenshotSupport.cardCornerRadius(for: CGSize(width: 1600, height: 900), factor: 2) == 180,
               "card corner radius clamps and scales with the short side")
        expect(abs(ScreenshotSupport.backdropBlurRadius(
                    for: CGSize(width: 1600, height: 900), factor: 1) - 31.5) < 0.001
                && ScreenshotSupport.backdropBlurRadius(
                    for: CGSize(width: 1600, height: 900), factor: -1) == 0,
               "background blur scales with the canvas and clamps its slider")
        let solidStyle = ScreenshotSupport.BackdropStyle(kind: .solid, colors: [[0.2, 0.4, 0.9]],
                                                         padding: 0.3, cornerRadius: 0.2,
                                                         blur: 0.6)
        let solidRoundTrip = ScreenshotSupport.BackdropStyle.decoded(solidStyle.encoded())
        expect(solidRoundTrip == solidStyle, "a backdrop style round-trips through JSON")
        let legacyStyle = ScreenshotSupport.BackdropStyle.decoded(
            #"{"kind":"solid","colors":[[0.2,0.4,0.9]],"padding":0.3,"cornerRadius":0.2}"#)
        expect(legacyStyle.kind == .solid && legacyStyle.blur == 0,
               "backgrounds saved before blur keep decoding without changing")
        expect(ScreenshotSupport.BackdropStyle.decoded(nil).kind == .none
                && ScreenshotSupport.BackdropStyle.decoded("").kind == .none
                && ScreenshotSupport.BackdropStyle.decoded("not json").kind == .none,
               "a missing or broken backdrop style falls back to none")
        expect(ScreenshotSupport.BackdropStyle().cornerRadius == 0,
               "the default backdrop leaves capture corners unchanged")
        let brokenSolid = ScreenshotSupport.BackdropStyle(kind: .solid, colors: nil)
        expect(brokenSolid.sanitized().kind == .none,
               "a solid style without colors demotes to none")
        let wildSliders = ScreenshotSupport.BackdropStyle(kind: .preset, presetID: "ocean",
                                                          padding: 9, cornerRadius: -3, blur: 8)
        expect(wildSliders.sanitized().padding == 1
                && wildSliders.sanitized().cornerRadius == 0
                && wildSliders.sanitized().blur == 1,
               "backdrop sliders clamp to their range")
        expect(ScreenshotSupport.BackdropStyle(kind: .preset, presetID: "bogus").sanitized().kind == .none
                && ScreenshotSupport.BackdropStyle(kind: .image, imagePath: nil).sanitized().kind == .none,
               "unknown presets and missing image paths demote to none")
        expect(ScreenshotSupport.BackdropStyle(kind: .gradient,
                                               colors: [[0, 2, -1], [0.5, 0.5, 0.5]])
                .sanitized().colors?.first == [0, 1, 0],
               "gradient colors clamp component by component")

        let presetList = [solidStyle,
                          ScreenshotSupport.BackdropStyle(kind: .gradient,
                                                          colors: [[1, 0, 0], [0, 0, 1]])]
        let decodedPresets = ScreenshotSupport.decodedBackdropPresets(
            ScreenshotSupport.encodedBackdropPresets(presetList))
        expect(decodedPresets == presetList, "saved backdrops round-trip through JSON")
        expect(ScreenshotSupport.decodedBackdropPresets("junk").isEmpty
                && ScreenshotSupport.decodedBackdropPresets(nil).isEmpty,
               "broken preset lists decode to empty")
        let overflow = Array(repeating: solidStyle, count: 40)
        expect(ScreenshotSupport.decodedBackdropPresets(
                ScreenshotSupport.encodedBackdropPresets(overflow)).count
                == ScreenshotSupport.backdropPresetLimit,
               "saved backdrops cap at the presets limit")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotBackdropStyle] as? String == ""
                && Defaults.registeredDefaults[DefaultsKey.screenshotBackdropPresets] as? String == "[]",
               "backdrop style and presets register empty")

        let wordBoxes = [CGRect(x: 0, y: 0, width: 40, height: 10),
                         CGRect(x: 50, y: 0, width: 40, height: 10),
                         CGRect(x: 0, y: 20, width: 40, height: 10)]
        expect(ScreenshotSupport.wordSelection(anchor: CGPoint(x: 5, y: 5),
                                               current: CGPoint(x: 60, y: 5),
                                               boxes: wordBoxes) == [0, 1],
               "a drag across a line selects the words it crosses")
        expect(ScreenshotSupport.wordSelection(anchor: CGPoint(x: 5, y: 5),
                                               current: CGPoint(x: 10, y: 25),
                                               boxes: wordBoxes) == [0, 2],
               "a drag across lines selects into the next line")
        let recognizedWords = [
            ScreenshotSupport.RecognizedWord(text: "ola", rect: wordBoxes[0], line: 0),
            ScreenshotSupport.RecognizedWord(text: "mundo", rect: wordBoxes[1], line: 0),
            ScreenshotSupport.RecognizedWord(text: "linha", rect: wordBoxes[2], line: 1),
        ]
        expect(ScreenshotSupport.joinedWords(recognizedWords, selected: [1, 0]) == "ola mundo",
               "selected words join in reading order with spaces")
        expect(ScreenshotSupport.joinedWords(recognizedWords, selected: [2, 0]) == "ola\nlinha",
               "line changes become newlines")
        expect(ScreenshotSupport.joinedWords(recognizedWords, selected: [9]).isEmpty
                && ScreenshotSupport.joinedWords(recognizedWords, selected: []).isEmpty,
               "out of range or empty selections copy nothing")
        let defaultScreenshotTools = ScreenshotSupport.Tool.allCases
        expect(defaultScreenshotTools.count == 13
                && Array(defaultScreenshotTools.prefix(9))
                    == [.select, .arrow, .pixelate, .crop, .text, .sticker,
                        .rect, .highlight, .freehand],
               "the screenshot rail leads with the nine most useful numbered tools")
        let customScreenshotTools = ScreenshotSupport.Tool.ordered(
            from: "crop,arrow,arrow,invalid")
        expect(Array(customScreenshotTools.prefix(2)) == [.crop, .arrow]
                && customScreenshotTools.count == 13
                && Set(customScreenshotTools).count == 13,
               "a saved screenshot tool order drops invalid duplicates and appends missing tools")
        expect(ScreenshotSupport.Tool.shortcutTool(number: 1,
                                                   orderRaw: nil,
                                                   enabled: true) == .select
                && ScreenshotSupport.Tool.shortcutTool(number: 3,
                                                       orderRaw: nil,
                                                       enabled: true) == .pixelate
                && ScreenshotSupport.Tool.shortcutTool(number: 9,
                                                       orderRaw: nil,
                                                       enabled: true) == .freehand
                && ScreenshotSupport.Tool.shortcutTool(number: 1,
                                                       orderRaw: nil,
                                                       enabled: false) == nil
                && ScreenshotSupport.Tool.shortcutTool(number: 10,
                                                       orderRaw: nil,
                                                       enabled: true) == nil,
               "number keys 1 through 9 follow tool order and can be disabled together")
        expect(ScreenshotSupport.Tool.shortcutNumber(for: .crop,
                                                     orderRaw: "arrow,crop",
                                                     enabled: true) == 2
                && ScreenshotSupport.Tool.shortcutNumber(for: .redact,
                                                         orderRaw: nil,
                                                         enabled: true) == nil,
               "the rail exposes only the first nine configured shortcut numbers")
        let cropAssignedFirst = ScreenshotSupport.Tool.assigningShortcut(
            1, to: .crop, orderRaw: nil)
        let selectWithoutShortcut = ScreenshotSupport.Tool.assigningShortcut(
            nil, to: .select, orderRaw: nil)
        expect(cropAssignedFirst.first == .crop
                && ScreenshotSupport.Tool.shortcutNumber(
                    for: .crop,
                    orderRaw: cropAssignedFirst.map(\.rawValue).joined(separator: ","),
                    enabled: true) == 1
                && selectWithoutShortcut.firstIndex(of: .select) == 9
                && ScreenshotSupport.Tool.shortcutNumber(
                    for: .select,
                    orderRaw: selectWithoutShortcut.map(\.rawValue).joined(separator: ","),
                    enabled: true) == nil,
               "the visible shortcut menu assigns a numbered slot or removes a tool from 1 through 9")

        expect(ScreenshotSupport.cropLoupeSampleRect(
            around: CGPoint(x: 50, y: 40),
            imageSize: CGSize(width: 100, height: 80))
            == CGRect(x: 44, y: 34, width: 13, height: 13),
               "the crop loupe centers its source pixels around an inner grip")
        expect(ScreenshotSupport.cropLoupeSampleRect(
            around: CGPoint(x: 100, y: 80),
            imageSize: CGSize(width: 100, height: 80))
            == CGRect(x: 87, y: 67, width: 13, height: 13),
               "the crop loupe keeps a full sample at the bottom right edge")
        // An even sample side has no middle cell. The sampled pixel then sat
        // half a cell right of and below the frame's centre, and the ring drawn
        // around it followed, which is what read as an off-centre reticle.
        for loupeZoom in [ScreenshotSupport.captureLoupeMinZoom, 1, 2,
                          ScreenshotSupport.captureLoupeMaxZoom] {
            let side = ScreenshotSupport.captureLoupeSampleSide(zoom: loupeZoom)
            let pointer = CGPoint(x: 80.4, y: 50.7)
            let image = CGSize(width: 160, height: 100)
            let sample = ScreenshotSupport.cropLoupeSampleRect(around: pointer,
                                                               imageSize: image,
                                                               sideLength: side)
            let loupeFrame = CGRect(x: 0, y: 0, width: 70, height: 70)
            let marked = ScreenshotSupport.captureLoupeTargetPixelRect(around: pointer,
                                                                       source: sample,
                                                                       frame: loupeFrame)
            expectClose(Double(marked.midX), Double(loupeFrame.midX),
                        "the loupe marks the pixel in the middle of its frame across the zoom range")
            expectClose(Double(marked.midY), Double(loupeFrame.midY),
                        "the marked pixel is as centred vertically as it is horizontally")
        }
        // The editor's crop loupe marks an edge between pixels, so it needs the
        // opposite parity: an even side puts that edge in the middle of the
        // frame, where an odd one leaves it half a cell short of centre.
        let cropEdgeSample = ScreenshotSupport.cropLoupeSampleRect(
            around: CGPoint(x: 100, y: 60),
            imageSize: CGSize(width: 400, height: 300),
            sideLength: 14,
            centredOnPixel: false)
        expect(cropEdgeSample == CGRect(x: 93, y: 53, width: 14, height: 14)
                && cropEdgeSample.midX == 100 && cropEdgeSample.midY == 60,
               "the crop loupe centres its sample on the handle's edge, not on a pixel cell")
        expect(ScreenshotSupport.cropLoupeSampleRect(
            around: CGPoint(x: 100, y: 60),
            imageSize: CGSize(width: 400, height: 300),
            sideLength: 13,
            centredOnPixel: false).width == 14,
               "an odd side grows to the next even one when the loupe centres on an edge")

        expect(ScreenshotSupport.cropLoupeSampleRect(
            around: .zero,
            imageSize: CGSize(width: 8, height: 5))
            == CGRect(x: 0, y: 0, width: 8, height: 5),
               "the crop loupe safely shrinks only for images smaller than its sample")
        expect(ScreenshotSupport.captureLoupeTargetPixelRect(
            around: CGPoint(x: 50.5, y: 40.2),
            source: CGRect(x: 43, y: 33, width: 14, height: 14),
            frame: CGRect(x: 0, y: 0, width: 70, height: 70))
            == CGRect(x: 35, y: 35, width: 5, height: 5),
               "the loupe highlights one whole source pixel, not the pointer's sub-pixel position")
        expect(ScreenshotSupport.captureLoupeTargetPixelRect(
            around: CGPoint(x: 100, y: 80),
            source: CGRect(x: 86, y: 66, width: 14, height: 14),
            frame: CGRect(x: 0, y: 0, width: 70, height: 70))
            == CGRect(x: 65, y: 65, width: 5, height: 5),
               "a pointer on the far display edge highlights the last pixel the picker can read")
        // The pixel the loupe marks and the pixel `confirmColor` copies come
        // from two independent expressions. Sweeping the whole overlay at
        // every zoom is what keeps them from drifting apart by one pixel.
        let sampledImageSize = CGSize(width: 160, height: 100)
        let sampledViewSize = CGSize(width: 320, height: 200)
        let sampledFrame = CGRect(x: 20, y: 30, width: 70, height: 70)
        var loupeAimFailure: String?
        for zoom in [ScreenshotSupport.captureLoupeMinZoom, 1, ScreenshotSupport.captureLoupeMaxZoom] {
            for stepX in 0...128 {
                for stepY in 0...80 {
                    let pixelPoint = ScreenshotSupport.imagePixelPoint(
                        fromView: CGPoint(x: CGFloat(stepX) * 2.5, y: CGFloat(stepY) * 2.5),
                        viewSize: sampledViewSize,
                        imageSize: sampledImageSize)
                    let source = ScreenshotSupport.cropLoupeSampleRect(
                        around: pixelPoint,
                        imageSize: sampledImageSize,
                        sideLength: ScreenshotSupport.captureLoupeSampleSide(zoom: zoom))
                    let highlight = ScreenshotSupport.captureLoupeTargetPixelRect(
                        around: pixelPoint, source: source, frame: sampledFrame)
                    let cellWidth = sampledFrame.width / source.width
                    let cellHeight = sampledFrame.height / source.height
                    let markedX = source.minX + ((highlight.minX - sampledFrame.minX) / cellWidth).rounded()
                    let markedY = source.minY + ((highlight.minY - sampledFrame.minY) / cellHeight).rounded()
                    // Copied verbatim from `confirmColor`.
                    let copiedX = CGFloat(min(max(Int(pixelPoint.x.rounded(.down)), 0),
                                              Int(sampledImageSize.width) - 1))
                    let copiedY = CGFloat(min(max(Int(pixelPoint.y.rounded(.down)), 0),
                                              Int(sampledImageSize.height) - 1))
                    if markedX != copiedX || markedY != copiedY {
                        loupeAimFailure = "at \(pixelPoint) zoom \(zoom) the loupe marks "
                            + "(\(markedX), \(markedY)) but the picker copies (\(copiedX), \(copiedY))"
                    }
                    if !sampledFrame.insetBy(dx: -0.001, dy: -0.001).contains(highlight) {
                        loupeAimFailure = "at \(pixelPoint) zoom \(zoom) the highlight leaves the loupe"
                    }
                }
            }
        }
        expect(loupeAimFailure == nil,
               loupeAimFailure ?? "the loupe highlight marks the pixel the color picker copies")
        expect(ScreenshotSupport.captureLoupeTargetPixelRect(
            around: .zero, source: .zero, frame: CGRect(x: 0, y: 0, width: 70, height: 70))
            == CGRect(x: 0, y: 0, width: 70, height: 70),
               "an empty sample leaves the loupe highlight harmless instead of dividing by zero")
        expectClose(ScreenshotSupport.captureLoupeZoom(1, adjustedBy: 1), 1.15,
                    "scrolling up zooms the capture loupe in")
        expectClose(ScreenshotSupport.captureLoupeInitialZoom(
            rememberLast: false, defaultZoom: 2, lastZoom: 4), 2,
                    "the capture loupe starts at its chosen default zoom")
        expectClose(ScreenshotSupport.captureLoupeInitialZoom(
            rememberLast: true, defaultZoom: 2, lastZoom: 4), 4,
                    "the capture loupe can restore its last zoom")
        expectClose(ScreenshotSupport.captureLoupeInitialZoom(
            rememberLast: false, defaultZoom: .nan, lastZoom: 4), 1,
                    "an invalid saved magnifier zoom falls back safely")
        expectClose(ScreenshotSupport.captureLoupeWheelDelta(
            scrollingDelta: 0, lineDelta: 0, fixedPointDelta: 0.25), 0.25,
                    "fractional mouse-wheel notches do not disappear when AppKit rounds to zero")
        expectClose(ScreenshotSupport.captureLoupeWheelDelta(
            scrollingDelta: 0, lineDelta: -1, fixedPointDelta: 0), -1,
                    "ordinary line-based mouse-wheel notches remain available to the magnifier")
        var steppedLoupeZoom = ScreenshotSupport.captureLoupeMinZoom
        var steppedLoupeSides: [CGFloat] = []
        for _ in 0..<12 {
            steppedLoupeZoom = ScreenshotSupport.captureLoupeSteppedZoom(
                steppedLoupeZoom, adjustedBy: 0.25)
            steppedLoupeSides.append(
                ScreenshotSupport.captureLoupeSampleSide(zoom: steppedLoupeZoom))
        }
        expect(steppedLoupeSides == [25, 23, 21, 19, 17, 15, 13, 11, 9, 7, 5, 3],
               "every stepped wheel notch changes one visible level across the whole zoom range")
        for _ in 0..<12 {
            steppedLoupeZoom = ScreenshotSupport.captureLoupeSteppedZoom(
                steppedLoupeZoom, adjustedBy: -0.25)
        }
        expectClose(steppedLoupeZoom, ScreenshotSupport.captureLoupeMinZoom,
                    "all stepped magnifier levels are reversible without dead notches")
        var fastLoupeZoom: CGFloat = 1
        for _ in 0..<6 {
            fastLoupeZoom = ScreenshotSupport.captureLoupeZoom(
                fastLoupeZoom, adjustedBy: 20)
        }
        expect(fastLoupeZoom > 2,
               "fast magnifier zoom preserves the original packet-by-packet behavior")
        expect(ScreenshotSupport.captureLoupeUsesSteppedZoom(
            steppedByDefault: true, optionPressed: false)
                && !ScreenshotSupport.captureLoupeUsesSteppedZoom(
                    steppedByDefault: true, optionPressed: true)
                && ScreenshotSupport.captureLoupeUsesSteppedZoom(
                    steppedByDefault: false, optionPressed: true),
               "Option temporarily swaps the chosen magnifier wheel mode")
        expectClose(ScreenshotSupport.captureLoupeZoom(0.5, adjustedBy: -1), 0.5,
                    "capture loupe zoom stays above its minimum")
        expectClose(ScreenshotSupport.captureLoupeZoom(10, adjustedBy: 1),
                    ScreenshotSupport.captureLoupeMaxZoom,
                    "capture loupe zoom stays below its maximum")
        expectClose(ScreenshotSupport.captureLoupeMaxZoom,
                    ScreenshotSupport.captureLoupeBaseSampleSide
                        / ScreenshotSupport.captureLoupeMinSampleSide,
                    "the zoom ceiling is derived from the smallest useful sample")
        expectClose(ScreenshotSupport.captureLoupeZoom(4, adjustedBy: 1),
                    ScreenshotSupport.captureLoupeMaxZoom,
                    "zoom reaches the three-pixel sample without a dead range above it")
        expectClose(ScreenshotSupport.captureLoupeSampleSide(zoom: 2), 7,
                    "higher capture loupe zoom samples fewer source pixels")
        expectClose(ScreenshotSupport.captureLoupeSampleSide(zoom: 0.5), 27,
                    "zooming the loupe out widens the sample")
        expectClose(ScreenshotSupport.captureLoupeSampleSide(
            zoom: ScreenshotSupport.captureLoupeMaxZoom), 3,
                    "maximum loupe zoom keeps a three pixel sample around the pointer")
        expect([0.5, 1, 2, 4, ScreenshotSupport.captureLoupeMaxZoom].allSatisfy { zoom in
            let side = ScreenshotSupport.captureLoupeSampleSide(zoom: zoom)
            return side.truncatingRemainder(dividingBy: 2) == 1
        }, "every loupe sample side is odd so an exact center pixel exists")
        expect(ScreenshotSupport.captureLoupeGridVisible(
                    frameSide: ScreenshotSupport.captureLoupeFrameSide, sampleSide: 13)
                && !ScreenshotSupport.captureLoupeGridVisible(
                    frameSide: ScreenshotSupport.captureLoupeFrameSide, sampleSide: 27)
                && !ScreenshotSupport.captureLoupeGridVisible(
                    frameSide: ScreenshotSupport.captureLoupeFrameSide, sampleSide: 0),
               "the loupe pixel grid appears only when cells are readable")
        expect(ScreenshotSupport.captureLoupeNudge(dx: 1, dy: 0, fast: false, scale: 2)
                == CGPoint(x: 0.5, y: 0),
               "an arrow nudge moves exactly one device pixel on Retina")
        expect(ScreenshotSupport.captureLoupeNudge(dx: 0, dy: -1, fast: true, scale: 2)
                == CGPoint(x: 0, y: -5),
               "a shifted nudge covers ten device pixels")
        expect(ScreenshotSupport.captureLoupeNudge(dx: -1, dy: 1, fast: false, scale: 0)
                == CGPoint(x: -1, y: 1),
               "a missing display scale falls back to whole points")

        expect(Defaults.registeredDefaults[DefaultsKey.screenshotFreeze] as? Bool == true,
               "the screen freezes during selection by default")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotShortcutEnabled] as? Bool == false,
               "the screenshot shortcut ships off like the other quick tools")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotAnnotationShadows] as? Bool == false,
               "screenshot annotation shadows ship off")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotShowLastRegion] as? Bool == true,
               "the previous capture outline stays visible by default, as it always was")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotLoupeStartsOn] as? Bool == false,
               "the always-on loupe is an opt-in and ships off")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotLoupeRememberZoom] as? Bool == false
                && Defaults.registeredDefaults[DefaultsKey.screenshotLoupeDefaultZoom] as? Double == 1
                && Defaults.registeredDefaults[
                    DefaultsKey.screenshotLoupeSteppedZoomByDefault] as? Bool == false,
               "magnifier zoom preferences preserve the original behavior by default")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotToolShortcutsEnabled] as? Bool == true,
               "screenshot number shortcuts ship enabled")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotPreviewPosition] as? String == "",
               "screenshot preview placement preserves the existing automatic behavior by default")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotPreviewTakesFocus] as? Bool == false,
               "the screenshot preview leaves the keyboard where it was by default; taking it is the opt-in")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotSharingEnabled] as? Bool == true,
               "temporary screenshot links preserve their existing availability by default")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotToolOrder] as? String
                == ScreenshotSupport.Tool.defaultOrderStorage,
               "the screenshot rail ships in its useful numbered order")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotLastSticker] as? String == "check",
               "the sticker tool starts with a safe built-in choice")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotShortcut] as? String
                == "control+option+command:21",
               "the default screenshot shortcut is control option command 4")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotFullScreenShortcutEnabled]
                as? Bool == false,
               "the direct full-screen shortcut ships off")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotFullScreenShortcut] as? String
                == "control+option+command:20",
               "the full-screen shortcut sits beside screenshot selection")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotLastCaptureShortcutEnabled]
                as? Bool == false,
               "the latest screenshot editor shortcut ships off")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotLastCaptureShortcut] as? String
                == "control+option+command:14",
               "the latest screenshot editor shortcut defaults to control option command E")
        expect(Defaults.registeredDefaults[DefaultsKey.recentCapturesShortcutEnabled]
                as? Bool == false,
               "the recent captures shortcut ships off")
        expect(Defaults.registeredDefaults[DefaultsKey.recentCapturesShortcut] as? String
                == "control+option+command:4",
               "the recent captures shortcut defaults to control option command H")
        expect(ScreenshotShareDuration.allCases.map(\.rawValue) == [3_600, 21_600, 86_400],
               "temporary links allow only one, six or twenty-four hours")
        let testShareEndpoint = ScreenshotSharingSupport.endpoint(
            bundleIdentifier: ScreenshotSharingSupport.developerBundleIdentifier,
            developerOverride: "https://test.example/")
        expect(testShareEndpoint.absoluteString == "https://test.example"
                && ScreenshotSharingSupport.endpoint(
                    bundleIdentifier: "com.vorssaint.utils",
                    developerOverride: "https://test.example").absoluteString
                    == ScreenshotSharingSupport.productionEndpoint.absoluteString
                && ScreenshotSharingSupport.endpoint(
                    bundleIdentifier: ScreenshotSharingSupport.developerBundleIdentifier,
                    developerOverride: "http://test.example")
                    == ScreenshotSharingSupport.productionEndpoint,
               "only the Developer build accepts a valid HTTPS test endpoint")
        expect(ScreenshotSharingSupport.uploadURL(endpoint: testShareEndpoint,
                                                  duration: .sixHours)?.absoluteString
                == "https://test.example/v1/screenshots?expiresIn=21600",
               "sharing builds the fixed upload route and expiration query")
        let shareNow = Date(timeIntervalSince1970: 1_000)
        let shareResponse = ScreenshotShareResponse(
            id: String(repeating: "a", count: 32),
            viewPath: "/s/\(String(repeating: "a", count: 32))",
            expiresAt: "1970-01-01T01:16:40.125Z",
            deleteToken: String(repeating: "b", count: 43))
        expect(ScreenshotSharingSupport.record(response: shareResponse,
                                                endpoint: testShareEndpoint,
                                                now: shareNow)?.url.absoluteString
                == "https://test.example/s/\(String(repeating: "a", count: 32))",
               "a valid service response becomes an owner-held link record")
        let forgedShareResponse = ScreenshotShareResponse(
            id: "guessable",
            viewPath: "/s/guessable",
            expiresAt: "1970-01-01T01:16:40.125Z",
            deleteToken: "short")
        expect(ScreenshotSharingSupport.record(response: forgedShareResponse,
                                                endpoint: testShareEndpoint,
                                                now: shareNow) == nil,
               "guessable ids and short deletion tokens are rejected")
        expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityScreenshot] as? Bool == true,
               "the panel row ships visible like its siblings")
        let recentCaptureIDs = (0..<14).map { _ in UUID() }
        expect(ScreenshotSupport.cappedRecentCaptureIDs(recentCaptureIDs)
                == Array(recentCaptureIDs.prefix(12))
                && ScreenshotSupport.recentCaptureLimit == 12,
               "recent captures keeps only the newest bounded set")
        let oversizedCaptureIDs = Array(recentCaptureIDs.prefix(3))
        expect(ScreenshotSupport.cappedRecentCaptureIDs(
            oversizedCaptureIDs,
            screenshotBytes: [
                oversizedCaptureIDs[0]: ScreenshotSupport.recentCaptureMaximumBytes - 1,
                oversizedCaptureIDs[1]: 2,
            ]) == [oversizedCaptureIDs[0], oversizedCaptureIDs[2]],
               "recent captures keeps the latest screenshot and respects its disk budget")
        expect(GlobalShortcutRole.screenshot.requiredEnableKeys == [DefaultsKey.screenshotShortcutEnabled]
                && GlobalShortcutRole.screenshot.availabilityFeatures == [.screenshot],
               "the screenshot shortcut keeps its old keys and follows its own tool")
        expect(!GlobalShortcutRole.availableRoles(isAvailable: recordingOnly.contains)
                .contains(.screenshot)
                && GlobalShortcutRole.availableRoles(isAvailable: recordingOnly.contains)
                    .contains(.screenRecorder)
                && GlobalShortcutRole.availableRoles(isAvailable: recordingOnly.contains)
                    .contains(.recentCaptures),
               "a recording-only install keeps the recorder and shared capture history shortcuts")
        expect(GlobalShortcutRole.screenshotFullScreen.requiredEnableKeys
                == [DefaultsKey.screenshotFullScreenShortcutEnabled]
                && GlobalShortcutRole.screenshotFullScreen.feature == .screenshot,
               "the full-screen shortcut has its own opt-in gate")
        expect(GlobalShortcutRole.screenshotLastCapture.requiredEnableKeys
                == [DefaultsKey.screenshotLastCaptureShortcutEnabled]
                && GlobalShortcutRole.screenshotLastCapture.feature == .screenshot,
               "the latest screenshot shortcut gates on its own toggle and the screenshot feature")
        expect(GlobalShortcutRole.recentCaptures.requiredEnableKeys
                == [DefaultsKey.recentCapturesShortcutEnabled]
                && GlobalShortcutRole.recentCaptures.availabilityFeatures
                    == [.screenshot, .screenRecorder],
               "the recent captures shortcut follows either feature that fills its history")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotClipboardShortcutEnabled]
                as? Bool == false
                && Defaults.registeredDefaults[DefaultsKey.screenshotClipboardShortcut] as? String
                == "control+option+command:35",
               "the clipboard image editor shortcut ships off with its own combination")
        expect(GlobalShortcutRole.screenshotClipboard.requiredEnableKeys
                == [DefaultsKey.screenshotClipboardShortcutEnabled]
                && GlobalShortcutRole.screenshotClipboard.feature == .screenshot,
               "the clipboard image shortcut gates on its own toggle and the screenshot feature")
        expect(ScreenshotSupport.clipboardImageScale(
            pixelSize: CGSize(width: 1200, height: 800),
            pointSize: CGSize(width: 600, height: 400)) == 2,
               "copied images preserve a consistent Retina scale")
        expect(ScreenshotSupport.clipboardImageScale(
            pixelSize: CGSize(width: 1200, height: 800),
            pointSize: CGSize(width: 600, height: 800)) == 1,
               "copied images with inconsistent metadata safely use 1x")
    }

    static func runDedicatedShortcuts(expect: (Bool, String) -> Void) {
        // MARK: Capture tool shortcuts

        expect(ScreenCaptureTool.screenshot.dedicatedShortcut.role == .screenshot
                && ScreenCaptureTool.screenshot.dedicatedShortcut.enabledKey
                    == DefaultsKey.screenshotShortcutEnabled,
               "the screenshot tool keeps the old general shortcut's keys as its own")
        expect(ScreenCaptureTool.allCases.map { $0.dedicatedShortcut.role }
                == [.screenshot, .screenRecorder, .screenOCR, .colorPicker],
               "every capture tool owns a shortcut role, in tool order")
        // The keys a tool registers have to be the ones its settings row writes.
        // Three roles once had a row and no registrar, so the key was recorded
        // and the combination did nothing (issue #708).
        expect(ScreenCaptureTool.allCases.allSatisfy { tool in
                let keys = tool.dedicatedShortcut
                return keys.role.requiredEnableKeys == [keys.enabledKey]
                    && keys.role.feature == tool.feature
               },
               "a capture tool registers exactly the keys its own settings row reads")
        expect(GlobalShortcutRole.captureRoles(in: GlobalShortcutRole.allCases)
                == GlobalShortcutRole.captureDisplayOrder,
               "every role of a capture feature reaches the shortcuts page, in display order")
        expect(GlobalShortcutRole.captureRoles(in: [.colorPicker, .screenshot, .commandBar])
                == [.screenshot, .colorPicker],
               "capture roles are reordered for display and other roles fall away")
    }

    static func runShareExpiry(expect: (Bool, String) -> Void) {
        // MARK: A sleeping clock
        for shareService in ["Sources/Vorssaint/Services/QuickTools/ScreenshotShareService.swift",
                             "Sources/Vorssaint/Services/Recorder/RecordingShareService.swift"] {
            let shareCode = ((try? String(contentsOfFile: shareService, encoding: .utf8)) ?? "")
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            expect(shareCode.contains("NSWorkspace.didWakeNotification"),
                   "\(shareService) recomputes share link expiry on wake, which its sleeping clock missed")
        }
    }
}
