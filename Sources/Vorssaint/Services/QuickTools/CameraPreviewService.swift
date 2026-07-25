// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import Carbon.HIToolbox
import SwiftUI

/// A quick mirror before video calls: a small floating panel with the live
/// camera image, summoned from the panel, the quick panel or a global
/// shortcut. The capture session exists only while the panel is on screen,
/// so the camera light and every resource die the moment it closes.
final class CameraPreviewService: ObservableObject {
    static let shared = CameraPreviewService()

    enum PreviewState {
        case idle, waitingPermission, starting, running, denied, noCamera
    }

    @Published private(set) var shortcutRegistrationFailed = false
    @Published private(set) var state: PreviewState = .idle
    @Published private(set) var devices: [AVCaptureDevice] = []
    @Published private(set) var selectedDeviceID: String?

    /// The session is created on show and destroyed on hide. The view builds
    /// its preview layer from it while the panel is up.
    private(set) var session: AVCaptureSession?

    private let hotkey = QuickToolHotkey(id: 16)
    /// startRunning blocks for a moment, so every session mutation happens
    /// here and only state lands back on the main thread.
    private let sessionQueue = DispatchQueue(label: "com.vorssaint.utils.camera-preview")
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var deviceObservers: [NSObjectProtocol] = []
    /// When the permission dialog resolves, the app that was frontmost
    /// before it reactivates a beat later; that activation must not count
    /// as the user clicking away from a mirror they just allowed.
    private var permissionResolvedAt: Date?

    private init() {
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    func syncWithPreferences() {
        let available = AppFeature.cameraPreview.isAvailable
        let enabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.cameraPreviewShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.cameraPreviewShortcut,
                                            fallback: .cameraPreviewDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut)
        if !available {
            hide()
        }
    }

    func suspend() {
        hotkey.unregister()
        hide()
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard AppFeature.cameraPreview.isAvailable, !isVisible else { return }
        let panel = ensurePanel()
        installMonitors(for: panel)
        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13
            panel.animator().alphaValue = 1
        }
        beginCapture()
    }

    func hide() {
        guard panel != nil else { return }
        removeMonitors()
        removeDeviceObservers()
        stopSession()
        panel?.orderOut(nil)
        state = .idle
        devices = []
        selectedDeviceID = nil
    }

    // MARK: - Capture

    private func beginCapture() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            state = .waitingPermission
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    Permissions.shared.refresh()
                    guard let self, self.isVisible else { return }
                    self.permissionResolvedAt = Date()
                    // The system dialog appears mid fade-in and was observed
                    // leaving the panel stuck transparent; the resolution is
                    // the moment the mirror must be fully there.
                    self.panel?.alphaValue = 1
                    if granted {
                        self.startSession()
                    } else {
                        self.state = .denied
                    }
                }
            }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    private func startSession() {
        // A session may still be alive when a queued permission callback or
        // a device replug lands here; two running sessions would fight over
        // the camera, so the old one always stops first.
        stopSession()
        state = .starting
        installDeviceObservers()
        refreshDevices()
        guard let device = preferredDevice() else {
            state = .noCamera
            return
        }
        selectedDeviceID = device.uniqueID
        let session = AVCaptureSession()
        self.session = session
        sessionQueue.async { [weak self] in
            session.beginConfiguration()
            if let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            let hasInput = !session.inputs.isEmpty
            if hasInput {
                session.startRunning()
            }
            DispatchQueue.main.async {
                guard let self, self.isVisible, self.session === session else { return }
                self.state = hasInput ? .running : .noCamera
            }
        }
    }

    private func stopSession() {
        guard let session else { return }
        self.session = nil
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
            for input in session.inputs {
                session.removeInput(input)
            }
        }
    }

    func selectCamera(_ device: AVCaptureDevice) {
        activateCamera(device, rememberChoice: true)
    }

    private func activateCamera(_ device: AVCaptureDevice, rememberChoice: Bool) {
        guard device.uniqueID != selectedDeviceID else { return }
        selectedDeviceID = device.uniqueID
        if rememberChoice {
            // The system remembers this choice per app, so the next preview
            // opens on the same camera without a key of our own. Only an
            // explicit pick may land here: a fallback after a disconnect
            // would overwrite the remembered camera with a stand-in.
            AVCaptureDevice.userPreferredCamera = device
        }
        guard let session else { return }
        sessionQueue.async { [weak self] in
            session.beginConfiguration()
            for input in session.inputs {
                session.removeInput(input)
            }
            if let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            let hasInput = !session.inputs.isEmpty
            DispatchQueue.main.async {
                guard let self, self.isVisible, self.session === session else { return }
                self.state = hasInput ? .running : .noCamera
            }
        }
    }

    private func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        devices = discovery.devices
    }

    private func preferredDevice() -> AVCaptureDevice? {
        if let preferred = AVCaptureDevice.userPreferredCamera,
           devices.contains(where: { $0.uniqueID == preferred.uniqueID }) {
            return preferred
        }
        return devices.first
    }

    /// Cameras coming and going (a Continuity iPhone arriving, a USB camera
    /// unplugged) only matter while the panel is up, so the observers live
    /// exactly as long as it does.
    private func installDeviceObservers() {
        guard deviceObservers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification,
                     AVCaptureDevice.wasDisconnectedNotification] {
            deviceObservers.append(center.addObserver(forName: name, object: nil,
                                                      queue: .main) { [weak self] _ in
                self?.handleDevicesChanged()
            })
        }
    }

    private func removeDeviceObservers() {
        for observer in deviceObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        deviceObservers = []
    }

    private func handleDevicesChanged() {
        guard isVisible else { return }
        refreshDevices()
        let selectedStillHere = devices.contains { $0.uniqueID == selectedDeviceID }
        switch state {
        case .running, .starting:
            if !selectedStillHere {
                if let fallback = devices.first {
                    activateCamera(fallback, rememberChoice: false)
                } else {
                    stopSession()
                    state = .noCamera
                }
            }
        case .noCamera:
            if !devices.isEmpty {
                startSession()
            }
        case .idle, .waitingPermission, .denied:
            break
        }
    }

    // MARK: - Panel

    /// Borderless panels refuse key status by default; the preview needs it
    /// so Esc closes it without a click.
    private final class KeyablePreviewPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyablePreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
                                        styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered,
                                        defer: false)
        panel.title = "Vorssaint"
        panel.isReleasedWhenClosed = false
        // A mirror is something the user drags next to the meeting window.
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: CameraPreviewView())
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    /// Near the top center of the screen with the mouse, where the camera
    /// sits, so the eyes stay close to the lens while checking the image.
    private func position(_ panel: NSPanel) {
        panel.contentViewController?.view.layoutSubtreeIfNeeded()
        let size = panel.contentViewController?.view.fittingSize ?? NSSize(width: 320, height: 240)
        let screen = NSScreen.pointerVisibleFrame
        let x = screen.midX - size.width / 2
        let y = screen.maxY - size.height - 48
        panel.setFrame(NSRect(x: max(screen.minX + 16, min(x, screen.maxX - size.width - 16)),
                              y: max(screen.minY + 16, y),
                              width: size.width,
                              height: size.height),
                       display: true,
                       animate: false)
    }

    // MARK: - Monitors

    /// While the system permission prompt may be up, an outside click or the
    /// prompt's own activation must not tear the panel down mid-question.
    private var dismissesOnOutsideInteraction: Bool {
        state != .waitingPermission
    }

    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.hide()
                return nil
            }
            return event
        }
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideInteraction else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) {
                self.hide()
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible, self.dismissesOnOutsideInteraction else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel) {
                self.hide()
            }
        }
        // Joining the meeting (or just moving on) activates another app;
        // the mirror has done its job and leaves on its own.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  self.dismissesOnOutsideInteraction,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            if let resolved = self.permissionResolvedAt,
               Date().timeIntervalSince(resolved) < 1.0 { return }
            self.hide()
        }
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }
}
