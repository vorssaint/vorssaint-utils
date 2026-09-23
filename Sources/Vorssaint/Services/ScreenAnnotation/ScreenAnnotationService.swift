// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Screen annotation overlay — draw on top of everything.
///
/// Architecture mirrors `ScreenshotSelectionController`:
/// - Full-screen borderless panel that can become key.
/// - View owns all mouse handlers (mouseDown/Dragged/Up).
/// - `NSTrackingArea(.activeAlways)` so `mouseDragged` fires even in
///   nonactivating panels.
/// - No `wantsLayer` on the view — transparent panel + layer = blank output.
final class ScreenAnnotationService: NSObject, ObservableObject {
    static let shared = ScreenAnnotationService()

    // MARK: - Panels

    private var canvasPanel: AnnotationCanvasPanel?
    private var toolbarPanel: NSPanel?
    private var drawingView: AnnotationDrawingView?
    private var sessionState = ScreenAnnotationSessionState()

    // MARK: - State

    private(set) var isDrawingActive = false
    private(set) var strokes: [AnnotationStroke] = []
    @Published private(set) var shortcutRegistrationFailed = false

    // Preferences (kept in sync with UserDefaults)
    @Published private(set) var tool: AnnotationTool = .pen
    @Published private(set) var color: AnnotationColor = .red
    @Published private(set) var width = ScreenAnnotationSupport.defaultWidth

    // MARK: - Monitors

    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?

    // MARK: - Shortcut

    private let hotkey = QuickToolHotkey(id: 61)

    private override init() {
        super.init()
        hotkey.onPress = { [weak self] in self?.toggleDrawing() }
    }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        guard AppFeature.screenAnnotation.isAvailable else { teardown(); return }
        syncShortcut()
        loadPreferences()
    }

    // Entry point from menu / shortcut
    @objc func toggleDrawing() {
        guard AppFeature.screenAnnotation.isAvailable else { return }
        if canvasPanel == nil { buildPanels() }
        isDrawingActive ? exitDrawingMode() : enterDrawingMode()
    }

    @objc func clearAll() {
        drawingView?.cancelTextEditor()
        strokes = ScreenAnnotationSupport.clear(strokes)
        drawingView?.needsDisplay = true
        orderOutCanvasWhenEmpty()
    }

    @objc func undo() {
        strokes = ScreenAnnotationSupport.undo(strokes)
        drawingView?.needsDisplay = true
        orderOutCanvasWhenEmpty()
    }

    @objc func hideOverlay() {
        exitDrawingMode()
        drawingView?.cancelTextEditor()
        strokes = ScreenAnnotationSupport.clear(strokes)
        drawingView?.needsDisplay = true
        canvasPanel?.orderOut(nil)
        toolbarPanel?.orderOut(nil)
        sessionState.resetAfterCanvasBecameEmpty()
    }

    func teardown() {
        exitDrawingMode()
        removeKeyMonitors()
        hotkey.unregister()
        canvasPanel?.orderOut(nil)
        canvasPanel?.contentView = nil
        canvasPanel = nil
        toolbarPanel?.orderOut(nil)
        toolbarPanel?.contentViewController = nil
        toolbarPanel = nil
        drawingView = nil
        strokes.removeAll()
        sessionState.resetAfterCanvasBecameEmpty()
    }

    // MARK: - Drawing mode

    private func enterDrawingMode() {
        isDrawingActive = true
        canvasPanel?.ignoresMouseEvents = ScreenAnnotationSupport.canvasIgnoresMouseEvents(isDrawing: true)
        showPanels()
        // Pattern from ScreenshotSelectionController:
        // 1) orderFrontRegardless
        // 2) makeKey — routes NSEvent.addLocalMonitor to this window
        canvasPanel?.makeKey()
        installKeyMonitors()
    }

    private func exitDrawingMode() {
        isDrawingActive = false
        drawingView?.commitTextEditor()
        // Keep the strokes visible, but restore pass-through to the app below.
        canvasPanel?.ignoresMouseEvents = ScreenAnnotationSupport.canvasIgnoresMouseEvents(isDrawing: false)
        removeKeyMonitors()
        canvasPanel?.resignKey()
        toolbarPanel?.orderOut(nil)
        drawingView?.needsDisplay = true
    }

    // MARK: - Panel building

    private func buildPanels() {
        guard let screen = NSScreen.withMouse else { return }
        let display = ScreenAnnotationDisplay(displayID: screen.displayID, frame: screen.frame)
        let placement = sessionState.begin(on: display)
        buildCanvasPanel(frame: placement.frame)
        buildToolbarPanel(frame: placement.frame)
    }


    /// Builds the full-screen drawing surface.
    /// Mirrors `ScreenshotOverlayPanel` from `ScreenshotSelectionController`.
    private func buildCanvasPanel(frame: NSRect) {
        let p = AnnotationCanvasPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        p.isReleasedWhenClosed = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        // Shielding-1 so it sits just below the toolbar
        p.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true   // critical for mouseMoved delivery
        p.ignoresMouseEvents = false

        let view = AnnotationDrawingView(service: self)
        view.frame = NSRect(origin: .zero, size: frame.size)
        view.autoresizingMask = [.width, .height]
        p.contentView = view
        self.canvasPanel = p
        self.drawingView = view
    }

    private func buildToolbarPanel(frame: NSRect) {
        let host = NSHostingController(rootView: AnyView(AnnotationToolbarView(service: self)))
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize

        let rect = toolbarFrame(for: frame, size: size)

        let p = NSPanel(contentRect: rect,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.ignoresMouseEvents = false
        p.contentViewController = host
        self.toolbarPanel = p
    }

    // MARK: - Show

    private func showPanels() {
        guard let screen = NSScreen.withMouse,
              let canvas = canvasPanel,
              let toolbar = toolbarPanel else { return }

        let fallback = ScreenAnnotationDisplay(displayID: screen.displayID, frame: screen.frame)
        let displays = NSScreen.screens.map {
            ScreenAnnotationDisplay(displayID: $0.displayID, frame: $0.frame)
        }
        let placement = sessionState.refresh(on: displays, fallback: fallback)
        if canvas.frame != placement.frame {
            canvas.setFrame(placement.frame, display: false)
        }
        canvas.orderFrontRegardless()

        if let host = toolbar.contentViewController {
            host.view.layoutSubtreeIfNeeded()
            let size = host.view.fittingSize
            let tb = toolbarFrame(for: placement.frame, size: size)
            toolbar.setFrame(tb, display: false)
        }
        toolbar.orderFrontRegardless()
    }

    private func toolbarFrame(for canvasFrame: NSRect, size: NSSize) -> NSRect {
        NSRect(x: canvasFrame.midX - size.width / 2,
               y: canvasFrame.minY + 24,
               width: max(size.width, 300),
               height: max(size.height, 44))
    }

    fileprivate func orderOutCanvasWhenEmpty() {
        guard strokes.isEmpty else { return }
        if isDrawingActive { exitDrawingMode() }
        canvasPanel?.orderOut(nil)
        toolbarPanel?.orderOut(nil)
        sessionState.resetAfterMutation(strokes: strokes)
    }

    // MARK: - Key monitors (pattern from ScreenshotSelectionController)

    private func installKeyMonitors() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self, event.window is AnnotationCanvasPanel else { return event }
                if event.type == .keyDown {
                    switch Int(event.keyCode) {
                    case kVK_Escape:
                        self.exitDrawingMode()
                    default:
                        break
                    }
                    return event
                }
                return event
            }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            self?.exitDrawingMode()
        }
    }

    private func removeKeyMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m) }
        globalKeyMonitor = nil
    }

    // MARK: - Preferences

    func loadPreferences() {
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.screenAnnotationTool),
           let t = AnnotationTool(rawValue: raw) { tool = t }
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.screenAnnotationColor) {
            color = colorForPreference(raw)
        }
        let w = UserDefaults.standard.double(forKey: DefaultsKey.screenAnnotationWidth)
        width = w > 0 ? min(max(w, 1), 40) : ScreenAnnotationSupport.defaultWidth
    }

    func setTool(_ t: AnnotationTool) {
        // The toolbar lives in its own panel, so picking a different tool
        // never resigns the text field's first-responder status the normal
        // way. Commit whatever was typed and give the keyboard back to the
        // canvas before switching, or the field keeps eating every key.
        if t != .text { drawingView?.commitTextEditor() }
        tool = t
        UserDefaults.standard.set(t.rawValue, forKey: DefaultsKey.screenAnnotationTool)
    }

    func setColor(_ c: AnnotationColor) {
        color = c
        drawingView?.updateActiveTextColor(c)
        UserDefaults.standard.set("\(c.red),\(c.green),\(c.blue)",
                                   forKey: DefaultsKey.screenAnnotationColor)
    }

    func setWidth(_ w: Double) {
        width = min(max(w, 1), 40)
        drawingView?.updateActiveTextWidth(width)
        UserDefaults.standard.set(width, forKey: DefaultsKey.screenAnnotationWidth)
    }

    func colorForPreference(_ value: String) -> AnnotationColor {
        let parts = value.split(separator: ",").compactMap { Double($0) }
        if parts.count == 3 {
            return AnnotationColor(red: parts[0], green: parts[1], blue: parts[2]).clamped()
        }
        switch value {
        case "orange": return .orange
        case "yellow": return .yellow
        case "green":  return .green
        case "blue":   return .blue
        case "purple": return .purple
        case "black":  return .black
        case "white":  return .white
        default:       return .red
        }
    }

    // MARK: - Stroke entry points (called from AnnotationDrawingView)

    fileprivate func beginStroke(at p: NSPoint, bounds: CGRect) {
        if tool == .text {
            // A click elsewhere while still editing must not silently
            // discard what was already typed.
            drawingView?.commitTextEditor()
            if let index = textStrokeIndex(at: p, bounds: bounds) {
                // Clicked an existing text: reopen it for editing instead of
                // stacking a new one on top. Removed now; commitText below
                // re-adds it (or drops it if left empty).
                let existing = strokes.remove(at: index)
                let origin = CGPoint(x: existing.points[0].x * Double(bounds.width),
                                     y: existing.points[0].y * Double(bounds.height))
                drawingView?.beginTextEditor(at: NSPoint(x: origin.x, y: origin.y),
                                             existingText: existing.text,
                                             existingColor: existing.color, existingWidth: existing.width)
                drawingView?.needsDisplay = true
                return
            }
            drawingView?.beginTextEditor(at: p, existingText: "")
            return
        }
        if tool == .eraser {
            let index = strokeIndex(at: p, bounds: bounds)
            if let index { strokes.remove(at: index) }
            drawingView?.needsDisplay = true
            orderOutCanvasWhenEmpty()
            return
        }
        let n = ScreenAnnotationSupport.normalized(
            point: AnnotationPoint(x: p.x, y: p.y),
            in: (Double(bounds.width), Double(bounds.height)))
        strokes.append(AnnotationStroke(tool: tool, color: color, width: width, points: [n, n]))
    }

    fileprivate func commitText(_ value: String, at p: NSPoint, bounds: CGRect, color overrideColor: AnnotationColor? = nil, width overrideWidth: Double? = nil) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let n = ScreenAnnotationSupport.normalized(
            point: AnnotationPoint(x: p.x, y: p.y),
            in: (Double(bounds.width), Double(bounds.height)))
        strokes.append(AnnotationStroke(tool: .text, color: overrideColor ?? color, width: overrideWidth ?? width,
                                        points: [n], text: text))
        drawingView?.needsDisplay = true
    }

    private func textStrokeSize(_ stroke: AnnotationStroke, originX: Double, boundsWidth: Double) -> CGSize {
        let font = NSFont.systemFont(ofSize: max(14, stroke.width * 3), weight: .medium)
        let wrapWidth = ScreenAnnotationSupport.textWrapWidth(originX: originX, boundsWidth: boundsWidth)
        let bounding = (stroke.text as NSString).boundingRect(
            with: NSSize(width: wrapWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font])
        return CGSize(width: max(40, bounding.width), height: max(24, bounding.height))
    }

    private func textStrokeIndex(at p: NSPoint, bounds: CGRect) -> Int? {
        let point = CGPoint(x: p.x, y: p.y)
        for index in strokes.indices.reversed() {
            let stroke = strokes[index]
            guard stroke.tool == .text, let first = stroke.points.first else { continue }
            let origin = CGPoint(x: first.x * Double(bounds.width), y: first.y * Double(bounds.height))
            let textSize = textStrokeSize(stroke, originX: Double(origin.x), boundsWidth: Double(bounds.width))
            let hit = CGRect(x: origin.x, y: origin.y, width: textSize.width, height: textSize.height)
            if hit.contains(point) { return index }
        }
        return nil
    }

    private func strokeIndex(at p: NSPoint, bounds: CGRect) -> Int? {
        let point = CGPoint(x: p.x, y: p.y)
        for index in strokes.indices.reversed() {
            let stroke = strokes[index]
            let points = stroke.points.map {
                CGPoint(x: $0.x * Double(bounds.width), y: $0.y * Double(bounds.height))
            }
            guard let first = points.first else { continue }
            let tolerance = max(12, stroke.width * 2)
            if stroke.tool == .text {
                let textSize = textStrokeSize(stroke, originX: Double(first.x), boundsWidth: Double(bounds.width))
                let hit = CGRect(x: first.x, y: first.y, width: textSize.width, height: textSize.height)
                if hit.insetBy(dx: -tolerance, dy: -tolerance).contains(point) { return index }
                continue
            }
            if stroke.tool == .rectangle || stroke.tool == .ellipse || stroke.tool == .redact {
                guard points.count >= 2 else { continue }
                let start = points[0]
                let end = points[1]
                let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                  width: abs(end.x - start.x), height: abs(end.y - start.y))
                if stroke.tool == .redact {
                    // Redact is a solid filled box: the whole area counts.
                    if rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) { return index }
                    continue
                }
                // Rectangle/ellipse are hollow outlines: only a ring near the
                // edge counts, matching ScreenshotEditorController.hitTest.
                let outer = rect.insetBy(dx: -tolerance / 2, dy: -tolerance / 2)
                guard outer.contains(point) else { continue }
                let inner = rect.insetBy(dx: tolerance, dy: tolerance)
                if inner.isEmpty || inner.width <= 0 || inner.height <= 0
                    || !inner.contains(point) {
                    return index
                }
                continue
            }
            if points.count == 1 {
                if hypot(point.x - first.x, point.y - first.y) <= tolerance { return index }
                continue
            }
            var closest = CGFloat.greatestFiniteMagnitude
            for (a, b) in zip(points, points.dropFirst()) {
                closest = min(closest, ScreenAnnotationSupport.distance(from: point, toSegmentFrom: a, to: b))
            }
            if closest <= tolerance { return index }
        }
        return nil
    }

    fileprivate func continueStroke(at p: NSPoint, bounds: CGRect) {
        guard let i = strokes.indices.last else { return }
        let n = ScreenAnnotationSupport.normalized(
            point: AnnotationPoint(x: p.x, y: p.y),
            in: (Double(bounds.width), Double(bounds.height)))
        let s = strokes[i]
        let nextPoints: [AnnotationPoint]
        if s.tool.isFreehand {
            nextPoints = ScreenAnnotationSupport.append(n, to: s.points)
        } else {
            nextPoints = [s.points[0], n]
        }
        strokes[i] = AnnotationStroke(tool: s.tool, color: s.color, width: s.width,
                                       points: nextPoints)
    }

    fileprivate func strokeColor(for stroke: AnnotationStroke) -> NSColor {
        NSColor(calibratedRed: stroke.color.red,
                green: stroke.color.green,
                blue: stroke.color.blue,
                alpha: stroke.tool == .highlighter ? 0.35 : 1)
    }

    // MARK: - Shortcut

    func syncShortcut() {
        let on = AppFeature.screenAnnotation.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.screenAnnotationShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.screenAnnotationShortcut,
                                            fallback: .screenAnnotationDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: on, shortcut: shortcut,
                                                  storageKey: DefaultsKey.screenAnnotationShortcut)
    }
}

// MARK: - Canvas panel

/// Full-screen drawing surface. Must return `canBecomeKey = true` so
/// `makeKey()` succeeds and the local event monitor filters work.
/// Pattern identical to `ScreenshotOverlayPanel`.
private final class AnnotationCanvasPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Route mouse events directly to the drawing view.
    /// Transparent panels may not deliver events through the normal
    /// responder chain, so the drawing view's handlers are invoked directly.
    /// Exception: while the text field is up, a click inside it must reach
    /// the field through the normal chain so it positions the caret there
    /// instead of always being read as "start a new stroke".
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            if let view = contentView as? AnnotationDrawingView {
                if event.type == .leftMouseDown, view.pointIsInsideActiveTextField(event) {
                    break
                }
                switch event.type {
                case .leftMouseDown:  view.mouseDown(with: event)
                case .leftMouseDragged: view.mouseDragged(with: event)
                case .leftMouseUp:    view.mouseUp(with: event)
                default: break
                }
                return
            }
        default:
            break
        }
        super.sendEvent(event)
    }
}

// MARK: - Drawing view

/// Freehand stroke receiver.
///
/// Key patterns from `ScreenshotOverlayView`:
/// - No `wantsLayer` — transparent NSPanel + CALayer conflict → blank output.
/// - `NSTrackingArea(.activeAlways, .inVisibleRect)` so `mouseDragged` fires
///   in non-activating panels.
/// - `acceptsFirstResponder = true`.
/// - `isFlipped = true` so coordinate origin matches screen pixels.
private final class AnnotationDrawingView: NSView, NSTextFieldDelegate {
    private weak var service: ScreenAnnotationService?
    private var isDragging = false
    private var textField: NSTextField?
    private var textOrigin: NSPoint?
    private var editingColor: AnnotationColor?
    private var editingWidth: Double?

    func updateActiveTextColor(_ c: AnnotationColor) {
        guard textField != nil else { return }
        editingColor = c
        textField?.textColor = NSColor(calibratedRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    func updateActiveTextWidth(_ w: Double) {
        guard let field = textField else { return }
        editingWidth = w
        let fontSize = CGFloat(max(14, w * 3))
        field.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
    }

    init(service: ScreenAnnotationService) {
        self.service = service
        super.init(frame: .zero)
        // Pattern from ScreenshotOverlayView: exact same options
        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self)
        addTrackingArea(tracking)
    }

    required init?(coder: NSCoder) { nil }

    /// Whether `event`'s location falls inside the live text field, so the
    /// panel's `sendEvent` can let a click there reach the field normally
    /// (positions the caret) instead of always routing to `mouseDown`
    /// (always reads as "start a new stroke").
    func pointIsInsideActiveTextField(_ event: NSEvent) -> Bool {
        guard let textField else { return false }
        let local = convert(event.locationInWindow, from: nil)
        return textField.frame.contains(local)
    }

    func beginTextEditor(at point: NSPoint, existingText: String = "",
                         existingColor: AnnotationColor? = nil, existingWidth: Double? = nil) {
        let fontSize = CGFloat(max(14, (existingWidth ?? service?.width ?? ScreenAnnotationSupport.defaultWidth) * 3))
        // No fixed box: the field grows to the edge of the screen so typing
        // long or multi-line text is never clipped or scrolled.
        let availableWidth = ScreenAnnotationSupport.textWrapWidth(originX: point.x, boundsWidth: bounds.width)
        let availableHeight = max(fontSize + 16, bounds.height - point.y - 24)
        let field = NSTextField(frame: NSRect(x: point.x, y: point.y,
                                               width: availableWidth, height: availableHeight))
        field.stringValue = existingText
        field.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let color = existingColor ?? service?.color
        field.textColor = color.map { NSColor(calibratedRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) } ?? .white
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.focusRingType = .none
        field.target = self
        field.action = #selector(commitTextEditor)
        field.delegate = self
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.maximumNumberOfLines = 0
        addSubview(field)
        textField = field
        textOrigin = point
        editingColor = existingColor
        editingWidth = existingWidth
        window?.makeFirstResponder(field)
        if !existingText.isEmpty, let editor = field.currentEditor() {
            editor.selectedRange = NSRange(location: existingText.utf16.count, length: 0)
        }
    }

    func cancelTextEditor() {
        let field = textField
        textField = nil
        textOrigin = nil
        editingColor = nil
        editingWidth = nil
        field?.removeFromSuperview()
        // Removing the field leaves first responder nil until the next
        // click; reclaim it now so the canvas — not the toolbar's own
        // controls — is what a keystroke like Escape reaches.
        window?.makeFirstResponder(self)
        service?.orderOutCanvasWhenEmpty()
    }

    @objc fileprivate func commitTextEditor() {
        guard let field = textField, let origin = textOrigin, let service else { return }
        service.commitText(field.stringValue, at: origin, bounds: bounds,
                           color: editingColor, width: editingWidth)
        cancelTextEditor()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitTextEditor()
    }

    /// Return inserts a newline instead of committing — only a click
    /// elsewhere, a tool switch or Escape ends editing.
    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        textView.insertNewlineIgnoringFieldEditor(nil)
        return true
    }

    override var acceptsFirstResponder: Bool { true }
    /// Flipped so origin is top-left, matching screen pixels.
    override var isFlipped: Bool { true }
    
    /// Critical: return self for all points so the view captures all mouse events.
    /// Without this, a transparent view may let clicks pass through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let textField {
            let local = convert(point, from: superview)
            if textField.frame.contains(local) {
                return textField.hitTest(local)
            }
        }
        return bounds.contains(point) ? self : nil
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let svc = service,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        for stroke in svc.strokes where !stroke.points.isEmpty {
            if stroke.tool == .text {
                let point = CGPoint(x: stroke.points[0].x * Double(bounds.width),
                                    y: stroke.points[0].y * Double(bounds.height))
                let font = NSFont.systemFont(ofSize: max(14, stroke.width * 3), weight: .medium)
                let wrapWidth = ScreenAnnotationSupport.textWrapWidth(originX: Double(point.x), boundsWidth: Double(bounds.width))
                let attributed = NSAttributedString(string: stroke.text,
                                    attributes: [.font: font,
                                                 .foregroundColor: svc.strokeColor(for: stroke)])
                attributed.draw(with: NSRect(x: point.x, y: point.y, width: wrapWidth,
                                             height: max(24, bounds.height - point.y)),
                                options: [.usesLineFragmentOrigin])
                continue
            }
            guard stroke.points.count > 1 else { continue }
            let path = CGMutablePath()
            for (i, pt) in stroke.points.enumerated() {
                let x = pt.x * Double(bounds.width)
                let y = pt.y * Double(bounds.height)
                if i == 0 { path.move(to: .init(x: x, y: y)) }
                else       { path.addLine(to: .init(x: x, y: y)) }
            }
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setLineWidth(stroke.width)
            ctx.setStrokeColor(svc.strokeColor(for: stroke).cgColor)
            let start = CGPoint(x: stroke.points[0].x * Double(bounds.width),
                                y: stroke.points[0].y * Double(bounds.height))
            let end = CGPoint(x: stroke.points[1].x * Double(bounds.width),
                              y: stroke.points[1].y * Double(bounds.height))
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                              width: abs(end.x - start.x), height: abs(end.y - start.y))
            switch stroke.tool {
            case .rectangle:
                ctx.addRect(rect)
                ctx.strokePath()
            case .ellipse:
                ctx.strokeEllipse(in: rect)
            case .redact:
                ctx.setFillColor(svc.strokeColor(for: stroke).cgColor)
                ctx.fill(rect)
            case .arrow:
                ctx.setFillColor(svc.strokeColor(for: stroke).cgColor)
                ctx.addPath(ScreenshotSupport.arrowSilhouette(from: start, to: end,
                                                               strokeWidth: stroke.width))
                ctx.fillPath()
            case .line, .pen, .highlighter:
                ctx.addPath(path)
                ctx.strokePath()
            case .eraser, .text:
                break
            }
        }
        ctx.restoreGState()
    }


    // MARK: Mouse events — pattern from ScreenshotOverlayView

    override func mouseDown(with event: NSEvent) {
        guard let svc = service, svc.isDrawingActive else { return }
        if svc.tool == .text || svc.tool == .eraser {
            isDragging = false
            let point = convert(event.locationInWindow, from: nil)
            svc.beginStroke(at: point, bounds: bounds)
            return
        }
        isDragging = true
        let point = convert(event.locationInWindow, from: nil)
        svc.beginStroke(at: point, bounds: bounds)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let svc = service, svc.isDrawingActive, isDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        svc.continueStroke(at: point, bounds: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        needsDisplay = true
    }
}

// MARK: - Toolbar (SwiftUI inside NSHostingController, pattern from QuickToolHUD)

private struct AnnotationToolbarView: View {
    @ObservedObject var service: ScreenAnnotationService
    @State private var selectedTool: AnnotationTool = .pen
    @State private var strokeWidth: Double = ScreenAnnotationSupport.defaultWidth

    private let presetColors: [AnnotationColor] = [.red, .orange, .yellow, .green,
                                                   .blue, .purple, .black, .white]
    private var strings: ScreenAnnotationStrings { FeatureStrings.annotation(L10n.shared.language) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                ForEach(AnnotationTool.allCases, id: \.rawValue) { tool in
                    toolButton(tool)
                }
            }

            Divider().frame(width: 420)

            HStack(spacing: 9) {
                ForEach(Array(presetColors.enumerated()), id: \.offset) { _, c in colorSwatch(c) }

                Divider().frame(height: 20)

                Slider(value: $strokeWidth, in: 1...30)
                    .frame(width: 90)
                    .onChange(of: strokeWidth) { _, w in service.setWidth(w) }

                Divider().frame(height: 20)

                Button { service.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help(strings.undo)
                Button { service.clearAll() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(strings.clear)

                Divider().frame(height: 20)

                Button { service.hideOverlay() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(strings.exit)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            selectedTool = service.tool
            strokeWidth  = service.width
        }
    }

    private func toolButton(_ t: AnnotationTool) -> some View {
        Button { service.setTool(t); selectedTool = t } label: {
            Image(systemName: toolSymbol(t))
                .frame(width: 27, height: 25)
        }
            .buttonStyle(.borderless)
            .background(selectedTool == t ? Color.accentColor.opacity(0.22) : .clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .foregroundStyle(selectedTool == t ? Color.accentColor : Color.primary)
            .help(toolName(t))
    }

    private func toolName(_ tool: AnnotationTool) -> String {
        switch tool {
        case .pen: return strings.pen
        case .highlighter: return strings.highlighter
        case .arrow: return strings.arrow
        case .line: return strings.line
        case .rectangle: return strings.rectangle
        case .ellipse: return strings.ellipse
        case .text: return strings.text
        case .redact: return strings.redact
        case .eraser: return strings.eraser
        }
    }

    private func toolSymbol(_ tool: AnnotationTool) -> String {
        switch tool {
        case .pen: return "pencil"
        case .highlighter: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .eraser: return "eraser"
        case .redact: return "rectangle.fill"
        }
    }

    private func colorSwatch(_ c: AnnotationColor) -> some View {
        Circle()
            .fill(Color(red: c.red, green: c.green, blue: c.blue))
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(
                service.color == c ? Color.primary : Color.clear,
                lineWidth: 2.5))
            .onTapGesture { service.setColor(c) }
    }
}
