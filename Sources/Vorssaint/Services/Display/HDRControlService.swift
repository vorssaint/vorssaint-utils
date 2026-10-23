// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Turns HDR on and off for displays that can run it in their current mode,
/// the same switch as "High Dynamic Range" in System Settings > Displays.
///
/// macOS has no public call for it; the SkyLight symbols resolve at runtime
/// and the feature reports itself unsupported when one is missing. macOS
/// remembers the choice per display on its own, so nothing is stored here.
///
/// Nothing runs while the feature is off: the screen observer exists only
/// while the switches are enabled, and the display list is read on demand.
final class HDRControlService: ObservableObject {
    static let shared = HDRControlService()

    static var isSupported: Bool { SkyLightDisplayBridge.hdrAvailable }

    @Published private(set) var displays: [HDRDisplay] = []
    /// Displays with a switch in flight; their rows wait for the result.
    @Published private(set) var workingIDs: Set<UInt32> = []
    /// Displays whose last switch did not take, until the next attempt.
    @Published private(set) var failedIDs: Set<UInt32> = []

    private var screenObserver: NSObjectProtocol?
    private let workQueue = DispatchQueue(label: "com.vorssaint.utils.hdr-control", qos: .userInitiated)

    private init() {}

    var isActive: Bool {
        Self.isSupported && AppFeature.hdrControl.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.hdrControlEnabled)
    }

    func syncWithPreferences() {
        if isActive { start() } else { stop() }
    }

    private func start() {
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
        refresh()
    }

    private func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        displays = []
        workingIDs = []
        failedIDs = []
    }

    /// Rereads which online displays can run HDR and whether each one is.
    /// Cheap enough to call whenever a surface showing the switches appears.
    func refresh() {
        guard isActive else { return }
        let fallback = FeatureStrings.hdrControl(L10n.shared.language).unnamedDisplay
        let names = Self.localizedScreenNames()
        let found = Self.onlineDisplayIDs().compactMap { id -> HDRDisplay? in
            guard SkyLightDisplayBridge.supportsHDR(id) == true else { return nil }
            return HDRDisplay(id: id,
                              name: HDRControlSupport.displayName(names[id], fallback: fallback),
                              isEnabled: SkyLightDisplayBridge.isHDREnabled(id) == true)
        }
        let ordered = HDRControlSupport.ordered(found, mainID: CGMainDisplayID())
        if ordered != displays { displays = ordered }
    }

    func setHDR(_ enabled: Bool, for id: UInt32) {
        guard isActive, !workingIDs.contains(id) else { return }
        workingIDs.insert(id)
        failedIDs.remove(id)
        workQueue.async { [weak self] in
            let settled = Self.switchAndWait(id, to: enabled)
            DispatchQueue.main.async {
                guard let self else { return }
                self.workingIDs.remove(id)
                if !settled { self.failedIDs.insert(id) }
                self.refresh()
            }
        }
    }

    /// The Quick Toggles tile: one switch for every HDR display at once.
    func toggleAll() {
        refresh()
        let target = HDRControlSupport.quickToggleTarget(displays)
        for display in displays where display.isEnabled != target {
            setHDR(target, for: display.id)
        }
    }

    // MARK: - System

    /// Asks for the switch, then waits for the display to report it, because
    /// the setter itself returns nothing that can be trusted.
    private static func switchAndWait(_ id: UInt32, to enabled: Bool) -> Bool {
        guard SkyLightDisplayBridge.setHDREnabled(id, enabled) else { return false }
        let deadline = Date().addingTimeInterval(HDRControlSupport.settleTimeout)
        while Date() < deadline {
            if HDRControlSupport.didSettle(requested: enabled,
                                           reported: SkyLightDisplayBridge.isHDREnabled(id)) {
                return true
            }
            Thread.sleep(forTimeInterval: HDRControlSupport.settlePollInterval)
        }
        return HDRControlSupport.didSettle(requested: enabled, reported: SkyLightDisplayBridge.isHDREnabled(id))
    }

    private static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    private static func localizedScreenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                             as? NSNumber)?.uint32Value else { continue }
            names[id] = screen.localizedName
        }
        return names
    }
}

// MARK: - Private symbol bridge

/// SkyLight's display HDR calls. They are private and undocumented, so each
/// resolves once through dlsym and a missing one turns the feature off rather
/// than the app. Prototypes as confirmed on macOS 27 (arm64): the display ID
/// in the first argument and the Bool in the second. The setter's return
/// register is left undefined on its early exits, so it is declared Void and
/// callers read the state back.
enum SkyLightDisplayBridge {
    typealias DisplayQueryFn = @convention(c) (UInt32) -> Bool
    typealias DisplaySetFn = @convention(c) (UInt32, Bool) -> Void

    private static let supportsHDRMode: DisplayQueryFn? = symbol("SLSDisplaySupportsHDRMode")
    private static let isHDRModeEnabled: DisplayQueryFn? = symbol("SLSDisplayIsHDRModeEnabled")
    private static let setHDRModeEnabled: DisplaySetFn? = symbol("SLSDisplaySetHDRModeEnabled")

    static var hdrAvailable: Bool {
        supportsHDRMode != nil && isHDRModeEnabled != nil && setHDRModeEnabled != nil
    }

    static func supportsHDR(_ id: UInt32) -> Bool? { supportsHDRMode?(id) }
    static func isHDREnabled(_ id: UInt32) -> Bool? { isHDRModeEnabled?(id) }

    @discardableResult
    static func setHDREnabled(_ id: UInt32, _ enabled: Bool) -> Bool {
        guard let setHDRModeEnabled else { return false }
        setHDRModeEnabled(id, enabled)
        return true
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle = SkyLight.handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

/// The one SkyLight handle every private WindowServer call resolves against.
enum SkyLight {
    static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
}
