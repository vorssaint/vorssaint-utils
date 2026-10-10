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
    @MainActor private var retiredReceivers: [ContinuityCameraReceiver] = []
    @MainActor private var targetApp: NSRunningApplication?

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
            if let currentApp, currentApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                self?.targetApp = currentApp
            }
            self?.performCapture()
        }
    }

    @MainActor
    private func performCapture() {
        dismiss(restoreTarget: false)

        NSApp.activate(ignoringOtherApps: true)

        let mouse = NSEvent.mouseLocation
        let panel = ContinuityPanel(
            contentRect: NSRect(x: mouse.x - 1, y: mouse.y - 1, width: 2, height: 2),
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
            self?.handleCapturedImage(image)
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
                NSMenu.popUpContextMenu(menu, with: event, for: receiver)

                // Do not order out immediately; Continuity Camera delivers photo asynchronously after menu closes.
                panel.ignoresMouseEvents = true

                // Timeout fallback after 60s if user cancels or leaves
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self, weak panel] in
                    MainActor.assumeIsolated {
                        if let self, let panel, self.panel === panel {
                            self.dismiss(restoreTarget: true)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func handleCapturedImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        let message = FeatureStrings.cameraPreview(L10n.shared.language).continuityCaptureHUD
        QuickToolHUD.show(icon: "iphone.and.arrow.forward", message: message)

        let target = self.targetApp
        self.targetApp = nil
        dismiss(restoreTarget: false)

        if let target, target.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            // Restore origin application focus so cursor reappears in input field
            target.activate()

            let autoPaste = UserDefaults.standard.bool(forKey: DefaultsKey.continuityCaptureAutoPasteEnabled)
            if autoPaste {
                // Post Cmd+V to automatically paste the captured photo at current cursor
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    let src = CGEventSource(stateID: .hidSystemState)
                    let vKey: CGKeyCode = 0x09 // kVK_ANSI_V
                    if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
                       let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) {
                        keyDown.flags = .maskCommand
                        keyUp.flags = .maskCommand
                        keyDown.postToPid(target.processIdentifier)
                        keyUp.postToPid(target.processIdentifier)
                        keyDown.post(tap: .cghidEventTap)
                        keyUp.post(tap: .cghidEventTap)
                    }
                }
            }
        }
    }

    @MainActor
    private func dismiss(restoreTarget: Bool = true) {
        let target = self.targetApp
        self.targetApp = nil
        if let active = activeReceiver {
            retiredReceivers.append(active)
            activeReceiver = nil
        }
        panel?.orderOut(nil)
        panel?.close()
        panel = nil

        if restoreTarget, let target, target.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            target.activate()
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
