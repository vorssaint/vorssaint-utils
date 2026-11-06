// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreGraphics
import Foundation
import os

/// Reads and switches display presets (P3-1600 nits, P3-600 nits, the
/// reference modes) through MonitorPanel, the private framework behind the
/// Preset menu in System Settings > Displays. It is loaded with dlopen and
/// called by selector, so a macOS that renames it hides the menu instead of
/// breaking the app.
///
/// Every framework call runs on one serial queue: a switch reconfigures the
/// panel and takes a quarter second, which must not stall a slider drag.
/// Reading and switching there passes the Main Thread Checker on macOS 26.
final class DisplayPresetService: ObservableObject {
    static let shared = DisplayPresetService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display-presets")

    /// Displays that offer a choice of presets, keyed by display id. Empty
    /// while the display controls or the preset menu are off.
    @Published private(set) var lists: [CGDirectDisplayID: DisplayPresetList] = [:]
    /// The preset each display is switching to, shown as chosen until the
    /// panel has switched so the menu does not snap back meanwhile.
    @Published private(set) var pendingSelections: [CGDirectDisplayID: Int] = [:]

    private let queue = DispatchQueue(label: "vorssaint.display-presets", qos: .userInitiated)
    /// Set while a read waits on the queue: requests made before it starts
    /// share it, requests made after it starts queue the next one.
    private let readLock = NSLock()
    private var readQueued = false
    private static let frameworkLoaded: Bool = {
        dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_LAZY) != nil
    }()

    private var displayChanges: AnyCancellable?

    /// A display plugged in or out changes which menus exist, so the lists
    /// follow the brightness rows rather than waiting for the next appear.
    private init() {
        displayChanges = BrightnessService.shared.$displays
            .map { $0.map(\.id) }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.refresh() }
    }

    private static var wanted: Bool {
        AppFeature.brightness.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.brightnessControlEnabled)
            && UserDefaults.standard.bool(forKey: DefaultsKey.displayPresetsEnabled)
    }

    /// Re-reads the presets of every display. Called when the display
    /// controls appear, so a preset picked in System Settings shows here.
    /// With the menu off, the framework is never loaded.
    func refresh() {
        guard Self.wanted else {
            if !lists.isEmpty { lists = [:] }
            return
        }
        readLock.lock()
        guard !readQueued else {
            readLock.unlock()
            return
        }
        readQueued = true
        readLock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            self.readLock.lock()
            self.readQueued = false
            self.readLock.unlock()
            let lists = Self.readLists()
            DispatchQueue.main.async {
                guard Self.wanted, self.lists != lists else { return }
                self.lists = lists
            }
        }
    }

    func isPending(_ id: CGDirectDisplayID) -> Bool { pendingSelections[id] != nil }

    func select(_ index: Int, for id: CGDirectDisplayID) {
        guard lists[id]?.activeIndex != index, pendingSelections[id] == nil else { return }
        pendingSelections[id] = index
        queue.async { [weak self] in
            let switched = Self.activate(index, on: id)
            let lists = Self.readLists()
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingSelections[id] = nil
                self.lists = lists
                // Reference presets fix the panel's brightness, so the
                // sliders read the display again.
                if switched { BrightnessService.shared.refresh(force: true) }
            }
        }
    }

    // MARK: - MonitorPanel

    /// A fresh manager per call: it snapshots the displays when created, and
    /// a kept one would miss a display plugged in since. It stays alive for
    /// the whole call, since its displays reach back to it while switching.
    private static func withDisplays<Result>(_ body: ([NSObject]) -> Result) -> Result {
        guard frameworkLoaded,
              let managerClass = NSClassFromString("MPDisplayMgr") as? NSObject.Type,
              managerClass.instancesRespond(to: NSSelectorFromString("displays")) else { return body([]) }
        let manager = managerClass.init()
        return withExtendedLifetime(manager) {
            body(manager.value(forKey: "displays") as? [NSObject] ?? [])
        }
    }

    private static func responds(_ object: NSObject, _ selectors: String...) -> Bool {
        selectors.allSatisfy { object.responds(to: NSSelectorFromString($0)) }
    }

    private static func displayID(_ display: NSObject) -> CGDirectDisplayID? {
        guard responds(display, "displayID") else { return nil }
        return (display.value(forKey: "displayID") as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    private static func presetObjects(_ display: NSObject) -> [NSObject] {
        guard responds(display, "hasPresets", "presets", "activePreset"),
              display.value(forKey: "hasPresets") as? Bool == true else { return [] }
        return (display.value(forKey: "presets") as? [NSObject] ?? []).filter {
            responds($0, "presetIndex", "presetName", "presetGroup", "isValid")
        }
    }

    private static func readLists() -> [CGDirectDisplayID: DisplayPresetList] {
        withDisplays(readLists)
    }

    private static func readLists(_ displays: [NSObject]) -> [CGDirectDisplayID: DisplayPresetList] {
        var lists: [CGDirectDisplayID: DisplayPresetList] = [:]
        for display in displays {
            guard let id = displayID(display) else { continue }
            let presets = presetObjects(display)
            guard !presets.isEmpty else { continue }
            let candidates = presets.map { preset in
                DisplayPresetSupport.Candidate(
                    index: (preset.value(forKey: "presetIndex") as? NSNumber)?.intValue ?? -1,
                    name: preset.value(forKey: "presetName") as? String,
                    group: (preset.value(forKey: "presetGroup") as? NSNumber)?.intValue ?? 0,
                    valid: preset.value(forKey: "isValid") as? Bool == true)
            }
            let active = (display.value(forKey: "activePreset") as? NSObject)
                .flatMap { $0.value(forKey: "presetIndex") as? NSNumber }?.intValue
            if let list = DisplayPresetSupport.list(candidates, activeIndex: active) {
                lists[id] = list
            }
        }
        return lists
    }

    private static func activate(_ index: Int, on id: CGDirectDisplayID) -> Bool {
        let selector = NSSelectorFromString("setActivePreset:")
        return withDisplays { displays in
            guard let display = displays.first(where: { displayID($0) == id }),
                  display.responds(to: selector),
                  let preset = presetObjects(display).first(where: {
                      ($0.value(forKey: "presetIndex") as? NSNumber)?.intValue == index
                          && $0.value(forKey: "isValid") as? Bool == true
                  }) else {
                log.error("preset \(index) not available on display \(id)")
                return false
            }
            _ = display.perform(selector, with: preset)
            log.info("display \(id) switched to preset \(index)")
            return true
        }
    }
}
