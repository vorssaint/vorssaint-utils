// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox

/// Invokes macOS Continuity Camera (from iPhone or iPad) on demand and puts the
/// captured photo directly onto the system clipboard.
final class ContinuityCaptureService: ObservableObject {
    static let shared = ContinuityCaptureService()

    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 62)
    @MainActor private var panel: NSPanel?
    @MainActor private var activeReceiver: ContinuityCameraReceiver?
    @MainActor private var targetApp: NSRunningApplication?
    @MainActor private var captureTimeoutTask: Task<Void, Never>?

    private init() {
        hotkey.onPress = { [weak self] in self?.capture() }
    }

    func syncWithPreferences() {
        let available = AppFeature.cameraPreview.isAvailable
        let enabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.continuityCaptureShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.continuityCaptureShortcut,
                                            fallback: .continuityCaptureDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.continuityCaptureShortcut)
    }

    func suspend() {
        hotkey.unregister()
        Task { @MainActor [weak self] in
            self?.dismiss()
        }
    }

    func capture() {
        let currentApp = NSWorkspace.shared.frontmostApplication
        Task { @MainActor [weak self] in
            guard let self else { return }
            let previousTarget = self.targetApp
            self.dismiss(restoreTarget: false)
            if let currentApp, currentApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                self.targetApp = currentApp
            } else {
                self.targetApp = previousTarget
            }
            self.performCapture()
        }
    }

    @MainActor
    private func performCapture() {
        NSApp.activate(ignoringOtherApps: true)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: mouse.x, y: mouse.y, width: 100, height: 100)
        let clampedX = min(max(mouse.x - 1, screenFrame.minX), screenFrame.maxX - 2)
        let clampedY = min(max(mouse.y - 1, screenFrame.minY), screenFrame.maxY - 2)

        let panel = ContinuityPanel(
            contentRect: NSRect(x: clampedX, y: clampedY, width: 2, height: 2),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = "Continuity Camera"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let receiver = ContinuityCameraReceiver(frame: NSRect(x: 0, y: 0, width: 2, height: 2))
        receiver.onImageReceived = { [weak self] image in
            Task { @MainActor [weak self] in
                self?.handleCapturedImage(image)
            }
        }

        panel.contentView = receiver
        self.panel = panel
        self.activeReceiver = receiver

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(receiver)

        DispatchQueue.main.async { [weak self, weak receiver, weak panel] in
            MainActor.assumeIsolated {
                guard let self, let receiver, let panel, panel === self.panel else { return }
                guard let event = NSEvent.mouseEvent(
                    with: .rightMouseDown,
                    location: NSPoint(x: 1, y: 1),
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: panel.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 0
                ) else {
                    self.dismiss(restoreTarget: true)
                    return
                }

                let menuTitle = FeatureStrings.cameraPreview(L10n.shared.language).continuityCaptureButton
                let menu = NSMenu(title: menuTitle)

                var actionDispatched = false
                let observer = NotificationCenter.default.addObserver(
                    forName: NSMenu.didSendActionNotification,
                    object: nil,
                    queue: nil
                ) { _ in
                    actionDispatched = true
                }

                NSMenu.popUpContextMenu(menu, with: event, for: receiver)

                NotificationCenter.default.removeObserver(observer)

                // If user cancelled the menu or no device action was invoked, dismiss immediately
                guard actionDispatched else {
                    self.dismiss(restoreTarget: true)
                    return
                }

                // Action was dispatched; ignore mouse events while awaiting photo delivery from device
                panel.ignoresMouseEvents = true

                // Timeout fallback after 90s if photo capture is abandoned on iOS device
                self.captureTimeoutTask?.cancel()
                self.captureTimeoutTask = Task { @MainActor [weak self, weak panel] in
                    try? await Task.sleep(nanoseconds: 90 * 1_000_000_000)
                    if let self, let panel, self.panel === panel {
                        self.dismiss(restoreTarget: true)
                    }
                }
            }
        }
    }

    @MainActor
    private func handleCapturedImage(_ image: NSImage) {
        captureTimeoutTask?.cancel()
        captureTimeoutTask = nil

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        pasteboard.declareVorssaintSource()

        let message = FeatureStrings.cameraPreview(L10n.shared.language).continuityCaptureHUD
        QuickToolHUD.show(icon: "iphone.and.arrow.forward", message: message)

        let target = self.targetApp
        self.targetApp = nil
        dismiss(restoreTarget: false)

        if let target, !target.isTerminated,
           target.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            // Restore origin application focus so cursor reappears in input field
            restoreFocus(to: target)

            let autoPaste = UserDefaults.standard.bool(forKey: DefaultsKey.continuityCaptureAutoPasteEnabled)
            if autoPaste {
                if AXIsProcessTrusted() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        guard !target.isTerminated else { return }
                        TransientPaste.shared.pasteCurrentContents()
                    }
                } else {
                    Permissions.shared.requestAccessibility()
                }
            }
        }
    }

    @MainActor
    private func dismiss(restoreTarget: Bool = true) {
        captureTimeoutTask?.cancel()
        captureTimeoutTask = nil

        let target = self.targetApp
        self.targetApp = nil
        activeReceiver = nil

        panel?.orderOut(nil)
        panel?.close()
        panel = nil

        if restoreTarget, let target {
            restoreFocus(to: target)
        }
    }

    @MainActor
    private func restoreFocus(to target: NSRunningApplication) {
        guard !target.isTerminated,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        ActivationHandoff.yield(to: target)
        if !target.activate(from: NSRunningApplication.current, options: []) {
            target.activate(options: [])
        }
    }
}

@MainActor
private final class ContinuityPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ContinuityCameraReceiver: NSImageView, @preconcurrency NSServicesMenuRequestor {
    var onImageReceived: ((NSImage) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.isEditable = true
        self.isEnabled = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.isEditable = true
        self.isEnabled = true
    }

    override var acceptsFirstResponder: Bool { true }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?,
                                returnType: NSPasteboard.PasteboardType?) -> Any? {
        if let type = returnType {
            if NSImage.imageTypes.contains(type.rawValue) || type == .pdf || type.rawValue == "com.adobe.pdf" {
                return self
            }
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    @objc func readSelection(from pasteboard: NSPasteboard) -> Bool {
        if let image = NSImage(pasteboard: pasteboard) {
            onImageReceived?(image)
            return true
        }
        return false
    }
}
