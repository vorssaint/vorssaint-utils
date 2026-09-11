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

    // MARK: - State

    private(set) var isDrawingActive = false
    private(set) var strokes: [AnnotationStroke] = []
    @Published private(set) var selectedStrokeIndex: Int?
    @Published private(set) var shortcutRegistrationFailed = false

    // Preferences (kept in sync with UserDefaults)
    @Published private(set) var tool: AnnotationTool = .pen
    @Published private(set) var color: AnnotationColor = .red
    @Published private(set) var width = ScreenAnnotationSupport.defaultWidth

    // MARK: - Monitors

    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?

    // MARK: - Shortcut (Carbon)

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var registeredShortcut: GlobalShortcut?

    private override init() { super.init() }

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
        strokes = ScreenAnnotationSupport.clear(strokes)
        drawingView?.needsDisplay = true
    }

    @objc func undo() {
        strokes = ScreenAnnotationSupport.undo(strokes)
        drawingView?.needsDisplay = true
    }

    @objc func hideOverlay() {
        exitDrawingMode()
        canvasPanel?.orderOut(nil)
        toolbarPanel?.orderOut(nil)
    }

    func teardown() {
        exitDrawingMode()
        removeKeyMonitors()
        unregisterShortcut()
        canvasPanel?.orderOut(nil)
        canvasPanel?.contentView = nil
        canvasPanel = nil
        toolbarPanel?.orderOut(nil)
        toolbarPanel?.contentViewController = nil
        toolbarPanel = nil
        drawingView = nil
        strokes.removeAll()
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
        // Keep the strokes visible, but restore pass-through to the app below.
        canvasPanel?.ignoresMouseEvents = ScreenAnnotationSupport.canvasIgnoresMouseEvents(isDrawing: false)
        removeKeyMonitors()
        canvasPanel?.resignKey()
        drawingView?.needsDisplay = true
    }

    // MARK: - Panel building

    private func buildPanels() {
        guard let screen = NSScreen.main else { return }
        buildCanvasPanel(screen: screen)
        buildToolbarPanel(screen: screen)
    }


    /// Builds the full-screen drawing surface.
    /// Mirrors `ScreenshotOverlayPanel` from `ScreenshotSelectionController`.
    private func buildCanvasPanel(screen: NSScreen) {
        let p = AnnotationCanvasPanel(
            contentRect: screen.frame,
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
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        view.autoresizingMask = [.width, .height]
        p.contentView = view
        self.canvasPanel = p
        self.drawingView = view
    }

    private func buildToolbarPanel(screen: NSScreen) {
        let host = NSHostingController(rootView: AnyView(AnnotationToolbarView(service: self)))
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize

        let rect = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + 24,
            width: max(size.width, 300),
            height: max(size.height, 44))

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
        guard let screen = NSScreen.main,
              let canvas = canvasPanel,
              let toolbar = toolbarPanel else { return }

        canvas.setFrame(screen.frame, display: false)
        canvas.orderFrontRegardless()

        if let host = toolbar.contentViewController {
            host.view.layoutSubtreeIfNeeded()
            let size = host.view.fittingSize
            let tb = NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.minY + 24,
                width: max(size.width, 300),
                height: max(size.height, 44))
            toolbar.setFrame(tb, display: false)
        }
        toolbar.orderFrontRegardless()
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
        tool = t
        UserDefaults.standard.set(t.rawValue, forKey: DefaultsKey.screenAnnotationTool)
    }

    func setColor(_ c: AnnotationColor) {
        color = c
        UserDefaults.standard.set("\(c.red),\(c.green),\(c.blue)",
                                   forKey: DefaultsKey.screenAnnotationColor)
    }

    func setWidth(_ w: Double) {
        width = min(max(w, 1), 40)
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
            drawingView?.beginTextEditor(at: p)
            return
        }
        if tool == .select || tool == .eraser {
            let index = strokeIndex(at: p, bounds: bounds)
            selectedStrokeIndex = tool == .select ? index : nil
            if tool == .eraser, let index { strokes.remove(at: index) }
            drawingView?.needsDisplay = true
            return
        }
        let n = ScreenAnnotationSupport.normalized(
            point: AnnotationPoint(x: p.x, y: p.y),
            in: (Double(bounds.width), Double(bounds.height)))
        strokes.append(AnnotationStroke(tool: tool, color: color, width: width, points: [n, n]))
    }

    fileprivate func commitText(_ value: String, at p: NSPoint, bounds: CGRect) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let n = ScreenAnnotationSupport.normalized(
            point: AnnotationPoint(x: p.x, y: p.y),
            in: (Double(bounds.width), Double(bounds.height)))
        strokes.append(AnnotationStroke(tool: .text, color: color, width: width,
                                        points: [n], text: text))
        drawingView?.needsDisplay = true
    }

    private func strokeIndex(at p: NSPoint, bounds: CGRect) -> Int? {
        let point = CGPoint(x: p.x, y: p.y)
        for index in strokes.indices.reversed() {
            let stroke = strokes[index]
            let points = stroke.points.map {
                CGPoint(x: $0.x * Double(bounds.width), y: $0.y * Double(bounds.height))
            }
            guard let first = points.first else { continue }
            var hit = CGRect(x: first.x, y: first.y, width: 1, height: 1)
            for candidate in points.dropFirst() { hit = hit.union(CGRect(x: candidate.x, y: candidate.y, width: 1, height: 1)) }
            if stroke.tool == .text {
                hit.size.width = max(40, CGFloat(stroke.text.count) * max(8, stroke.width * 2.2))
                hit.size.height = max(24, stroke.width * 4)
            }
            let tolerance = max(12, stroke.width * 2)
            if hit.insetBy(dx: -tolerance, dy: -tolerance).contains(point) { return index }
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

    // MARK: - Carbon shortcut

    func syncShortcut() {
        let on = AppFeature.screenAnnotation.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.screenAnnotationShortcutEnabled)
        on ? registerShortcut() : unregisterShortcut()
    }

    private func registerShortcut() {
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.screenAnnotationShortcut,
                                            fallback: .screenAnnotationDefault)
        if hotKeyRef != nil, registeredShortcut == shortcut { return }
        unregisterShortcut()
        if hotKeyHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(
                GetEventDispatcherTarget(),
                { _, event, userData -> OSStatus in
                    guard let userData else { return OSStatus(eventNotHandledErr) }
                    var id = EventHotKeyID()
                    if let event {
                        GetEventParameter(event,
                                          EventParamName(kEventParamDirectObject),
                                          EventParamType(typeEventHotKeyID),
                                          nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                    }
                    guard id.signature == 0x5655_414E, id.id == 7 else {
                        return OSStatus(eventNotHandledErr)
                    }
                    let svc = Unmanaged<ScreenAnnotationService>
                        .fromOpaque(userData).takeUnretainedValue()
                    DispatchQueue.main.async { svc.toggleDrawing() }
                    return noErr
                },
                1, &spec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.carbonKeyCode, shortcut.carbonModifiers,
            EventHotKeyID(signature: 0x5655_414E, id: 7),
            GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRef = ref; registeredShortcut = shortcut
            shortcutRegistrationFailed = false
        } else {
            hotKeyRef = nil; registeredShortcut = nil
            shortcutRegistrationFailed = true
        }
    }

    private func unregisterShortcut() {
        if let h = hotKeyRef { UnregisterEventHotKey(h) }
        hotKeyRef = nil; registeredShortcut = nil
        shortcutRegistrationFailed = false
    }
}

// MARK: - Canvas panel

/// Full-screen drawing surface. Must return `canBecomeKey = true` so
/// `makeKey()` succeeds and the local event monitor filters work.
/// Pattern identical to `ScreenshotOverlayPanel`.
private final class AnnotationCanvasPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    
    /// Route mouse events directly to the drawing view.
    /// Pattern from Annotate's OverlayWindow: transparent panels may not
    /// deliver events through the normal responder chain.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            NSLog("🎯 AnnotationCanvasPanel.sendEvent: \(event.type.rawValue) at \(event.locationInWindow)")
            NSLog("🎯 contentView type: \(type(of: contentView))")
            if let view = contentView as? AnnotationDrawingView {
                NSLog("🎯 Routing to AnnotationDrawingView")
                switch event.type {
                case .leftMouseDown:  view.mouseDown(with: event)
                case .leftMouseDragged: view.mouseDragged(with: event)
                case .leftMouseUp:    view.mouseUp(with: event)
                default: break
                }
                return
            } else {
                NSLog("❌ contentView is NOT AnnotationDrawingView")
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

    func beginTextEditor(at point: NSPoint) {
        textField?.removeFromSuperview()
        let field = NSTextField(frame: NSRect(x: point.x, y: point.y,
                                               width: 300, height: 34))
        field.font = NSFont.systemFont(ofSize: 18, weight: .medium)
        field.textColor = .white
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.focusRingType = .none
        field.target = self
        field.action = #selector(commitTextEditor)
        field.delegate = self
        addSubview(field)
        textField = field
        textOrigin = point
        window?.makeFirstResponder(field)
    }

    func cancelTextEditor() {
        textField?.removeFromSuperview()
        textField = nil
        textOrigin = nil
    }

    @objc private func commitTextEditor() {
        guard let field = textField, let origin = textOrigin, let service else { return }
        service.commitText(field.stringValue, at: origin, bounds: bounds)
        cancelTextEditor()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitTextEditor()
    }

    override var acceptsFirstResponder: Bool { true }
    /// Flipped so origin is top-left, matching screen pixels.
    override var isFlipped: Bool { true }
    
    /// Critical: return self for all points so the view captures all mouse events.
    /// Without this, a transparent view may let clicks pass through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return bounds.contains(point) ? self : nil
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let svc = service,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        for (index, stroke) in svc.strokes.enumerated() where !stroke.points.isEmpty {
            if stroke.tool == .text {
                let point = CGPoint(x: stroke.points[0].x * Double(bounds.width),
                                    y: stroke.points[0].y * Double(bounds.height))
                let font = NSFont.systemFont(ofSize: max(14, stroke.width * 3), weight: .medium)
                let textSize = (stroke.text as NSString).size(withAttributes: [.font: font])
                NSAttributedString(string: stroke.text,
                                    attributes: [.font: font,
                                                 .foregroundColor: svc.strokeColor(for: stroke)])
                    .draw(at: point)
                if svc.selectedStrokeIndex == index {
                    ctx.setStrokeColor(NSColor.systemBlue.cgColor)
                    ctx.setLineWidth(2)
                    ctx.setLineDash(phase: 0, lengths: [5, 3])
                    ctx.stroke(CGRect(x: point.x - 4, y: point.y - 4,
                                      width: textSize.width + 8, height: textSize.height + 8))
                }
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
            case .select, .text, .eraser:
                break
            }
            if svc.selectedStrokeIndex == index {
                ctx.setStrokeColor(NSColor.systemBlue.cgColor)
                ctx.setLineWidth(2)
                ctx.setLineDash(phase: 0, lengths: [5, 3])
                ctx.stroke(rect.insetBy(dx: -6, dy: -6))
            }
        }
        ctx.restoreGState()
    }


    // MARK: Mouse events — pattern from ScreenshotOverlayView

    override func mouseDown(with event: NSEvent) {
        guard let svc = service, svc.isDrawingActive else { return }
        if svc.tool == .text || svc.tool == .select || svc.tool == .eraser {
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
            .help(t.rawValue.capitalized)
    }

    private func toolSymbol(_ tool: AnnotationTool) -> String {
        switch tool {
        case .select: return "cursorarrow"
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
