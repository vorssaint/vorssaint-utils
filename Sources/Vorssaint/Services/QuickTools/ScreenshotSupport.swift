// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Pure logic for the screenshot tool: capture routing, selection geometry,
/// coordinate conversions between the window server, screens and image
/// pixels, the annotation model and file naming. No AppKit so the unit test
/// harness compiles it standalone.
enum ScreenshotSupport {

    // MARK: - Preferences

    /// Optional countdown before the capture starts, so menus, tooltips and
    /// hover states can be staged first.
    static let allowedDelays = [0, 3, 5, 10]

    static func sanitizedDelay(_ raw: Int) -> Int {
        allowedDelays.contains(raw) ? raw : 0
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

    /// Places the capture preview beside the selection when possible, then
    /// falls back near the pointer and clamps the whole panel to the display.
    static func quickPreviewFrame(size: CGSize,
                                  anchor: CGRect,
                                  pointer: CGPoint,
                                  visibleFrame: CGRect) -> CGRect {
        let gap: CGFloat = 14
        let inset: CGFloat = 10
        let usable = visibleFrame.insetBy(dx: inset, dy: inset)

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

    /// A quieter, corner-anchored placement used when a default action is
    /// configured — the HUD is now just a confirmation, not something the
    /// person needs to act on, so it stays out of the way in the corner
    /// instead of popping up next to the selection.
    static func quickPreviewCornerFrame(size: CGSize, visibleFrame: CGRect) -> CGRect {
        let inset: CGFloat = 16
        let usable = visibleFrame.insetBy(dx: inset, dy: inset)
        let x = max(usable.minX, usable.maxX - size.width)
        let y = usable.minY
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
    static func fileName(prefix: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(formatter.string(from: date)).png"
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

    /// A stable square of source pixels for the crop loupe. Near an image
    /// edge the sample slides inward instead of shrinking, while the loupe's
    /// crosshair still points at the exact adjusted pixel.
    static let captureLoupeBaseSampleSide: CGFloat = 12
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

    static func cropLoupeSampleRect(around point: CGPoint,
                                    imageSize: CGSize,
                                    sideLength: CGFloat = 14) -> CGRect {
        let width = min(max(1, floor(sideLength)), max(1, floor(imageSize.width)))
        let height = min(max(1, floor(sideLength)), max(1, floor(imageSize.height)))
        let x = min(max(floor(point.x - width / 2), 0), max(0, floor(imageSize.width) - width))
        let y = min(max(floor(point.y - height / 2), 0), max(0, floor(imageSize.height) - height))
        return CGRect(x: x, y: y, width: width, height: height)
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

        init(kind: Kind = .none,
             presetID: String? = nil,
             colors: [[Double]]? = nil,
             imagePath: String? = nil,
             padding: Double = 0.5,
             cornerRadius: Double = 0) {
            self.kind = kind
            self.presetID = presetID
            self.colors = colors
            self.imagePath = imagePath
            self.padding = padding
            self.cornerRadius = cornerRadius
        }

        /// Clamps sliders, validates colors and drops broken configurations
        /// back to .none, so a damaged persisted value can never wedge the
        /// editor.
        func sanitized() -> BackdropStyle {
            var style = self
            style.padding = style.padding.isFinite ? max(0, min(1, style.padding)) : 0.5
            style.cornerRadius = style.cornerRadius.isFinite
                ? max(0, min(1, style.cornerRadius)) : 0.1
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
