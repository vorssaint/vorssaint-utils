// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat

enum ScreenshotFeatureTests {
    static func run(_ suite: TestSuite) {
        let registrationDomain = UserDefaults.standard.volatileDomain(
            forName: UserDefaults.registrationDomain)
        defer {
            UserDefaults.standard.setVolatileDomain(registrationDomain,
                                                    forName: UserDefaults.registrationDomain)
        }

        let featureRuntimeSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/App/FeatureRuntime.swift",
            encoding: .utf8)) ?? ""
        let layoutDictionary = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary
        let layoutSources = (TISCreateInputSourceList(layoutDictionary, true)?.takeRetainedValue()
            as? [TISInputSource]) ?? []
        func testLayoutData(for idString: String) -> Data? {
            guard let source = layoutSources.first(where: {
                guard let identifier = TISGetInputSourceProperty($0, kTISPropertyInputSourceID)
                else { return false }
                return Unmanaged<CFString>.fromOpaque(identifier).takeUnretainedValue() as String
                    == idString
            }), let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else { return nil }
            return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        }

        // MARK: Screenshot tool

        let ownScreenshotWindows: Set<CGWindowID> = [11, 12, 13]
        let protectedScreenshotWindows: Set<CGWindowID> = [12, 99]
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotHideVorssaintWindows]
                as? Bool == true,
               "screenshots hide Vorssaint windows by default")
        suite.expect(SettingsBackupSupport.exportKeys().contains(
            DefaultsKey.screenshotHideVorssaintWindows),
               "the screenshot window visibility preference travels in backups")
        // An editor or a pinned capture is an ordinary window, so the
        // visibility preference has to reach it; the overlays and HUDs taking
        // the capture stay out either way (issue #780).
        let workflowWindows: Set<CGWindowID> = [12]
        let contentWindows: Set<CGWindowID> = [11, 13]
        suite.expect(ScreenshotCapturePolicy.protectedWindowIDs(
            workflowWindowIDs: workflowWindows,
            contentWindowIDs: contentWindows,
            honoursVisibilityPreference: true
        ) == workflowWindows,
        "a screenshot protects only the surfaces taking it")
        suite.expect(ScreenshotCapturePolicy.protectedWindowIDs(
            workflowWindowIDs: workflowWindows,
            contentWindowIDs: contentWindows,
            honoursVisibilityPreference: false
        ) == ownScreenshotWindows,
        "a recording is exempt from the preference and protects both kinds")
        suite.expect(ScreenshotCapturePolicy.excludedWindowIDs(
            hideVorssaintWindows: false,
            ownWindowIDs: ownScreenshotWindows,
            protectedWindowIDs: ScreenshotCapturePolicy.protectedWindowIDs(
                workflowWindowIDs: workflowWindows,
                contentWindowIDs: contentWindows,
                honoursVisibilityPreference: true)
        ) == workflowWindows,
        "showing Vorssaint windows leaves an editor and a pin in the capture")
        suite.expect(ScreenshotCapturePolicy.canPickWindow(
            13,
            isOwnWindow: true,
            hideVorssaintWindows: false,
            protectedWindowIDs: ScreenshotCapturePolicy.protectedWindowIDs(
                workflowWindowIDs: workflowWindows,
                contentWindowIDs: contentWindows,
                honoursVisibilityPreference: true)
        ), "a pinned capture can be picked while Vorssaint windows are shown")
        suite.expect(ScreenshotCapturePolicy.excludedWindowIDs(
            hideVorssaintWindows: true,
            ownWindowIDs: ownScreenshotWindows,
            protectedWindowIDs: protectedScreenshotWindows
        ) == ownScreenshotWindows,
        "screenshot hiding Vorssaint excludes every own window")
        suite.expect(ScreenshotCapturePolicy.excludedWindowIDs(
            hideVorssaintWindows: false,
            ownWindowIDs: ownScreenshotWindows,
            protectedWindowIDs: protectedScreenshotWindows
        ) == [12],
        "screenshot keeps protected windows excluded while Vorssaint is visible")
        suite.expect(ScreenshotCapturePolicy.canPickWindow(
            7,
            isOwnWindow: false,
            hideVorssaintWindows: true,
            protectedWindowIDs: protectedScreenshotWindows
        ), "screenshot can always pick an ordinary external window")
        suite.expect(!ScreenshotCapturePolicy.canPickWindow(
            11,
            isOwnWindow: true,
            hideVorssaintWindows: true,
            protectedWindowIDs: protectedScreenshotWindows
        ), "screenshot cannot pick a Vorssaint window while hiding them")
        suite.expect(ScreenshotCapturePolicy.canPickWindow(
            11,
            isOwnWindow: true,
            hideVorssaintWindows: false,
            protectedWindowIDs: protectedScreenshotWindows
        ), "screenshot can pick an ordinary Vorssaint window when visible")
        suite.expect(!ScreenshotCapturePolicy.canPickWindow(
            12,
            isOwnWindow: true,
            hideVorssaintWindows: false,
            protectedWindowIDs: protectedScreenshotWindows
        ), "screenshot cannot pick its own protected capture UI")

        // Another process can draw a border around a window as a window of its
        // own; clicking there has to capture the window it surrounds.
        let framed = ScreenshotCapturePolicy.CaptureWindow(
            id: 81, ownerPID: 500, frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let decoration = ScreenshotCapturePolicy.CaptureWindow(
            id: 80, ownerPID: 700, frame: framed.frame.insetBy(dx: -12, dy: -12), isUntitled: true)
        suite.expect(ScreenshotCapturePolicy.decorationWindowIDs(frontToBack: [decoration, framed]) == [80]
                     && ScreenshotCapturePolicy.decorationWindowIDs(frontToBack: [framed, decoration]) == [80],
                     "a border drawn around a window by another process is never the picked window")
        let between = ScreenshotCapturePolicy.CaptureWindow(
            id: 90, ownerPID: 800, frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        suite.expect(ScreenshotCapturePolicy.decorationWindowIDs(frontToBack: [decoration, between, framed]).isEmpty,
                     "a border only frames the window right next to it in the stack")
        let ordinary: [ScreenshotCapturePolicy.CaptureWindow] = [
            .init(id: 82, ownerPID: 600, frame: framed.frame.insetBy(dx: -16, dy: -16)),
            .init(id: 83, ownerPID: 600, frame: framed.frame, isUntitled: true),
            .init(id: 84, ownerPID: 600, frame: CGRect(x: 90, y: 80, width: 830, height: 640), isUntitled: true),
            .init(id: 85, ownerPID: 600, frame: framed.frame.insetBy(dx: -40, dy: -40), isUntitled: true),
            .init(id: 86, ownerPID: 500, frame: framed.frame.insetBy(dx: -12, dy: -12), isUntitled: true),
        ]
        for window in ordinary {
            suite.expect(ScreenshotCapturePolicy.decorationWindowIDs(frontToBack: [window, framed]).isEmpty
                         && ScreenshotCapturePolicy.decorationWindowIDs(frontToBack: [framed, window]).isEmpty,
                         "a titled, equal, uneven, distant or same-app window stays pickable (\(window.id))")
        }

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
        func attachedCoverage(windowAt origin: CGPoint) -> ScreenshotSupport.AlphaCoverage {
            var alpha = [UInt8](repeating: 0, count: 40 * 20)
            for row in Int(origin.y)..<Int(origin.y) + 6 {
                for column in Int(origin.x)..<Int(origin.x) + 8 { alpha[row * 40 + column] = 255 }
            }
            return ScreenshotSupport.AlphaCoverage(alpha: alpha, width: 40, height: 20)
        }
        let placedWindow = CGRect(x: 20, y: 10, width: 8, height: 6)
        let packedWindow = CGRect(x: 0, y: 0, width: 8, height: 6)
        suite.expect(ScreenshotSupport.attachedCaptureCrop(
            placed: placedWindow, packed: packedWindow,
            coverage: attachedCoverage(windowAt: CGPoint(x: 20, y: 10))) == placedWindow,
               "a window drawn where it sits on the display is cropped there")
        suite.expect(ScreenshotSupport.attachedCaptureCrop(
            placed: placedWindow, packed: packedWindow,
            coverage: attachedCoverage(windowAt: .zero)) == packedWindow,
               "windows packed into the corner of the capture are cropped whole, not as a slice")
        suite.expect(ScreenshotSupport.attachedCaptureCrop(
            placed: CGRect(x: 4, y: 2, width: 8, height: 6), packed: packedWindow,
            coverage: attachedCoverage(windowAt: CGPoint(x: 4, y: 2))) == CGRect(x: 4, y: 2, width: 8, height: 6),
               "an overlapping placement still follows where the window was drawn")
        suite.expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [sheet, capturedWindow])
            == ScreenshotCapturePolicy.AttachedCapturePlan(
                windowIDs: [1, 2], bounds: capturedWindow.frame),
               "a sheet on the clicked window joins its capture, the window drawn first")
        suite.expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [capturedWindow, sheet]) == nil,
               "a window behind the clicked one is not stacked on it")
        let windowOfAnotherApp = CaptureWindow(
            id: 3, ownerPID: 900, frame: CGRect(x: 300, y: 100, width: 400, height: 300))
        suite.expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [windowOfAnotherApp, capturedWindow]) == nil,
               "another application's window over the clicked one stays out of the shot")
        // The case that decides the rule: a compose or second document window
        // of the same app, in front and overlapping, but reaching past the
        // edge. It is not what was asked for, so the ordinary capture answers.
        let composeWindow = CaptureWindow(
            id: 4, ownerPID: 500, frame: CGRect(x: 700, y: 300, width: 500, height: 400))
        suite.expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [composeWindow, capturedWindow]) == nil,
               "a same-app window reaching past the clicked window is not drawn into its shot")
        let detachedWindow = CaptureWindow(
            id: 5, ownerPID: 500, frame: CGRect(x: 2_000, y: 100, width: 200, height: 200))
        suite.expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [detachedWindow, capturedWindow]) == nil,
               "a window of the same app that does not touch the clicked one is not attached")
        suite.expect(ScreenshotCapturePolicy.attachedCapturePlan(
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
        suite.expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [fullWidthSheet, capturedWindow])?.windowIDs
            == [1, 6],
               "a sheet the full width of its window still joins the capture")
        // Two stacked windows are drawn in the order they are shown.
        suite.expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow,
            frontToBack: [sheet, fullWidthSheet, capturedWindow])?.windowIDs == [1, 6, 2],
               "what is stacked on the window is drawn back to front")
        // A target the list does not hold cannot have anything in front of it.
        suite.expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [sheet]) == nil,
               "a window missing from the list does not treat everything as stacked on it")
        suite.expect(captureEngineSource.contains("$0.frame.intersects(plan.bounds)")
                && captureEngineSource.contains("hits.count == 1")
                && !captureEngineSource.contains(".contains(plan.bounds)"),
               "a window straddling two displays falls back to the single-window capture instead of a one-display slice")

        let geometricAttachment = ScreenshotCapturePolicy.AttachedCapturePlan(
            windowIDs: [1, 6, 2], bounds: capturedWindow.frame)
        suite.expect(ScreenshotCapturePolicy.confirmedAttachment(
            geometricAttachment, confirmedIDs: nil) == geometricAttachment,
               "missing Accessibility confirmation leaves the geometric attachment unchanged")
        suite.expect(ScreenshotCapturePolicy.confirmedAttachment(
            geometricAttachment, confirmedIDs: [2])
            == ScreenshotCapturePolicy.AttachedCapturePlan(
                windowIDs: [1, 2], bounds: capturedWindow.frame),
               "Accessibility confirmation keeps its matching attachment in capture order")
        suite.expect(ScreenshotCapturePolicy.confirmedAttachment(
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
        suite.expect(accessibilityGate != nil && attachmentConfirmation != nil
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
        suite.expect(unresolvedCandidatePasses != nil && standardWindowFails != nil && childrenPassIsAbsent,
               "AX keeps unresolved candidates and excludes only identified standard windows")

        suite.expect(ScreenshotSupport.sanitizedDelay(5) == 5
                && ScreenshotSupport.sanitizedDelay(7) == 0
                && ScreenshotSupport.sanitizedDelay(-3) == 0,
               "capture delay only accepts the offered steps")
        suite.expect(ScreenshotSupport.scrollingCaptureMaximumDuration == 120
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
        suite.expect(forwardScrollTransition
                == .advanced(overlap: 44,
                             direction: .forward,
                             contentColumns: 0..<16),
               "scrolling screenshots find the exact shared rows deterministically: \(forwardScrollTransition)")
        let backwardScrollTransition = ScreenshotSupport.scrollingTransition(
            previous: nextScrollSample,
            current: firstScrollSample)
        suite.expect(backwardScrollTransition
                == .advanced(overlap: 44,
                             direction: .backward,
                             contentColumns: 0..<16),
               "scrolling screenshots identify backward movement without duplicating it: \(backwardScrollTransition)")
        suite.expect(ScreenshotSupport.scrollingTransition(previous: nextScrollSample,
                                                     current: nextScrollSample) == .end,
               "an unchanged capture marks the real end of scrolling")
        suite.expect(ScreenshotSupport.scrollingSamplesAreStable(nextScrollSample,
                                                           nextScrollSample),
               "settling recognizes two unchanged scrolling frames")
        let shortFinalScrollSample = scrollingSample(offset: 8)
        suite.expect(ScreenshotSupport.scrollingTransition(previous: firstScrollSample,
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
        suite.expect(ScreenshotSupport.scrollingTransition(
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
        suite.expect(ScreenshotSupport.scrollingTransition(previous: fixedBottomStart,
                                                     current: fixedBottomNext)
                == .advanced(overlap: 78,
                             direction: .forward,
                             contentColumns: 0..<16),
               "a fixed footer does not hide the moving page overlap")
        suite.expect(ScreenshotSupport.scrollingFixedBottomRows(
            previous: fixedBottomStart,
            current: fixedBottomNext,
            overlap: 78,
            contentColumns: 0..<16) == 18,
               "scrolling capture identifies a fixed footer at the bottom edge")
        suite.expect(ScreenshotSupport.scrollingFixedBottomRows(
            previous: firstScrollSample,
            current: scrollingSample(offset: 42),
            overlap: 78,
            contentColumns: 0..<16) == 0,
               "ordinary moving content is never mistaken for a fixed footer")
        suite.expect(ScreenshotSupport.scrollingNewContentRows(
            imageHeight: 120,
            overlap: 78,
            fixedBottomRows: 18) == 60..<102,
               "new scrolling pixels move above the fixed footer instead of copying it")
        suite.expect(ScreenshotSupport.scrollingNewContentRows(
            imageHeight: 120,
            overlap: 78,
            fixedBottomRows: 0) == 78..<120,
               "captures without a fixed footer keep the original crop geometry")
        // Each input is independent: repeating the same pure call adds no case.
        for offset in [8, 76] {
            let transition = ScreenshotSupport.scrollingTransition(
                previous: firstScrollSample,
                current: scrollingSample(offset: offset))
            suite.expect(transition == .advanced(overlap: 120 - offset,
                                            direction: .forward,
                                            contentColumns: 0..<16),
                   "scroll matching handles an advance of \(offset) rows: \(transition)")
        }
        let retinaScrollStart = scrollingSample(width: 32, height: 900, offset: 0)
        let retinaScrollNext = scrollingSample(width: 32, height: 900, offset: 558)
        suite.expect(ScreenshotSupport.scrollingTransition(previous: retinaScrollStart,
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
        suite.expect(ScreenshotSupport.scrollingTransition(previous: fixedColumnsStart,
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
        suite.expect(changedColumnsTransition
                == .advanced(overlap: 78,
                             direction: .forward,
                             contentColumns: 6..<18),
               "scroll matching survives a changed block inside moving content: \(changedColumnsTransition)")
        suite.expect(ScreenshotSupport.scrollingPixelRange(sampleColumns: 6..<18,
                                                     sampleWidth: 24,
                                                     imageWidth: 1_920) == 480..<1_440,
               "the moving sample columns map back to the exact captured pixels")
        var unmatchedScrollPixels = [UInt8](repeating: 0, count: 16 * 120)
        for index in unmatchedScrollPixels.indices {
            unmatchedScrollPixels[index] = UInt8((index * 47 + index / 11) % 253)
        }
        let unmatchedScrollSample = ScreenshotSupport.ScrollingSample(
            width: 16, height: 120, pixels: unmatchedScrollPixels)
        suite.expect(ScreenshotSupport.scrollingTransition(previous: firstScrollSample,
                                                     current: unmatchedScrollSample) == .unmatched,
               "ambiguous content fails instead of inventing a seam")
        suite.expectClose(Double(ScreenshotSupport.captureScale(fromDPI: 144) ?? 0), 2,
                    "the cached screenshot restores its Retina scale from PNG metadata")
        suite.expect(ScreenshotSupport.captureScale(fromDPI: nil) == nil
                && ScreenshotSupport.captureScale(fromDPI: 0) == nil
                && ScreenshotSupport.captureScale(fromDPI: .infinity) == nil,
               "missing or broken PNG scale metadata never opens a misleading capture")

        let dragRect = ScreenshotSupport.selectionRect(from: CGPoint(x: 100, y: 80),
                                                       to: CGPoint(x: 40, y: 200))
        suite.expect(dragRect == CGRect(x: 40, y: 80, width: 60, height: 120),
               "a drag in any direction normalizes to a positive rect")
        let squareRect = ScreenshotSupport.selectionRect(from: CGPoint(x: 10, y: 10),
                                                         to: CGPoint(x: 40, y: 90),
                                                         square: true)
        suite.expect(squareRect.width == squareRect.height && squareRect.width == 80,
               "shift constrains the selection to a square")
        let centered = ScreenshotSupport.selectionRect(from: CGPoint(x: 50, y: 50),
                                                       to: CGPoint(x: 70, y: 60),
                                                       fromCenter: true)
        suite.expect(centered == CGRect(x: 30, y: 40, width: 40, height: 20),
               "option grows the selection from the center")
        let cropBounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let cropDraft = CGRect(x: 120, y: 90, width: 400, height: 300)
        suite.expect(ScreenshotSupport.startsNewCropSelection(
                    at: CGPoint(x: 300, y: 250), draft: cropBounds, within: cropBounds),
               "dragging inside the initial full-image crop starts a new selection")
        suite.expect(!ScreenshotSupport.startsNewCropSelection(
                    at: CGPoint(x: 300, y: 250), draft: cropDraft, within: cropBounds),
               "dragging inside an adjusted crop keeps moving it")
        suite.expect(ScreenshotSupport.startsNewCropSelection(
                    at: CGPoint(x: 700, y: 500), draft: cropDraft, within: cropBounds),
               "dragging elsewhere in the image replaces an adjusted crop")
        suite.expect(!ScreenshotSupport.startsNewCropSelection(
                    at: CGPoint(x: 900, y: 700), draft: cropDraft, within: cropBounds),
               "a drag outside the image cannot start a crop")
        suite.expect(ScreenshotSupport.isClick(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 7, y: 8))
                && !ScreenshotSupport.isClick(from: .zero, to: CGPoint(x: 12, y: 0)),
               "a tiny drag is a click, a real drag is not")

        // The crop chrome, the loupe cross and the image applyCrop produces are
        // three drawings of one edge. They agree only while pixelSnappedCropRect
        // is the single thing deciding where that edge is.
        let snapBounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let looseDraft = CGRect(x: 100.4, y: 60.4, width: 100, height: 100)
        let snappedDraft = ScreenshotSupport.pixelSnappedCropRect(looseDraft, within: snapBounds)
        suite.expect(snappedDraft == CGRect(x: 100, y: 60, width: 100, height: 100),
               "a crop draft rounds each edge to the nearest pixel boundary")
        suite.expect(snappedDraft.maxX == 200,
               "a crop draft does not grow outward the way CGRect.integral would")
        suite.expect(ScreenshotSupport.pixelSnappedCropRect(snappedDraft, within: snapBounds)
                == snappedDraft,
               "snapping a crop draft that already sits on pixels changes nothing")
        suite.expect(ScreenshotSupport.pixelSnappedCropRect(
                    CGRect(x: 100.4, y: 60.4, width: 100.2, height: 100.2), within: snapBounds)
                == CGRect(x: 100, y: 60, width: 101, height: 101),
               "a crop edge past the halfway mark rounds to the next boundary")
        let movedDraft = ScreenshotSupport.pixelSnappedCropRect(
            ScreenshotSupport.movedRect(snappedDraft,
                                        by: CGPoint(x: 12.6, y: -4.3),
                                        within: snapBounds),
            within: snapBounds)
        suite.expect(movedDraft.size == snappedDraft.size,
               "moving a crop draft never changes its size")
        suite.expect(ScreenshotSupport.pixelSnappedCropRect(
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
        suite.expect(snappedSample.midX == snappedEdge.x && snappedSample.midY == snappedEdge.y,
               "the crop loupe centres on the edge it marks once the draft sits on pixels")
        let looseEdge = ScreenshotSupport.Handle.left.position(in: looseDraft)
        let looseSample = ScreenshotSupport.cropLoupeSampleRect(around: looseEdge,
                                                                imageSize: snapImageSize,
                                                                sideLength: 14,
                                                                centredOnPixel: false)
        suite.expect(looseSample.midX != looseEdge.x,
               "an even sample side alone does not centre a fractional crop edge")

        var patternParts = DateComponents()
        patternParts.year = 2026
        patternParts.month = 7
        patternParts.day = 24
        patternParts.hour = 15
        patternParts.minute = 4
        patternParts.second = 9
        if let patternDate = Calendar(identifier: .gregorian).date(from: patternParts) {
            suite.expect(ScreenshotSupport.expandSaveSubfolder("%y-%mo", date: patternDate) == "26-07",
                   "short date tokens expand zero padded")
            suite.expect(ScreenshotSupport.expandSaveSubfolder("%year/%month", date: patternDate)
                   == "2026/July",
                   "long date tokens expand before their short prefixes and nest with slashes")
            suite.expect(ScreenshotSupport.expandSaveSubfolder("", date: patternDate) == "",
                   "an empty subfolder pattern means no subfolder")
            suite.expect(ScreenshotSupport.expandSaveSubfolder("../up//./%y", date: patternDate)
                   == "up/26",
                   "dot, dot-dot and empty components never escape the base folder")
            suite.expect(ScreenshotSupport.expandFileNamePattern("Shot %d at %h.%mi.%s",
                                                           date: patternDate, number: 0)
                   == "Shot 24 at 15.04.09",
                   "file name patterns expand the day and time tokens")
            suite.expect(ScreenshotSupport.expandFileNamePattern("Shot-%#", date: patternDate, number: 7)
                   == "Shot-7",
                   "a single number token renders the sequence unpadded")
            suite.expect(ScreenshotSupport.expandFileNamePattern("%###-%y", date: patternDate, number: 7)
                   == "007-26",
                   "a longer number token zero pads to its length")
            suite.expect(ScreenshotSupport.fileNamePatternUsesNumber("Shot-%#")
                    && !ScreenshotSupport.fileNamePatternUsesNumber("Shot-%y"),
                   "only patterns with the number token consume the sequence")
            suite.expect(ScreenshotSupport.expandFileNamePattern("a/b %h:%mi", date: patternDate, number: 0)
                   == "a-b 15-04",
                   "slashes and colons in a file name pattern become dashes")
        } else {
            suite.expect(false, "gregorian calendar produced the fixed pattern date")
        }

        let cornerFrame = ScreenshotSupport.quickPreviewFrame(
            size: CGSize(width: 310, height: 210),
            anchor: .zero,
            pointer: .zero,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            position: .bottomRight)
        suite.expect(cornerFrame == CGRect(x: 1114, y: 16, width: 310, height: 210),
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
        suite.expect(configuredPreviewFrame(.topLeft)
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
        suite.expect(ScreenshotSupport.quickPreviewVisibleFrame(
            anchor: CGRect(x: -900, y: 200, width: 500, height: 400),
            pointer: CGPoint(x: -500, y: 300),
            screens: previewScreens,
            fallback: .zero) == previewScreens[0].visibleFrame,
               "a capture uses the visible frame of its display in a three-display layout")
        suite.expect(ScreenshotSupport.quickPreviewVisibleFrame(
            anchor: CGRect(x: 1300, y: 500, width: 500, height: 500),
            pointer: CGPoint(x: 1700, y: 650),
            screens: previewScreens,
            fallback: .zero) == previewScreens[2].visibleFrame,
               "a capture crossing displays uses the screen containing most of it")
        suite.expect(ScreenshotSupport.quickPreviewVisibleFrame(
            anchor: CGRect(x: 5000, y: 5000, width: 400, height: 300),
            pointer: CGPoint(x: 700, y: 500),
            screens: previewScreens,
            fallback: .zero) == previewScreens[1].visibleFrame,
               "a disconnected capture display falls back to the current pointer display")
        // AppKit reports the pointer on a display's top row at frame.maxY.
        suite.expect(ScreenshotSupport.quickPreviewVisibleFrame(
            anchor: CGRect(x: 5000, y: 5000, width: 400, height: 300),
            pointer: CGPoint(x: 2000, y: 1324),
            screens: previewScreens,
            fallback: .zero) == previewScreens[2].visibleFrame,
               "a disconnected capture display falls back to the display whose top row holds the pointer")
        let stackedScreens = [
            (frame: CGRect(x: 0, y: 900, width: 1440, height: 900),
             visibleFrame: CGRect(x: 0, y: 900, width: 1440, height: 875)),
            (frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
             visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)),
        ]
        for screens in [stackedScreens, Array(stackedScreens.reversed())] {
            suite.expect(ScreenshotSupport.quickPreviewVisibleFrame(
                anchor: CGRect(x: 100, y: 800, width: 400, height: 200),
                pointer: CGPoint(x: 300, y: 900),
                screens: screens,
                fallback: .zero) == stackedScreens[1].visibleFrame,
                   "an even split across stacked displays goes to the lower one when its top row holds the pointer")
        }
        suite.expect(ScreenshotSupport.QuickPreviewPosition.allCases.map(\.rawValue)
                == ["", "topLeft", "topRight", "bottomLeft", "bottomRight"]
                && ScreenshotSupport.QuickPreviewPosition(rawValue: "bogus") == nil,
               "preview positions keep stable storage values and reject unknown values")
        suite.expect(ScreenshotDefaultAction(rawValue: "") == ScreenshotDefaultAction.none
                && ScreenshotDefaultAction(rawValue: "saveAndCopy") == .saveAndCopy
                && ScreenshotDefaultAction(rawValue: "bogus") == nil,
               "after-capture actions decode from their stored raw values")

        // A gesture that ends with more than one release, like a drag made
        // with three fingers, delivers events after the capture is over.
        suite.expect(ScreenshotSupport.selectionAcceptsPointerInput(sessionIsOver: false,
                                                              capturePending: false),
               "a live selection answers the pointer")
        suite.expect(!ScreenshotSupport.selectionAcceptsPointerInput(sessionIsOver: true,
                                                               capturePending: false),
               "a session that is over ignores the tail of a gesture")
        suite.expect(!ScreenshotSupport.selectionAcceptsPointerInput(sessionIsOver: false,
                                                               capturePending: true),
               "a capture already on its way ignores further pointer input")
        suite.expect(!ScreenshotSupport.selectionAcceptsPointerInput(sessionIsOver: true,
                                                               capturePending: true),
               "both at once still ignores the pointer")
        let captureMenuSuite = "com.vorssaint.tests.capture-menu.\(UUID().uuidString)"
        let captureMenuDefaults = UserDefaults(suiteName: captureMenuSuite)!
        defer { captureMenuDefaults.removePersistentDomain(forName: captureMenuSuite) }
        for tool in ScreenCaptureTool.allCases {
            suite.expect(tool.showsCaptureMenu(fromShortcut: true, defaults: captureMenuDefaults),
                   "an existing install keeps the capture menu for \(tool)")
            suite.expect(Defaults.registeredDefaults[tool.showCaptureMenuOnShortcutKey] as? Bool == true
                    && SettingsBackupSupport.exportKeys().contains(tool.showCaptureMenuOnShortcutKey),
                   "capture menu preferences default on and travel with settings backups")
        }
        captureMenuDefaults.register(defaults: Defaults.registeredDefaults)
        for hiddenTool in ScreenCaptureTool.allCases {
            captureMenuDefaults.set(false, forKey: hiddenTool.showCaptureMenuOnShortcutKey)
            let reopenedDefaults = UserDefaults(suiteName: captureMenuSuite)!
            for tool in ScreenCaptureTool.allCases {
                suite.expect(tool.showsCaptureMenu(fromShortcut: true, defaults: reopenedDefaults)
                        == (tool != hiddenTool),
                       "hiding the menu for \(hiddenTool) persists without changing \(tool)'s preference")
                suite.expect(tool.showsCaptureMenu(fromShortcut: false, defaults: reopenedDefaults),
                       "buttons still open the capture menu even when a shortcut hides it")
            }
            captureMenuDefaults.set(true, forKey: hiddenTool.showCaptureMenuOnShortcutKey)
            suite.expect(hiddenTool.showsCaptureMenu(fromShortcut: true, defaults: captureMenuDefaults),
                   "turning the setting back on restores the shortcut menu")
        }
        let recordingOnly: Set<AppFeature> = [.screenRecorder]
        suite.expect(ScreenCaptureTool.available(isAvailable: recordingOnly.contains) == [.recording],
               "the capture chooser hides every uninstalled mode")
        let captureFeatures: Set<AppFeature> = [.screenshot, .screenRecorder,
                                                .screenOCR, .colorPicker]
        suite.expect(ScreenCaptureTool.available(isAvailable: captureFeatures.contains)
                == [.screenshot, .recording, .text, .color],
               "the capture chooser keeps a stable order for every installed mode")
        let captureSettingsSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/ScreenCaptureSettings.swift",
            encoding: .utf8)) ?? ""
        suite.expect(captureSettingsSource.contains("selectedTool")
                && captureSettingsSource.contains("ScreenCaptureToolPicker(tools: availableTools")
                && captureSettingsSource.contains("ToolShortcutRows(tool: currentTool")
                && captureSettingsSource.contains("RecentCapturesShortcutRows()"),
               "the capture page keeps tool and shared-history shortcuts in the top section")
        let recentCaptureServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/RecentCaptureService.swift",
            encoding: .utf8)) ?? ""
        suite.expect(recentCaptureServiceSource.contains("QuickToolHotkey(id: 21)")
                && recentCaptureServiceSource.contains(
                    "hotkey.onPress = { [weak self] in self?.showHistoryWindow() }")
                && featureRuntimeSource.components(separatedBy:
                    "RecentCaptureService.shared.syncWithPreferences()").count == 3,
               "the history shortcut opens its window and follows both capture producers")
        let recentCapturePaletteCode = recentCaptureServiceSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(recentCapturePaletteCode.contains("panel.hidesOnDeactivate = false")
                && !recentCapturePaletteCode.contains("hidesOnDeactivate = true")
                && recentCapturePaletteCode.contains("NSWorkspace.didActivateApplicationNotification")
                && !recentCapturePaletteCode.contains("NSApplication.didResignActiveNotification")
                && recentCapturePaletteCode.contains(
                    "NSWorkspace.shared.notificationCenter.removeObserver("),
               "a recent captures palette appears promptly and leaves when another app activates")
        suite.expect(!ScreenshotSupport.captureAvailabilityChanged(
                    activeTools: [.screenshot, .recording],
                    availableTools: [.screenshot, .recording])
                && ScreenshotSupport.captureAvailabilityChanged(
                    activeTools: [.screenshot, .recording],
                    availableTools: [.recording])
                && ScreenshotSupport.captureAvailabilityChanged(
                    activeTools: [.screenshot],
                    availableTools: [.screenshot, .text]),
               "capture countdowns and selectors end whenever installed modes change")
        suite.expect(ScreenshotSupport.captureRouteIsAuthorized(
                    selected: .screenshot,
                    isAvailable: { $0 == .screenshot })
                && !ScreenshotSupport.captureRouteIsAuthorized(
                    selected: .screenshot,
                    isAvailable: { _ in false }),
               "a capture result is routed only while its selected feature remains installed")
        suite.expect(ScreenCaptureTool.allCases.map(\.shortcutKey) == ["1", "2", "3", "4"]
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
        suite.expect(liveScreenshotPolicy == .init(freeze: false, includePointer: true,
                                             hideVorssaintWindows: true,
                                             keepsContentWindowsOut: true,
                                             usesGeometry: false)
                && recorderPolicy == .init(freeze: true, includePointer: false,
                                           hideVorssaintWindows: false,
                                           keepsContentWindowsOut: true,
                                           usesGeometry: true)
                && textPolicy == .init(freeze: true, includePointer: false,
                                       hideVorssaintWindows: true,
                                       keepsContentWindowsOut: true,
                                       usesGeometry: false),
               "switching capture mode rebuilds the frozen frame, pointer and window policy")
        let colorPolicy = ScreenshotSupport.unifiedCapturePolicy(
            for: .color,
            screenshotFreeze: false,
            screenshotIncludePointer: true,
            screenshotHideVorssaintWindows: true)
        suite.expect(textPolicy.sharesSource(with: colorPolicy)
                && !textPolicy.sharesSource(with: recorderPolicy)
                && !textPolicy.sharesSource(with: liveScreenshotPolicy),
               "only freeze, pointer and window policy decide whether a mode needs its own photograph")
        // With "Hide Vorssaint windows" off, freeze on and the pointer off,
        // every tool wants the same pixels except for the editors and pins
        // recording keeps out, so switching to or from recording has to
        // re-photograph and re-list the pickable windows (issue #780).
        let shownWindowPolicies = Dictionary(uniqueKeysWithValues: ScreenCaptureTool.allCases.map {
            ($0, ScreenshotSupport.unifiedCapturePolicy(
                for: $0,
                screenshotFreeze: true,
                screenshotIncludePointer: false,
                screenshotHideVorssaintWindows: false))
        })
        suite.expect(shownWindowPolicies[.recording]?.keepsContentWindowsOut == true
                && shownWindowPolicies[.screenshot]?.keepsContentWindowsOut == false
                && shownWindowPolicies[.text]?.keepsContentWindowsOut == false
                && shownWindowPolicies[.color]?.keepsContentWindowsOut == false,
               "only recording keeps editors and pins out while Vorssaint windows are shown")
        suite.expect(shownWindowPolicies[.recording].map { recording in
            [ScreenCaptureTool.screenshot, .text, .color].allSatisfy { tool in
                guard let other = shownWindowPolicies[tool] else { return false }
                return !recording.sharesSource(with: other) && !other.sharesSource(with: recording)
            }
        } == true,
               "switching between recording and screenshot, text or color refreshes the picture and pickable windows both ways")
        suite.expect(shownWindowPolicies[.screenshot].map { screenshot in
            [ScreenCaptureTool.text, .color].allSatisfy {
                shownWindowPolicies[$0].map(screenshot.sharesSource(with:)) == true
            }
        } == true,
               "tools that show the same windows keep the picture they already have")
        let hiddenWindowPolicies = ScreenCaptureTool.allCases.map {
            ScreenshotSupport.unifiedCapturePolicy(
                for: $0,
                screenshotFreeze: true,
                screenshotIncludePointer: false,
                screenshotHideVorssaintWindows: true)
        }
        suite.expect(hiddenWindowPolicies.allSatisfy(\.keepsContentWindowsOut),
               "hiding Vorssaint windows keeps editors and pins out of every tool")
        suite.expect(ScreenshotSupport.captureGuideIsVisible(pointerOnDisplay: true,
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
        suite.expect(ScreenshotSupport.offersRepeatLastRegion(isPickingColor: false,
                                                        storedRegionDisplayIsAvailable: true),
               "the repeat hint is offered once a region is stored on a display still in the session")
        suite.expect(!ScreenshotSupport.offersRepeatLastRegion(isPickingColor: false,
                                                         storedRegionDisplayIsAvailable: false),
               "no repeat hint before the first capture, or when its display is gone")
        suite.expect(!ScreenshotSupport.offersRepeatLastRegion(isPickingColor: true,
                                                         storedRegionDisplayIsAvailable: true),
               "the colour picker has no region to repeat, matching repeatLastRegion's own guard")
        let captureSelectionSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift",
            encoding: .utf8)) ?? ""
        suite.expect(captureSelectionSource.contains(
            "override func mouseExited(with event: NSEvent) {\n        refreshPointerState()\n        refreshGuideVisibility()"),
               "system chrome cannot hide the capture chooser while the pointer remains on its display")
        suite.expect(captureSelectionSource.contains(
            "screenCaptureOptions?.showsCaptureMenu == false ? 82 : 146")
                && captureSelectionSource.contains(
                    ".opacity(options.selectedTool == .recording ? 1 : 0)"),
               "capture modes reserve the recording controls' height so the chooser never jumps")
        suite.expect(captureSelectionSource.contains("screenCaptureToolDidChange()")
                && captureSelectionSource.contains("!nextPolicy.sharesSource(with: capturePolicy)")
                && captureSelectionSource.contains("adoptCapturePolicy(nextPolicy)")
                && captureSelectionSource.contains("panel.update(frozenImage:")
                && captureSelectionSource.contains("screenCaptureOptions?.onSelectionChange ="),
               "a capture mode that needs other pixels gets them behind the panels, which stay on screen")
        suite.expect(captureSelectionSource.contains("private var pointerIsInside = false")
                && !captureSelectionSource.contains("|| bounds.contains(hoverPoint)"),
               "the capture loupe draws on only the display that owns the current pointer")
        let captureServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/ScreenCaptureService.swift",
            encoding: .utf8)) ?? ""
        suite.expect(!captureServiceSource.contains("replaceSelection"),
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
        suite.expect(!quickPreviewSource.isEmpty, "the screenshot preview source reads back for its shape check")
        let quickPreviewCode = quickPreviewSource.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        // Split at the hosting controller: the hover closure is built above it,
        // so the presentation statements are what remains.
        let presentBody = quickPreviewCode.components(separatedBy: "let host = NSHostingController")
            .dropFirst().first?.components(separatedBy: "private func").first ?? ""
        suite.expect(presentBody.contains("orderFrontRegardless()"),
               "the screenshot preview is presented without activating the app")
        // A click is the hand-off, and it is read in sendEvent because the
        // hosted SwiftUI content answers presses that never reach mouseDown.
        let panelBody = quickPreviewCode.components(separatedBy: "class ScreenshotQuickPreviewPanel")
            .dropFirst().first?.components(separatedBy: "\n}").first ?? ""
        // The preference keys the panel only after it is on screen, and the
        // line above the call is the preference check itself, so dropping the
        // guard or keying before ordering front both go red.
        let presentLines = presentBody.components(separatedBy: "\n")
        let orderFrontLine = presentLines.firstIndex { $0.contains("orderFrontRegardless()") } ?? -1
        let makeKeyLine = presentLines.firstIndex { $0.contains("makeKey") } ?? -1
        suite.expect(orderFrontLine >= 0 && makeKeyLine > orderFrontLine
                && presentLines[makeKeyLine - 1].contains("screenshotPreviewTakesFocus"),
               "presenting the screenshot preview takes key focus only behind the preference, once the panel is on screen")
        let makeKeyCount = quickPreviewCode.components(separatedBy: "makeKey").count - 1
        let panelMakeKeyCount = panelBody.components(separatedBy: "makeKey").count - 1
        suite.expect(makeKeyCount == panelMakeKeyCount + 1 && panelMakeKeyCount >= 1,
               "hover never takes key focus; only the preferred presentation and the panel's own click hand-off may")
        suite.expect(panelBody.contains("sendEvent") && panelBody.contains("leftMouseDown")
                && panelBody.contains("makeKey") && panelBody.contains("super.sendEvent"),
               "clicking the screenshot preview takes key focus and still delivers every preview button")

        // With the controls in Dynamic Island, the island's panel holds key
        // focus and the selection surface never becomes key on its own, so
        // AppKit would spend the first click making it key and swallow it.
        // The overlay view claims that click; comments are stripped so prose
        // cannot answer for the code.
        let selectionSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift",
            encoding: .utf8)) ?? ""
        let overlayViewBody = selectionSource.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
            .components(separatedBy: "class ScreenshotOverlayView").dropFirst().first?
            .components(separatedBy: "\n}").first ?? ""
        suite.expect(overlayViewBody.contains("acceptsFirstMouse") && overlayViewBody.contains("acceptsFirstMouse(for event: NSEvent?) -> Bool { true }"),
               "the capture surface claims the first click so a drag works while Dynamic Island holds key focus")
        // Both editors state a size the same way. The recorder wrote
        // "1960x1274" beside a screenshot editor that already read
        // "2940 \u{00D7} 1912 px", and the letter x is the tell.
        let recorderEditorSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Recorder/RecorderEditorView.swift",
            encoding: .utf8)) ?? ""
        suite.expect(!recorderEditorSource.isEmpty, "the recorder editor source reads back for its shape check")
        suite.expect(recorderEditorSource.contains("\\(Int(size.width)) \u{00D7} \\(Int(size.height))"),
               "the recorder states its output size with the multiplication sign")
        // A card that names itself twice reads like filler. The look cards had
        // borrowed the shape, pointer and background labels as subtitles, so
        // two of the three said their own name back in English.
        let inspectorSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Recorder/RecorderInspector.swift",
            encoding: .utf8)) ?? ""
        suite.expect(!inspectorSource.isEmpty, "the recorder inspector source reads back for its shape check")
        suite.expect(!inspectorSource.contains("subtitle"),
               "a look card carries one name, not a label borrowed from another control")
        // A button says what it does. The empty zoom state had borrowed the
        // timeline lane's hint, so the button read "Click here to add a zoom"
        // while being the very thing the reader was already looking at.
        for language in AppLanguage.allCases {
            let recorder = FeatureStrings.recorder(language)
            suite.expect(!recorder.addZoomButton.isEmpty
                    && recorder.addZoomButton != recorder.zoomLaneEmptyHint,
                   "the empty zoom state has its own button label in \(language.rawValue)")
        }
        // A menu row says where the command lives. Every Mac app has a menu
        // named after itself, so the app menu read its own name twice.
        suite.expect(CommandBarMenuPath.crumb(appName: "Notes", path: ["Notes"]) == "Notes",
               "the app menu does not say the app name twice")
        suite.expect(CommandBarMenuPath.crumb(appName: "Notes", path: ["File", "Export"])
                == "Notes \u{203A} File \u{203A} Export",
               "a real trail keeps every step")
        suite.expect(CommandBarMenuPath.crumb(appName: "Notes", path: []) == "Notes",
               "a command straight off the app names only the app")
        suite.expect(CommandBarMenuPath.crumb(appName: "Notes", path: ["", "View"])
                == "Notes \u{203A} View",
               "an empty step leaves no dangling separator")
        // The cleanup above is the only kind that survives exit(). A defer
        // that removes a file here would look like housekeeping and do none.
        let suiteSource = (try? String(contentsOfFile: "Tests/ScreenshotFeatureTests.swift",
                                       encoding: .utf8)) ?? ""
        suite.expect(!suiteSource.isEmpty, "the suite reads itself back for its own shape check")
        // Split so the needle never matches the line that looks for it.
        let deadCleanup = "defer { try? FileManager" + ".default.removeItem"
        suite.expect(!suiteSource.contains(deadCleanup),
               "scratch is handed back before the run reports, never by a defer this exit skips")
        // A word pinned to a fixed column has to be allowed to give: the
        // backdrop sliders were labelled in a 64-point column that the Turkish
        // and Spanish words for blur run past, so they were being cut.
        let widestBackdropLabel = AppLanguage.allCases
            .flatMap { language -> [String] in
                let screenshot = FeatureStrings.screenshot(language)
                return [screenshot.backdropPaddingLabel,
                        screenshot.backdropCornersLabel,
                        screenshot.backdropBlurLabel]
            }
            .map(\.count).max() ?? 0
        suite.expect(widestBackdropLabel >= 10,
               "the backdrop labels are long enough somewhere for the column to matter")
        for path in ["Sources/Vorssaint/UI/Screenshot/ScreenshotBackdropPopover.swift",
                     "Sources/Vorssaint/UI/Recorder/RecorderInspector.swift"] {
            let code = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            suite.expect(!code.isEmpty, "the slider source reads back for its shape check")
            let pinned = code.components(separatedBy: "\n")
                .filter { $0.contains(".frame(width: 64, alignment: .leading)")
                          || $0.contains(".frame(width: 50, alignment: .leading)") }
            suite.expect(!pinned.isEmpty, "the pinned label column is still there in \(path)")
            suite.expect(code.components(separatedBy: "minimumScaleFactor(0.82)").count - 1 == pinned.count,
                   "every label pinned to that column may shrink instead of being cut (\(path))")
        }

        let cocoa = ScreenshotSupport.cocoaRect(fromWindowServer: CGRect(x: 10, y: 30, width: 200, height: 100),
                                                mainScreenHeight: 900)
        suite.expect(cocoa == CGRect(x: 10, y: 770, width: 200, height: 100),
               "window server rects convert to Cocoa coordinates")
        let viewRect = ScreenshotSupport.flippedViewRect(fromCocoa: cocoa,
                                                         screenFrame: CGRect(x: 0, y: 0, width: 1600, height: 900))
        suite.expect(viewRect == CGRect(x: 10, y: 30, width: 200, height: 100),
               "the round trip back to a flipped view restores the window server rect")
        suite.expect(ScreenshotSupport.cocoaRect(fromFlippedView: viewRect,
                                           screenFrame: CGRect(x: 0, y: 0,
                                                               width: 1600, height: 900)) == cocoa,
               "a flipped overlay rect maps back to its Cocoa screen position")
        let pixels = ScreenshotSupport.imagePixelRect(fromView: CGRect(x: 10, y: 20, width: 30, height: 40),
                                                      viewSize: CGSize(width: 100, height: 100),
                                                      imageSize: CGSize(width: 200, height: 200))
        suite.expect(pixels == CGRect(x: 20, y: 40, width: 60, height: 80),
               "view points scale to image pixels")
        suite.expect(ScreenshotSupport.imagePixelRect(fromView: CGRect(x: -20, y: -20, width: 500, height: 500),
                                                viewSize: CGSize(width: 100, height: 100),
                                                imageSize: CGSize(width: 200, height: 200))
                == CGRect(x: 0, y: 0, width: 200, height: 200),
               "pixel rects clamp to the image")
        suite.expect(ScreenshotSupport.imagePixelPoint(fromView: CGPoint(x: 50, y: 25),
                                                 viewSize: CGSize(width: 100, height: 50),
                                                 imageSize: CGSize(width: 200, height: 100))
                == CGPoint(x: 100, y: 50),
               "the capture loupe maps its pointer to the matching source pixel")
        suite.expect(ScreenshotSupport.imagePixelPoint(fromView: CGPoint(x: -10, y: 90),
                                                 viewSize: CGSize(width: 100, height: 50),
                                                 imageSize: CGSize(width: 200, height: 100))
                == CGPoint(x: 0, y: 100),
               "the capture loupe clamps source points at display edges")
        let editorMinimum = ScreenshotSupport.editorMinimumContentSize(
            visibleSize: CGSize(width: 1470, height: 956))
        suite.expect(editorMinimum == CGSize(width: 980, height: 680),
               "the screenshot editor opens on a comfortable canvas")
        let editorSmallDisplay = ScreenshotSupport.editorMinimumContentSize(
            visibleSize: CGSize(width: 700, height: 500))
        suite.expect(editorSmallDisplay == CGSize(width: 700, height: 500),
               "the editor minimum never exceeds a compact display")
        let smallCaptureWindow = ScreenshotSupport.editorContentSize(
            imagePointSize: CGSize(width: 180, height: 100),
            visibleSize: CGSize(width: 1470, height: 956))
        suite.expect(smallCaptureWindow == editorMinimum,
               "a small screenshot still receives the full editing canvas")
        let largeCaptureWindow = ScreenshotSupport.editorContentSize(
            imagePointSize: CGSize(width: 2200, height: 1400),
            visibleSize: CGSize(width: 1470, height: 956))
        suite.expect(largeCaptureWindow.width <= 1470 * 0.90
                && largeCaptureWindow.height <= 956 * 0.88,
               "a large screenshot editor stays inside the visible display")
        suite.expect(ScreenshotSupport.editorOwnsKeyEvent(eventWindowNumber: 42,
                                                    editorWindowNumber: 42,
                                                    editorIsKey: true),
               "screenshot editor owns key events carrying its window number")
        suite.expect(ScreenshotSupport.editorOwnsKeyEvent(eventWindowNumber: 0,
                                                    editorWindowNumber: 42,
                                                    editorIsKey: true),
               "screenshot editor owns windowless menu key equivalents while key")
        suite.expect(!ScreenshotSupport.editorOwnsKeyEvent(eventWindowNumber: 0,
                                                     editorWindowNumber: 42,
                                                     editorIsKey: false),
               "inactive screenshot editor ignores windowless key events")
        suite.expect(!ScreenshotSupport.editorOwnsKeyEvent(eventWindowNumber: 7,
                                                     editorWindowNumber: 42,
                                                     editorIsKey: true),
               "screenshot editor ignores events explicitly owned by another window")
        let previewFrame = ScreenshotSupport.quickPreviewFrame(
            size: CGSize(width: 286, height: 210),
            anchor: CGRect(x: 1100, y: 100, width: 300, height: 300),
            pointer: CGPoint(x: 1300, y: 220),
            visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 956))
        suite.expect(CGRect(x: 10, y: 10, width: 1450, height: 936).contains(previewFrame),
               "the quick capture preview stays fully inside the visible display")

        let pickable = [ScreenshotSupport.PickableWindow(windowID: 1, frame: CGRect(x: 0, y: 0, width: 50, height: 50)),
                        ScreenshotSupport.PickableWindow(windowID: 2, frame: CGRect(x: 0, y: 0, width: 400, height: 400))]
        suite.expect(ScreenshotSupport.window(at: CGPoint(x: 10, y: 10), in: pickable)?.windowID == 1,
               "the frontmost window wins a click")
        suite.expect(ScreenshotSupport.window(at: CGPoint(x: 300, y: 300), in: pickable)?.windowID == 2
                && ScreenshotSupport.window(at: CGPoint(x: 900, y: 900), in: pickable) == nil,
               "clicks outside every window pick nothing")

        let fileDate = Date(timeIntervalSince1970: 1_752_486_065) // 2025-07-14 09:41:05 UTC
        let fileName = ScreenshotSupport.fileName(prefix: "Screenshot", date: fileDate)
        suite.expect(fileName.hasPrefix("Screenshot 20") && fileName.hasSuffix(".png")
                && !fileName.contains(":") && fileName.contains(" at "),
               "file names are dated, colon free and png")
        suite.expect(ScreenshotSupport.uniqueFileName("a.png", exists: { _ in false }) == "a.png",
               "a free name stays untouched")
        suite.expect(ScreenshotSupport.uniqueFileName("a.png", exists: { $0 == "a.png" }) == "a 2.png",
               "a taken name gets the next numbered variant")
        suite.expect(ScreenshotSupport.uniqueFileName("a.png",
                                                exists: { $0 == "a.png" || $0 == "a 2.png" }) == "a 3.png",
               "numbering keeps walking until a free name")
        let recentID = UUID()
        suite.expect(ScreenshotSupport.isRecentCaptureCacheFileName("\(recentID.uuidString).png")
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
        suite.expect(firstDrag?.lastPathComponent == "Capture.png"
                && firstDrag.flatMap { try? Data(contentsOf: $0) } == dragData,
               "a screenshot drag writes the complete payload with its file name")
        suite.expect(firstDrag != nil && secondDrag != nil && firstDrag != secondDrag,
               "simultaneous screenshot drags receive separate temporary files")
        let unrelatedDrag = dragRoot.appendingPathComponent("ScreenshotDrag-not-owned",
                                                            isDirectory: true)
        try? FileManager.default.createDirectory(at: unrelatedDrag,
                                                 withIntermediateDirectories: true)
        ScreenshotSupport.removeTemporaryDragDirectories(directory: dragRoot)
        suite.expect(firstDrag.map { !FileManager.default.fileExists(atPath: $0.path) } == true
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
        suite.expect(staleCopy.map { !FileManager.default.fileExists(atPath: $0.path) } == true,
               "copying a screenshot removes expired copied files")
        suite.expect(currentCopy?.lastPathComponent == "Capture.png"
                && nextCopy?.lastPathComponent == "Capture 2.png"
                && currentCopy.flatMap { try? Data(contentsOf: $0) } == dragData,
               "copied screenshots stay as unique complete png files")
        suite.expect(currentCopy.map { ScreenshotSupport.isCopiedScreenshot($0, in: copyRoot) } == true,
               "clipboard history recognizes a copied screenshot only inside its private cache")
        suite.expect(currentCopy.map {
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
        suite.expect(pruneVictims == [lateStaleCopy],
               "a late stale copy is pruned without evicting the published file")
        let copySymlink = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotCopyLink-\(UUID().uuidString)")
        try? FileManager.default.createSymbolicLink(at: copySymlink,
                                                     withDestinationURL: copyRoot)
        let symlinkCopy = try? ScreenshotSupport.copiedFile(
            data: dragData, name: "Linked.png", directory: copySymlink)
        suite.expect(symlinkCopy == nil
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
        suite.expect(renumbered.filter { $0.tool == .counter }.map(\.number) == [1, 2],
               "deleting a counter renumbers the rest without holes")
        suite.expect(renumbered[0].tool == .arrow || renumbered.count == 3,
               "renumbering never drops annotations")

        let layered = [
            ScreenshotSupport.Annotation(tool: .text),
            ScreenshotSupport.Annotation(tool: .rect),
            ScreenshotSupport.Annotation(tool: .arrow),
        ]
        let sentBack = ScreenshotSupport.reordering(layered, moving: layered[1].id, .backward)
        suite.expect(sentBack.map(\.id) == [layered[1].id, layered[0].id, layered[2].id],
               "sending back swaps an annotation with the one drawn before it")
        let broughtForward = ScreenshotSupport.reordering(layered, moving: layered[1].id, .forward)
        suite.expect(broughtForward.map(\.id) == [layered[0].id, layered[2].id, layered[1].id],
               "bringing forward swaps an annotation with the one drawn after it")
        suite.expect(ScreenshotSupport.reordering(layered, moving: layered[0].id, .backward).map(\.id)
                == layered.map(\.id)
                && ScreenshotSupport.reordering(layered, moving: layered[2].id, .forward).map(\.id)
                == layered.map(\.id),
               "an annotation at either end of the order stays put in that direction")
        suite.expect(ScreenshotSupport.reordering(layered, moving: UUID(), .forward).map(\.id)
                == layered.map(\.id),
               "an unknown annotation leaves the order alone")
        suite.expect(!ScreenshotSupport.canReorder(layered, moving: layered[0].id, .backward)
                && ScreenshotSupport.canReorder(layered, moving: layered[0].id, .forward)
                && !ScreenshotSupport.canReorder(layered, moving: layered[2].id, .forward)
                && ScreenshotSupport.canReorder(layered, moving: layered[2].id, .backward),
               "each direction is offered only while the annotation can still take it")
        suite.expect(!ScreenshotSupport.canReorder(layered, moving: UUID(), .forward)
                && !ScreenshotSupport.canReorder([], moving: layered[0].id, .backward),
               "an annotation that is not there can never be reordered")
        let screenshotEditorSource = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/ScreenshotEditorController.swift",
            encoding: .utf8)) ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let screenshotSupportSource = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/ScreenshotSupport.swift",
            encoding: .utf8)) ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(screenshotEditorSource.contains("if tool != .select, tool != .crop {\n            selectedID = nil\n        }"),
               "the editor clears stale selection before creating a new annotation")
        suite.expect(!screenshotEditorSource.contains("annotations.append(annotation)\n            selectedID = annotation.id\n            draftID = annotation.id")
                && screenshotEditorSource.contains("} else if let draftID {\n                selectedID = draftID"),
               "a shape is selected only after its drag ends")
        suite.expect(screenshotSupportSource.contains("let color: ColorID?")
                && screenshotSupportSource.contains("let stroke: StrokeID?")
                && screenshotSupportSource.contains("let arrowStyle: ArrowStyleID?"),
               "selection styles can leave controls untouched when a mark does not use them")

        let resized = ScreenshotSupport.resizedRect(CGRect(x: 10, y: 10, width: 100, height: 100),
                                                    dragging: .bottomRight,
                                                    to: CGPoint(x: 50, y: 60))
        suite.expect(resized == CGRect(x: 10, y: 10, width: 40, height: 50),
               "dragging a handle resizes the rect")
        let crossed = ScreenshotSupport.resizedRect(CGRect(x: 10, y: 10, width: 100, height: 100),
                                                    dragging: .right,
                                                    to: CGPoint(x: 0, y: 0))
        suite.expect(crossed.width == 10 && crossed.minX == 0,
               "dragging a handle across the opposite edge flips instead of going negative")
        let movedCrop = ScreenshotSupport.movedRect(
            CGRect(x: 20, y: 30, width: 80, height: 60),
            by: CGPoint(x: 50, y: -100),
            within: CGRect(x: 0, y: 0, width: 120, height: 100))
        suite.expect(movedCrop == CGRect(x: 40, y: 0, width: 80, height: 60),
               "dragging inside a crop moves it without resizing past the image edges")
        suite.expect(ScreenshotSupport.handle(at: CGPoint(x: 10, y: 10),
                                        rect: CGRect(x: 10, y: 10, width: 100, height: 100),
                                        tolerance: 6) == .topLeft,
               "handle hit testing finds the corner")

        let head = ScreenshotSupport.arrowHead(from: CGPoint(x: 0, y: 0),
                                               to: CGPoint(x: 100, y: 0),
                                               strokeWidth: 4)
        suite.expect(head.left.x < 100 && head.right.x < 100 && head.left.y != head.right.y,
               "arrow heads open behind the tip")
        let shortHead = ScreenshotSupport.arrowHead(from: .zero,
                                                    to: CGPoint(x: 10, y: 0),
                                                    strokeWidth: 14)
        suite.expect(shortHead.left.x >= 0 && shortHead.right.x >= 0,
               "a short arrow head never extends behind its tail")
        let arrowPath = ScreenshotSupport.arrowSilhouette(from: CGPoint(x: 100, y: 20),
                                                          to: CGPoint(x: 100, y: 300),
                                                          strokeWidth: 40)
        suite.expect(arrowPath.contains(CGPoint(x: 100, y: 30),
                                  using: .winding,
                                  transform: .identity),
               "the arrow tail stays filled where its cap meets the shaft")
        suite.expect(arrowPath.contains(CGPoint(x: 100, y: 190),
                                  using: .winding,
                                  transform: .identity),
               "the arrow stays filled where its shaft meets the head")
        let arrowStyles = ScreenshotSupport.ArrowStyleID.allCases
        suite.expect(arrowStyles == [.filled, .outline, .open, .doubleEnded, .scribbly]
                && ScreenshotSupport.ArrowStyleID.sanitized("unknown") == .filled,
               "the screenshot editor offers five arrow styles and safely falls back to solid")
        let openArrow = ScreenshotSupport.Annotation(tool: .arrow,
                                                     points: [.zero, CGPoint(x: 100, y: 100)],
                                                     arrowStyle: .open)
        suite.expect(openArrow.arrowStyle == .open,
               "arrow annotations retain the chosen style independently of color and thickness")
        let stableScribble = ScreenshotSupport.scribblyArrowGeometry(
            from: .zero,
            to: CGPoint(x: 160, y: 80),
            strokeWidth: 4,
            seed: 17)
        let sameScribble = ScreenshotSupport.scribblyArrowGeometry(
            from: .zero,
            to: CGPoint(x: 160, y: 80),
            strokeWidth: 4,
            seed: 17)
        let differentScribble = ScreenshotSupport.scribblyArrowGeometry(
            from: .zero,
            to: CGPoint(x: 160, y: 80),
            strokeWidth: 4,
            seed: 18)
        suite.expect(stableScribble == sameScribble
                && stableScribble != differentScribble
                && stableScribble.shaft.count > 2,
               "scribbly arrows vary by seed but keep one stable design when redrawn")
        suite.expect(ScreenshotSupport.arrowStrokePath(from: .zero, to: CGPoint(x: 100, y: 0),
                                                 strokeWidth: 4, style: .filled, seed: 0) == nil
                && arrowStyles.filter { $0 != .filled }.allSatisfy {
                    ScreenshotSupport.arrowStrokePath(from: .zero, to: CGPoint(x: 100, y: 0),
                                                      strokeWidth: 4, style: $0, seed: 17)?
                        .boundingBox.width ?? 0 >= 100
                },
               "the solid arrow is a filled silhouette and every other style is one stroked path")
        // With shadows on, a shaft pixel under the head's shadow must match a
        // shaft pixel far from the head: the head and the shaft are one
        // stroke, so the head never shades the shaft where they meet.
        let seamShaft: [ScreenshotSupport.ArrowStyleID: Bool] = Dictionary(
            uniqueKeysWithValues: [ScreenshotSupport.ArrowStyleID.open, .doubleEnded].map { style in
                let width = 160, height = 80
                var pixels = [UInt8](repeating: 0, count: width * height * 4)
                let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                    guard let context = CGContext(data: buffer.baseAddress,
                                                  width: width,
                                                  height: height,
                                                  bitsPerComponent: 8,
                                                  bytesPerRow: width * 4,
                                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                    else { return false }
                    context.translateBy(x: 0, y: CGFloat(height))
                    context.scaleBy(x: 1, y: -1)
                    ScreenshotRenderer.drawAnnotations(
                        [ScreenshotSupport.Annotation(tool: .arrow,
                                                      points: [CGPoint(x: 20, y: 40), CGPoint(x: 140, y: 40)],
                                                      color: .green,
                                                      stroke: .large,
                                                      arrowStyle: style)],
                        in: context,
                        pixelated: [:],
                        imageSize: CGSize(width: width, height: height),
                        scale: 2,
                        annotationShadowsEnabled: true)
                    return true
                }
                // Rows are stored top-down, the same way the flipped context draws.
                func pixel(_ x: Int, _ y: Int) -> ArraySlice<UInt8> {
                    let offset = (y * width + x) * 4
                    return pixels[offset..<offset + 4]
                }
                return (style, drawn && pixel(120, 40) == pixel(60, 40) && pixel(60, 40).last == 255)
            })
        suite.expect(seamShaft.values.allSatisfy { $0 },
               "a stroked arrow's head casts no shadow onto its own shaft")
        let thickArrow = ScreenshotSupport.Annotation(tool: .arrow, stroke: .large)
        let thinArrow = ScreenshotSupport.Annotation(tool: .arrow, stroke: .small)
        suite.expect(ScreenshotSupport.selectionStyle(for: thinArrow).stroke == .some(.small)
                && ScreenshotSupport.selectionStyle(for: thinArrow)
                    != ScreenshotSupport.selectionStyle(for: thickArrow),
               "selecting a thin arrow exposes its own stroke in the editor controls")
        let stickerStyle = ScreenshotSupport.selectionStyle(
            for: ScreenshotSupport.Annotation(tool: .sticker,
                                               color: .blue,
                                               stroke: .large))
        let pixelateStyle = ScreenshotSupport.selectionStyle(
            for: ScreenshotSupport.Annotation(tool: .pixelate,
                                               color: .green,
                                               stroke: .large))
        let highlightStyle = ScreenshotSupport.selectionStyle(
            for: ScreenshotSupport.Annotation(tool: .highlight,
                                               color: .yellow,
                                               stroke: .large))
        suite.expect(stickerStyle == ScreenshotSupport.SelectionStyle(color: nil,
                                                                stroke: nil,
                                                                arrowStyle: nil)
                && pixelateStyle == ScreenshotSupport.SelectionStyle(
                    color: nil, stroke: nil, arrowStyle: nil,
                    blurLevel: ScreenshotSupport.BlurStrength.defaultLevel)
                && highlightStyle.color == .some(.yellow)
                && highlightStyle.stroke == nil
                && highlightStyle.arrowStyle == nil,
               "selection sync leaves unused sticker and pixelation controls alone")
        let Strength = ScreenshotSupport.BlurStrength.self
        let capture = CGSize(width: 1920, height: 1080)
        suite.expect(ScreenshotSupport.pixelBlockSize(for: capture)
                    == ScreenshotSupport.pixelBlockSize(for: capture, level: Strength.defaultLevel)
                && ScreenshotSupport.pixelBlockSize(for: capture, level: 1)
                    < ScreenshotSupport.pixelBlockSize(for: capture, level: 2)
                && ScreenshotSupport.pixelBlockSize(for: capture, level: 2)
                    < ScreenshotSupport.pixelBlockSize(for: capture)
                && ScreenshotSupport.pixelBlockSize(for: capture)
                    < ScreenshotSupport.pixelBlockSize(for: capture, level: 4)
                && ScreenshotSupport.pixelBlockSize(for: capture, level: 4)
                    < ScreenshotSupport.pixelBlockSize(for: capture, level: 5),
               "each blur level coarsens the mosaic, and the middle keeps the old strength")
        suite.expect(Strength.sanitized(0) == 1 && Strength.sanitized(9) == 5
                && Strength.blockFactor(for: Strength.defaultLevel) == 1
                && ScreenshotSupport.pixelBlockSize(for: CGSize(width: 40, height: 40), level: 1) >= 2,
               "blur levels stay in range and never shrink the mosaic to nothing")
        suite.expect([0, 1, 2, 3].allSatisfy { Strength.startingLevel(remembered: $0) == Strength.defaultLevel }
                && Strength.startingLevel(remembered: 4) == 4 && Strength.startingLevel(remembered: 5) == 5
                && Strength.startingLevel(remembered: 9) == 5,
               "a new capture never starts pixelating at a light level that can leave text readable")
        var lightArea = ScreenshotSupport.Annotation(tool: .pixelate)
        lightArea.blurLevel = 1
        var strongArea = ScreenshotSupport.Annotation(tool: .pixelate)
        strongArea.blurLevel = 5
        var outlinedArea = ScreenshotSupport.Annotation(tool: .rect)
        outlinedArea.blurLevel = 4
        suite.expect(ScreenshotSupport.mosaicLevels(for: [lightArea, strongArea, strongArea, outlinedArea]) == [1, 5]
                && ScreenshotSupport.mosaicLevels(for: [outlinedArea]).isEmpty,
               "the editor keeps a sampled mosaic only for the levels its pixelate areas use")
        func filled(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGImage? {
            let context = CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
            context?.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
            return context?.makeImage()
        }
        if let base = filled(0.5, 0.5, 0.5), let light = filled(1, 0, 0), let heavy = filled(0, 0, 1) {
            let marks = [
                ScreenshotSupport.Annotation(tool: .pixelate,
                                             rect: CGRect(x: 0, y: 0, width: 10, height: 10),
                                             blurLevel: 1),
                ScreenshotSupport.Annotation(tool: .pixelate,
                                             rect: CGRect(x: 10, y: 0, width: 10, height: 10),
                                             blurLevel: 5),
            ]
            let export = ScreenshotRenderer.renderExport(
                baseImage: base, annotations: marks, pixelated: [1: light, 5: heavy], scale: 1,
                annotationShadowsEnabled: false, watermark: ScreenshotSupport.WatermarkStyle(),
                watermarkImage: nil, style: ScreenshotSupport.BackdropStyle(kind: .none, cornerRadius: 0),
                fill: .none, downscaleTo1x: false)
            var pixels = [UInt8](repeating: 0, count: 20 * 10 * 4)
            let read = export.map { export -> Bool in
                pixels.withUnsafeMutableBytes { buffer in
                    let context = CGContext(data: buffer.baseAddress, width: 20, height: 10,
                                            bitsPerComponent: 8, bytesPerRow: 80,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                    context?.draw(export.image, in: CGRect(x: 0, y: 0, width: 20, height: 10))
                    return context != nil
                }
            } ?? false
            let left = Array(pixels[(5 * 20 + 3) * 4..<(5 * 20 + 3) * 4 + 3])
            let right = Array(pixels[(5 * 20 + 16) * 4..<(5 * 20 + 16) * 4 + 3])
            suite.expect(read && left[0] > 200 && left[2] < 50 && right[2] > 200 && right[0] < 50,
                   "an export with mixed blur levels draws each area from its own mosaic")
        }
        // Compare the exported pixels with the old full-size cache path. The
        // pixelate rect cuts across mosaic cells, exercising the clip too.
        let mosaicWidth = 26, mosaicHeight = 19
        let mosaicSource = CGContext(data: nil, width: mosaicWidth, height: mosaicHeight,
                                     bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        mosaicSource?.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        mosaicSource?.fill(CGRect(x: 0, y: 0, width: 13, height: mosaicHeight))
        mosaicSource?.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        mosaicSource?.fill(CGRect(x: 13, y: 0, width: 13, height: mosaicHeight))
        var sampledIsSmaller = false
        var exportedPixelsMatch = false
        if let source = mosaicSource?.makeImage(),
           let sampled = ScreenshotRenderer.pixelatedImage(from: source),
           let oldFull = CGContext(data: nil, width: mosaicWidth, height: mosaicHeight,
                                   bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            sampledIsSmaller = sampled.width < source.width && sampled.height < source.height
            oldFull.interpolationQuality = .none
            oldFull.draw(sampled, in: CGRect(x: 0, y: 0, width: mosaicWidth, height: mosaicHeight))
            if let expanded = oldFull.makeImage() {
                let area = ScreenshotSupport.Annotation(
                    tool: .pixelate, rect: CGRect(x: 3, y: 2, width: 19, height: 14))
                func exportedPixels(using mosaic: CGImage) -> [UInt8]? {
                    guard let image = ScreenshotRenderer.renderExport(
                        baseImage: source, annotations: [area], pixelated: [3: mosaic], scale: 1,
                        annotationShadowsEnabled: false, watermark: ScreenshotSupport.WatermarkStyle(),
                        watermarkImage: nil, style: ScreenshotSupport.BackdropStyle(kind: .none, cornerRadius: 0),
                        fill: .none, downscaleTo1x: false)?.image else { return nil }
                    var pixels = [UInt8](repeating: 0, count: mosaicWidth * mosaicHeight * 4)
                    let read = pixels.withUnsafeMutableBytes { buffer -> Bool in
                        guard let context = CGContext(data: buffer.baseAddress, width: mosaicWidth,
                                                      height: mosaicHeight, bitsPerComponent: 8,
                                                      bytesPerRow: mosaicWidth * 4,
                                                      space: CGColorSpaceCreateDeviceRGB(),
                                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                        else { return false }
                        context.draw(image, in: CGRect(x: 0, y: 0, width: mosaicWidth, height: mosaicHeight))
                        return true
                    }
                    return read ? pixels : nil
                }
                if let compactPixels = exportedPixels(using: sampled),
                   let expandedPixels = exportedPixels(using: expanded) {
                    exportedPixelsMatch = compactPixels == expandedPixels
                }
            }
        }
        suite.expect(sampledIsSmaller, "pixelation caches sampled pixels instead of a full capture")
        suite.expect(exportedPixelsMatch, "sampled mosaics export the same clipped pixels as full-size mosaics")
        let bigText = ScreenshotSupport.Annotation(tool: .text, stroke: .small, textSize: 48)
        suite.expect(ScreenshotSupport.selectionStyle(for: bigText)
                == ScreenshotSupport.SelectionStyle(color: .red, stroke: nil,
                                                    arrowStyle: nil, textSize: 48)
                && ScreenshotSupport.selectionStyle(for: thinArrow).textSize == nil,
               "text exposes its own point size, not the shape thickness")
        suite.expect(ScreenshotRenderer.fontSize(for: 48, scale: 2) == 96
                && ScreenshotRenderer.textBounds("Hi", at: .zero, textSize: 48, scale: 1).height
                    > ScreenshotRenderer.textBounds("Hi", at: .zero, textSize: 12, scale: 1).height,
               "text size alone drives the rendered font")
        suite.expect(ScreenshotSupport.sanitizedTextSize(0) == ScreenshotSupport.defaultTextSize
                && ScreenshotSupport.sanitizedTextSize(2) == ScreenshotSupport.textSizes.first
                && ScreenshotSupport.sanitizedTextSize(500) == ScreenshotSupport.textSizes.last
                && ScreenshotSupport.sanitizedTextSize(19) == 19,
               "a stored text size stays inside the offered range")
        suite.expect(ScreenshotSupport.steppedTextSize(from: 19, up: true) == 24
                && ScreenshotSupport.steppedTextSize(from: 19, up: false) == 16
                && ScreenshotSupport.steppedTextSize(from: 20, up: false) == 19
                && ScreenshotSupport.steppedTextSize(from: 96, up: true) == nil
                && ScreenshotSupport.steppedTextSize(from: 10, up: false) == nil,
               "the size buttons step through the presets and stop at the ends")
        suite.expect(screenshotEditorSource.contains("let strokeChanged = usesStroke && annotations[index].stroke != stroke")
                && screenshotEditorSource.contains("if usesStroke { annotations[index].stroke = stroke }"),
               "picking text or a highlight never records a thickness edit it has no control for")
        let screenshotEditorViewSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Screenshot/ScreenshotEditorView.swift",
            encoding: .utf8)) ?? ""
        suite.expect(screenshotEditorViewSource.contains("isHovered || isActive ? 0.9 : 0.55"),
               "tool shortcut labels stay visible on idle rail buttons")
        suite.expect(screenshotEditorSource.contains("syncControls(to: hit)"),
               "the editor synchronizes controls from the selected annotation")
        let existingSelectionSource: String
        if let start = screenshotEditorSource.range(of: "private func selectExistingAnnotation"),
           let end = screenshotEditorSource.range(of: "private func updateDraft") {
            existingSelectionSource = String(screenshotEditorSource[start.lowerBound..<end.lowerBound])
        } else {
            existingSelectionSource = ""
        }
        suite.expect(existingSelectionSource.contains("syncControls(to: hit)"),
               "creation-tool taps synchronize controls before selecting the annotation")
        let finishSelectionSource: String
        if let start = screenshotEditorSource.range(of: "private func finishSelectDrag"),
           let end = screenshotEditorSource.range(of: "private func selectExistingAnnotation") {
            finishSelectionSource = String(screenshotEditorSource[start.lowerBound..<end.lowerBound])
        } else {
            finishSelectionSource = ""
        }
        suite.expect(finishSelectionSource.contains("syncControls(to: hit)"),
               "selection-tool taps synchronize controls for every selected mark")
        suite.expect(abs(ScreenshotSupport.distance(from: CGPoint(x: 50, y: 10),
                                              toSegment: CGPoint(x: 0, y: 0),
                                              CGPoint(x: 100, y: 0)) - 10) < 0.001,
               "segment distance measures perpendicular offset")
        suite.expect(ScreenshotSupport.distance(from: CGPoint(x: -30, y: 0),
                                          toSegment: CGPoint(x: 0, y: 0),
                                          CGPoint(x: 100, y: 0)) == 30,
               "segment distance clamps to the endpoints")

        suite.expect(ScreenshotSupport.pixelBlockSize(for: CGSize(width: 5500, height: 3600)) == 65
                && ScreenshotSupport.pixelBlockSize(for: CGSize(width: 200, height: 120)) == 10,
               "pixelation blocks scale with the capture and never get too fine")
        suite.expect(ScreenshotSupport.downscaledSize(pixelSize: CGSize(width: 800, height: 600), scale: 2)
                == CGSize(width: 400, height: 300),
               "the 1x option halves a Retina capture")
        suite.expect(ScreenshotSupport.downscaledSize(pixelSize: CGSize(width: 800, height: 600), scale: 1)
                == CGSize(width: 800, height: 600),
               "a 1x capture never downscales")

        // Every picture the app writes says how big it is on screen, the way
        // a system screenshot does, so Preview and a paste show a Retina
        // capture at its own size instead of doubled and softened.
        func encodedDensity(_ data: Data?) -> (width: Int, dpi: Double)? {
            guard let data,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?,
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let dpi = properties[kCGImagePropertyDPIWidth] as? NSNumber
            else { return nil }
            return (width.intValue, dpi.doubleValue)
        }
        let retinaContext = CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        retinaContext?.setFillColor(CGColor(gray: 0.5, alpha: 1))
        retinaContext?.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        let retinaCapture = retinaContext?.makeImage()
        suite.expect(retinaCapture != nil, "a Retina test capture can be drawn")
        if let retinaCapture {
            let plain = ScreenshotSupport.BackdropStyle(kind: .none, cornerRadius: 0)
            let full = ScreenshotRenderer.renderExport(baseImage: retinaCapture, annotations: [],
                                                       pixelated: [:], scale: 2,
                                                       annotationShadowsEnabled: false,
                                                       watermark: ScreenshotSupport.WatermarkStyle(),
                                                       watermarkImage: nil,
                                                       style: plain, fill: .none,
                                                       downscaleTo1x: false)
            suite.expect(full?.scale == 2 && full?.image.width == 8,
                   "a Retina export keeps its pixels and its density")
            let halved = ScreenshotRenderer.renderExport(baseImage: retinaCapture, annotations: [],
                                                         pixelated: [:], scale: 2,
                                                         annotationShadowsEnabled: false,
                                                         watermark: ScreenshotSupport.WatermarkStyle(),
                                                         watermarkImage: nil,
                                                         style: plain, fill: .none,
                                                         downscaleTo1x: true)
            suite.expect(halved?.scale == 1 && halved?.image.width == 4,
                   "the 1x option halves the pixels and reports 1x density")
            let png = encodedDensity(ScreenshotRenderer.pngData(from: retinaCapture, scale: 2))
            suite.expect(png?.width == 8 && png?.dpi == 144,
                   "a Retina PNG carries 144 DPI over every pixel")
            let tiff = encodedDensity(ScreenshotRenderer.tiffData(from: retinaCapture, scale: 2))
            suite.expect(tiff?.width == 8 && tiff?.dpi == 144,
                   "the pasteboard TIFF carries the same density as the PNG")
            suite.expect(encodedDensity(ScreenshotRenderer.pngData(from: retinaCapture, scale: 1))?.dpi == 72,
                   "a 1x picture stays at 72 DPI")
            suite.expect(ScreenshotSupport.captureScale(fromDPI: png?.dpi) == 2,
                   "the stored density reads back as the capture scale")
        }
        suite.expect(ScreenshotSupport.backdropPadding(for: CGSize(width: 100, height: 100), factor: 0.5) == 24,
               "backdrop padding keeps a floor for tiny captures")
        suite.expect(ScreenshotSupport.backdropPadding(for: CGSize(width: 4000, height: 4000), factor: 1)
                == (4000 * 0.175).rounded(),
               "the margin slider grows the backdrop padding")
        suite.expect(ScreenshotSupport.backdropPadding(for: CGSize(width: 4000, height: 4000), factor: 0)
                == 140,
               "margin zero still keeps a small frame")
        suite.expect(ScreenshotSupport.BackdropID.allCases.filter { $0 != .none }
                .allSatisfy { $0.stops.count == 2 },
               "every backdrop gradient has its two stops")
        suite.expect(ScreenshotSupport.ColorID.sanitized("bogus") == .red
                && ScreenshotSupport.StrokeID.sanitized(nil) == .medium,
               "style choices sanitize to safe defaults")
        suite.expect(ScreenshotSupport.StickerID.sanitized("bogus") == .check
                && ScreenshotSupport.StickerID.allCases.count == 12,
               "stickers keep a safe default and a compact built-in set")
        let stickerRect = ScreenshotSupport.stickerRect(
            centeredAt: CGPoint(x: 5, y: 5),
            side: 40,
            within: CGRect(x: 0, y: 0, width: 100, height: 80))
        suite.expect(stickerRect == CGRect(x: 0, y: 0, width: 40, height: 40),
               "a sticker placed at an edge stays fully inside the image")

        suite.expect(ScreenshotSupport.cardCornerRadius(for: CGSize(width: 1600, height: 900), factor: 0) == 0
                && ScreenshotSupport.cardCornerRadius(for: CGSize(width: 1600, height: 900), factor: 1) == 180
                && ScreenshotSupport.cardCornerRadius(for: CGSize(width: 1600, height: 900), factor: 2) == 180,
               "card corner radius clamps and scales with the short side")
        suite.expect(abs(ScreenshotSupport.backdropBlurRadius(
                    for: CGSize(width: 1600, height: 900), factor: 1) - 31.5) < 0.001
                && ScreenshotSupport.backdropBlurRadius(
                    for: CGSize(width: 1600, height: 900), factor: -1) == 0,
               "background blur scales with the canvas and clamps its slider")
        let solidStyle = ScreenshotSupport.BackdropStyle(kind: .solid, colors: [[0.2, 0.4, 0.9]],
                                                         padding: 0.3, cornerRadius: 0.2,
                                                         blur: 0.6)
        let solidRoundTrip = ScreenshotSupport.BackdropStyle.decoded(solidStyle.encoded())
        suite.expect(solidRoundTrip == solidStyle, "a backdrop style round-trips through JSON")
        let legacyStyle = ScreenshotSupport.BackdropStyle.decoded(
            #"{"kind":"solid","colors":[[0.2,0.4,0.9]],"padding":0.3,"cornerRadius":0.2}"#)
        suite.expect(legacyStyle.kind == .solid && legacyStyle.blur == 0,
               "backgrounds saved before blur keep decoding without changing")
        suite.expect(ScreenshotSupport.BackdropStyle.decoded(nil).kind == .none
                && ScreenshotSupport.BackdropStyle.decoded("").kind == .none
                && ScreenshotSupport.BackdropStyle.decoded("not json").kind == .none,
               "a missing or broken backdrop style falls back to none")
        suite.expect(ScreenshotSupport.BackdropStyle().cornerRadius == 0,
               "the default backdrop leaves capture corners unchanged")
        let brokenSolid = ScreenshotSupport.BackdropStyle(kind: .solid, colors: nil)
        suite.expect(brokenSolid.sanitized().kind == .none,
               "a solid style without colors demotes to none")
        let wildSliders = ScreenshotSupport.BackdropStyle(kind: .preset, presetID: "ocean",
                                                          padding: 9, cornerRadius: -3, blur: 8)
        suite.expect(wildSliders.sanitized().padding == 1
                && wildSliders.sanitized().cornerRadius == 0
                && wildSliders.sanitized().blur == 1,
               "backdrop sliders clamp to their range")
        suite.expect(ScreenshotSupport.BackdropStyle(kind: .preset, presetID: "bogus").sanitized().kind == .none
                && ScreenshotSupport.BackdropStyle(kind: .image, imagePath: nil).sanitized().kind == .none,
               "unknown presets and missing image paths demote to none")
        suite.expect(ScreenshotSupport.BackdropStyle(kind: .gradient,
                                               colors: [[0, 2, -1], [0.5, 0.5, 0.5]])
                .sanitized().colors?.first == [0, 1, 0],
               "gradient colors clamp component by component")

        let presetList = [solidStyle,
                          ScreenshotSupport.BackdropStyle(kind: .gradient,
                                                          colors: [[1, 0, 0], [0, 0, 1]])]
        let decodedPresets = ScreenshotSupport.decodedBackdropPresets(
            ScreenshotSupport.encodedBackdropPresets(presetList))
        suite.expect(decodedPresets == presetList, "saved backdrops round-trip through JSON")
        suite.expect(ScreenshotSupport.decodedBackdropPresets("junk").isEmpty
                && ScreenshotSupport.decodedBackdropPresets(nil).isEmpty,
               "broken preset lists decode to empty")
        let overflow = Array(repeating: solidStyle, count: 40)
        suite.expect(ScreenshotSupport.decodedBackdropPresets(
                ScreenshotSupport.encodedBackdropPresets(overflow)).count
                == ScreenshotSupport.backdropPresetLimit,
               "saved backdrops cap at the presets limit")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotBackdropStyle] as? String == ""
                && Defaults.registeredDefaults[DefaultsKey.screenshotBackdropPresets] as? String == "[]",
               "backdrop style and presets register empty")

        // Watermark: the mark of your own that rides along every capture.
        let textMark = ScreenshotSupport.WatermarkStyle(kind: .text, text: "  Vorssaint  ",
                                                        color: "blue", anchor: .topLeading,
                                                        size: 0.5, opacity: 0.3, rotation: 30)
        let markRoundTrip = ScreenshotSupport.WatermarkStyle.decoded(textMark.encoded())
        suite.expect(markRoundTrip == textMark.sanitized() && markRoundTrip.text == "Vorssaint"
                && markRoundTrip.anchor == .topLeading && markRoundTrip.rotation == 30,
               "a watermark style round-trips through JSON, trimmed")
        suite.expect(ScreenshotSupport.WatermarkStyle.decoded(nil).kind == .none
                && ScreenshotSupport.WatermarkStyle.decoded("").kind == .none
                && ScreenshotSupport.WatermarkStyle.decoded("not json").kind == .none,
               "a missing or broken watermark style falls back to none")
        suite.expect(ScreenshotSupport.WatermarkStyle(kind: .text, text: "   ").sanitized().kind == .none
                && ScreenshotSupport.WatermarkStyle(kind: .image, imagePath: nil).sanitized().kind == .none
                && ScreenshotSupport.WatermarkStyle(kind: .image, imagePath: "").sanitized().kind == .none,
               "a watermark without its text or picture demotes to none")
        let wildMark = ScreenshotSupport.WatermarkStyle(kind: .text, text: "x", color: "bogus",
                                                        size: 7, opacity: 0, rotation: 400).sanitized()
        suite.expect(wildMark.color == "white" && wildMark.size == 1 && wildMark.opacity == 0.05
                && wildMark.rotation == 90,
               "watermark sliders clamp and an unknown color reads as white")
        let brokenMark = ScreenshotSupport.WatermarkStyle(kind: .text, text: "x", size: .nan,
                                                          opacity: .infinity, rotation: -.infinity)
            .sanitized()
        suite.expect(brokenMark.size == 0.3 && brokenMark.opacity == 0.4 && brokenMark.rotation == 0,
               "non-finite watermark sliders reset to their defaults")
        suite.expect(ScreenshotSupport.WatermarkStyle(kind: .text, text: String(repeating: "a", count: 500))
                .sanitized().text.count == ScreenshotSupport.WatermarkStyle.textLimit,
               "watermark text is capped")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotWatermarkStyle] as? String == ""
                && Defaults.registeredDefaults[DefaultsKey.screenshotWatermarkPresets] as? String == "[]",
               "the watermark style and presets register empty")
        let markPresets = [textMark.sanitized(),
                           ScreenshotSupport.WatermarkStyle(kind: .image, imagePath: "/logo.png",
                                                            anchor: .center, size: 0.8,
                                                            opacity: 0.2, rotation: -45)]
        suite.expect(ScreenshotSupport.decodedWatermarkPresets(
                ScreenshotSupport.encodedWatermarkPresets(markPresets)) == markPresets,
               "saved watermarks round-trip through JSON with their placement")
        suite.expect(ScreenshotSupport.decodedWatermarkPresets("junk").isEmpty
                && ScreenshotSupport.decodedWatermarkPresets(nil).isEmpty
                && ScreenshotSupport.decodedWatermarkPresets(
                    ScreenshotSupport.encodedWatermarkPresets(
                        [ScreenshotSupport.WatermarkStyle(kind: .text, text: " ")])).isEmpty,
               "broken preset lists and marks without content decode to nothing")
        suite.expect(ScreenshotSupport.decodedWatermarkPresets(
                ScreenshotSupport.encodedWatermarkPresets(
                    Array(repeating: markPresets[0], count: 40))).count
                == ScreenshotSupport.backdropPresetLimit,
               "saved watermarks cap at the presets limit")

        let hdCanvas = CGSize(width: 1920, height: 1080)
        suite.expect(ScreenshotSupport.watermarkFontSize(for: hdCanvas, factor: 0) == 22
                && ScreenshotSupport.watermarkFontSize(for: hdCanvas, factor: 1) == 173
                && ScreenshotSupport.watermarkFontSize(for: CGSize(width: 20, height: 20), factor: 0) == 8,
               "watermark text scales with the short side and keeps a legible floor")
        suite.expect(ScreenshotSupport.watermarkImageWidth(for: CGSize(width: 1000, height: 500), factor: 0) == 50
                && ScreenshotSupport.watermarkImageWidth(for: CGSize(width: 1000, height: 500), factor: 1) == 500
                && ScreenshotSupport.watermarkImageWidth(for: CGSize(width: 1000, height: 500), factor: 2) == 500,
               "a watermark picture spans from a corner mark to half the width")
        let markCanvas = CGSize(width: 1000, height: 600)
        let markSize = CGSize(width: 200, height: 50)
        let cornerMark = ScreenshotSupport.watermarkPlacement(contentSize: markSize, rotation: 0,
                                                              anchor: .bottomTrailing, in: markCanvas)
        suite.expect(cornerMark?.fit == 1 && cornerMark?.center == CGPoint(x: 870, y: 545),
               "an upright mark sits against the bottom-right margin")
        suite.expect(ScreenshotSupport.watermarkPlacement(contentSize: markSize, rotation: 0,
                                                    anchor: .center, in: markCanvas)?.center
                == CGPoint(x: 500, y: 300),
               "a centered mark sits in the middle of the capture")
        let turnedMark = ScreenshotSupport.watermarkPlacement(contentSize: markSize, rotation: 90,
                                                              anchor: .topLeading, in: markCanvas)
        suite.expectClose(Double(turnedMark?.center.x ?? 0), 55, "a turned mark is placed by its turned width")
        suite.expectClose(Double(turnedMark?.center.y ?? 0), 130, "a turned mark is placed by its turned height")
        let wideMark = ScreenshotSupport.watermarkPlacement(contentSize: CGSize(width: 2000, height: 100),
                                                            rotation: 0, anchor: .bottomTrailing,
                                                            in: markCanvas)
        suite.expectClose(Double(wideMark?.fit ?? 0), 0.47, "a mark wider than the capture shrinks to the margins")
        suite.expectClose(Double(wideMark?.center.x ?? 0), 500, "a shrunk mark spans the width between the margins")
        suite.expect(ScreenshotSupport.watermarkPlacement(contentSize: .zero, rotation: 0,
                                                    anchor: .center, in: markCanvas) == nil
                && ScreenshotSupport.watermarkPlacement(contentSize: markSize, rotation: .nan,
                                                        anchor: .center, in: markCanvas) == nil,
               "an empty or non-finite mark has no placement")

        // The exporter draws the mark where the placement says, over the
        // capture, and nothing at all while it is off.
        func solidImage(width: Int, height: Int, gray: CGFloat) -> CGImage? {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.setFillColor(CGColor(gray: gray, alpha: 1))
            context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
            return context?.makeImage()
        }
        func exportPixels(_ image: CGImage) -> [UInt8]? {
            var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: image.width,
                                              height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return true
            }
            return drawn ? data : nil
        }
        // A bitmap's first row is its top, so memory rows read in the
        // annotations' top-left space.
        func channel(_ data: [UInt8], width: Int, height: Int, x: Int, y: Int, _ index: Int) -> Int {
            Int(data[(y * width + x) * 4 + index])
        }
        func isWhite(_ data: [UInt8], width: Int, height: Int, x: Int, y: Int) -> Bool {
            (0..<3).allSatisfy { channel(data, width: width, height: height, x: x, y: y, $0) == 255 }
        }
        func markedExport(_ watermark: ScreenshotSupport.WatermarkStyle,
                          picture: CGImage?, base: CGImage) -> [UInt8]? {
            ScreenshotRenderer.renderExport(baseImage: base, annotations: [], pixelated: [:],
                                            scale: 1, annotationShadowsEnabled: false,
                                            watermark: watermark, watermarkImage: picture,
                                            style: ScreenshotSupport.BackdropStyle(kind: .none,
                                                                                   cornerRadius: 0),
                                            fill: .none, downscaleTo1x: false)
                .flatMap { exportPixels($0.image) }
        }
        let markWidth = 120
        let markHeight = 80
        if let white = solidImage(width: markWidth, height: markHeight, gray: 1),
           let stamp = solidImage(width: 4, height: 4, gray: 0) {
            let untouched = markedExport(ScreenshotSupport.WatermarkStyle(), picture: nil, base: white)
            suite.expect(untouched.map { data in
                (0..<markWidth).allSatisfy { x in
                    (0..<markHeight).allSatisfy { y in
                        isWhite(data, width: markWidth, height: markHeight, x: x, y: y)
                    }
                }
            } == true, "no watermark leaves the capture untouched")
            let textStamp = ScreenshotSupport.WatermarkStyle(kind: .text, text: "X", color: "black",
                                                             anchor: .bottomTrailing, size: 1,
                                                             opacity: 1)
            let stamped = markedExport(textStamp, picture: nil, base: white)
            suite.expect(stamped.map { data in
                (100..<markWidth).contains { x in
                    (56..<markHeight).contains { y in
                        !isWhite(data, width: markWidth, height: markHeight, x: x, y: y)
                    }
                }
            } == true, "a text watermark lands in its corner of the export")
            suite.expect(stamped.map { data in
                (0..<60).allSatisfy { x in
                    (0..<40).allSatisfy { y in
                        isWhite(data, width: markWidth, height: markHeight, x: x, y: y)
                    }
                }
            } == true, "a corner text watermark leaves the opposite corner alone")
            let pictureStamp = ScreenshotSupport.WatermarkStyle(kind: .image, imagePath: "/stamp.png",
                                                                anchor: .topLeading, size: 1,
                                                                opacity: 1)
            let pictured = markedExport(pictureStamp, picture: stamp, base: white)
            // Width factor 1 is half the capture, 60 pixels, so the picture
            // fills the top-left 4...64 square behind the 5% margin.
            suite.expect(pictured.map { data in
                channel(data, width: markWidth, height: markHeight, x: 34, y: 10, 0) < 40
                    && channel(data, width: markWidth, height: markHeight, x: 62, y: 62, 0) < 40
                    && isWhite(data, width: markWidth, height: markHeight, x: 66, y: 34)
                    && isWhite(data, width: markWidth, height: markHeight, x: 34, y: 70)
                    && isWhite(data, width: markWidth, height: markHeight, x: 100, y: 70)
            } == true, "a picture watermark covers exactly its placed square")
            let faded = markedExport(
                ScreenshotSupport.WatermarkStyle(kind: .image, imagePath: "/stamp.png",
                                                 anchor: .topLeading, size: 1, opacity: 0.5),
                picture: stamp, base: white)
            suite.expect(faded.map { data in
                let value = channel(data, width: markWidth, height: markHeight, x: 34, y: 34, 0)
                return value > 100 && value < 160
            } == true, "a faded watermark lets the capture through")
            suite.expect(markedExport(pictureStamp, picture: nil, base: white).map { data in
                isWhite(data, width: markWidth, height: markHeight, x: 34, y: 34)
            } == true, "a picture watermark whose file is missing draws nothing")
        }

        let wordBoxes = [CGRect(x: 0, y: 0, width: 40, height: 10),
                         CGRect(x: 50, y: 0, width: 40, height: 10),
                         CGRect(x: 0, y: 20, width: 40, height: 10)]
        suite.expect(ScreenshotSupport.wordSelection(anchor: CGPoint(x: 5, y: 5),
                                               current: CGPoint(x: 60, y: 5),
                                               boxes: wordBoxes) == [0, 1],
               "a drag across a line selects the words it crosses")
        suite.expect(ScreenshotSupport.wordSelection(anchor: CGPoint(x: 5, y: 5),
                                               current: CGPoint(x: 10, y: 25),
                                               boxes: wordBoxes) == [0, 2],
               "a drag across lines selects into the next line")
        let recognizedWords = [
            ScreenshotSupport.RecognizedWord(text: "ola", rect: wordBoxes[0], line: 0),
            ScreenshotSupport.RecognizedWord(text: "mundo", rect: wordBoxes[1], line: 0),
            ScreenshotSupport.RecognizedWord(text: "linha", rect: wordBoxes[2], line: 1),
        ]
        suite.expect(ScreenshotSupport.joinedWords(recognizedWords, selected: [1, 0]) == "ola mundo",
               "selected words join in reading order with spaces")
        suite.expect(ScreenshotSupport.joinedWords(recognizedWords, selected: [2, 0]) == "ola\nlinha",
               "line changes become newlines")
        suite.expect(ScreenshotSupport.joinedWords(recognizedWords, selected: [9]).isEmpty
                && ScreenshotSupport.joinedWords(recognizedWords, selected: []).isEmpty,
               "out of range or empty selections copy nothing")
        let defaultScreenshotTools = ScreenshotSupport.Tool.allCases
        suite.expect(defaultScreenshotTools.count == 13
                && Array(defaultScreenshotTools.prefix(9))
                    == [.select, .arrow, .pixelate, .crop, .text, .sticker,
                        .rect, .highlight, .freehand],
               "the screenshot rail leads with the nine most useful numbered tools")
        let customScreenshotTools = ScreenshotSupport.Tool.ordered(
            from: "crop,arrow,arrow,invalid")
        suite.expect(Array(customScreenshotTools.prefix(2)) == [.crop, .arrow]
                && customScreenshotTools.count == 13
                && Set(customScreenshotTools).count == 13,
               "a saved screenshot tool order drops invalid duplicates and appends missing tools")
        suite.expect(ScreenshotSupport.Tool.shortcutTool(number: 1,
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
        suite.expect(ScreenshotSupport.Tool.shortcutNumber(for: .crop,
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
        suite.expect(cropAssignedFirst.first == .crop
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

        // MARK: Remappable screenshot tool shortcuts
        do {
            typealias Tool = ScreenshotSupport.Tool
            let text = GlobalShortcut(keyCode: Int64(kVK_ANSI_T), modifiers: [])
            let pen = GlobalShortcut(keyCode: Int64(kVK_ANSI_K), modifiers: [.control, .option, .command])
            let one = GlobalShortcut(keyCode: Int64(kVK_ANSI_1), modifiers: [])
            let raw = Tool.bindingsStorage([.text: text, .freehand: pen])
            suite.expect(Tool.bindings(from: raw) == [.text: text, .freehand: pen], "tool bindings round trip")
            suite.expect(raw == "text=:17,freehand=control+option+command:40", "tool binding storage has stable tool order")
            suite.expect(GlobalShortcut(storageValue: text.storageValue) == nil
                && GlobalShortcut(storageValue: text.storageValue, requiringModifier: false) == text,
                "bare editor keys do not weaken global shortcut validation")
            suite.expect(Tool.bindings(from: "unknown=:17,text=oops,rect=super:15,arrow=:999999").isEmpty
                && Tool.bindings(from: "").isEmpty, "invalid imported tool bindings are discarded")
            suite.expect(Tool.bindings(from: "text=:17,text=:45")[.text]?.keyCode == Int64(kVK_ANSI_N),
                   "the last valid binding for a duplicate tool wins")
            suite.expect(Tool.bindings(from: "text=:17,arrow=:17") == [.arrow: text],
                   "duplicate imported shortcuts have one deterministic owner")
            let commandKeys = [kVK_ANSI_C, kVK_ANSI_S, kVK_ANSI_Z, kVK_ANSI_P, kVK_ANSI_0,
                               kVK_ANSI_1, kVK_ANSI_Equal, kVK_ANSI_Minus, kVK_Delete,
                               kVK_ForwardDelete, kVK_ANSI_W, kVK_ANSI_Q]
            for key in commandKeys {
                for flags: GlobalShortcutModifiers in [.command, [.command, .shift], [.command, .option, .control]] {
                    let reserved = GlobalShortcut(keyCode: Int64(key), modifiers: flags)
                    suite.expect(Tool.isReservedEditorKey(reserved)
                        && Tool.bindings(from: "text=\(reserved.storageValue)").isEmpty,
                        "editor and menu command \(reserved.storageValue) stays reserved on read")
                }
            }
            for key in [kVK_Escape, kVK_Return, kVK_ANSI_KeypadEnter, kVK_Delete, kVK_ForwardDelete] {
                suite.expect(Tool.isReservedEditorKey(.init(keyCode: Int64(key), modifiers: []))
                    && Tool.isReservedEditorKey(.init(keyCode: Int64(key), modifiers: .shift)),
                    "bare and shifted editor action \(key) cannot be rebound")
            }
            suite.expect(!Tool.isReservedEditorKey(text) && !Tool.isReservedEditorKey(pen), "custom tool keys are allowed")
            func resolve(_ key: GlobalShortcut, number: Int? = nil, bindings: String? = raw,
                         enabled: Bool = true) -> Tool? {
                Tool.shortcutTool(keyCode: key.keyCode, modifiers: key.modifiers, number: number,
                                  orderRaw: nil, bindingsRaw: bindings, enabled: enabled)
            }
            suite.expect(resolve(text) == .text && resolve(pen) == .freehand, "bare and modified keys select their tools")
            suite.expect(resolve(text, enabled: false) == nil && resolve(one, number: 1, enabled: false) == nil,
                   "disabling shortcuts gates both custom bindings and position digits")
            suite.expect(resolve(.init(keyCode: text.keyCode, modifiers: .shift)) == nil,
                   "custom bindings require an exact modifier match")
            suite.expect(resolve(.init(keyCode: Int64(kVK_ANSI_5), modifiers: []), number: 5) == nil,
                   "a rebound tool no longer answers to its old digit")
            suite.expect(resolve(.init(keyCode: Int64(kVK_ANSI_5), modifiers: []), number: 5,
                           bindings: "text=command:8") == .text,
                   "a rejected reserved binding falls back to the position digit")
            // Every outside owner is injected: the real checks read defaults
            // and the WindowServer, and the order is the point under test.
            func rejection(_ key: GlobalShortcut, excluding tool: Tool = .arrow,
                           role: GlobalShortcutRole? = nil, layout: String? = nil,
                           system: Bool = false) -> Tool.BindingRejection? {
                Tool.bindingRejection(for: key, excluding: tool, bindingsRaw: raw,
                                      roleConflict: { _ in role },
                                      windowLayoutConflict: { _ in layout },
                                      systemConflict: { _ in system })
            }
            suite.expect(rejection(text) == .tool(.text) && rejection(text, excluding: .text) == nil
                && rejection(pen, excluding: .freehand) == nil,
                   "a key bound to another tool is rejected and a tool's own key is not")
            suite.expect(rejection(pen, excluding: .freehand, role: .keepAwake) == .role(.keepAwake)
                && rejection(pen, excluding: .freehand, layout: "Left") == .windowLayout("Left")
                && rejection(pen, excluding: .freehand, system: true) == .system,
                   "keys owned by an enabled feature, a window layout action or macOS are rejected before saving")
            suite.expect(rejection(.init(keyCode: Int64(kVK_Escape), modifiers: []), role: .keepAwake) == .reserved
                && rejection(text, role: .keepAwake, system: true) == .tool(.text)
                && rejection(pen, excluding: .freehand, role: .keepAwake, layout: "Left") == .role(.keepAwake)
                && rejection(pen, excluding: .freehand, layout: "Left", system: true) == .windowLayout("Left"),
                   "editor keys and tools answer first and the system table is read last")
            for (index, tool) in Tool.allCases.enumerated() {
                suite.expect(Tool.shortcutTool(keyCode: -1, modifiers: [], number: index + 1,
                        orderRaw: nil, bindingsRaw: "", enabled: true)
                    == Tool.shortcutTool(number: index + 1, orderRaw: nil, enabled: true),
                       "empty bindings preserve position behavior for \(tool)")
                suite.expect((Tool.shortcutLabel(for: tool, orderRaw: nil, bindingsRaw: "", enabled: true) != nil)
                    == (index < Tool.shortcutLimit), "only the first nine tools get default badges")
            }
            suite.expect(Tool.shortcutLabel(for: .text, orderRaw: nil, bindingsRaw: raw, enabled: true) == text.displayString
                && Tool.shortcutLabel(for: .text, orderRaw: nil, bindingsRaw: raw, enabled: false) == nil,
                   "a bound tool's badge shows its caps and disabling shortcuts hides every badge")
            suite.expect(resolve(.init(keyCode: Int64(kVK_ANSI_1), modifiers: .shift), number: 1, bindings: "") == .select,
                   "AZERTY Shift plus a printed digit preserves the existing digit path")
            let moved = Tool.assigningBinding(one, digit: 1, to: .text, orderRaw: nil, bindingsRaw: raw)
            suite.expect(Tool.ordered(from: moved.orderRaw).first == .text
                && Tool.bindings(from: moved.bindingsRaw) == [.freehand: pen],
                   "recording a digit moves the tool and clears its custom binding")
            let cleared = Tool.assigningBinding(nil, to: .text, orderRaw: nil, bindingsRaw: raw)
            suite.expect(Tool.ordered(from: cleared.orderRaw).firstIndex(of: .text) == Tool.shortcutLimit
                && Tool.shortcutLabel(for: .text, orderRaw: cleared.orderRaw,
                    bindingsRaw: cleared.bindingsRaw, enabled: true) == nil,
                   "Delete clears the binding and moves the tool outside the numbered slots")
            let rebound = Tool.assigningBinding(text, to: .text, orderRaw: "crop,text", bindingsRaw: "")
            suite.expect(Tool.ordered(from: rebound.orderRaw).prefix(2) == [.crop, .text]
                && Tool.bindings(from: rebound.bindingsRaw)[.text] == text, "custom recording preserves rail order")
            suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotToolShortcuts] as? String == ""
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.screenshotToolShortcuts),
                   "empty tool bindings are registered and included in settings backups")
            // What a key "is" comes from what it types on the active layout,
            // so these pin the layout instead of trusting the test machine's.
            if let usData = testLayoutData(for: "com.apple.keylayout.US") {
                GlobalShortcut.refreshLayoutLabels(layoutData: usData)
                let shiftedOne = GlobalShortcut(keyCode: Int64(kVK_ANSI_1), modifiers: .shift)
                suite.expect(Tool.shortcutDigit(one) == 1
                    && Tool.shortcutDigit(.init(keyCode: Int64(kVK_ANSI_Keypad1), modifiers: [])) == 1
                    && Tool.shortcutDigit(shiftedOne) == nil
                    && Tool.shortcutDigit(.init(keyCode: Int64(kVK_ANSI_1), modifiers: .command)) == nil
                    && Tool.shortcutDigit(.init(keyCode: Int64(kVK_ANSI_0), modifiers: [])) == nil
                    && Tool.shortcutDigit(text) == nil,
                       "on US a bare or keypad digit names a slot; ⇧1 types !, and ⌘1, 0 and letters do not")
                suite.expect(Tool.bindings(from: "text=\(one.storageValue)")[.text] == one
                    && Tool.activeBindings(from: "text=\(one.storageValue)").isEmpty
                    && resolve(one, number: 1, bindings: "text=\(one.storageValue)") == .select
                    && Tool.bindings(from: Tool.bindingsStorage([.text: shiftedOne]))[.text] == shiftedOne,
                       "a saved binding on a digit key is suspended so the digit keeps its slot, ⇧1 stays a key")
            }
            if let frenchData = testLayoutData(for: "com.apple.keylayout.French") {
                GlobalShortcut.refreshLayoutLabels(layoutData: frenchData)
                let shiftedOne = GlobalShortcut(keyCode: Int64(kVK_ANSI_1), modifiers: .shift)
                suite.expect(GlobalShortcut.layoutKeyLabel(for: one.keyCode, usesCommand: false) == "&"
                    && GlobalShortcut.layoutKeyLabel(for: one.keyCode, usesCommand: false, usesShift: true) == "1"
                    && Tool.shortcutDigit(shiftedOne) == 1 && Tool.shortcutDigit(one) == nil,
                       "AZERTY reads 1 from Shift on the & key and leaves bare & as a key")
                let ampersand = Tool.bindingsStorage([.text: one])
                suite.expect(Tool.bindings(from: ampersand)[.text] == one
                    && Tool.activeBindings(from: Tool.bindingsStorage([.text: shiftedOne])).isEmpty
                    && Tool.bindingRejection(for: one, excluding: .text, bindingsRaw: "",
                                             roleConflict: { _ in nil }, windowLayoutConflict: { _ in nil },
                                             systemConflict: { _ in false }) == nil,
                       "AZERTY records & as a binding with no conflict against 1, and ⇧& is a slot, not a binding")
                let movedFrench = Tool.assigningBinding(shiftedOne, digit: Tool.shortcutDigit(shiftedOne),
                                                        to: .text, orderRaw: nil, bindingsRaw: ampersand)
                suite.expect(Tool.ordered(from: movedFrench.orderRaw).first == .text
                    && Tool.bindings(from: movedFrench.bindingsRaw).isEmpty
                    && Tool.shortcutTool(keyCode: shiftedOne.keyCode, modifiers: shiftedOne.modifiers, number: 1,
                                         orderRaw: movedFrench.orderRaw, bindingsRaw: movedFrench.bindingsRaw,
                                         enabled: true) == .text,
                       "AZERTY Shift+& moves the tool into slot 1 instead of saving ⇧&, and then selects it")
            }
            for layoutID in ["com.apple.keylayout.French", "com.apple.keylayout.Russian"] {
                if let data = testLayoutData(for: layoutID) {
                    GlobalShortcut.refreshLayoutLabels(layoutData: data)
                    let key = GlobalShortcut(keyCode: Int64(kVK_ANSI_Q), modifiers: [])
                    let binding = Tool.bindingsStorage([.text: key])
                    suite.expect(key.displayString == (layoutID.hasSuffix("French") ? "A" : "Й")
                        && resolve(key, bindings: binding) == .text,
                           "custom tool keys route and label correctly for \(layoutID)")
                }
            }
            GlobalShortcut.refreshLayoutLabels()
            let suiteName = "com.vorssaint.tests.editor-bindings.\(UUID().uuidString)"
            let prefs = UserDefaults(suiteName: suiteName)!
            defer { prefs.removePersistentDomain(forName: suiteName) }
            prefs.set(false, forKey: DefaultsKey.screenshotToolShortcutsEnabled)
            prefs.register(defaults: Defaults.registeredDefaults)
            prefs.set(raw, forKey: DefaultsKey.screenshotToolShortcuts)
            suite.expect(!prefs.bool(forKey: DefaultsKey.screenshotToolShortcutsEnabled)
                && Tool.bindings(from: prefs.string(forKey: DefaultsKey.screenshotToolShortcuts))[.text] == text,
                   "registering and saving bindings preserves an existing disabled preference")
        }

        suite.expect(ScreenshotSupport.cropLoupeSampleRect(
            around: CGPoint(x: 50, y: 40),
            imageSize: CGSize(width: 100, height: 80))
            == CGRect(x: 44, y: 34, width: 13, height: 13),
               "the crop loupe centers its source pixels around an inner grip")
        suite.expect(ScreenshotSupport.cropLoupeSampleRect(
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
            suite.expectClose(Double(marked.midX), Double(loupeFrame.midX),
                        "the loupe marks the pixel in the middle of its frame across the zoom range")
            suite.expectClose(Double(marked.midY), Double(loupeFrame.midY),
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
        suite.expect(cropEdgeSample == CGRect(x: 93, y: 53, width: 14, height: 14)
                && cropEdgeSample.midX == 100 && cropEdgeSample.midY == 60,
               "the crop loupe centres its sample on the handle's edge, not on a pixel cell")
        suite.expect(ScreenshotSupport.cropLoupeSampleRect(
            around: CGPoint(x: 100, y: 60),
            imageSize: CGSize(width: 400, height: 300),
            sideLength: 13,
            centredOnPixel: false).width == 14,
               "an odd side grows to the next even one when the loupe centres on an edge")

        suite.expect(ScreenshotSupport.cropLoupeSampleRect(
            around: .zero,
            imageSize: CGSize(width: 8, height: 5))
            == CGRect(x: 0, y: 0, width: 8, height: 5),
               "the crop loupe safely shrinks only for images smaller than its sample")
        suite.expect(ScreenshotSupport.captureLoupeTargetPixelRect(
            around: CGPoint(x: 50.5, y: 40.2),
            source: CGRect(x: 43, y: 33, width: 14, height: 14),
            frame: CGRect(x: 0, y: 0, width: 70, height: 70))
            == CGRect(x: 35, y: 35, width: 5, height: 5),
               "the loupe highlights one whole source pixel, not the pointer's sub-pixel position")
        suite.expect(ScreenshotSupport.captureLoupeTargetPixelRect(
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
        suite.expect(loupeAimFailure == nil,
               loupeAimFailure ?? "the loupe highlight marks the pixel the color picker copies")
        suite.expect(ScreenshotSupport.captureLoupeTargetPixelRect(
            around: .zero, source: .zero, frame: CGRect(x: 0, y: 0, width: 70, height: 70))
            == CGRect(x: 0, y: 0, width: 70, height: 70),
               "an empty sample leaves the loupe highlight harmless instead of dividing by zero")
        suite.expectClose(ScreenshotSupport.captureLoupeZoom(1, adjustedBy: 1), 1.15,
                    "scrolling up zooms the capture loupe in")
        suite.expectClose(ScreenshotSupport.captureLoupeInitialZoom(
            rememberLast: false, defaultZoom: 2, lastZoom: 4), 2,
                    "the capture loupe starts at its chosen default zoom")
        suite.expectClose(ScreenshotSupport.captureLoupeInitialZoom(
            rememberLast: true, defaultZoom: 2, lastZoom: 4), 4,
                    "the capture loupe can restore its last zoom")
        suite.expectClose(ScreenshotSupport.captureLoupeInitialZoom(
            rememberLast: false, defaultZoom: .nan, lastZoom: 4), 1,
                    "an invalid saved magnifier zoom falls back safely")
        suite.expectClose(ScreenshotSupport.captureLoupeWheelDelta(
            scrollingDelta: 0, lineDelta: 0, fixedPointDelta: 0.25), 0.25,
                    "fractional mouse-wheel notches do not disappear when AppKit rounds to zero")
        suite.expectClose(ScreenshotSupport.captureLoupeWheelDelta(
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
        suite.expect(steppedLoupeSides == [25, 23, 21, 19, 17, 15, 13, 11, 9, 7, 5, 3],
               "every stepped wheel notch changes one visible level across the whole zoom range")
        for _ in 0..<12 {
            steppedLoupeZoom = ScreenshotSupport.captureLoupeSteppedZoom(
                steppedLoupeZoom, adjustedBy: -0.25)
        }
        suite.expectClose(steppedLoupeZoom, ScreenshotSupport.captureLoupeMinZoom,
                    "all stepped magnifier levels are reversible without dead notches")
        var fastLoupeZoom: CGFloat = 1
        for _ in 0..<6 {
            fastLoupeZoom = ScreenshotSupport.captureLoupeZoom(
                fastLoupeZoom, adjustedBy: 20)
        }
        suite.expect(fastLoupeZoom > 2,
               "fast magnifier zoom preserves the original packet-by-packet behavior")
        suite.expect(ScreenshotSupport.captureLoupeUsesSteppedZoom(
            steppedByDefault: true, optionPressed: false)
                && !ScreenshotSupport.captureLoupeUsesSteppedZoom(
                    steppedByDefault: true, optionPressed: true)
                && ScreenshotSupport.captureLoupeUsesSteppedZoom(
                    steppedByDefault: false, optionPressed: true),
               "Option temporarily swaps the chosen magnifier wheel mode")
        suite.expectClose(ScreenshotSupport.captureLoupeZoom(0.5, adjustedBy: -1), 0.5,
                    "capture loupe zoom stays above its minimum")
        suite.expectClose(ScreenshotSupport.captureLoupeZoom(10, adjustedBy: 1),
                    ScreenshotSupport.captureLoupeMaxZoom,
                    "capture loupe zoom stays below its maximum")
        suite.expectClose(ScreenshotSupport.captureLoupeMaxZoom,
                    ScreenshotSupport.captureLoupeBaseSampleSide
                        / ScreenshotSupport.captureLoupeMinSampleSide,
                    "the zoom ceiling is derived from the smallest useful sample")
        suite.expectClose(ScreenshotSupport.captureLoupeZoom(4, adjustedBy: 1),
                    ScreenshotSupport.captureLoupeMaxZoom,
                    "zoom reaches the three-pixel sample without a dead range above it")
        suite.expectClose(ScreenshotSupport.captureLoupeSampleSide(zoom: 2), 7,
                    "higher capture loupe zoom samples fewer source pixels")
        suite.expectClose(ScreenshotSupport.captureLoupeSampleSide(zoom: 0.5), 27,
                    "zooming the loupe out widens the sample")
        suite.expectClose(ScreenshotSupport.captureLoupeSampleSide(
            zoom: ScreenshotSupport.captureLoupeMaxZoom), 3,
                    "maximum loupe zoom keeps a three pixel sample around the pointer")
        suite.expect([0.5, 1, 2, 4, ScreenshotSupport.captureLoupeMaxZoom].allSatisfy { zoom in
            let side = ScreenshotSupport.captureLoupeSampleSide(zoom: zoom)
            return side.truncatingRemainder(dividingBy: 2) == 1
        }, "every loupe sample side is odd so an exact center pixel exists")
        suite.expect(ScreenshotSupport.captureLoupeGridVisible(
                    frameSide: ScreenshotSupport.captureLoupeFrameSide, sampleSide: 13)
                && !ScreenshotSupport.captureLoupeGridVisible(
                    frameSide: ScreenshotSupport.captureLoupeFrameSide, sampleSide: 27)
                && !ScreenshotSupport.captureLoupeGridVisible(
                    frameSide: ScreenshotSupport.captureLoupeFrameSide, sampleSide: 0),
               "the loupe pixel grid appears only when cells are readable")
        suite.expect(ScreenshotSupport.captureLoupeNudge(dx: 1, dy: 0, fast: false, scale: 2)
                == CGPoint(x: 0.5, y: 0),
               "an arrow nudge moves exactly one device pixel on Retina")
        suite.expect(ScreenshotSupport.captureLoupeNudge(dx: 0, dy: -1, fast: true, scale: 2)
                == CGPoint(x: 0, y: -5),
               "a shifted nudge covers ten device pixels")
        suite.expect(ScreenshotSupport.captureLoupeNudge(dx: -1, dy: 1, fast: false, scale: 0)
                == CGPoint(x: -1, y: 1),
               "a missing display scale falls back to whole points")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotFreeze] as? Bool == true,
               "the screen freezes during selection by default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotShortcutEnabled] as? Bool == false,
               "the screenshot shortcut ships off like the other quick tools")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotAnnotationShadows] as? Bool == false,
               "screenshot annotation shadows ship off")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotShowLastRegion] as? Bool == true,
               "the previous capture outline stays visible by default, as it always was")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotLoupeStartsOn] as? Bool == false,
               "the always-on loupe is an opt-in and ships off")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotLoupeRememberZoom] as? Bool == false
                && Defaults.registeredDefaults[DefaultsKey.screenshotLoupeDefaultZoom] as? Double == 1
                && Defaults.registeredDefaults[
                    DefaultsKey.screenshotLoupeSteppedZoomByDefault] as? Bool == false,
               "magnifier zoom preferences preserve the original behavior by default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotToolShortcutsEnabled] as? Bool == true,
               "screenshot number shortcuts ship enabled")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotPreviewPosition] as? String == "",
               "screenshot preview placement preserves the existing automatic behavior by default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotPreviewTakesFocus] as? Bool == true,
               "the screenshot preview takes the keyboard as it appears by default, so its shortcuts work at once; leaving it is the opt-out")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotSharingEnabled] as? Bool == true,
               "temporary screenshot links preserve their existing availability by default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotToolOrder] as? String
                == ScreenshotSupport.Tool.defaultOrderStorage,
               "the screenshot rail ships in its useful numbered order")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotLastBlurLevel] as? Int
                == ScreenshotSupport.BlurStrength.defaultLevel,
               "the pixelate tool starts at the strength it always had")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotLastTextSize] as? Int
                == ScreenshotSupport.defaultTextSize,
               "text starts at the size the medium thickness used to give it")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotLastSticker] as? String == "check",
               "the sticker tool starts with a safe built-in choice")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotLastArrowStyle] as? String == "filled",
               "the arrow tool starts with the existing solid style")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotShortcut] as? String
                == "control+option+command:21",
               "the default screenshot shortcut is control option command 4")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotFullScreenShortcutEnabled]
                as? Bool == false,
               "the direct full-screen shortcut ships off")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotFullScreenShortcut] as? String
                == "control+option+command:20",
               "the full-screen shortcut sits beside screenshot selection")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotLastCaptureShortcutEnabled]
                as? Bool == false,
               "the latest screenshot editor shortcut ships off")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotLastCaptureShortcut] as? String
                == "control+option+command:14",
               "the latest screenshot editor shortcut defaults to control option command E")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.recentCapturesShortcutEnabled]
                as? Bool == false,
               "the recent captures shortcut ships off")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.recentCapturesShortcut] as? String
                == "control+option+command:4",
               "the recent captures shortcut defaults to control option command H")
        suite.expect(ScreenshotShareDuration.allCases.map(\.rawValue) == [3_600, 21_600, 86_400],
               "temporary links allow only one, six or twenty-four hours")
        let testShareEndpoint = ScreenshotSharingSupport.endpoint(
            bundleIdentifier: ScreenshotSharingSupport.developerBundleIdentifier,
            developerOverride: "https://test.example/")
        suite.expect(testShareEndpoint.absoluteString == "https://test.example"
                && ScreenshotSharingSupport.endpoint(
                    bundleIdentifier: "com.vorssaint.utils",
                    developerOverride: "https://test.example").absoluteString
                    == ScreenshotSharingSupport.productionEndpoint.absoluteString
                && ScreenshotSharingSupport.endpoint(
                    bundleIdentifier: ScreenshotSharingSupport.developerBundleIdentifier,
                    developerOverride: "http://test.example")
                    == ScreenshotSharingSupport.productionEndpoint,
               "only the Developer build accepts a valid HTTPS test endpoint")
        suite.expect(ScreenshotSharingSupport.uploadURL(endpoint: testShareEndpoint,
                                                  duration: .sixHours)?.absoluteString
                == "https://test.example/v1/screenshots?expiresIn=21600",
               "sharing builds the fixed upload route and expiration query")
        let shareNow = Date(timeIntervalSince1970: 1_000)
        let shareResponse = ScreenshotShareResponse(
            id: String(repeating: "a", count: 32),
            viewPath: "/s/\(String(repeating: "a", count: 32))",
            expiresAt: "1970-01-01T01:16:40.125Z",
            deleteToken: String(repeating: "b", count: 43))
        suite.expect(ScreenshotSharingSupport.record(response: shareResponse,
                                                endpoint: testShareEndpoint,
                                                now: shareNow)?.url.absoluteString
                == "https://test.example/s/\(String(repeating: "a", count: 32))",
               "a valid service response becomes an owner-held link record")
        let forgedShareResponse = ScreenshotShareResponse(
            id: "guessable",
            viewPath: "/s/guessable",
            expiresAt: "1970-01-01T01:16:40.125Z",
            deleteToken: "short")
        suite.expect(ScreenshotSharingSupport.record(response: forgedShareResponse,
                                                endpoint: testShareEndpoint,
                                                now: shareNow) == nil,
               "guessable ids and short deletion tokens are rejected")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityScreenshot] as? Bool == true,
               "the panel row ships visible like its siblings")
        let recentCaptureIDs = (0..<14).map { _ in UUID() }
        suite.expect(ScreenshotSupport.cappedRecentCaptureIDs(recentCaptureIDs)
                == Array(recentCaptureIDs.prefix(12))
                && ScreenshotSupport.recentCaptureLimit == 12,
               "recent captures keeps only the newest bounded set")
        let oversizedCaptureIDs = Array(recentCaptureIDs.prefix(3))
        suite.expect(ScreenshotSupport.cappedRecentCaptureIDs(
            oversizedCaptureIDs,
            screenshotBytes: [
                oversizedCaptureIDs[0]: ScreenshotSupport.recentCaptureMaximumBytes - 1,
                oversizedCaptureIDs[1]: 2,
            ]) == [oversizedCaptureIDs[0], oversizedCaptureIDs[2]],
               "recent captures keeps the latest screenshot and respects its disk budget")
        suite.expect(GlobalShortcutRole.screenshot.requiredEnableKeys == [DefaultsKey.screenshotShortcutEnabled]
                && GlobalShortcutRole.screenshot.availabilityFeatures == [.screenshot],
               "the screenshot shortcut keeps its old keys and follows its own tool")
        suite.expect(!GlobalShortcutRole.availableRoles(isAvailable: recordingOnly.contains)
                .contains(.screenshot)
                && GlobalShortcutRole.availableRoles(isAvailable: recordingOnly.contains)
                    .contains(.screenRecorder)
                && GlobalShortcutRole.availableRoles(isAvailable: recordingOnly.contains)
                    .contains(.recentCaptures),
               "a recording-only install keeps the recorder and shared capture history shortcuts")
        suite.expect(GlobalShortcutRole.screenshotFullScreen.requiredEnableKeys
                == [DefaultsKey.screenshotFullScreenShortcutEnabled]
                && GlobalShortcutRole.screenshotFullScreen.feature == .screenshot,
               "the full-screen shortcut has its own opt-in gate")
        suite.expect(GlobalShortcutRole.screenshotLastCapture.requiredEnableKeys
                == [DefaultsKey.screenshotLastCaptureShortcutEnabled]
                && GlobalShortcutRole.screenshotLastCapture.feature == .screenshot,
               "the latest screenshot shortcut gates on its own toggle and the screenshot feature")
        suite.expect(GlobalShortcutRole.recentCaptures.requiredEnableKeys
                == [DefaultsKey.recentCapturesShortcutEnabled]
                && GlobalShortcutRole.recentCaptures.availabilityFeatures
                    == [.screenshot, .screenRecorder],
               "the recent captures shortcut follows either feature that fills its history")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotClipboardShortcutEnabled]
                as? Bool == false
                && Defaults.registeredDefaults[DefaultsKey.screenshotClipboardShortcut] as? String
                == "control+option+command:35",
               "the clipboard image editor shortcut ships off with its own combination")
        suite.expect(GlobalShortcutRole.screenshotClipboard.requiredEnableKeys
                == [DefaultsKey.screenshotClipboardShortcutEnabled]
                && GlobalShortcutRole.screenshotClipboard.feature == .screenshot,
               "the clipboard image shortcut gates on its own toggle and the screenshot feature")
        suite.expect(ScreenshotSupport.clipboardImageScale(
            pixelSize: CGSize(width: 1200, height: 800),
            pointSize: CGSize(width: 600, height: 400)) == 2,
               "copied images preserve a consistent Retina scale")
        suite.expect(ScreenshotSupport.clipboardImageScale(
            pixelSize: CGSize(width: 1200, height: 800),
            pointSize: CGSize(width: 600, height: 800)) == 1,
               "copied images with inconsistent metadata safely use 1x")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.cameraPreviewShortcutEnabled] as? Bool == false,
               "the camera preview shortcut ships off like the other quick tools")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.cameraPreviewShortcut] as? String
                == "control+option+command:13",
               "the default camera preview shortcut is control option command W")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityCameraPreview] as? Bool == true,
               "the camera preview panel row ships visible like its siblings")
        suite.expect(GlobalShortcutRole.cameraPreview.requiredEnableKeys == [DefaultsKey.cameraPreviewShortcutEnabled]
                && GlobalShortcutRole.cameraPreview.feature == .cameraPreview,
               "the camera preview shortcut role gates on its toggle and feature")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.scratchpadShortcutEnabled] as? Bool == false,
               "the scratchpad shortcut ships off like the other quick tools")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.scratchpadShortcut] as? String
                == "control+option+command:45",
               "the default scratchpad shortcut is control option command N")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityScratchpad] as? Bool == true,
               "the scratchpad panel row ships visible like its siblings")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.scratchpadRetention] as? String == "never",
               "the scratchpad keeps text until cleared by default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.scratchpadCloseOnClickOutside] as? Bool == true,
               "a click outside puts the scratchpad away unless the user keeps it floating")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.scratchpadCloseOnClickOutside),
               "the scratchpad dismissal choice travels with the settings backup")
        suite.expect(GlobalShortcutRole.scratchpad.requiredEnableKeys == [DefaultsKey.scratchpadShortcutEnabled]
                && GlobalShortcutRole.scratchpad.feature == .scratchpad,
               "the scratchpad shortcut role gates on its toggle and feature")
        let scratchpadViewSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Scratchpad/ScratchpadView.swift",
            encoding: .utf8)) ?? ""
        let scratchpadHitTargetContracts = [
            "Image(systemName: \"plus\")\n                    .font(.system(size: 12, weight: .semibold))\n                    .frame(width: 22, height: 22)\n                    .contentShape(Rectangle())",
            "Image(systemName: \"ellipsis\")\n                    .font(.system(size: 12, weight: .semibold))\n                    .frame(width: 22, height: 22)\n                    .contentShape(Rectangle())",
            ".fill(selected ? Color.accentColor.opacity(0.16) : Color.clear)\n                }\n                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))",
            "Image(systemName: service.isPinned ? \"pin.fill\" : \"pin\")\n                    .font(.system(size: 12, weight: .semibold))\n                    .frame(width: 22, height: 22)\n                    .contentShape(Rectangle())",
            "Image(systemName: \"xmark.circle.fill\")\n                    .font(.system(size: 14))\n                    .foregroundStyle(.secondary)\n                    .frame(width: 22, height: 22)\n                    .contentShape(Rectangle())",
        ]
        suite.expect(scratchpadHitTargetContracts.allSatisfy { scratchpadViewSource.contains($0) },
               "the scratchpad tab bar and header controls keep their full padded hit targets")
        suite.expect(ScratchpadRetention.sanitized("day") == .day
                && ScratchpadRetention.sanitized("week") == .week
                && ScratchpadRetention.sanitized("month") == .month
                && ScratchpadRetention.sanitized(nil) == .never
                && ScratchpadRetention.sanitized("yesterday") == .never,
               "scratchpad retention sanitizes to the allowed periods and falls back to never")
        suite.expect(ScratchpadRetention.never.maxIdleInterval == nil
                && ScratchpadRetention.day.maxIdleInterval == 86_400
                && ScratchpadRetention.week.maxIdleInterval == 7 * 86_400
                && ScratchpadRetention.month.maxIdleInterval == 30 * 86_400,
               "scratchpad retention periods are a day, a week and thirty days")
        suite.expect(ScratchpadSupport.dismissesOnOutsideClick(isPinned: false, exportModalActive: false)
                && !ScratchpadSupport.dismissesOnOutsideClick(isPinned: true, exportModalActive: false)
                && !ScratchpadSupport.dismissesOnOutsideClick(isPinned: false, exportModalActive: true),
               "the scratchpad pin and export dialog both block outside-click dismissal")
        let markdownPreview = ScratchpadSupport.markdownPreview(
            "# Heading\n\n**Bold** and *italic* with [link](https://example.com)\n\n- First\n- Second\n\n1. Third\n\n```\ncode\n```")
        suite.expect(markdownPreview.map(\.kind) == [
                    .heading(1), .paragraph,
                    .unorderedListItem(depth: 1), .unorderedListItem(depth: 1),
                    .orderedListItem(ordinal: 1, depth: 1), .code
                ]
                && String(markdownPreview[0].text.characters) == "Heading"
                && String(markdownPreview[2].text.characters) == "First"
                && String(markdownPreview[5].text.characters) == "code"
                && markdownPreview[2].containerID == markdownPreview[3].containerID
                && markdownPreview[2].containerID != nil
                && markdownPreview[3].containerID != markdownPreview[4].containerID
                && markdownPreview[1].text.runs.contains {
                    $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
                }
                && markdownPreview[1].text.runs.contains {
                    $0.inlinePresentationIntent?.contains(.emphasized) == true
                }
                && markdownPreview[1].text.runs.contains { $0.link != nil },
               "the scratchpad preview renders semantic blocks and inline formatting")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.scratchpadBackgroundOpacity] as? Double == 0.0,
               "the scratchpad keeps its familiar translucent background by default")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.scratchpadBackgroundOpacity),
               "the scratchpad background choice travels with the settings backup")
        suite.expect(ScratchpadSupport.sanitizedBackgroundOpacity(0.7) == 0.7,
               "a scratchpad background opacity inside the range is kept")
        suite.expect(ScratchpadSupport.sanitizedBackgroundOpacity(0)
                == ScratchpadSupport.backgroundOpacityRange.lowerBound
                && ScratchpadSupport.sanitizedBackgroundOpacity(-3)
                == ScratchpadSupport.backgroundOpacityRange.lowerBound,
               "the scratchpad background never goes below the familiar translucent style")
        suite.expect(ScratchpadSupport.sanitizedBackgroundOpacity(4) == 1.0
                && ScratchpadSupport.sanitizedBackgroundOpacity(.nan) == 1.0
                && ScratchpadSupport.sanitizedBackgroundOpacity(.infinity) == 1.0,
               "a high or broken scratchpad opacity falls back to fully opaque")
        let scratchpadNow = Date(timeIntervalSince1970: 1_784_000_000)
        suite.expect(!ScratchpadSupport.shouldClear(lastEdited: nil, now: scratchpadNow, retention: .day)
                && !ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(-90_000),
                                                  now: scratchpadNow, retention: .never)
                && !ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(-3_600),
                                                  now: scratchpadNow, retention: .day)
                && ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(-90_000),
                                                 now: scratchpadNow, retention: .day)
                && !ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(-90_000),
                                                  now: scratchpadNow, retention: .week)
                && ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(-8 * 86_400),
                                                 now: scratchpadNow, retention: .week)
                && !ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(60),
                                                  now: scratchpadNow, retention: .day),
               "the scratchpad only clears when a period is chosen and the last edit is older than it")
        let scratchpadExportName = ScratchpadSupport.exportFileName(title: "Scratchpad",
                                                                    date: scratchpadNow)
        suite.expect(scratchpadExportName.hasPrefix("Scratchpad 20")
                && scratchpadExportName.hasSuffix(".txt")
                && scratchpadExportName.count == "Scratchpad ".count + 14,
               "scratchpad export file name is the title plus the local date")
        let firstPadID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondPadID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let thirdPadID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let migratedScratchpad = ScratchpadDocument.initial(
            defaultName: "Scratchpad", id: firstPadID, text: "existing text",
            modifiedAt: scratchpadNow.addingTimeInterval(-120))
        let twoPads = migratedScratchpad.addingPad(defaultName: "Scratchpad", id: secondPadID)
        let threePads = twoPads?.addingPad(defaultName: "Scratchpad", id: thirdPadID)
        suite.expect(threePads?.pads.map(\.name) == ["Scratchpad 1", "Scratchpad 2", "Scratchpad 3"]
                && threePads?.pads.map(\.id) == [firstPadID, secondPadID, thirdPadID]
                && threePads?.selectedID == thirdPadID,
               "new scratchpads append in order, receive clear names and become selected")
        suite.expect(ScratchpadSupport.nextPadName(defaultName: "Scratchpad",
                                             existingNames: ["Scratchpad"]) == "Scratchpad 2",
               "an existing unnumbered scratchpad still occupies the first numbered slot")
        let renamedPad = threePads?.renaming(secondPadID, to: "  Work\nideas  ")
        suite.expect(renamedPad?.pads[1].name == "Work ideas"
                && ScratchpadSupport.sanitizedPadName(String(repeating: "x", count: 50)).count
                    == ScratchpadDocument.maximumNameLength
                && threePads?.renaming(secondPadID, to: "   ") == nil,
               "scratchpad names stay single-line, bounded and never empty")
        let selectedFirst = renamedPad?.selecting(firstPadID)
        let removedFirst = selectedFirst?.removing(firstPadID)
        suite.expect(removedFirst?.pads.map(\.id) == [secondPadID, thirdPadID]
                && removedFirst?.selectedID == secondPadID,
               "closing the selected scratchpad keeps order and selects its nearest neighbor")
        suite.expect(migratedScratchpad.removing(firstPadID) == nil,
               "the last scratchpad cannot be closed")
        suite.expect(ScratchpadSupport.requiresCloseConfirmation(migratedScratchpad.pads[0])
                && !ScratchpadSupport.requiresCloseConfirmation(
                    ScratchpadDocument.initial(defaultName: "Scratchpad").pads[0]),
               "only closing a scratchpad with content needs destructive confirmation")

        suite.expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "t",
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: true) == .createPad,
               "Command-T creates a scratchpad tab while the pad is focused")
        suite.expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "t",
                                                   commandOnly: true,
                                                   canCreatePad: false,
                                                   canClosePad: true) == nil,
               "Command-T is idle at the scratchpad tab limit")
        suite.expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "w",
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: true) == .closeSelectedPad,
               "Command-W closes the selected scratchpad tab when more than one remains")
        suite.expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "w",
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: false) == .hidePad,
               "Command-W on the last scratchpad tab hides the pad")
        suite.expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "t",
                                                   commandOnly: false,
                                                   canCreatePad: true,
                                                   canClosePad: true) == nil
                && ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "w",
                                                       commandOnly: false,
                                                       canCreatePad: true,
                                                       canClosePad: true) == nil
                && ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "a",
                                                       commandOnly: true,
                                                       canCreatePad: true,
                                                       canClosePad: true) == nil,
               "scratchpad tab shortcuts need Command alone on T or W")
        suite.expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "W",
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: true) == .closeSelectedPad,
               "Caps Lock preserves the scratchpad close shortcut")
        suite.expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "z",
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: true) == nil,
               "the AZERTY Z at the US W position must not close a scratchpad")
        suite.expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: nil,
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: true) == nil,
               "events without a character do not trigger scratchpad tab shortcuts")
        suite.expect(ScratchpadFindShortcut.action(charactersIgnoringModifiers: "f",
                                                   modifierFlags: .command) == .showFindInterface
                && ScratchpadFindShortcut.action(charactersIgnoringModifiers: "g",
                                                 modifierFlags: .command) == .nextMatch
                && ScratchpadFindShortcut.action(charactersIgnoringModifiers: "G",
                                                 modifierFlags: [.command, .shift]) == .previousMatch,
               "Command-F opens the scratchpad find bar and Command-G steps through matches both ways")
        suite.expect(ScratchpadFindShortcut.action(charactersIgnoringModifiers: "F",
                                                   modifierFlags: [.command, .capsLock]) == .showFindInterface
                && ScratchpadFindShortcut.action(charactersIgnoringModifiers: "g",
                                                 modifierFlags: [.command, .numericPad]) == .nextMatch,
               "Caps Lock and device flags do not break the scratchpad find keys")
        suite.expect(ScratchpadFindShortcut.action(charactersIgnoringModifiers: "f",
                                                   modifierFlags: []) == nil
                && ScratchpadFindShortcut.action(charactersIgnoringModifiers: "f",
                                                 modifierFlags: [.command, .option]) == nil
                && ScratchpadFindShortcut.action(charactersIgnoringModifiers: "F",
                                                 modifierFlags: [.command, .shift]) == nil
                && ScratchpadFindShortcut.action(charactersIgnoringModifiers: "g",
                                                 modifierFlags: [.command, .control]) == nil
                && ScratchpadFindShortcut.action(charactersIgnoringModifiers: "t",
                                                 modifierFlags: .command) == nil
                && ScratchpadFindShortcut.action(charactersIgnoringModifiers: nil,
                                                 modifierFlags: .command) == nil,
               "typing F or G and other Command chords stay with the scratchpad text")
        var limitedScratchpads = migratedScratchpad
        for _ in 2...ScratchpadDocument.maximumPadCount {
            limitedScratchpads = limitedScratchpads.addingPad(defaultName: "Scratchpad")!
        }
        suite.expect(limitedScratchpads.pads.count == ScratchpadDocument.maximumPadCount
                && limitedScratchpads.addingPad(defaultName: "Scratchpad") == nil,
               "scratchpads keep a small fixed upper bound")
        var retainedScratchpads = ScratchpadDocument.initial(
            defaultName: "Scratchpad",
            id: firstPadID,
            text: "expired text",
            modifiedAt: scratchpadNow.addingTimeInterval(-90_000))
        retainedScratchpads = retainedScratchpads.addingPad(defaultName: "Scratchpad",
                                                             id: secondPadID)!
        retainedScratchpads.updateSelectedText("recent text",
                                               modifiedAt: scratchpadNow.addingTimeInterval(-300))
        retainedScratchpads.applyRetention(.day, now: scratchpadNow)
        suite.expect(retainedScratchpads.pads[0].text.isEmpty
                && retainedScratchpads.pads[1].text == "recent text",
               "retention clears only scratchpads whose own text expired")
        let scratchpadDocumentData = renamedPad?.encoded()
        let decodedScratchpads = ScratchpadDocument.decoded(scratchpadDocumentData,
                                                            defaultName: "Scratchpad")
        suite.expect(decodedScratchpads == renamedPad,
               "scratchpad text, names, order and selection round-trip together")
        let scratchpadBackup = SettingsBackupSupport.payload(appVersion: "test") { key in
            key == DefaultsKey.scratchpadDocument ? scratchpadDocumentData : nil
        }
        let restoredScratchpadSettings = SettingsBackupSupport.sanitizedSettings(from: scratchpadBackup)
        suite.expect(restoredScratchpadSettings?[DefaultsKey.scratchpadDocument] == nil,
               "the scratchpad's own text stays out of a settings backup people copy around")
        let safeScratchpadExportName = ScratchpadSupport.exportFileName(
            title: "Work/Ideas: 1", date: scratchpadNow)
        suite.expect(safeScratchpadExportName.hasPrefix("Work-Ideas- 1 ")
                && !safeScratchpadExportName.contains("/")
                && !safeScratchpadExportName.contains(":"),
               "scratchpad export names cannot turn tab names into path components")

        // Muting every microphone, not just the one the Mac is set to: an app
        // pointed at a device of its own has to go silent too.
        suite.expect(MicMuteSupport.isOwnDevice(name: "Vorssaint Mixer")
                && MicMuteSupport.isOwnDevice(name: "Vorssaint Island Levels")
                && MicMuteSupport.isOwnDevice(name: "Vorssaint Recorder")
                && !MicMuteSupport.isOwnDevice(name: "MacBook Air Microphone"),
               "the mute skips the app's own aggregate devices and no other")
        suite.expect(!MicMuteSupport.shouldSaveVolume(nil)
                && !MicMuteSupport.shouldSaveVolume(0)
                && !MicMuteSupport.shouldSaveVolume(0.005)
                && MicMuteSupport.shouldSaveVolume(0.4),
               "a level worth restoring is remembered and a silent one never is")
        suite.expect(MicMuteSupport.volumeToRestore(uid: "mic-a",
                                              saved: ["mic-a": 0.4, "mic-b": 0.9],
                                              legacy: 0.6) == 0.4
                && MicMuteSupport.volumeToRestore(uid: "mic-c",
                                                  saved: ["mic-a": 0.4],
                                                  legacy: 0.6) == 0.6
                && MicMuteSupport.volumeToRestore(uid: "mic-c", saved: [:], legacy: 0)
                    == MicMuteSupport.fallbackVolume
                && MicMuteSupport.volumeToRestore(uid: "mic-a",
                                                  saved: ["mic-a": 0],
                                                  legacy: 0) == MicMuteSupport.fallbackVolume,
               "each microphone gets its own level back, then the older single level, then a usable one")
        suite.expect(MicMuteSupport.restoreTargets(recorded: ["mic-a", "gone"],
                                             present: ["mic-a", "mic-b"]) == ["mic-a"]
                && MicMuteSupport.restoreTargets(recorded: nil,
                                                 present: ["mic-a", "mic-b"]) == ["mic-a", "mic-b"]
                && MicMuteSupport.restoreTargets(recorded: [],
                                                 present: ["mic-a", "mic-b"]).isEmpty
                && MicMuteSupport.restoreTargets(recorded: ["mic-a"], present: []).isEmpty,
               "unmuting touches the microphones this app muted, every one with no record, and none when the record is empty")
        suite.expect(MicMuteSupport.absentClaims(recorded: ["mic-a", "headset"],
                                           present: ["mic-a"]) == ["headset"]
                && MicMuteSupport.absentClaims(recorded: ["mic-a"],
                                               present: ["mic-a", "mic-b"]).isEmpty
                && MicMuteSupport.absentClaims(recorded: nil, present: ["mic-a"]).isEmpty
                && MicMuteSupport.absentClaims(recorded: ["headset"], present: []) == ["headset"],
               "a sweep keeps the claim on a microphone this app muted that is unplugged right now, so it is released when it returns")
        let micMuteServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/MicMuteService.swift",
            encoding: .utf8)) ?? ""
        let reapply = micMuteServiceSource.range(of: "private func reapplyIfNeeded() {")
            .map { micMuteServiceSource[$0.lowerBound...] }
            .flatMap { body in body.range(of: "\n    }\n").map { body[..<$0.lowerBound] } }
            .map(String.init) ?? ""
        suite.expect(reapply.contains("if wantsMute {") && !reapply.contains("micMuteActive")
                && micMuteServiceSource.contains(
                    "private func apply(muted: Bool, announce: Bool) {\n        wantsMute = muted"),
               "a device change re-asserts the mute request in flight, never the persisted flag it is about to replace")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.radialMenuEnabled] as? Bool == false,
               "the radial menu ships off by default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.radialMenuShortcut] as? String
                == "control+option+command:49",
               "the default radial menu shortcut is control option command space")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.radialMenuAtPointer] as? Bool == true,
               "the radial menu opens at the pointer by default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.radialMenuMouseButton] as? String == "off",
               "the side button trigger ships off")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.radialMenuActivationMode] as? String == "pressOrHold",
               "the radial menu preserves its adaptive gesture by default")
        suite.expect(RadialMenuActivationMode.sanitized("press") == .press
                && RadialMenuActivationMode.sanitized("hold") == .hold
                && RadialMenuActivationMode.sanitized(nil) == .pressOrHold
                && RadialMenuActivationMode.sanitized("future-mode") == .pressOrHold,
               "the radial activation mode decodes known values and safely falls back")
        suite.expect(!RadialMenuActivationMode.press.startsHeld(
                    requestedHold: true, hasHeldButton: false, shortcutHasModifiers: true)
                && RadialMenuActivationMode.hold.startsHeld(
                    requestedHold: true, hasHeldButton: false, shortcutHasModifiers: true)
                && RadialMenuActivationMode.pressOrHold.startsHeld(
                    requestedHold: false, hasHeldButton: true, shortcutHasModifiers: false)
                && !RadialMenuActivationMode.hold.startsHeld(
                    requestedHold: false, hasHeldButton: false, shortcutHasModifiers: true),
               "only hold-capable summons enter the held phase")
        suite.expect(RadialMenuActivationMode.pressOrHold.releaseAction(hasSelection: false) == .stayOpen
                && RadialMenuActivationMode.hold.releaseAction(hasSelection: false) == .dismiss
                && RadialMenuActivationMode.hold.releaseAction(hasSelection: true) == .select,
               "release keeps the adaptive wheel, dismisses an empty strict hold, or selects its target")
        suite.expect(RadialMenuSupport.shortcutIsStillHeld(modifiersHeld: true, superKeyHeld: false)
                && RadialMenuSupport.shortcutIsStillHeld(modifiersHeld: false, superKeyHeld: true)
                && !RadialMenuSupport.shortcutIsStillHeld(modifiersHeld: false, superKeyHeld: false),
               "the radial hold follows physical modifiers or the virtual super key")
        suite.expect(RadialMenuMouseTrigger.sanitized("back") == .back
                && RadialMenuMouseTrigger.sanitized("forward").buttonNumber == 4
                && RadialMenuMouseTrigger.back.buttonNumber == 3
                && MouseButtonShortcutSupport.buttonRange.allSatisfy {
                    RadialMenuMouseTrigger.sanitized(
                        RadialMenuMouseTrigger.button($0).rawValue).buttonNumber == $0
                }
                && RadialMenuMouseTrigger.sanitized(nil) == .off
                && RadialMenuMouseTrigger.sanitized("teleport") == .off
                && RadialMenuMouseTrigger.sanitized("button:2") == .off
                && RadialMenuMouseTrigger.sanitized("button:32") == .off
                && RadialMenuMouseTrigger.off.buttonNumber == nil,
               "the mouse trigger round-trips every extra button and falls back to off")
        suite.expect(RadialMenuMouseTrigger.back.buttonNumber == MouseNavigationSupport.backButtonNumber
                && RadialMenuMouseTrigger.forward.buttonNumber == MouseNavigationSupport.forwardButtonNumber,
               "the wheel and mouse navigation agree on which button is which")
        suite.expect(!RadialMenuSupport.claimsMouseButton(3) && !RadialMenuSupport.claimsMouseButton(4),
               "with the feature off no side button is claimed away from navigation")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.panelControlRadialMenu] as? Bool == true,
               "the radial menu panel row ships visible like its siblings")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.radialMenuItems] == nil,
               "the items blob has no registered default so a fresh install detects the starter wheel")
        suite.expect(GlobalShortcutRole.radialMenu.requiredEnableKeys == [DefaultsKey.radialMenuEnabled]
                && GlobalShortcutRole.radialMenu.feature == .radialMenu,
               "the radial menu shortcut role gates on the feature toggle")

        // MARK: Capture tool shortcuts

        suite.expect(ScreenCaptureTool.screenshot.dedicatedShortcut.role == .screenshot
                && ScreenCaptureTool.screenshot.dedicatedShortcut.enabledKey
                    == DefaultsKey.screenshotShortcutEnabled,
               "the screenshot tool keeps the old general shortcut's keys as its own")
        suite.expect(ScreenCaptureTool.allCases.map { $0.dedicatedShortcut.role }
                == [.screenshot, .screenRecorder, .screenOCR, .colorPicker],
               "every capture tool owns a shortcut role, in tool order")
        // The keys a tool registers have to be the ones its settings row writes.
        // Three roles once had a row and no registrar, so the key was recorded
        // and the combination did nothing (issue #708).
        suite.expect(ScreenCaptureTool.allCases.allSatisfy { tool in
                let keys = tool.dedicatedShortcut
                return keys.role.requiredEnableKeys == [keys.enabledKey]
                    && keys.role.feature == tool.feature
               },
               "a capture tool registers exactly the keys its own settings row reads")
        suite.expect(GlobalShortcutRole.captureRoles(in: GlobalShortcutRole.allCases)
                == GlobalShortcutRole.captureDisplayOrder,
               "every role of a capture feature reaches the shortcuts page, in display order")
        suite.expect(GlobalShortcutRole.captureRoles(in: [.colorPicker, .screenshot, .commandBar])
                == [.screenshot, .colorPicker],
               "capture roles are reordered for display and other roles fall away")
        GlobalShortcut.refreshLayoutLabels()
    }
}
