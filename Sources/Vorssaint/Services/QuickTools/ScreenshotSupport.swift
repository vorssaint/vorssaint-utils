// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The actions that share the screen-selection surface. Availability is read
/// when the chooser opens, so an uninstalled feature never leaves a dead mode
/// behind.
enum ScreenCaptureTool: String, CaseIterable {
    case screenshot
    case recording
    case text
    case color
    case translate

    var shortcutKey: String {
        switch self {
        case .screenshot: return "1"
        case .recording: return "2"
        case .text: return "3"
        case .color: return "4"
        case .translate: return "5"
        }
    }

    static func matchingShortcut(_ characters: String?) -> ScreenCaptureTool? {
        guard let characters else { return nil }
        return allCases.first { $0.shortcutKey == characters }
    }

    var feature: AppFeature {
        switch self {
        case .screenshot: return .screenshot
        case .recording: return .screenRecorder
        case .text: return .screenOCR
        case .color: return .colorPicker
        case .translate: return .liveTranslation
        }
    }

    /// A tool's own global shortcut, which opens the chooser already on that
    /// mode. The screenshot tool's entry keeps the storage keys of the old
    /// general capture shortcut, so an existing combination keeps working
    /// unchanged under its new per-tool name.
    ///
    /// Every case must have a hotkey registered for it. `ScreenCaptureService`
    /// builds exactly one per case from this list, so a tool cannot gain a
    /// settings row whose key nothing registers, which is what left three of
    /// them doing nothing (issue #708).
    struct DedicatedShortcut {
        let role: GlobalShortcutRole
        let enabledKey: String
    }

    var dedicatedShortcut: DedicatedShortcut {
        switch self {
        case .screenshot:
            return DedicatedShortcut(role: .screenshot,
                                     enabledKey: DefaultsKey.screenshotShortcutEnabled)
        case .recording:
            return DedicatedShortcut(role: .screenRecorder,
                                     enabledKey: DefaultsKey.recorderShortcutEnabled)
        case .text:
            return DedicatedShortcut(role: .screenOCR,
                                     enabledKey: DefaultsKey.screenOCRShortcutEnabled)
        case .color:
            return DedicatedShortcut(role: .colorPicker,
                                     enabledKey: DefaultsKey.colorPickerShortcutEnabled)
        case .translate:
            return DedicatedShortcut(role: .liveTranslation,
                                     enabledKey: DefaultsKey.liveTranslationShortcutEnabled)
        }
    }

    var systemImageName: String {
        switch self {
        case .screenshot: return "camera.viewfinder"
        case .recording: return "record.circle"
        case .text: return "text.viewfinder"
        case .color: return "eyedropper"
        case .translate: return "character.bubble"
        }
    }

    func settingsTitle(_ strings: Strings, language: AppLanguage) -> String {
        switch self {
        case .screenshot: return FeatureStrings.screenshot(language).pageTitle
        case .recording: return FeatureStrings.recorder(language).pageTitle
        case .text: return strings.ocrName
        case .color: return strings.colorPickerName
        case .translate: return FeatureStrings.liveTranslation(language).pageTitle
        }
    }

    /// Live Translation needs macOS 15 for the Translation framework, so it
    /// stays out of the list on older systems rather than exposing a mode
    /// that would immediately fail to start.
    static func available(isAvailable: (AppFeature) -> Bool = { $0.isAvailable })
        -> [ScreenCaptureTool] {
        allCases.filter {
            guard isAvailable($0.feature) else { return false }
            if $0 == .translate, #unavailable(macOS 15.0) { return false }
            return true
        }
    }
}

/// Pure logic for the screenshot tool: capture routing, selection geometry,
/// coordinate conversions between the window server, screens and image
/// pixels, the annotation model and file naming. No AppKit so the unit test
/// harness compiles it standalone.
enum ScreenshotSupport {

    struct UnifiedCapturePolicy: Equatable {
        let freeze: Bool
        let includePointer: Bool
        let hideVorssaintWindows: Bool
        let usesGeometry: Bool
    }

    static func unifiedCapturePolicy(for tool: ScreenCaptureTool,
                                     screenshotFreeze: Bool,
                                     screenshotIncludePointer: Bool,
                                     screenshotHideVorssaintWindows: Bool)
        -> UnifiedCapturePolicy {
        UnifiedCapturePolicy(
            freeze: tool == .screenshot ? screenshotFreeze : true,
            includePointer: tool == .screenshot && screenshotIncludePointer,
            hideVorssaintWindows: tool != .recording && screenshotHideVorssaintWindows,
            usesGeometry: tool == .recording || tool == .translate)
    }

    static func captureAvailabilityChanged(activeTools: [ScreenCaptureTool],
                                           availableTools: [ScreenCaptureTool]) -> Bool {
        activeTools != availableTools
    }

    static func captureRouteIsAuthorized(
        selected: ScreenCaptureTool,
        isAvailable: (AppFeature) -> Bool = { $0.isAvailable }
    ) -> Bool {
        isAvailable(selected.feature)
    }

    static func captureGuideIsVisible(pointerOnDisplay: Bool,
                                      selectionInProgress: Bool,
                                      capturePending: Bool) -> Bool {
        pointerOnDisplay && !selectionInProgress && !capturePending
    }

    // MARK: - Preferences

    static let recentCaptureLimit = 12
    static let recentCaptureMaximumBytes: Int64 = 256 * 1024 * 1024

    static func isRecentCaptureCacheFileName(_ name: String) -> Bool {
        guard name == URL(fileURLWithPath: name).lastPathComponent,
              name.lowercased().hasSuffix(".png") else { return false }
        let stem = String(name.dropLast(4))
        if UUID(uuidString: stem) != nil { return true }
        let suffix = "-thumbnail"
        return stem.hasSuffix(suffix)
            && UUID(uuidString: String(stem.dropLast(suffix.count))) != nil
    }

    static func cappedRecentCaptureIDs(_ ids: [UUID],
                                       screenshotBytes: [UUID: Int64] = [:]) -> [UUID] {
        var kept: [UUID] = []
        var bytes: Int64 = 0
        var keptScreenshot = false
        for id in ids.prefix(recentCaptureLimit) {
            guard let size = screenshotBytes[id] else {
                kept.append(id)
                continue
            }
            let safeSize = max(0, size)
            if keptScreenshot, bytes + safeSize > recentCaptureMaximumBytes { continue }
            kept.append(id)
            keptScreenshot = true
            bytes += safeSize
        }
        return kept
    }

    /// Optional countdown before the capture starts, so menus, tooltips and
    /// hover states can be staged first.
    static let allowedDelays = [0, 3, 5, 10]

    static func sanitizedDelay(_ raw: Int) -> Int {
        allowedDelays.contains(raw) ? raw : 0
    }

    /// Remaining stroke for the one-second countdown ring. Time drives the
    /// value directly so a delayed frame catches up instead of restarting the
    /// animation or leaving the ring frozen.
    static func countdownRingProgress(elapsed: TimeInterval,
                                      duration: TimeInterval = 0.92) -> CGFloat {
        guard elapsed.isFinite, duration.isFinite, duration > 0 else { return 0 }
        let fraction = min(max(elapsed / duration, 0), 1)
        return CGFloat(1 - fraction)
    }

    // MARK: - Scrolling capture

    /// A failed scroll target must never keep the capture alive forever or
    /// exhaust memory. Reaching a guard keeps the valid portion and explains
    /// why the capture stopped.
    static let scrollingCaptureMaximumDuration: TimeInterval = 120
    static let scrollingCaptureMaximumFrames = 512
    static let scrollingCaptureMaximumRetainedPixels = 60_000_000
    static let scrollingCaptureMaximumPixels = 60_000_000

    struct ScrollingSample: Equatable {
        let width: Int
        let height: Int
        let pixels: [UInt8]

        var isValid: Bool {
            width > 0 && height > 0 && pixels.count == width * height
        }
    }

    enum ScrollingDirection: Equatable {
        case forward
        case backward
    }

    enum ScrollingTransition: Equatable {
        case end
        case advanced(overlap: Int,
                      direction: ScrollingDirection,
                      contentColumns: Range<Int>)
        case unmatched
    }

    static func scrollingSamplesAreStable(_ previous: ScrollingSample,
                                          _ current: ScrollingSample,
                                          contentColumns: Range<Int>? = nil) -> Bool {
        previous.isValid && current.isValid
            && previous.width == current.width
            && previous.height == current.height
            && scrollingDifference(previous,
                                   current,
                                   columns: contentColumns ?? 0..<previous.width) <= 1.5
    }

    /// Finds how many rows two successive views share. The calculation is
    /// deliberately pure: captures only provide small grayscale samples and
    /// the exact same matching policy is exercised by the test harness.
    static func scrollingTransition(previous: ScrollingSample,
                                    current: ScrollingSample,
                                    contentColumns: Range<Int>? = nil) -> ScrollingTransition {
        guard previous.isValid, current.isValid,
              previous.width == current.width,
              previous.height == current.height,
              previous.height >= 24
        else { return .unmatched }

        let columns = contentColumns ?? 0..<previous.width
        guard columns.lowerBound >= 0,
              columns.upperBound <= previous.width,
              !columns.isEmpty
        else { return .unmatched }

        if scrollingSamplesAreStable(previous,
                                     current,
                                     contentColumns: columns) {
            return .end
        }

        let height = previous.height
        // The final scroll at the bottom of a page is often only a few rows.
        // Treating every advance below 18% as a mismatch discarded an otherwise
        // valid capture on short pages just before it could detect the end.
        let minimumAdvance = max(2, Int((Double(height) * 0.01).rounded()))
        let maximumAdvance = min(height - 8, Int((Double(height) * 0.88).rounded()))
        guard minimumAdvance <= maximumAdvance else { return .unmatched }

        struct Match {
            let advance: Int
            let reversed: Bool
            let contentColumns: Range<Int>
            let supportingTiles: Int
            let longestRun: Int
            let matchingRows: Int
            let difference: Double
        }

        let tiles = scrollingColumnTiles(in: columns, sampleWidth: previous.width)
        let movingTiles = tiles.filter {
            scrollingDifference(previous, current, columns: $0) > 1.5
        }
        guard !movingTiles.isEmpty else { return .unmatched }

        var matches: [Match] = []
        for advance in minimumAdvance...maximumAdvance {
            for reversed in [false, true] {
                guard let match = scrollingCandidate(previous: previous,
                                                     current: current,
                                                     advance: advance,
                                                     reversed: reversed,
                                                     tiles: movingTiles) else { continue }
                matches.append(Match(advance: advance,
                                     reversed: reversed,
                                     contentColumns: match.contentColumns,
                                     supportingTiles: match.supportingTiles,
                                     longestRun: match.longestRun,
                                     matchingRows: match.matchingRows,
                                     difference: match.difference))
            }
        }
        guard !matches.isEmpty else { return .unmatched }
        matches.sort {
            if $0.contentColumns.count != $1.contentColumns.count {
                return $0.contentColumns.count > $1.contentColumns.count
            }
            if $0.supportingTiles != $1.supportingTiles {
                return $0.supportingTiles > $1.supportingTiles
            }
            if $0.longestRun != $1.longestRun { return $0.longestRun > $1.longestRun }
            if $0.matchingRows != $1.matchingRows { return $0.matchingRows > $1.matchingRows }
            return $0.difference < $1.difference
        }

        let best = matches[0]
        let requiredRun = max(8, min(28, height / 12))
        guard best.longestRun >= requiredRun else {
            return .unmatched
        }

        // Repeated blank bands can look equally good at several offsets. A
        // unique match is required instead of guessing and creating a seam.
        if let rival = matches.dropFirst().first(where: {
            $0.reversed != best.reversed || abs($0.advance - best.advance) > 2
        }),
           rival.contentColumns.count >= best.contentColumns.count - 1,
           rival.supportingTiles >= best.supportingTiles - 1,
           rival.longestRun >= best.longestRun - 2,
           rival.matchingRows >= best.matchingRows - max(3, best.supportingTiles * 3),
           rival.difference <= best.difference + 0.75 {
            return .unmatched
        }
        return .advanced(overlap: height - best.advance,
                         direction: best.reversed ? .backward : .forward,
                         contentColumns: best.contentColumns)
    }

    /// A fixed footer stays at the same viewport rows while the page behind it
    /// advances. Keeping that suffix in every new strip repeats it throughout
    /// the final image, so identify it separately from the moving overlap.
    static func scrollingFixedBottomRows(previous: ScrollingSample,
                                         current: ScrollingSample,
                                         overlap: Int,
                                         contentColumns: Range<Int>) -> Int {
        guard previous.isValid, current.isValid,
              previous.width == current.width,
              previous.height == current.height,
              overlap > 0, overlap < previous.height,
              contentColumns.lowerBound >= 0,
              contentColumns.upperBound <= previous.width,
              !contentColumns.isEmpty
        else { return 0 }

        var rows = 0
        for row in stride(from: previous.height - 1, through: 0, by: -1) {
            let start = row * previous.width
            var difference = 0
            for column in contentColumns {
                difference += abs(Int(previous.pixels[start + column])
                    - Int(current.pixels[start + column]))
            }
            let average = Double(difference) / Double(contentColumns.count)
            guard average <= 2 else { break }
            rows += 1
        }

        let minimumRows = max(4, min(12, previous.height / 100))
        guard rows >= minimumRows, rows < overlap else { return 0 }
        return rows
    }

    /// Rows newly revealed by a forward scroll. A fixed footer shifts this
    /// range upward by its own height; its pixels are appended once at the end.
    static func scrollingNewContentRows(imageHeight: Int,
                                        overlap: Int,
                                        fixedBottomRows: Int) -> Range<Int>? {
        guard imageHeight > 0,
              overlap > 0, overlap < imageHeight,
              fixedBottomRows >= 0, fixedBottomRows < overlap
        else { return nil }
        return (overlap - fixedBottomRows)..<(imageHeight - fixedBottomRows)
    }

    private static func scrollingDifference(_ lhs: ScrollingSample,
                                            _ rhs: ScrollingSample,
                                            columns: Range<Int>) -> Double {
        guard columns.lowerBound >= 0,
              columns.upperBound <= lhs.width,
              !columns.isEmpty else { return .infinity }
        let topInset = max(0, lhs.height / 24)
        var difference = 0
        var count = 0
        for row in topInset..<(lhs.height - topInset) {
            let start = row * lhs.width
            for column in columns {
                difference += abs(Int(lhs.pixels[start + column])
                    - Int(rhs.pixels[start + column]))
                count += 1
            }
        }
        return count > 0 ? Double(difference) / Double(count) : .infinity
    }

    private struct ScrollingCandidate {
        let contentColumns: Range<Int>
        let supportingTiles: Int
        let longestRun: Int
        let matchingRows: Int
        let difference: Double
    }

    private static func scrollingColumnTiles(in columns: Range<Int>,
                                             sampleWidth: Int) -> [Range<Int>] {
        let tileWidth = max(2, sampleWidth / 8)
        var tiles: [Range<Int>] = []
        var lower = columns.lowerBound
        while lower < columns.upperBound {
            let upper = min(columns.upperBound, lower + tileWidth)
            if upper - lower >= 2 || tiles.isEmpty {
                tiles.append(lower..<upper)
            }
            lower = upper
        }
        return tiles
    }

    private static func scrollingCandidate(previous: ScrollingSample,
                                           current: ScrollingSample,
                                           advance: Int,
                                           reversed: Bool,
                                           tiles: [Range<Int>]) -> ScrollingCandidate? {
        let requiredRun = max(8, min(28, previous.height / 12))
        let matches = tiles.map { tile -> (Range<Int>, ScrollingRowMatch?) in
            guard let match = scrollingMatch(previous: previous,
                                              current: current,
                                              advance: advance,
                                              reversed: reversed,
                                              columns: tile),
                  match.longestRun >= requiredRun,
                  match.matchingRows >= max(requiredRun, match.comparedRows / 3)
            else { return (tile, nil) }
            return (tile, match)
        }

        let minimumTiles = matches.count >= 3 ? 2 : 1
        var runs: [[(Range<Int>, ScrollingRowMatch)]] = []
        var run: [(Range<Int>, ScrollingRowMatch)] = []
        var skippedOneTile = false
        for (tile, match) in matches {
            if let match {
                run.append((tile, match))
            } else if !run.isEmpty, !skippedOneTile {
                skippedOneTile = true
            } else {
                if !run.isEmpty { runs.append(run) }
                run = []
                skippedOneTile = false
            }
        }
        if !run.isEmpty { runs.append(run) }

        return runs.compactMap { supported -> ScrollingCandidate? in
            guard supported.count >= minimumTiles,
                  let first = supported.first,
                  let last = supported.last else { return nil }
            let contentColumns = first.0.lowerBound..<last.0.upperBound
            guard let combined = scrollingMatch(previous: previous,
                                                 current: current,
                                                 advance: advance,
                                                 reversed: reversed,
                                                 columns: contentColumns),
                  combined.longestRun >= requiredRun,
                  combined.matchingRows >= max(requiredRun, combined.comparedRows / 3)
            else { return nil }
            return ScrollingCandidate(contentColumns: contentColumns,
                                      supportingTiles: supported.count,
                                      longestRun: combined.longestRun,
                                      matchingRows: combined.matchingRows,
                                      difference: combined.difference)
        }.max {
            if $0.contentColumns.count != $1.contentColumns.count {
                return $0.contentColumns.count < $1.contentColumns.count
            }
            if $0.matchingRows != $1.matchingRows {
                return $0.matchingRows < $1.matchingRows
            }
            return $0.difference > $1.difference
        }
    }

    private struct ScrollingRowMatch {
        let longestRun: Int
        let matchingRows: Int
        let comparedRows: Int
        let difference: Double
    }

    private static func scrollingMatch(previous: ScrollingSample,
                                       current: ScrollingSample,
                                       advance: Int,
                                       reversed: Bool,
                                       columns: Range<Int>) -> ScrollingRowMatch? {
        let width = previous.width
        let edgeInset = max(2, previous.height / 10)
        let lastRow = previous.height - advance - edgeInset
        guard lastRow > edgeInset,
              columns.lowerBound >= 0,
              columns.upperBound <= width,
              !columns.isEmpty else { return nil }

        var longestRun = 0
        var run = 0
        var matchingRows = 0
        var comparedRows = 0
        var totalDifference = 0
        var comparedPixels = 0
        for currentRow in edgeInset..<lastRow {
            let previousRow = currentRow + advance
            let previousStart = (reversed ? currentRow : previousRow) * width
            let currentStart = (reversed ? previousRow : currentRow) * width
            var rowDifference = 0
            for column in columns {
                rowDifference += abs(Int(previous.pixels[previousStart + column])
                    - Int(current.pixels[currentStart + column]))
            }
            let rowPixels = columns.count
            let average = Double(rowDifference) / Double(rowPixels)
            totalDifference += rowDifference
            comparedPixels += rowPixels
            comparedRows += 1
            if average <= 8 {
                run += 1
                matchingRows += 1
                longestRun = max(longestRun, run)
            } else {
                run = 0
            }
        }
        guard comparedPixels > 0 else { return nil }
        return ScrollingRowMatch(longestRun: longestRun,
                                 matchingRows: matchingRows,
                                 comparedRows: comparedRows,
                                 difference: Double(totalDifference) / Double(comparedPixels))
    }

    static func scrollingPixelRange(sampleColumns: Range<Int>,
                                    sampleWidth: Int,
                                    imageWidth: Int) -> Range<Int>? {
        guard sampleWidth > 0, imageWidth > 0,
              sampleColumns.lowerBound >= 0,
              sampleColumns.upperBound <= sampleWidth,
              !sampleColumns.isEmpty else { return nil }
        let lower = sampleColumns.lowerBound * imageWidth / sampleWidth
        let upper = (sampleColumns.upperBound * imageWidth + sampleWidth - 1) / sampleWidth
        guard lower >= 0, upper <= imageWidth, lower < upper else { return nil }
        return lower..<upper
    }

    /// Restores the pixels-per-point scale stored as standard PNG DPI.
    static func captureScale(fromDPI dpi: Double?) -> CGFloat? {
        guard let dpi, dpi.isFinite else { return nil }
        let scale = dpi / 72
        guard (0.5...4).contains(scale) else { return nil }
        return CGFloat(scale)
    }

    /// Uses the logical size carried by a copied image when it describes one
    /// consistent display scale. Imported files without that metadata edit at 1x.
    static func clipboardImageScale(pixelSize: CGSize, pointSize: CGSize) -> CGFloat {
        guard pixelSize.width > 0, pixelSize.height > 0,
              pointSize.width > 0, pointSize.height > 0
        else { return 1 }
        let horizontal = pixelSize.width / pointSize.width
        let vertical = pixelSize.height / pointSize.height
        guard horizontal.isFinite, vertical.isFinite,
              abs(horizontal - vertical) <= max(horizontal, vertical) * 0.05
        else { return 1 }
        return captureScale(fromDPI: Double((horizontal + vertical) / 2) * 72) ?? 1
    }

    // MARK: - Selection geometry

    /// Rectangle between two drag points. `square` constrains to the largest
    /// square that fits the drag; `fromCenter` treats the origin as the
    /// center when Option is held.
    static func selectionRect(from origin: CGPoint,
                              to current: CGPoint,
                              square: Bool = false,
                              fromCenter: Bool = false) -> CGRect {
        var dx = current.x - origin.x
        var dy = current.y - origin.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        if fromCenter {
            return CGRect(x: origin.x - abs(dx), y: origin.y - abs(dy),
                          width: abs(dx) * 2, height: abs(dy) * 2)
        }
        return CGRect(x: min(origin.x, origin.x + dx),
                      y: min(origin.y, origin.y + dy),
                      width: abs(dx), height: abs(dy))
    }

    /// A full-image crop cannot move, so an interior drag must start a new
    /// selection. Dragging outside an existing crop replaces it as well.
    static func startsNewCropSelection(at point: CGPoint,
                                       draft: CGRect,
                                       within bounds: CGRect) -> Bool {
        bounds.contains(point)
            && (draft.standardized == bounds.standardized || !draft.contains(point))
    }

    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var result = rect.intersection(bounds)
        if result.isNull { result = .zero }
        return result
    }

    /// A press that never travelled beyond this is a click, which captures
    /// the window under the cursor instead of a region.
    static let clickDragThreshold: CGFloat = 4

    static func isClick(from origin: CGPoint, to end: CGPoint) -> Bool {
        abs(end.x - origin.x) < clickDragThreshold && abs(end.y - origin.y) < clickDragThreshold
    }

    /// Whether the selection surface should still answer the pointer. Once a
    /// capture is on its way, or the session is over, every remaining event
    /// has to do nothing: the surface has already left the screen and the
    /// picture is being taken. Gestures that end with more than one release,
    /// like a drag made with three fingers, deliver exactly those late events.
    static func selectionAcceptsPointerInput(sessionIsOver: Bool, capturePending: Bool) -> Bool {
        !sessionIsOver && !capturePending
    }

    // MARK: - Coordinate conversions

    /// Window-server rectangles (top-left origin, global) into Cocoa global
    /// coordinates (bottom-left origin). `mainScreenHeight` is the height of
    /// the primary screen, which anchors both systems.
    static func cocoaRect(fromWindowServer rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.origin.x,
               y: mainScreenHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// A Cocoa global rectangle into the coordinates of a top-left-origin
    /// (flipped) view that covers `screenFrame` exactly.
    static func flippedViewRect(fromCocoa rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX - screenFrame.minX,
               y: screenFrame.maxY - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// A rectangle in a flipped screen overlay back into Cocoa global
    /// coordinates. This anchors transient controls beside the captured area.
    static func cocoaRect(fromFlippedView rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: screenFrame.minX + rect.minX,
               y: screenFrame.maxY - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    /// A rectangle in a flipped view of `viewSize` points mapped onto an
    /// image of `imageSize` pixels covering the same area, rounded outward to
    /// whole pixels and clamped to the image.
    static func imagePixelRect(fromView rect: CGRect,
                               viewSize: CGSize,
                               imageSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let scaleX = imageSize.width / viewSize.width
        let scaleY = imageSize.height / viewSize.height
        let scaled = CGRect(x: rect.minX * scaleX,
                            y: rect.minY * scaleY,
                            width: rect.width * scaleX,
                            height: rect.height * scaleY).integral
        return clamp(scaled, to: CGRect(origin: .zero, size: imageSize))
    }

    /// A point in the flipped full-screen overlay mapped to the source
    /// image. Keeping this separate from rectangle rounding lets a pixel
    /// loupe follow the pointer without jumping by whole selections.
    static func imagePixelPoint(fromView point: CGPoint,
                                viewSize: CGSize,
                                imageSize: CGSize) -> CGPoint {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        return CGPoint(x: min(max(point.x / viewSize.width * imageSize.width, 0),
                              imageSize.width),
                       y: min(max(point.y / viewSize.height * imageSize.height, 0),
                              imageSize.height))
    }

    // MARK: - Quick preview placement

    enum QuickPreviewPosition: String, CaseIterable {
        case automatic = ""
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    /// Picks the display containing most of the capture. The pointer breaks
    /// an exact tie and is also the fallback when a display was disconnected
    /// or rearranged before the preview appears.
    static func quickPreviewVisibleFrame(
        anchor: CGRect,
        pointer: CGPoint,
        screens: [(frame: CGRect, visibleFrame: CGRect)],
        fallback: CGRect
    ) -> CGRect {
        var selected: (frame: CGRect, visibleFrame: CGRect)?
        var selectedArea: CGFloat = 0
        for screen in screens {
            let overlap = anchor.intersection(screen.frame)
            let area = overlap.isNull ? 0 : max(0, overlap.width) * max(0, overlap.height)
            let winsTie = area == selectedArea
                && area > 0
                && screen.frame.contains(pointer)
                && !(selected?.frame.contains(pointer) ?? false)
            if area > selectedArea || winsTie {
                selected = screen
                selectedArea = area
            }
        }
        if let selected { return selected.visibleFrame }
        return screens.first { $0.frame.contains(pointer) }?.visibleFrame ?? fallback
    }

    /// Places the capture preview beside the selection in automatic mode, or
    /// in the selected display corner, and clamps it to the visible frame.
    static func quickPreviewFrame(size: CGSize,
                                  anchor: CGRect,
                                  pointer: CGPoint,
                                  visibleFrame: CGRect,
                                  position: QuickPreviewPosition = .automatic) -> CGRect {
        let inset: CGFloat = position == .automatic ? 10 : 16
        let usable = visibleFrame.insetBy(dx: inset, dy: inset)

        if position != .automatic {
            let x: CGFloat
            let y: CGFloat
            switch position {
            case .automatic, .bottomRight:
                x = max(usable.minX, usable.maxX - size.width)
                y = usable.minY
            case .topLeft:
                x = usable.minX
                y = max(usable.minY, usable.maxY - size.height)
            case .topRight:
                x = max(usable.minX, usable.maxX - size.width)
                y = max(usable.minY, usable.maxY - size.height)
            case .bottomLeft:
                x = usable.minX
                y = usable.minY
            }
            return CGRect(origin: CGPoint(x: x, y: y), size: size)
        }

        let gap: CGFloat = 14
        var x = anchor.maxX + gap
        if x + size.width > usable.maxX {
            x = anchor.minX - size.width - gap
        }
        if x < usable.minX || x + size.width > usable.maxX {
            x = pointer.x + gap
        }

        var y = anchor.midY - size.height / 2
        if y < usable.minY || y + size.height > usable.maxY {
            let below = anchor.minY - size.height - gap
            let above = anchor.maxY + gap
            if below >= usable.minY {
                y = below
            } else if above + size.height <= usable.maxY {
                y = above
            } else {
                y = pointer.y - size.height / 2
            }
        }

        x = min(max(x, usable.minX), max(usable.minX, usable.maxX - size.width))
        y = min(max(y, usable.minY), max(usable.minY, usable.maxY - size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    // MARK: - Editor layout

    /// A fresh editor should be large enough for its controls and canvas,
    /// while still fitting compact or rotated displays.
    static func editorMinimumContentSize(visibleSize: CGSize) -> CGSize {
        CGSize(width: min(visibleSize.width,
                          min(980, max(760, visibleSize.width * 0.76))),
               height: min(visibleSize.height,
                           min(680, max(560, visibleSize.height * 0.72))))
    }

    /// Initial content size for an editor window. Large captures fit inside
    /// the display and small captures still open on a comfortable canvas.
    static func editorContentSize(imagePointSize: CGSize,
                                  visibleSize: CGSize) -> CGSize {
        let chrome = CGSize(width: 96, height: 140)
        let minimum = editorMinimumContentSize(visibleSize: visibleSize)
        let maximum = CGSize(width: max(minimum.width, visibleSize.width * 0.90),
                             height: max(minimum.height, visibleSize.height * 0.88))
        let fit = min(1,
                      min((maximum.width - chrome.width) / max(imagePointSize.width, 1),
                          (maximum.height - chrome.height) / max(imagePointSize.height, 1)))
        let preferred = CGSize(width: imagePointSize.width * fit + chrome.width,
                               height: imagePointSize.height * fit + chrome.height)
        return CGSize(width: min(maximum.width, max(minimum.width, preferred.width)),
                      height: min(maximum.height, max(minimum.height, preferred.height)))
    }

    /// Local key monitors normally receive the editor's window number, but
    /// AppKit can clear it while resolving a main-menu key equivalent such as
    /// Command-Z. In that case the key window still owns the event. Never use
    /// the fallback for an event that explicitly belongs to another window.
    static func editorOwnsKeyEvent(eventWindowNumber: Int,
                                   editorWindowNumber: Int,
                                   editorIsKey: Bool) -> Bool {
        guard editorWindowNumber != 0 else { return false }
        if eventWindowNumber == editorWindowNumber { return true }
        return eventWindowNumber == 0 && editorIsKey
    }

    // MARK: - Window picking

    struct PickableWindow: Equatable {
        let windowID: UInt32
        /// Frame in the flipped coordinates of the overlay's own view.
        let frame: CGRect
    }

    /// First window whose frame contains the point; the list keeps the window
    /// server's front-to-back order, so the visible window wins.
    static func window(at point: CGPoint, in windows: [PickableWindow]) -> PickableWindow? {
        windows.first { $0.frame.contains(point) }
    }

    // MARK: - File naming

    /// Stable local file name with a localizable prefix and colon-free time.
    static func fileName(prefix: String, date: Date, fileExtension: String = "png") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date)).\(fileExtension)"
    }

    /// Writes one drag payload into its own temporary directory. Separate
    /// directories keep captures made in the same second from replacing each
    /// other while either drag is still in flight.
    static func temporaryDragFile(data: Data, name: String,
                                  directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let folder = directory.appendingPathComponent("ScreenshotDrag-\(UUID().uuidString)",
                                                       isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent((name as NSString).lastPathComponent)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Keeps copied captures available long enough for paste targets that read
    /// the file after accepting its URL from the pasteboard.
    static func copiedFile(data: Data, name: String, directory: URL) throws -> URL {
        guard Int64(data.count) <= copiedFileMaximumBytes else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        return try copiedFileLock.withLock {
            let manager = FileManager.default
            try preparePrivateCacheDirectory(directory, manager: manager)
            let safeName = (name as NSString).lastPathComponent
            let uniqueName = uniqueFileName(safeName) { candidate in
                manager.fileExists(atPath: directory.appendingPathComponent(candidate).path)
            }
            let url = directory.appendingPathComponent(uniqueName)
            try data.write(to: url, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return url
        }
    }

    static func copiedFilesDirectory(fileManager: FileManager = .default,
                                     bundle: Bundle = .main) -> URL? {
        guard let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let bundleID = bundle.bundleIdentifier else { return nil }
        return base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Copied Screenshots", isDirectory: true)
    }

    static func isCopiedScreenshot(_ url: URL, in directory: URL) -> Bool {
        let file = url.standardizedFileURL
        let root = directory.standardizedFileURL
        guard file.deletingLastPathComponent().path == root.path,
              file.pathExtension.lowercased() == "png",
              let rootValues = try? root.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              rootValues.isDirectory == true,
              rootValues.isSymbolicLink != true,
              let values = try? file.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    struct CopiedFilePruneCandidate: Equatable {
        let url: URL
        let date: Date
        let bytes: Int64
    }

    private static let copiedFileLock = NSLock()
    private static let copiedFileMaximumCount = 100
    private static let copiedFileMaximumBytes: Int64 = 256 * 1024 * 1024

    private static func preparePrivateCacheDirectory(_ directory: URL,
                                                     manager: FileManager) throws {
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let values = try directory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    static func copiedFilePruneVictims(_ files: [CopiedFilePruneCandidate],
                                       preserving current: URL,
                                       maximumCount: Int,
                                       maximumBytes: Int64) -> [URL] {
        let currentPath = current.standardizedFileURL.path
        guard let currentFile = files.first(where: {
            $0.url.standardizedFileURL.path == currentPath
        }) else { return [] }
        var count = 1
        var bytes = max(0, currentFile.bytes)
        var victims: [URL] = []
        for file in files.sorted(by: {
            $0.date == $1.date
                ? $0.url.standardizedFileURL.path < $1.url.standardizedFileURL.path
                : $0.date > $1.date
        })
            where file.url.standardizedFileURL.path != currentPath {
            if count < maximumCount
                && file.bytes >= 0
                && bytes <= maximumBytes
                && file.bytes <= maximumBytes - bytes {
                count += 1
                bytes += file.bytes
            } else {
                victims.append(file.url)
            }
        }
        return victims
    }

    /// Applies the cache bounds only after `current` has reached the pasteboard.
    /// A stale render may finish later, but it can never evict the published URL.
    static func pruneCopiedFiles(in directory: URL, preserving current: URL,
                                 now: Date = Date()) {
        copiedFileLock.withLock {
            let manager = FileManager.default
            guard isCopiedScreenshot(current, in: directory) else { return }
            let keys: Set<URLResourceKey> = [
                .contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
            ]
            guard let children = try? manager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: Array(keys)) else { return }
            let files = children.compactMap { url -> CopiedFilePruneCandidate? in
                guard url.pathExtension.lowercased() == "png",
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      values.isSymbolicLink != true else { return nil }
                return CopiedFilePruneCandidate(
                    url: url,
                    date: values.contentModificationDate ?? .distantPast,
                    bytes: Int64(values.fileSize ?? 0))
            }
            let currentPath = current.standardizedFileURL.path
            let cutoff = now.addingTimeInterval(-24 * 3600)
            let expired = files.filter {
                $0.url.standardizedFileURL.path != currentPath && $0.date < cutoff
            }
            let expiredURLs = Set(expired.map(\.url))
            let currentFiles = files.filter { !expiredURLs.contains($0.url) }
            let budgetVictims = copiedFilePruneVictims(
                currentFiles,
                preserving: current,
                maximumCount: copiedFileMaximumCount,
                maximumBytes: copiedFileMaximumBytes
            )
            for victim in expired.map(\.url) + budgetVictims {
                try? manager.removeItem(at: victim)
            }
        }
    }

    static func removeTemporaryDragDirectories(
        directory: URL = FileManager.default.temporaryDirectory
    ) {
        let manager = FileManager.default
        guard let children = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let prefix = "ScreenshotDrag-"
        for child in children {
            let name = child.lastPathComponent
            guard name.hasPrefix(prefix),
                  UUID(uuidString: String(name.dropFirst(prefix.count))) != nil,
                  let values = try? child.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else { continue }
            try? manager.removeItem(at: child)
        }
    }

    /// Expands a date-token pattern into a relative subfolder path, e.g.
    /// "%y-%mo" becomes "24-03" and "%year/%month" becomes "2024/March".
    /// Slashes in the pattern become nested folders. The result never
    /// escapes the base folder: empty, "." and ".." components are dropped.
    /// An empty pattern expands to an empty string, meaning no subfolder.
    static func expandSaveSubfolder(_ pattern: String, date: Date) -> String {
        guard !pattern.isEmpty else { return "" }
        return applyingDateTokens(pattern, date: date)
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .joined(separator: "/")
    }
    /// Expands a non-empty file name pattern with the same date tokens as
    /// `expandSaveSubfolder`, plus "%#" (and "%##", "%###", …) for an
    /// auto-incrementing, zero-padded number. Slashes and colons would nest
    /// folders or fail the write, so they become dashes. Callers are
    /// responsible for falling back to the default name when the pattern is
    /// blank, and for appending the file extension.
    static func expandFileNamePattern(_ pattern: String, date: Date, number: Int) -> String {
        let withDate = applyingDateTokens(pattern, date: date)
        return applyingNumberTokens(withDate, number: number)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }
    /// Whether a file name pattern actually uses the number sequence, so
    /// callers know whether to advance and persist it.
    static func fileNamePatternUsesNumber(_ pattern: String) -> Bool {
        pattern.contains("%#")
    }
    private static func applyingDateTokens(_ pattern: String, date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = parts.year ?? 0
        // Longer tokens are substituted first so "%year"/"%month" don't get
        // clobbered by their short prefixes "%y"/"%mo" during replacement.
        let tokens: [(String, String)] = [
            ("%year", String(format: "%04d", year)),
            ("%month", monthName(parts.month ?? 1)),
            ("%y", String(format: "%02d", year % 100)),
            ("%mo", String(format: "%02d", parts.month ?? 0)),
            ("%d", String(format: "%02d", parts.day ?? 0)),
            ("%h", String(format: "%02d", parts.hour ?? 0)),
            ("%mi", String(format: "%02d", parts.minute ?? 0)),
            ("%s", String(format: "%02d", parts.second ?? 0))
        ]
        var result = pattern
        for (token, value) in tokens {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return result
    }
    /// Replaces runs like "%#", "%##", "%###" with `number`, zero-padded to
    /// the run's length (minus the leading "%"). Matches are expanded from
    /// the end of the string backwards so earlier ranges stay valid.
    private static func applyingNumberTokens(_ pattern: String, number: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: "%#+") else { return pattern }
        let fullRange = NSRange(pattern.startIndex..<pattern.endIndex, in: pattern)
        var result = pattern
        let matches = regex.matches(in: pattern, range: fullRange)
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let padding = max(match.range.length - 1, 1)
            result.replaceSubrange(range, with: String(format: "%0\(padding)d", number))
        }
        return result
    }

    private static func monthName(_ month: Int) -> String {
        var components = DateComponents()
        components.year = 2000
        components.month = month
        components.day = 1
        guard let date = Calendar(identifier: .gregorian).date(from: components) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date)
    }

    /// First free variant of a file name: "name.png", "name 2.png", ….
    static func uniqueFileName(_ name: String, exists: (String) -> Bool) -> String {
        guard exists(name) else { return name }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        for index in 2...9999 {
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            if !exists(candidate) { return candidate }
        }
        return name
    }

    // MARK: - Annotation model

    enum Tool: String, CaseIterable {
        // Case order is the default rail order and therefore the default
        // mapping for keys 1 through 9. Put the common actions first.
        case select, arrow, pixelate, crop, text, sticker, rect, highlight,
             freehand, line, ellipse, counter, redact

        static let shortcutLimit = 9

        static var defaultOrderStorage: String {
            allCases.map(\.rawValue).joined(separator: ",")
        }

        /// Tools that create an annotation by dragging a rectangle.
        var dragsRect: Bool {
            switch self {
            case .rect, .ellipse, .highlight, .pixelate, .redact: return true
            case .select, .arrow, .line, .freehand, .text, .sticker, .counter, .crop:
                return false
            }
        }

        /// Existing rectangular marks with visible resize grips.
        var resizesWithHandles: Bool {
            dragsRect || self == .sticker
        }

        /// Saved ids first, then any tools added by a later version in the
        /// canonical order. Invalid and duplicate ids never reach the UI.
        static func ordered(from raw: String?) -> [Tool] {
            var seen = Set<Tool>()
            var result: [Tool] = []
            for id in (raw ?? "").split(separator: ",") {
                guard let tool = Tool(rawValue: String(id)),
                      seen.insert(tool).inserted
                else { continue }
                result.append(tool)
            }
            for tool in allCases where seen.insert(tool).inserted {
                result.append(tool)
            }
            return result
        }

        static func shortcutTool(number: Int,
                                 orderRaw: String?,
                                 enabled: Bool) -> Tool? {
            guard enabled, (1...shortcutLimit).contains(number) else { return nil }
            let order = ordered(from: orderRaw)
            let index = number - 1
            return order.indices.contains(index) ? order[index] : nil
        }

        static func shortcutNumber(for tool: Tool,
                                   orderRaw: String?,
                                   enabled: Bool) -> Int? {
            guard enabled,
                  let index = ordered(from: orderRaw).firstIndex(of: tool),
                  index < shortcutLimit
            else { return nil }
            return index + 1
        }

        /// Assigning a number is the same operation as moving the tool into
        /// that numbered rail slot. Choosing no shortcut moves it just below
        /// the first nine, where it remains available without a key.
        static func assigningShortcut(_ number: Int?,
                                      to tool: Tool,
                                      orderRaw: String?) -> [Tool] {
            var order = ordered(from: orderRaw)
            guard let current = order.firstIndex(of: tool) else { return order }
            if number == nil, current >= shortcutLimit { return order }
            order.remove(at: current)
            let destination: Int
            if let number, (1...shortcutLimit).contains(number) {
                destination = min(number - 1, order.count)
            } else {
                destination = min(shortcutLimit, order.count)
            }
            order.insert(tool, at: destination)
            return order
        }
    }

    enum ColorID: String, CaseIterable {
        case red, orange, yellow, green, blue, purple, black, white

        /// sRGB components, shared by live rendering and export.
        var components: (red: Double, green: Double, blue: Double) {
            switch self {
            case .red: return (0.93, 0.26, 0.21)
            case .orange: return (1.00, 0.58, 0.00)
            case .yellow: return (1.00, 0.80, 0.00)
            case .green: return (0.20, 0.78, 0.35)
            case .blue: return (0.04, 0.52, 1.00)
            case .purple: return (0.69, 0.32, 0.87)
            case .black: return (0.09, 0.09, 0.11)
            case .white: return (1.00, 1.00, 1.00)
            }
        }

        static func sanitized(_ raw: String?) -> ColorID {
            ColorID(rawValue: raw ?? "") ?? .red
        }
    }

    enum StrokeID: String, CaseIterable {
        case small, medium, large

        /// Line width in image points at 1x; export multiplies by the image
        /// scale so marks keep their weight on Retina captures.
        var width: CGFloat {
            switch self {
            case .small: return 2
            case .medium: return 4
            case .large: return 7
            }
        }

        static func sanitized(_ raw: String?) -> StrokeID {
            StrokeID(rawValue: raw ?? "") ?? .medium
        }
    }

    enum StickerID: String, CaseIterable {
        case check, cross, star, heart, thumbsUp, thumbsDown,
             smile, laugh, party, fire, warning, eyes

        var glyph: String {
            switch self {
            case .check: return "✅"
            case .cross: return "❌"
            case .star: return "⭐️"
            case .heart: return "❤️"
            case .thumbsUp: return "👍"
            case .thumbsDown: return "👎"
            case .smile: return "😀"
            case .laugh: return "😂"
            case .party: return "🎉"
            case .fire: return "🔥"
            case .warning: return "⚠️"
            case .eyes: return "👀"
            }
        }

        static func sanitized(_ raw: String?) -> StickerID {
            StickerID(rawValue: raw ?? "") ?? .check
        }
    }

    static func stickerSide(for imageSize: CGSize, scale: CGFloat) -> CGFloat {
        let shortSide = min(imageSize.width, imageSize.height)
        let minimum = min(52 * scale, shortSide * 0.45)
        return max(1, max(minimum, min(shortSide * 0.16, 128 * scale)))
    }

    static func stickerRect(centeredAt point: CGPoint,
                            side: CGFloat,
                            within bounds: CGRect) -> CGRect {
        let fittedSide = min(max(1, side), min(bounds.width, bounds.height))
        let rect = CGRect(x: point.x - fittedSide / 2,
                          y: point.y - fittedSide / 2,
                          width: fittedSide,
                          height: fittedSide)
        return movedRect(rect, by: .zero, within: bounds)
    }

    /// One annotation on the canvas. Geometry lives in image-point
    /// coordinates (top-left origin), so export is resolution-exact and the
    /// view only scales for display.
    struct Annotation: Identifiable, Equatable {
        let id: UUID
        var tool: Tool
        var rect: CGRect
        var points: [CGPoint]
        var text: String
        var color: ColorID
        var stroke: StrokeID
        var number: Int

        init(id: UUID = UUID(),
             tool: Tool,
             rect: CGRect = .zero,
             points: [CGPoint] = [],
             text: String = "",
             color: ColorID = .red,
             stroke: StrokeID = .medium,
             number: Int = 0) {
            self.id = id
            self.tool = tool
            self.rect = rect
            self.points = points
            self.text = text
            self.color = color
            self.stroke = stroke
            self.number = number
        }
    }

    /// Which way a selected annotation moves through the drawing order.
    enum LayerMove {
        case forward, backward
    }

    /// Whether the annotation has somewhere to go: false at the end it is
    /// already heading for, and for an id that is not in the array.
    static func canReorder(_ annotations: [Annotation],
                           moving id: UUID,
                           _ move: LayerMove) -> Bool {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return false }
        return annotations.indices.contains(move == .forward ? index + 1 : index - 1)
    }

    /// Moves one annotation a single step through the array the renderer draws
    /// in order, so a shape can go behind text that was written first. An
    /// annotation already at the end it is heading for stays put, and an
    /// unknown id leaves the array alone.
    static func reordering(_ annotations: [Annotation],
                           moving id: UUID,
                           _ move: LayerMove) -> [Annotation] {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return annotations }
        let target = move == .forward ? index + 1 : index - 1
        guard annotations.indices.contains(target) else { return annotations }
        var reordered = annotations
        reordered.swapAt(index, target)
        return reordered
    }

    /// Counters stay 1…n in creation order; deleting one renumbers the rest
    /// so a sequence never shows a hole.
    static func renumberingCounters(_ annotations: [Annotation]) -> [Annotation] {
        var next = 1
        return annotations.map { annotation in
            guard annotation.tool == .counter else { return annotation }
            var updated = annotation
            updated.number = next
            next += 1
            return updated
        }
    }

    /// Counter badge diameter for an image, scaling with capture resolution
    /// so badges stay readable without swallowing small screenshots.
    static func counterDiameter(for imageSize: CGSize, scale: CGFloat) -> CGFloat {
        max(22, min(imageSize.width, imageSize.height) / 24) * scale
    }

    // MARK: - Selection handles

    enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        func position(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
            case .top: return CGPoint(x: rect.midX, y: rect.minY)
            case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
            case .right: return CGPoint(x: rect.maxX, y: rect.midY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
            case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
            case .left: return CGPoint(x: rect.minX, y: rect.midY)
            }
        }
    }

    static func handle(at point: CGPoint, rect: CGRect, tolerance: CGFloat) -> Handle? {
        Handle.allCases.first { handle in
            let position = handle.position(in: rect)
            return abs(position.x - point.x) <= tolerance && abs(position.y - point.y) <= tolerance
        }
    }

    /// The rectangle after dragging `handle` to `point`. Width and height are
    /// kept non-negative by swapping edges when a drag crosses over.
    static func resizedRect(_ rect: CGRect, dragging handle: Handle, to point: CGPoint) -> CGRect {
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        switch handle {
        case .topLeft: minX = point.x; minY = point.y
        case .top: minY = point.y
        case .topRight: maxX = point.x; minY = point.y
        case .right: maxX = point.x
        case .bottomRight: maxX = point.x; maxY = point.y
        case .bottom: maxY = point.y
        case .bottomLeft: minX = point.x; maxY = point.y
        case .left: minX = point.x
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY),
                      width: abs(maxX - minX), height: abs(maxY - minY))
    }

    /// Moves an existing crop without resizing it, stopping cleanly at the
    /// image edges instead of shrinking the rectangle through intersection.
    static func movedRect(_ rect: CGRect,
                          by delta: CGPoint,
                          within bounds: CGRect) -> CGRect {
        guard rect.width <= bounds.width, rect.height <= bounds.height else {
            return rect.intersection(bounds)
        }
        let x = min(max(rect.minX + delta.x, bounds.minX), bounds.maxX - rect.width)
        let y = min(max(rect.minY + delta.y, bounds.minY), bounds.maxY - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    /// The pixel rectangle a crop draft stands for. A crop cuts on pixel
    /// boundaries, so the chrome, the loupe cross and `applyCrop` all read the
    /// draft through here and mark the same edge. Rounding both edges to the
    /// nearest boundary leaves an already snapped rectangle the same size under
    /// a move, because the two edges carry the same fraction.
    static func pixelSnappedCropRect(_ rect: CGRect, within bounds: CGRect) -> CGRect {
        let minX = (rect.minX).rounded()
        let minY = (rect.minY).rounded()
        let maxX = (rect.maxX).rounded()
        let maxY = (rect.maxY).rounded()
        return clamp(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
                     to: bounds)
    }

    /// A stable square of source pixels for the crop loupe. Near an image
    /// edge the sample slides inward instead of shrinking, and the loupe's
    /// reticle still marks the exact adjusted pixel.
    static let captureLoupeBaseSampleSide: CGFloat = 13
    static let captureLoupeMinZoom: CGFloat = 0.5
    static let captureLoupeMaxZoom: CGFloat = 4

    static func captureLoupeZoom(_ zoom: CGFloat, adjustedBy scrollDelta: CGFloat) -> CGFloat {
        guard scrollDelta != 0 else {
            return min(max(zoom, captureLoupeMinZoom), captureLoupeMaxZoom)
        }
        let factor: CGFloat = scrollDelta > 0 ? 1.15 : 1 / 1.15
        return min(max(zoom * factor, captureLoupeMinZoom), captureLoupeMaxZoom)
    }

    static func captureLoupeSampleSide(zoom: CGFloat) -> CGFloat {
        let clamped = min(max(zoom, captureLoupeMinZoom), captureLoupeMaxZoom)
        return captureLoupeBaseSampleSide / clamped
    }

    /// The square of source pixels a loupe magnifies. The two loupes centre on
    /// different things and therefore need opposite parities.
    ///
    /// The capture loupe reads a color, so it centres on a whole *pixel*
    /// (`centredOnPixel`): the side is forced odd because an even one has no
    /// middle cell, which left the sampled pixel half a cell right of and below
    /// the frame's centre, and the ring drawn around it followed. Centring on
    /// the floored coordinate keeps the pointer's sub-pixel position out of it.
    ///
    /// The editor's crop loupe marks a crop *edge*, which runs between pixels.
    /// An edge lands in the middle of the frame only when the side is even and
    /// the coordinate is whole, so that caller passes `centredOnPixel: false`
    /// and reads a draft `pixelSnappedCropRect` has put on a boundary.
    static func cropLoupeSampleRect(around point: CGPoint,
                                    imageSize: CGSize,
                                    sideLength: CGFloat = 13,
                                    centredOnPixel: Bool = true) -> CGRect {
        let imageWidth = max(1, floor(imageSize.width))
        let imageHeight = max(1, floor(imageSize.height))
        var side = max(1, floor(sideLength))
        let isEven = side.truncatingRemainder(dividingBy: 2) == 0
        if centredOnPixel, isEven {
            side = max(1, side - 1)
        } else if !centredOnPixel, !isEven {
            side += 1
        }
        let width = min(side, imageWidth)
        let height = min(side, imageHeight)
        let x = centredOnPixel ? floor(point.x) - floor(width / 2) : floor(point.x - width / 2)
        let y = centredOnPixel ? floor(point.y) - floor(height / 2) : floor(point.y - height / 2)
        return CGRect(x: min(max(x, 0), imageWidth - width),
                      y: min(max(y, 0), imageHeight - height),
                      width: width,
                      height: height)
    }

    /// Where the one source pixel under `point` lands inside a loupe frame.
    /// It floors the coordinate exactly like the color read does, so a
    /// highlight built from this rect can never mark a neighbour of the pixel
    /// that gets copied, and the pointer's sub-pixel position stops leaking
    /// into the drawing.
    static func captureLoupeTargetPixelRect(around point: CGPoint,
                                            source: CGRect,
                                            frame: CGRect) -> CGRect {
        guard source.width >= 1, source.height >= 1 else { return frame }
        let column = min(max(floor(point.x), source.minX), source.maxX - 1)
        let row = min(max(floor(point.y), source.minY), source.maxY - 1)
        let width = frame.width / source.width
        let height = frame.height / source.height
        return CGRect(x: frame.minX + (column - source.minX) * width,
                      y: frame.minY + (row - source.minY) * height,
                      width: width,
                      height: height)
    }

    // MARK: - Shape geometry

    /// Arrow head as two wing points for a line ending at `tip`. The head
    /// grows with the stroke so thick arrows stay proportionate.
    static func arrowHead(from tail: CGPoint,
                          to tip: CGPoint,
                          strokeWidth: CGFloat) -> (left: CGPoint, right: CGPoint) {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let distance = hypot(tip.x - tail.x, tip.y - tail.y)
        let preferred = max(10, strokeWidth * 3.4)
        let proportional = max(distance * 0.72, min(strokeWidth * 1.2, distance))
        let length = min(preferred, proportional)
        let spread: CGFloat = .pi / 7
        let left = CGPoint(x: tip.x - length * cos(angle - spread),
                           y: tip.y - length * sin(angle - spread))
        let right = CGPoint(x: tip.x - length * cos(angle + spread),
                            y: tip.y - length * sin(angle + spread))
        return (left, right)
    }

    /// One continuous outline for the complete arrow. Keeping the shaft,
    /// round tail and head on the same contour avoids winding-rule cutouts
    /// where independently filled shapes would overlap.
    static func arrowSilhouette(from tail: CGPoint,
                                to tip: CGPoint,
                                strokeWidth: CGFloat) -> CGPath {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let head = arrowHead(from: tail, to: tip, strokeWidth: strokeWidth)
        let baseMid = CGPoint(x: (head.left.x + head.right.x) / 2,
                              y: (head.left.y + head.right.y) / 2)
        let half = strokeWidth / 2
        let perpendicular = CGPoint(x: -sin(angle) * half,
                                    y: cos(angle) * half)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: tail.x + perpendicular.x,
                              y: tail.y + perpendicular.y))
        path.addLine(to: CGPoint(x: baseMid.x + perpendicular.x,
                                 y: baseMid.y + perpendicular.y))
        path.addLine(to: head.left)
        path.addLine(to: tip)
        path.addLine(to: head.right)
        path.addLine(to: CGPoint(x: baseMid.x - perpendicular.x,
                                 y: baseMid.y - perpendicular.y))
        path.addLine(to: CGPoint(x: tail.x - perpendicular.x,
                                 y: tail.y - perpendicular.y))
        path.addArc(center: tail,
                    radius: half,
                    startAngle: angle - .pi / 2,
                    endAngle: angle + .pi / 2,
                    clockwise: true)
        path.closeSubpath()
        return path
    }

    /// Distance from a point to a segment, for hit-testing lines and arrows.
    static func distance(from point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    // MARK: - Redaction

    /// Pixelation block size in image pixels: coarse enough that the mosaic
    /// carries no legible detail, scaled to the capture so small crops and
    /// full screens redact equally well.
    static func pixelBlockSize(for imageSize: CGSize) -> Int {
        max(10, Int(min(imageSize.width, imageSize.height) / 55))
    }

    // MARK: - Export

    /// Pixel size after the optional 1x downscale of a Retina capture.
    static func downscaledSize(pixelSize: CGSize, scale: CGFloat) -> CGSize {
        guard scale > 1 else { return pixelSize }
        return CGSize(width: (pixelSize.width / scale).rounded(),
                      height: (pixelSize.height / scale).rounded())
    }

    // MARK: - Backdrop

    /// Padded background, corner rounding and shadow applied during export.
    enum BackdropID: String, CaseIterable {
        case none, ocean, sunset, forest, candy, graphite

        /// Gradient stops as sRGB components, top-left to bottom-right.
        var stops: [(red: Double, green: Double, blue: Double)] {
            switch self {
            case .none: return []
            case .ocean: return [(0.20, 0.47, 0.96), (0.45, 0.83, 0.98)]
            case .sunset: return [(0.99, 0.36, 0.42), (1.00, 0.75, 0.35)]
            case .forest: return [(0.07, 0.56, 0.43), (0.62, 0.87, 0.50)]
            case .candy: return [(0.66, 0.32, 0.95), (0.99, 0.56, 0.65)]
            case .graphite: return [(0.23, 0.25, 0.31), (0.55, 0.60, 0.70)]
            }
        }

    }

    /// Padding around the image for a backdrop. `factor` is the user's margin
    /// slider (0…1); even 0 keeps a small frame so the gradient always shows,
    /// and a floor keeps a visible margin around small captures.
    static func backdropPadding(for imageSize: CGSize, factor: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, factor))
        let side = min(imageSize.width, imageSize.height)
        let proportional = side * (0.035 + 0.14 * clamped)
        return max(24, proportional).rounded()
    }

    /// Corner rounding of the capture card in image pixels. Factor 0 keeps
    /// the capture square; 1 is a generous fifth of the short side.
    static func cardCornerRadius(for imageSize: CGSize, factor: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, factor))
        return (clamped * min(imageSize.width, imageSize.height) * 0.2).rounded()
    }

    /// Gaussian blur radius in output pixels. Keeping it proportional makes
    /// the same slider look consistent on small screenshots and 4K video.
    static func backdropBlurRadius(for size: CGSize, factor: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, factor))
        return clamped * min(size.width, size.height) * 0.035
    }

    /// The full backdrop configuration behind a capture, persisted as JSON
    /// (one style in use, plus the user's saved presets). Colors are sRGB
    /// components so the codec stays pure and testable.
    struct BackdropStyle: Codable, Equatable {
        enum Kind: String, Codable {
            case none, preset, solid, gradient, image
        }

        var kind: Kind
        /// BackdropID raw value when kind == .preset.
        var presetID: String?
        /// 1 color (solid) or 2 colors (gradient), each [r, g, b] in 0…1.
        var colors: [[Double]]?
        /// Absolute path when kind == .image (user image or a wallpaper).
        var imagePath: String?
        var padding: Double
        var cornerRadius: Double
        var blur: Double

        init(kind: Kind = .none,
             presetID: String? = nil,
             colors: [[Double]]? = nil,
             imagePath: String? = nil,
             padding: Double = 0.5,
             cornerRadius: Double = 0,
             blur: Double = 0) {
            self.kind = kind
            self.presetID = presetID
            self.colors = colors
            self.imagePath = imagePath
            self.padding = padding
            self.cornerRadius = cornerRadius
            self.blur = blur
        }

        private enum CodingKeys: String, CodingKey {
            case kind, presetID, colors, imagePath, padding, cornerRadius, blur
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            kind = try values.decode(Kind.self, forKey: .kind)
            presetID = try values.decodeIfPresent(String.self, forKey: .presetID)
            colors = try values.decodeIfPresent([[Double]].self, forKey: .colors)
            imagePath = try values.decodeIfPresent(String.self, forKey: .imagePath)
            padding = try values.decode(Double.self, forKey: .padding)
            cornerRadius = try values.decode(Double.self, forKey: .cornerRadius)
            blur = try values.decodeIfPresent(Double.self, forKey: .blur) ?? 0
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(kind, forKey: .kind)
            try values.encodeIfPresent(presetID, forKey: .presetID)
            try values.encodeIfPresent(colors, forKey: .colors)
            try values.encodeIfPresent(imagePath, forKey: .imagePath)
            try values.encode(padding, forKey: .padding)
            try values.encode(cornerRadius, forKey: .cornerRadius)
            try values.encode(blur, forKey: .blur)
        }

        /// Clamps sliders, validates colors and drops broken configurations
        /// back to .none, so a damaged persisted value can never wedge the
        /// editor.
        func sanitized() -> BackdropStyle {
            var style = self
            style.padding = style.padding.isFinite ? max(0, min(1, style.padding)) : 0.5
            style.cornerRadius = style.cornerRadius.isFinite
                ? max(0, min(1, style.cornerRadius)) : 0.1
            style.blur = style.blur.isFinite ? max(0, min(1, style.blur)) : 0
            switch style.kind {
            case .none:
                break
            case .preset:
                guard let id = style.presetID, BackdropID(rawValue: id) != nil,
                      BackdropID(rawValue: id) != BackdropID.none
                else { return style.demoted() }
            case .solid:
                guard let colors = style.colors, colors.count == 1,
                      colors.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) })
                else { return style.demoted() }
                style.colors = colors.map { $0.map { max(0, min(1, $0)) } }
            case .gradient:
                guard let colors = style.colors, colors.count == 2,
                      colors.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) })
                else { return style.demoted() }
                style.colors = colors.map { $0.map { max(0, min(1, $0)) } }
            case .image:
                guard let path = style.imagePath, !path.isEmpty
                else { return style.demoted() }
            }
            return style
        }

        private func demoted() -> BackdropStyle {
            var style = self
            style.kind = .none
            style.presetID = nil
            style.colors = nil
            style.imagePath = nil
            return style
        }

        func encoded() -> String {
            guard let data = try? JSONEncoder().encode(self) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }

        static func decoded(_ raw: String?) -> BackdropStyle {
            guard let raw, !raw.isEmpty,
                  let data = raw.data(using: .utf8),
                  let style = try? JSONDecoder().decode(BackdropStyle.self, from: data)
            else { return BackdropStyle() }
            return style.sanitized()
        }
    }

    // MARK: - Recognized text (selectable on the canvas)

    /// One word of recognized text, in image-pixel coordinates.
    struct RecognizedWord: Equatable {
        let text: String
        let rect: CGRect
        /// Line index, so copied selections keep their line breaks.
        let line: Int
    }

    /// Words a selection drag touches, in reading order. A hairline drag
    /// still selects what it crosses.
    static func wordSelection(anchor: CGPoint,
                              current: CGPoint,
                              boxes: [CGRect]) -> [Int] {
        let rect = selectionRect(from: anchor, to: current)
            .insetBy(dx: -1, dy: -1)
        return boxes.indices.filter { boxes[$0].intersects(rect) }
    }

    /// Joins selected words with spaces inside a line and newlines between
    /// lines, whatever order the indexes arrive in.
    static func joinedWords(_ words: [RecognizedWord], selected: [Int]) -> String {
        let picked = selected.sorted().compactMap { words.indices.contains($0) ? words[$0] : nil }
        guard !picked.isEmpty else { return "" }
        var lines: [String] = []
        var currentLine = picked[0].line
        var currentWords: [String] = []
        for word in picked {
            if word.line != currentLine {
                lines.append(currentWords.joined(separator: " "))
                currentWords = []
                currentLine = word.line
            }
            currentWords.append(word.text)
        }
        lines.append(currentWords.joined(separator: " "))
        return lines.joined(separator: "\n")
    }

    /// Saved custom backdrops, capped at the configured limit.
    static let backdropPresetLimit = 12

    static func decodedBackdropPresets(_ raw: String?) -> [BackdropStyle] {
        guard let raw, !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let presets = try? JSONDecoder().decode([BackdropStyle].self, from: data)
        else { return [] }
        return presets.map { $0.sanitized() }
            .filter { $0.kind != .none }
            .suffix(backdropPresetLimit)
            .map { $0 }
    }

    static func encodedBackdropPresets(_ presets: [BackdropStyle]) -> String {
        guard let data = try? JSONEncoder().encode(Array(presets.suffix(backdropPresetLimit)))
        else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

/// The action to run automatically right after a capture, chosen in
/// Settings. `.none` leaves the quick-preview HUD waiting for the user, as
/// before this setting existed.
enum ScreenshotDefaultAction: String, CaseIterable {
    case none = ""
    case save
    case saveAndCopy
    case copy
    case edit

    /// The persisted choice; an unknown raw value reads as `.none`.
    static var current: ScreenshotDefaultAction {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.screenshotDefaultAction) ?? ""
        return ScreenshotDefaultAction(rawValue: raw) ?? .none
    }
}
