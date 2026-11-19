// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SwiftUI

/// Interactive full-screen overlay for picking a single click target or recording
/// a sequence of screen click coordinates for a macro.
final class AutoClickerScreenPicker {

    static let shared = AutoClickerScreenPicker()

    private var scrimPanels: [NSPanel] = []
    private var hudPanel: NSPanel?
    private var keyMonitor: Any?
    private var isActive = false

    private var recordedSteps: [AutoClickerMacroStep] = []
    private var stepNumberOffset = 0
    private var hudState = PickerHUDState()

    private var singleCompletion: ((CGPoint?) -> Void)?
    private var macroCompletion: (([AutoClickerMacroStep]) -> Void)?

    private init() {}

    // MARK: - Public API

    func pickSinglePoint(completion: @escaping (CGPoint?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cancelActiveSession()
            self.isActive = true
            self.singleCompletion = completion
            self.macroCompletion = nil
            self.recordedSteps = []
            self.stepNumberOffset = 0

            let text = FeatureStrings.autoClicker(L10n.shared.language)
            self.hudState.isMacroMode = false
            self.hudState.stepCount = 0
            self.hudState.title = text.pickerSingleHint
            self.hudState.undoTitle = text.pickerUndoAction
            self.hudState.doneTitle = text.pickerDoneAction
            self.hudState.cancelTitle = text.pickerCancelAction

            self.presentOverlays(isMacroMode: false)
        }
    }

    func recordMacroSteps(existingCount: Int, completion: @escaping ([AutoClickerMacroStep]) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cancelActiveSession()
            self.isActive = true
            self.singleCompletion = nil
            self.macroCompletion = completion
            self.recordedSteps = []
            self.stepNumberOffset = existingCount

            let text = FeatureStrings.autoClicker(L10n.shared.language)
            self.hudState.isMacroMode = true
            self.hudState.stepCount = 0
            self.hudState.title = text.pickerMacroHint
            self.hudState.undoTitle = text.pickerUndoAction
            self.hudState.doneTitle = text.pickerDoneAction
            self.hudState.cancelTitle = text.pickerCancelAction

            self.presentOverlays(isMacroMode: true)
        }
    }

    // MARK: - Overlay Management

    private func presentOverlays(isMacroMode: Bool) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            finish(cancelled: true)
            return
        }

        let primaryMaxY = screens.first?.frame.maxY ?? 0

        for screen in screens {
            let panel = PickerScrimPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

            let canvas = PickerCanvasView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                screenFrame: screen.frame,
                primaryScreenMaxY: primaryMaxY,
                isMacroMode: isMacroMode
            )
            canvas.stepsProvider = { [weak self] in
                guard let self else { return [] }
                return self.recordedSteps.enumerated().map { index, step in
                    (self.stepNumberOffset + index + 1, CGPoint(x: step.x, y: step.y), step.button)
                }
            }
            canvas.onPointClicked = { [weak self] cgPoint, button in
                self?.handlePointClick(cgPoint, button: button)
            }

            panel.contentView = canvas
            panel.orderFrontRegardless()
            scrimPanels.append(panel)
        }

        presentHUDPanel(on: NSScreen.main ?? screens[0])
        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        scrimPanels.first?.makeKeyAndOrderFront(nil)
    }

    private func presentHUDPanel(on screen: NSScreen) {
        let width: CGFloat = hudState.isMacroMode ? 480 : 380
        let height: CGFloat = 46
        let originX = screen.visibleFrame.midX - width / 2
        let originY = screen.visibleFrame.maxY - height - 24

        let panel = NSPanel(
            contentRect: NSRect(x: originX, y: originY, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let hudView = PickerHUDView(
            state: hudState,
            onUndo: { [weak self] in self?.undoLastStep() },
            onDone: { [weak self] in self?.finish(cancelled: false) },
            onCancel: { [weak self] in self?.finish(cancelled: true) }
        )
        panel.contentView = NSHostingView(rootView: hudView)
        panel.orderFrontRegardless()
        hudPanel = panel
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.finish(cancelled: true)
                return nil
            }
            if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
                if self?.hudState.isMacroMode == true {
                    self?.finish(cancelled: false)
                    return nil
                }
            }
            return event
        }
    }

    // MARK: - Actions

    private func handlePointClick(_ cgPoint: CGPoint, button: AutoClickerButton) {
        guard isActive else { return }

        if hudState.isMacroMode {
            let step = AutoClickerMacroStep(
                x: cgPoint.x.rounded(),
                y: cgPoint.y.rounded(),
                button: button,
                delayAfterMs: 200,
                clickCount: 1
            )
            recordedSteps.append(step)
            hudState.stepCount = recordedSteps.count
            refreshCanvases()
        } else {
            let completion = singleCompletion
            tearDown()
            completion?(cgPoint)
        }
    }

    private func undoLastStep() {
        guard !recordedSteps.isEmpty else { return }
        recordedSteps.removeLast()
        hudState.stepCount = recordedSteps.count
        refreshCanvases()
    }

    private func refreshCanvases() {
        for panel in scrimPanels {
            panel.contentView?.needsDisplay = true
        }
    }

    private func finish(cancelled: Bool) {
        if hudState.isMacroMode {
            let steps = cancelled ? [] : recordedSteps
            let completion = macroCompletion
            tearDown()
            completion?(steps)
        } else {
            let completion = singleCompletion
            tearDown()
            completion?(nil)
        }
    }

    private func cancelActiveSession() {
        guard isActive else { return }
        finish(cancelled: true)
    }

    private func tearDown() {
        isActive = false
        singleCompletion = nil
        macroCompletion = nil

        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        hudPanel?.close()
        hudPanel = nil

        for panel in scrimPanels {
            panel.close()
        }
        scrimPanels.removeAll()
    }
}

// MARK: - HUD State & SwiftUI View

private final class PickerHUDState: ObservableObject {
    @Published var isMacroMode = false
    @Published var stepCount = 0
    @Published var title = ""
    @Published var undoTitle = "Undo"
    @Published var doneTitle = "Done"
    @Published var cancelTitle = "Cancel"
}

private struct PickerHUDView: View {
    @ObservedObject var state: PickerHUDState
    let onUndo: () -> Void
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.isMacroMode ? "record.circle" : "scope")
                .foregroundStyle(state.isMacroMode ? .red : .accentColor)

            if state.isMacroMode {
                Text("\(state.stepCount) · \(state.title)")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .lineLimit(1)
            } else {
                Text(state.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if state.isMacroMode {
                Button(state.undoTitle, action: onUndo)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(state.stepCount == 0)

                Button(state.doneTitle, action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Button(state.cancelTitle, action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThickMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Scrim Panel & Canvas

private final class PickerScrimPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class PickerCanvasView: NSView {
    private let screenFrame: CGRect
    private let primaryScreenMaxY: CGFloat
    private let isMacroMode: Bool

    private var localMousePoint: NSPoint?
    private var trackingArea: NSTrackingArea?

    var stepsProvider: (() -> [(Int, CGPoint, AutoClickerButton)])?
    var onPointClicked: ((CGPoint, AutoClickerButton) -> Void)?

    init(frame: NSRect, screenFrame: CGRect, primaryScreenMaxY: CGFloat, isMacroMode: Bool) {
        self.screenFrame = screenFrame
        self.primaryScreenMaxY = primaryScreenMaxY
        self.isMacroMode = isMacroMode
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        localMousePoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        localMousePoint = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        emitClick(event: event, button: .left)
    }

    override func rightMouseDown(with event: NSEvent) {
        if isMacroMode {
            emitClick(event: event, button: .right)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        if isMacroMode && event.buttonNumber == 2 {
            emitClick(event: event, button: .middle)
        }
    }

    private func emitClick(event: NSEvent, button: AutoClickerButton) {
        let appKitScreenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        let cgPoint = CGEvent(source: nil)?.location
            ?? AutoClickerCoordinates.cgPoint(fromAppKitPoint: appKitScreenPoint, primaryScreenMaxY: primaryScreenMaxY)
        onPointClicked?(cgPoint, button)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()

        if let steps = stepsProvider?() {
            for (number, cgPoint, button) in steps {
                let appKitPoint = AutoClickerCoordinates.appKitPoint(
                    fromCGPoint: cgPoint,
                    primaryScreenMaxY: primaryScreenMaxY
                )
                guard screenFrame.contains(appKitPoint) else { continue }
                let local = NSPoint(
                    x: appKitPoint.x - screenFrame.minX,
                    y: appKitPoint.y - screenFrame.minY
                )
                drawStepBadge(number: number, at: local, button: button)
            }
        }

        if let point = localMousePoint {
            drawCrosshair(at: point)
        }
    }

    private func drawCrosshair(at point: NSPoint) {
        NSColor.white.withAlphaComponent(0.45).setStroke()
        let hLine = NSBezierPath()
        hLine.move(to: NSPoint(x: 0, y: point.y))
        hLine.line(to: NSPoint(x: bounds.width, y: point.y))
        hLine.lineWidth = 1
        hLine.stroke()

        let vLine = NSBezierPath()
        vLine.move(to: NSPoint(x: point.x, y: 0))
        vLine.line(to: NSPoint(x: point.x, y: bounds.height))
        vLine.lineWidth = 1
        vLine.stroke()

        let appKitScreen = NSPoint(x: screenFrame.minX + point.x, y: screenFrame.minY + point.y)
        let cgPoint = AutoClickerCoordinates.cgPoint(fromAppKitPoint: appKitScreen, primaryScreenMaxY: primaryScreenMaxY)
        let label = "X: \(Int(cgPoint.x.rounded()))  Y: \(Int(cgPoint.y.rounded()))"

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = (label as NSString).size(withAttributes: attrs)
        let badgeRect = NSRect(
            x: min(point.x + 14, bounds.width - size.width - 18),
            y: max(point.y - 28, 8),
            width: size.width + 12,
            height: size.height + 6
        )
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 6, yRadius: 6).fill()
        (label as NSString).draw(
            at: NSPoint(x: badgeRect.minX + 6, y: badgeRect.minY + 3),
            withAttributes: attrs
        )
    }

    private func drawStepBadge(number: Int, at point: NSPoint, button: AutoClickerButton) {
        let radius: CGFloat = 13
        let circleRect = NSRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        let fillColor: NSColor = switch button {
        case .left: .systemBlue
        case .right: .systemOrange
        case .middle: .systemPurple
        }

        fillColor.withAlphaComponent(0.92).setFill()
        NSBezierPath(ovalIn: circleRect).fill()

        NSColor.white.setStroke()
        let border = NSBezierPath(ovalIn: circleRect)
        border.lineWidth = 2
        border.stroke()

        let text = "\(number)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: NSPoint(x: point.x - textSize.width / 2, y: point.y - textSize.height / 2),
            withAttributes: attrs
        )
    }
}
