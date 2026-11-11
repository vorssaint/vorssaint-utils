// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The capture screen. The frozen screenshot is shown dimmed on one panel per
/// display; dragging selects an area, which can then be moved and resized by
/// its handles and drawn on. Every position is a whole point in one space
/// shared by all displays, read from the pointer's own location, so a
/// selection can span displays.
final class ShotOverlay: NSObject, NSTextViewDelegate {
    enum Mode {
        /// Select, draw, then copy, save or print.
        case annotate
        /// Choose an area of one display for another feature and hand it back.
        case pick((ScreenRegionCapture.Region?) -> Void)
    }

    fileprivate final class Screen {
        let panel: ShotPanel
        let canvas: ShotCanvas
        let display: ShotDisplay
        init(panel: ShotPanel, canvas: ShotCanvas, display: ShotDisplay) {
            self.panel = panel
            self.canvas = canvas
            self.display = display
        }
    }

    private enum Drag { case none, selecting, handle, drawing }

    /// Line widths and text size per tool, kept while the app runs.
    private static var widths: [ShotTool: Double] = [
        .pen: 3, .line: 3, .arrow: 3, .rectangle: 3, .circle: 3, .marker: 16, .text: 18, .blur: 4,
    ]
    private static let grip: Double = 6
    private static let markerOpacity = 0.4

    private let service: ScreenshotService
    private let frame: ShotFrame
    private let mode: Mode
    private let renderer: ShotRenderer
    private var screens: [Screen] = []
    private var shapes = ShotShapes()
    private let defaults = UserDefaults.standard

    private var selection: ShotRect?
    private var tool: ShotTool = .none
    private var drag: Drag = .none
    private var handle: ShotHandle = .none
    private var dragStart = (x: 0, y: 0)
    private var selectionStart = ShotRect.zero
    private var current: ShotShape?
    private var cursor = (x: 0, y: 0)
    private var closed = false
    private var modal = false
    private var pickDelivered = false
    private var ownsColorPanel = false

    private var textView: NSTextView?
    private weak var textScreen: Screen?
    private var textAt = (x: 0, y: 0)

    private var hint: String?
    private var hintWork: DispatchWorkItem?

    private var toolsBar: ShotBar?
    private var actionsBar: ShotBar?
    private var toolButtons: [ShotTool: ShotBarButton] = [:]
    private var swatch: ShotSwatch?
    private var previousApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

    var onClose: (() -> Void)?
    /// Where the pointer is, in the shared space. Replaced when the overlay
    /// is driven without a pointer.
    var pointerSource: () -> (x: Int, y: Int) = ShotFrame.pointer
    /// Builds the panels without putting them on screen.
    var isHeadless = false

    var isPicking: Bool {
        if case .pick = mode { return true }
        return false
    }

    private var color: UInt32 {
        UInt32(defaults.string(forKey: DefaultsKey.shotColor) ?? "", radix: 16).map { $0 & 0xFFFFFF } ?? 0xFF0000
    }

    init(service: ScreenshotService, frame: ShotFrame, mode: Mode) {
        self.service = service
        self.frame = frame
        self.mode = mode
        renderer = ShotRenderer(frame: frame)
        super.init()
        if !isPicking {
            buildToolbars()
            if defaults.bool(forKey: DefaultsKey.shotKeepSelection),
               let last = ShotRect(storageValue: defaults.string(forKey: DefaultsKey.shotLastSelection) ?? "") {
                let kept = last.intersection(frame.bounds)
                if !kept.isEmpty { selection = kept }
            }
        }
    }

    // MARK: Windows

    func show() {
        cursor = pointerSource()
        previousApp = NSWorkspace.shared.frontmostApplication
        for display in frame.displays {
            guard let nsScreen = NSScreen.screens.first(where: { $0.displayID == display.id }) else { continue }
            let panel = ShotPanel(screen: nsScreen)
            let canvas = ShotCanvas(frame: NSRect(origin: .zero, size: nsScreen.frame.size))
            canvas.autoresizingMask = [.width, .height]
            let screen = Screen(panel: panel, canvas: canvas, display: display)
            canvas.overlay = self
            canvas.screen = screen
            panel.contentView = canvas
            screens.append(screen)
        }
        guard !screens.isEmpty else { close(); return }
        if !isHeadless {
            screens.forEach { $0.panel.orderFrontRegardless() }
            activate(screen(atX: Double(cursor.x), y: Double(cursor.y)))
        }
        // Another app coming to the front (Command-Tab, a notification
        // clicked) cancels the capture. The tool's own dialogs do not count.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, !self.closed, !self.modal,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != getpid() else { return }
            self.close()
        }
        if selection != nil { placeToolbars() }
        updateCursor()
    }

    private func activate(_ screen: Screen) {
        guard !isHeadless else { return }
        screen.panel.makeKey()
        screen.panel.makeFirstResponder(textView ?? screen.canvas)
    }

    func close() {
        guard !closed else { return }
        closed = true
        hintWork?.cancel()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        if !isPicking, let selection {
            defaults.set(selection.storageValue, forKey: DefaultsKey.shotLastSelection)
        }
        if ownsColorPanel {
            let colorPanel = NSColorPanel.shared
            ownsColorPanel = false
            colorPanel.setTarget(nil)
            colorPanel.setAction(nil)
            colorPanel.orderOut(nil)
        }
        for screen in screens {
            screen.canvas.overlay = nil
            screen.panel.orderOut(nil)
            screen.panel.close()
        }
        screens.removeAll()
        NSCursor.arrow.set()
        // A dialog of the tool brought this app forward; the app that was in
        // front before the capture gets the keyboard back.
        if NSApp.isActive, let previousApp, previousApp.processIdentifier != getpid(), !previousApp.isTerminated {
            previousApp.activate()
        }
        if case .pick(let completion) = mode, !pickDelivered {
            pickDelivered = true
            completion(nil)
        }
        onClose?()
    }

    private func screen(atX x: Double, y: Double) -> Screen {
        let display = frame.display(atX: x, y: y)
        return screens.first { $0.display.id == display.id } ?? screens[0]
    }

    private func invalidate() {
        screens.forEach { $0.canvas.needsDisplay = true }
    }

    private func hidePanels() {
        screens.forEach { $0.panel.orderOut(nil) }
    }

    private func showPanels() {
        guard !closed else { return }
        screens.forEach { $0.panel.orderFrontRegardless() }
        activate(screen(atX: Double(cursor.x), y: Double(cursor.y)))
        updateCursor()
    }

    // MARK: Mouse

    fileprivate func mouseDown(on screen: Screen, clickCount: Int) {
        let p = pointerSource()
        cursor = p
        if !isHeadless, !screen.panel.isKeyWindow { screen.panel.makeKey() }
        if textView != nil {
            commitText()
            if tool != .text { return }
        }

        if clickCount == 2, tool == .none, shapes.count == 0, !isPicking {
            selectDisplay(allOnRepeat: false)
            return
        }

        guard let sel = selection else {
            begin(.selecting, at: p)
            return
        }

        let hit = ShotGeometry.hitTest(sel, x: Double(p.x), y: Double(p.y), grip: Self.grip)
        if hit == .inside, tool == .text {
            startText(on: screen, at: p)
            return
        }
        if hit == .inside, tool != .none {
            let shape = ShotShape(tool: tool, color: color,
                                  opacity: tool == .marker ? Self.markerOpacity : 1,
                                  width: Self.widths[tool] ?? 3)
            let point = ShotPoint(x: Double(p.x), y: Double(p.y))
            shape.points = [point, point]
            current = shape
            begin(.drawing, at: p)
            return
        }
        if hit != .none {
            handle = hit
            selectionStart = sel
            begin(.handle, at: p)
            return
        }
        // Outside the selection: start over, unless that would throw away drawings.
        if shapes.count == 0 {
            selection = nil
            begin(.selecting, at: p)
        }
    }

    private func begin(_ newDrag: Drag, at p: (x: Int, y: Int)) {
        drag = newDrag
        dragStart = p
        if newDrag == .selecting || newDrag == .handle { hideToolbars() }
        invalidate()
    }

    fileprivate func mouseMoved() {
        let p = pointerSource()
        if p == cursor, drag == .none { return }
        cursor = p
        switch drag {
        case .selecting:
            if abs(p.x - dragStart.x) > 1 || abs(p.y - dragStart.y) > 1 {
                selection = ShotRect.fromCorners(dragStart.x, dragStart.y, p.x, p.y).intersection(frame.bounds)
            }
        case .handle:
            selection = ShotGeometry.drag(selectionStart, handle: handle, dx: p.x - dragStart.x,
                                          dy: p.y - dragStart.y, bounds: frame.bounds)
        case .drawing:
            if let current {
                let point = ShotPoint(x: Double(p.x), y: Double(p.y))
                if current.tool == .pen || current.tool == .marker {
                    if current.end != point { current.points.append(point) }
                } else {
                    current.points[current.points.count - 1] = point
                }
            }
        case .none:
            break
        }
        updateCursor()
        invalidate()
    }

    fileprivate func mouseUp() {
        let finished = drag
        drag = .none
        if finished == .drawing, let current {
            shapes.add(current)
            self.current = nil
        }
        if finished == .selecting, selection?.isEmpty == true { selection = nil }
        if finished == .selecting, isPicking, let selection {
            deliverPick(selection)
            return
        }
        if finished == .selecting || finished == .handle, selection != nil { placeToolbars() }
        updateCursor()
        invalidate()
    }

    /// Right click clears the selection, or cancels when there is none.
    fileprivate func rightClick() {
        guard drag == .none else { return }
        if selection != nil, shapes.count == 0 {
            selection = nil
            hideToolbars()
            updateCursor()
            invalidate()
        } else if selection == nil {
            close()
        }
    }

    fileprivate func scroll(deltaY: CGFloat) {
        guard tool != .none, deltaY != 0 else { return }
        let step: Double = deltaY > 0 ? 1 : -1
        let range: ClosedRange<Double> = tool == .text ? 8...96 : 1...60
        let size = min(max((Self.widths[tool] ?? 3) + step * (tool == .text || tool == .marker ? 2 : 1),
                           range.lowerBound), range.upperBound)
        Self.widths[tool] = size
        let strings = FeatureStrings.shot(L10n.shared.language)
        showHint(String(format: tool == .text ? strings.textSizeHintFormat : strings.sizeHintFormat, Int(size)))
        if tool == .text, let textView {
            textView.font = ShotRenderer.textFont(size: size)
            resizeTextView()
        }
    }

    private func showHint(_ text: String) {
        hint = text
        hintWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hint = nil
            self?.invalidate()
        }
        hintWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
        invalidate()
    }

    private func pointerIsOverToolbar() -> Bool {
        for bar in [toolsBar, actionsBar] {
            guard let bar, !bar.isHidden, let canvas = bar.superview as? ShotCanvas,
                  let display = canvas.screen?.display else { continue }
            let local = CGPoint(x: cursor.x - display.bounds.x, y: cursor.y - display.bounds.y)
            if bar.frame.contains(local) { return true }
        }
        return false
    }

    private func updateCursor() {
        var shape = NSCursor.crosshair
        if drag == .handle {
            shape = Self.cursor(for: handle)
        } else if drag == .none, pointerIsOverToolbar() {
            shape = .arrow
        } else if drag == .none, let sel = selection {
            let hit = ShotGeometry.hitTest(sel, x: Double(cursor.x), y: Double(cursor.y), grip: Self.grip)
            if hit == .inside {
                switch tool {
                case .none: shape = .openHand
                case .text: shape = .iBeam
                default: shape = .crosshair
                }
            } else {
                shape = Self.cursor(for: hit)
            }
        }
        shape.set()
    }

    private static func cursor(for handle: ShotHandle) -> NSCursor {
        switch handle {
        case .n, .s: return .resizeUpDown
        case .e, .w: return .resizeLeftRight
        case .nw, .se:
            if #available(macOS 15.0, *) { return .frameResize(position: .topLeft, directions: .all) }
            return .crosshair
        case .ne, .sw:
            if #available(macOS 15.0, *) { return .frameResize(position: .topRight, directions: .all) }
            return .crosshair
        case .inside: return .closedHand
        case .none: return .crosshair
        }
    }

    /// Command-A or a double click: the display under the pointer; Command-A
    /// again takes every display.
    private func selectDisplay(allOnRepeat: Bool) {
        let display = frame.display(atX: Double(cursor.x), y: Double(cursor.y)).bounds
        selection = allOnRepeat && selection == display ? frame.bounds : display
        placeToolbars()
        updateCursor()
        invalidate()
    }

    private func deliverPick(_ selection: ShotRect) {
        guard case .pick(let completion) = mode, !pickDelivered else { return }
        let display = frame.display(atX: Double(selection.x) + Double(selection.width) / 2,
                                    y: Double(selection.y) + Double(selection.height) / 2)
        let area = selection.intersection(display.bounds)
        guard !area.isEmpty else { close(); return }
        let scale = display.scale
        let region = ScreenRegionCapture.Region(
            displayID: display.id, windowID: nil,
            pixelRect: CGRect(x: CGFloat(area.x - display.bounds.x) * scale,
                              y: CGFloat(area.y - display.bounds.y) * scale,
                              width: CGFloat(area.width) * scale, height: CGFloat(area.height) * scale),
            anchorRect: ShotFrame.cocoaRect(from: area), scale: scale)
        pickDelivered = true
        close()
        completion(region)
    }

    // MARK: Keyboard

    /// True when the key was the overlay's own.
    fileprivate func keyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        if event.keyCode == 53 {
            if textView != nil { cancelText() } else { close() }
            return true
        }
        if textView != nil { return false } // typing
        if isPicking { return true }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if command {
            switch key {
            case "a": selectDisplay(allOnRepeat: true)
            case "c": output(copyImage)
            case "s": output(saveImage)
            case "p": output(printImage)
            case "z": undo()
            default: return false
            }
            return true
        }
        guard let sel = selection, drag == .none, (123...126).contains(Int(event.keyCode)) else { return false }
        let step = flags.contains(.option) ? 10 : 1
        let dx = event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0
        let dy = event.keyCode == 126 ? -step : event.keyCode == 125 ? step : 0
        // Arrows move the selection; Shift+arrows resize it from the bottom-right corner.
        selection = shift
            ? ShotGeometry.drag(sel, handle: .se, dx: dx, dy: dy, bounds: frame.bounds)
            : ShotGeometry.move(sel, dx: dx, dy: dy, bounds: frame.bounds)
        placeToolbars()
        invalidate()
        return true
    }

    private func undo() {
        if shapes.undo() { invalidate() }
    }

    // MARK: Text

    private func startText(on screen: Screen, at p: (x: Int, y: Int)) {
        let size = Self.widths[.text] ?? 18
        let view = NSTextView(frame: NSRect(x: CGFloat(p.x - screen.display.bounds.x),
                                            y: CGFloat(p.y - screen.display.bounds.y), width: 24, height: size + 6))
        view.delegate = self
        view.isRichText = false
        view.drawsBackground = false
        view.font = ShotRenderer.textFont(size: size)
        let textColor = NSColor(cgColor: ShotRenderer.cgColor(color)) ?? .red
        view.textColor = textColor
        view.insertionPointColor = textColor
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                   height: CGFloat.greatestFiniteMagnitude)
        view.isHorizontallyResizable = true
        view.isVerticallyResizable = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.wantsLayer = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.7).cgColor
        screen.canvas.addSubview(view)
        textView = view
        textScreen = screen
        textAt = p
        if !isHeadless { screen.panel.makeKey() }
        screen.panel.makeFirstResponder(view)
    }

    private func resizeTextView() {
        guard let textView, let container = textView.textContainer, let layout = textView.layoutManager else { return }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let lineHeight = layout.defaultLineHeight(for: textView.font ?? ShotRenderer.textFont(size: 18))
        textView.setFrameSize(NSSize(width: max(24, used.width.rounded(.up) + 4),
                                     height: max(lineHeight, used.height).rounded(.up) + 2))
    }

    func textDidChange(_ notification: Notification) {
        resizeTextView()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        cancelText()
        return true
    }

    private func commitText() {
        guard let textView else { return }
        let shape = ShotShape(tool: .text, color: color,
                              fontSize: Double(textView.font?.pointSize ?? CGFloat(Self.widths[.text] ?? 18)))
        shape.text = textView.string
        shape.points = [ShotPoint(x: Double(textAt.x), y: Double(textAt.y))]
        shapes.add(shape)
        cancelText()
    }

    private func cancelText() {
        guard let textView else { return }
        let screen = textScreen
        textView.delegate = nil
        textView.removeFromSuperview()
        self.textView = nil
        textScreen = nil
        if let screen { activate(screen) }
        invalidate()
    }

    // MARK: Toolbars

    private func buildToolbars() {
        let shot = FeatureStrings.screenshot(L10n.shared.language)
        let extra = FeatureStrings.shot(L10n.shared.language)
        let common = L10n.shared.s

        let tools = ShotBar(vertical: true)
        func addTool(_ tool: ShotTool, symbol: String, tip: String) {
            let button = ShotBarButton(symbol: symbol, tip: tip) { [weak self] in self?.select(tool) }
            toolButtons[tool] = button
            tools.add(button)
        }
        addTool(.pen, symbol: "pencil", tip: shot.toolFreehand)
        addTool(.line, symbol: "line.diagonal", tip: shot.toolLine)
        addTool(.arrow, symbol: "arrow.up.right", tip: shot.toolArrow)
        addTool(.rectangle, symbol: "rectangle", tip: shot.toolRect)
        addTool(.circle, symbol: "circle", tip: shot.toolEllipse)
        addTool(.marker, symbol: "highlighter", tip: shot.toolHighlight)
        addTool(.text, symbol: "textformat", tip: shot.toolText)
        addTool(.blur, symbol: "checkerboard.rectangle", tip: shot.toolBlur)
        let swatch = ShotSwatch()
        self.swatch = swatch
        tools.add(ShotBarButton(content: swatch, tip: shot.colorLabel) { [weak self] in self?.pickColor() })
        tools.add(ShotBarButton(symbol: "arrow.uturn.backward", tip: "\(common.menuUndo) (⌘Z)") { [weak self] in
            self?.undo()
        })
        toolsBar = tools

        let actions = ShotBar(vertical: false)
        actions.add(ShotBarButton(symbol: "photo", tip: extra.openInPreview) { [weak self] in
            guard let self else { return }
            self.output(self.openInPreview)
        })
        actions.add(ShotBarButton(symbol: "printer", tip: "\(extra.print) (⌘P)") { [weak self] in
            guard let self else { return }
            self.output(self.printImage)
        })
        actions.add(ShotBarButton(symbol: "doc.on.doc", tip: "\(shot.copyButton) (⌘C)") { [weak self] in
            guard let self else { return }
            self.output(self.copyImage)
        })
        actions.add(ShotBarButton(symbol: "square.and.arrow.down", tip: "\(shot.saveButton) (⌘S)") { [weak self] in
            guard let self else { return }
            self.output(self.saveImage)
        })
        actions.addSeparator()
        actions.add(ShotBarButton(symbol: "xmark", tip: "\(common.menuClose) (Esc)") { [weak self] in
            self?.close()
        })
        actionsBar = actions
        updateSwatch()
    }

    private func select(_ newTool: ShotTool) {
        if textView != nil { commitText() }
        tool = tool == newTool ? .none : newTool
        for (key, button) in toolButtons { button.isSelected = key == tool }
        updateCursor()
    }

    private func pickColor() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = NSColor(cgColor: ShotRenderer.cgColor(color)) ?? .red
        panel.setTarget(self)
        panel.setAction(#selector(colorPicked(_:)))
        ownsColorPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
    }

    @objc private func colorPicked(_ sender: NSColorPanel) {
        guard !closed, let rgb = sender.color.usingColorSpace(.sRGB) else { return }
        let value = (Int((rgb.redComponent * 255).rounded()) << 16)
            | (Int((rgb.greenComponent * 255).rounded()) << 8)
            | Int((rgb.blueComponent * 255).rounded())
        defaults.set(String(format: "%06X", value), forKey: DefaultsKey.shotColor)
        updateSwatch()
        if let textView {
            textView.textColor = sender.color
            textView.insertionPointColor = sender.color
        }
    }

    private func updateSwatch() {
        swatch?.color = NSColor(cgColor: ShotRenderer.cgColor(color)) ?? .red
    }

    private func hideToolbars() {
        toolsBar?.isHidden = true
        actionsBar?.isHidden = true
    }

    /// Puts both toolbars on the display holding the selection's bottom-right corner.
    private func placeToolbars() {
        guard let sel = selection, !closed, let toolsBar, let actionsBar else { hideToolbars(); return }
        let screen = screen(atX: Double(sel.right - 1), y: Double(sel.bottom - 1))
        for bar in [toolsBar, actionsBar] {
            if bar.superview !== screen.canvas {
                bar.removeFromSuperview()
                screen.canvas.addSubview(bar)
            }
            bar.isHidden = false
        }
        let placed = ShotGeometry.placeToolbars(
            selection: sel, display: screen.display.bounds,
            tools: (Int(toolsBar.frame.width.rounded(.up)), Int(toolsBar.frame.height.rounded(.up))),
            actions: (Int(actionsBar.frame.width.rounded(.up)), Int(actionsBar.frame.height.rounded(.up))),
            gap: 6)
        let origin = screen.display.bounds
        toolsBar.setFrameOrigin(NSPoint(x: placed.tools.x - origin.x, y: placed.tools.y - origin.y))
        actionsBar.setFrameOrigin(NSPoint(x: placed.actions.x - origin.x, y: placed.actions.y - origin.y))
    }

    // MARK: Output

    private func output(_ action: (CGImage, CGFloat) -> Bool) {
        if textView != nil { commitText() }
        guard drag == .none, !isPicking, let shot = renderedSelection() else { return }
        modal = true
        let done = action(shot.image, shot.scale)
        modal = false
        if done { close() }
    }

    /// The selection with its drawings, as it would be copied or saved.
    func renderedSelection() -> (image: CGImage, scale: CGFloat)? {
        guard let sel = selection else { return nil }
        return frame.render(sel, shapes: shapes.items, renderer: renderer)
    }

    private func copyImage(_ image: CGImage, scale: CGFloat) -> Bool {
        close()
        service.copy(image, scale: scale)
        return true
    }

    /// The dialogs are ordinary windows, so the capture screen steps out of
    /// their way and comes back when they are cancelled.
    private func saveImage(_ image: CGImage, scale: CGFloat) -> Bool {
        hidePanels()
        let saved = service.saveWithPanel(image, scale: scale)
        if !saved { showPanels() }
        return saved
    }

    private func printImage(_ image: CGImage, scale: CGFloat) -> Bool {
        hidePanels()
        let printed = service.print(image, scale: scale)
        if !printed { showPanels() }
        return printed
    }

    private func openInPreview(_ image: CGImage, scale: CGFloat) -> Bool {
        // Preview comes forward by itself; nothing is handed back to the app
        // that was in front.
        previousApp = nil
        close()
        service.openInPreview(image, scale: scale)
        return true
    }

    // MARK: Drawing

    /// Draws one display's part of the capture screen. The context's space is
    /// the shared one.
    fileprivate func render(_ context: CGContext, on screen: Screen) {
        let display = screen.display.bounds
        ShotFrame.draw(screen.display.image, in: display, context: context)

        context.saveGState()
        context.beginPath()
        context.addRect(cgRect(display))
        if let sel = selection { context.addRect(cgRect(sel)) }
        context.setFillColor(CGColor(gray: 0, alpha: 0.45))
        context.fillPath(using: .evenOdd)
        context.restoreGState()

        if let sel = selection {
            context.saveGState()
            context.clip(to: cgRect(sel))
            for shape in shapes.items { renderer.draw(shape, in: context) }
            if let current { renderer.draw(current, in: context) }
            context.restoreGState()
            drawSelection(sel, in: context, display: screen.display)
        }

        let selecting = selection == nil || drag == .selecting || (drag == .handle && handle != .inside)
        if selecting, display.contains(Double(cursor.x), Double(cursor.y)) {
            if selection == nil { drawCrosshair(in: context, display: display) }
            if defaults.bool(forKey: DefaultsKey.shotMagnifier) { drawMagnifier(in: context, display: screen.display) }
        }
        if let hint, display.contains(Double(cursor.x), Double(cursor.y)) {
            drawLabel(hint, x: CGFloat(cursor.x) + 16, y: CGFloat(cursor.y) + 16, in: context)
        }
    }

    private func cgRect(_ rect: ShotRect) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    private func drawSelection(_ sel: ShotRect, in context: CGContext, display: ShotDisplay) {
        let rect = cgRect(sel)
        context.saveGState()
        context.setLineWidth(1)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.stroke(rect)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.stroke(rect)
        context.restoreGState()

        if drag != .drawing, !isPicking {
            let size: CGFloat = 7
            let points = [
                (rect.minX, rect.minY), (rect.midX, rect.minY), (rect.maxX, rect.minY),
                (rect.minX, rect.midY), (rect.maxX, rect.midY),
                (rect.minX, rect.maxY), (rect.midX, rect.maxY), (rect.maxX, rect.maxY),
            ]
            context.saveGState()
            context.setLineWidth(1)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            for (x, y) in points {
                guard display.bounds.contains(Double(x) - 1, Double(y) - 1)
                        || display.bounds.contains(Double(x), Double(y)) else { continue }
                let knob = CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
                context.fill(knob)
                context.stroke(knob)
            }
            context.restoreGState()
        }

        // W×H above the top-left corner, on the display that holds that corner.
        guard display.bounds.contains(Double(sel.x), Double(sel.y)) else { return }
        let scale = frame.scale(for: sel)
        let text = "\(Int((CGFloat(sel.width) * scale).rounded())) × \(Int((CGFloat(sel.height) * scale).rounded()))"
        let size = Self.labelSize(text)
        let place = ShotGeometry.placeSizeLabel(selection: sel, display: display.bounds,
                                                label: (Int(size.width.rounded(.up)), Int(size.height.rounded(.up))),
                                                gap: 4)
        drawLabel(text, x: CGFloat(place.x), y: CGFloat(place.y), in: context)
    }

    private func drawCrosshair(in context: CGContext, display: ShotRect) {
        let x = CGFloat(cursor.x) + 0.5, y = CGFloat(cursor.y) + 0.5
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.35))
        context.setLineWidth(1)
        context.beginPath()
        context.move(to: CGPoint(x: CGFloat(display.x), y: y))
        context.addLine(to: CGPoint(x: CGFloat(display.right), y: y))
        context.move(to: CGPoint(x: x, y: CGFloat(display.y)))
        context.addLine(to: CGPoint(x: x, y: CGFloat(display.bottom)))
        context.strokePath()
        context.restoreGState()
    }

    /// A zoomed view of the pixels around the pointer, with its position and
    /// colour, like a loupe.
    private func drawMagnifier(in context: CGContext, display: ShotDisplay) {
        guard let hit = frame.pixel(atX: cursor.x, y: cursor.y) else { return }
        let span = 15
        let size: CGFloat = 120
        let gap: CGFloat = 20
        let bounds = display.bounds
        let info = "\(hit.px), \(hit.py)   \(frame.hex(atX: cursor.x, y: cursor.y))"
        let infoSize = (info as NSString).size(withAttributes: Self.labelAttributes(size: 11))
        let total = size + infoSize.height + 8
        var x = CGFloat(cursor.x) + gap, y = CGFloat(cursor.y) + gap
        if x + size > CGFloat(bounds.right) { x = CGFloat(cursor.x) - gap - size }
        if y + total > CGFloat(bounds.bottom) { y = CGFloat(cursor.y) - gap - total }

        context.saveGState()
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: x - 1, y: y - 1, width: size + 2, height: total + 2))
        let cell = size / CGFloat(span)
        // Only the pixels that exist are drawn; past a display's edge the loupe stays black.
        let wanted = CGRect(x: hit.px - span / 2, y: hit.py - span / 2, width: span, height: span)
        let available = wanted.intersection(CGRect(x: 0, y: 0, width: hit.display.image.width,
                                                   height: hit.display.image.height))
        if !available.isNull, let crop = hit.display.image.cropping(to: available) {
            let target = CGRect(x: x + (available.minX - wanted.minX) * cell,
                                y: y + (available.minY - wanted.minY) * cell,
                                width: available.width * cell, height: available.height * cell)
            context.interpolationQuality = .none
            context.saveGState()
            context.translateBy(x: target.minX, y: target.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(crop, in: CGRect(origin: .zero, size: target.size))
            context.restoreGState()
        }
        let center = CGRect(x: x + cell * CGFloat(span / 2), y: y + cell * CGFloat(span / 2), width: cell, height: cell)
        context.setLineWidth(1)
        context.setStrokeColor(CGColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.6))
        context.beginPath()
        context.move(to: CGPoint(x: x, y: center.midY))
        context.addLine(to: CGPoint(x: center.minX, y: center.midY))
        context.move(to: CGPoint(x: center.maxX, y: center.midY))
        context.addLine(to: CGPoint(x: x + size, y: center.midY))
        context.move(to: CGPoint(x: center.midX, y: y))
        context.addLine(to: CGPoint(x: center.midX, y: center.minY))
        context.move(to: CGPoint(x: center.midX, y: center.maxY))
        context.addLine(to: CGPoint(x: center.midX, y: y + size))
        context.strokePath()
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.stroke(center)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.5))
        context.stroke(CGRect(x: x, y: y, width: size, height: size))
        context.restoreGState()
        drawText(info, at: CGPoint(x: x + 4, y: y + size + 4), size: 11, in: context)
    }

    private static func labelAttributes(size: CGFloat = 12) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: NSColor.white]
    }

    private static func labelSize(_ text: String) -> CGSize {
        let size = (text as NSString).size(withAttributes: labelAttributes())
        return CGSize(width: size.width + 12, height: size.height + 6)
    }

    private func drawLabel(_ text: String, x: CGFloat, y: CGFloat, in context: CGContext) {
        let size = Self.labelSize(text)
        context.saveGState()
        context.setFillColor(CGColor(gray: 0, alpha: 0.75))
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: size.width, height: size.height),
                               cornerWidth: 4, cornerHeight: 4, transform: nil))
        context.fillPath()
        context.restoreGState()
        drawText(text, at: CGPoint(x: x + 6, y: y + 3), size: 12, in: context)
    }

    private func drawText(_ text: String, at point: CGPoint, size: CGFloat, in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        (text as NSString).draw(at: point, withAttributes: Self.labelAttributes(size: size))
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Full-screen borderless panel for one display. It never activates the app,
/// so the app in front keeps its place, but it takes the keyboard.
private final class ShotPanel: OverlayPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Draws one display's part of the capture screen and hands its events on.
private final class ShotCanvas: NSView {
    weak var overlay: ShotOverlay?
    var screen: ShotOverlay.Screen?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let overlay, let screen, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: -CGFloat(screen.display.bounds.x), y: -CGFloat(screen.display.bounds.y))
        overlay.render(context, on: screen)
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        guard let screen else { return }
        overlay?.mouseDown(on: screen, clickCount: event.clickCount)
    }
    override func mouseDragged(with event: NSEvent) { overlay?.mouseMoved() }
    override func mouseMoved(with event: NSEvent) { overlay?.mouseMoved() }
    override func mouseEntered(with event: NSEvent) { overlay?.mouseMoved() }
    override func mouseUp(with event: NSEvent) { overlay?.mouseUp() }
    override func rightMouseUp(with event: NSEvent) { overlay?.rightClick() }
    override func scrollWheel(with event: NSEvent) { overlay?.scroll(deltaY: event.scrollingDeltaY) }

    override func keyDown(with event: NSEvent) {
        if overlay?.keyDown(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        return overlay?.keyDown(event) == true || super.performKeyEquivalent(with: event)
    }

    // The overlay answers every key itself; an unanswered one stays silent.
    override func noResponder(for eventSelector: Selector) {}
}

/// A dark rounded strip of buttons beside the selection.
private final class ShotBar: NSView {
    private let vertical: Bool
    private var offset: CGFloat = 3
    private static let padding: CGFloat = 3

    override var isFlipped: Bool { true }

    init(vertical: Bool) {
        self.vertical = vertical
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.125, green: 0.125, blue: 0.125, alpha: 0.97).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 8
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    func add(_ button: ShotBarButton) {
        let side = ShotBarButton.side + 2
        button.setFrameOrigin(vertical ? NSPoint(x: Self.padding + 1, y: offset + 1)
                                       : NSPoint(x: offset + 1, y: Self.padding + 1))
        addSubview(button)
        offset += side
        resize()
    }

    func addSeparator() {
        let line = NSView(frame: vertical
            ? NSRect(x: Self.padding + 6, y: offset + 3, width: ShotBarButton.side - 10, height: 1)
            : NSRect(x: offset + 3, y: Self.padding + 6, width: 1, height: ShotBarButton.side - 10))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
        addSubview(line)
        offset += 7
        resize()
    }

    private func resize() {
        let thickness = ShotBarButton.side + 2 + Self.padding * 2
        setFrameSize(vertical ? NSSize(width: thickness, height: offset + Self.padding)
                              : NSSize(width: offset + Self.padding, height: thickness))
    }

    // A press on the strip between two buttons must not start a selection under it.
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
}

private final class ShotBarButton: NSView {
    static let side: CGFloat = 32
    private let action: () -> Void
    private var hovered = false
    private var pressed = false
    private var tracking: NSTrackingArea?

    var isSelected = false {
        didSet { refresh() }
    }

    convenience init(symbol: String, tip: String, action: @escaping () -> Void) {
        let image = NSImageView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(configuration)
        image.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        image.imageScaling = .scaleProportionallyDown
        self.init(content: image, tip: tip, action: action)
    }

    init(content: NSView, tip: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        wantsLayer = true
        layer?.cornerRadius = 6
        toolTip = tip
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tip)
        content.setFrameOrigin(NSPoint(x: ((Self.side - content.frame.width) / 2).rounded(),
                                       y: ((Self.side - content.frame.height) / 2).rounded()))
        addSubview(content)
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // The whole square is the button, whatever it shows inside.
        frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    private func refresh() {
        let color: NSColor
        if isSelected {
            color = NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 0.55)
        } else if pressed {
            color = NSColor.white.withAlphaComponent(0.22)
        } else if hovered {
            color = NSColor.white.withAlphaComponent(0.12)
        } else {
            color = .clear
        }
        layer?.backgroundColor = color.cgColor
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; refresh(); NSCursor.arrow.set() }
    override func mouseExited(with event: NSEvent) { hovered = false; pressed = false; refresh() }
    override func mouseDown(with event: NSEvent) { pressed = true; refresh() }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        let wasPressed = pressed
        pressed = false
        refresh()
        if inside, wasPressed { action() }
    }
    override func rightMouseUp(with event: NSEvent) {}
}

/// The drawing colour, as the colour button shows it.
private final class ShotSwatch: NSView {
    var color: NSColor = .red {
        didSet { layer?.backgroundColor = color.cgColor }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        layer?.backgroundColor = color.cgColor
    }

    required init?(coder: NSCoder) { nil }
}
