// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

final class NotchSpacesService: ObservableObject {
    static let shared = NotchSpacesService()

    struct Snapshot: Equatable {
        var displayID: CGDirectDisplayID?
        var displayName = ""
        var spaces: [NotchSpace] = []
        var current: NotchSpace? {
            spaces.first { $0.current && ($0.displayID == nil || $0.displayID == displayID) }
        }
        func spaces(on display: CGDirectDisplayID) -> [NotchSpace] {
            spaces.filter { $0.displayID == nil || $0.displayID == display }
        }
    }

    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var switching = false
    @Published private(set) var shortcutUnavailable = false
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var travel: DispatchWorkItem?
    private var generation = UUID()
    private var running = false
    private var originalCursorLocation: CGPoint?
    private var warpedCursorLocation: CGPoint?

    private init() {}

    var hasCompactActivity: Bool {
        hasIdleContent && !UserDefaults.standard.bool(forKey: DefaultsKey.notchSpacesIdleEnabled)
            && UserDefaults.standard.bool(forKey: DefaultsKey.notchSpacesShowCurrent)
    }

    var hasIdleContent: Bool {
        running && NotchSpacesSupport.isEnabled() && snapshot.spaces.contains(where: \.current)
    }

    func currentTitle(language: AppLanguage) -> String {
        let strings = FeatureStrings.notchSpaces(language)
        return snapshot.current?.currentLabel(strings) ?? strings.title
    }

    func syncWithPreferences() {
        guard NotchSpacesSupport.isEnabled() else { stop(); return }
        if !running {
            running = true
            let workspace = NSWorkspace.shared.notificationCenter
            for (center, name) in [(workspace, NSWorkspace.activeSpaceDidChangeNotification),
                                   (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)] {
                let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.refresh()
                }
                observers.append((center, token))
            }
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        refresh()
    }

    func stop() {
        running = false
        timer?.invalidate(); timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
        cancelTravel()
        snapshot = Snapshot()
        shortcutUnavailable = false
    }

    func refresh() {
        guard running, NotchSpacesSupport.isEnabled(), let topology = SpaceWindowBridge.topology() else {
            if snapshot != Snapshot() { snapshot = Snapshot() }
            return
        }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let displayID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let display = topology.displays.first { $0.displayID == displayID }
            ?? (!NSScreen.screensHaveSeparateSpaces ? topology.displays.first : nil)
        guard display != nil else { snapshot = Snapshot(); return }
        let names = UserDefaults.standard.dictionary(forKey: DefaultsKey.notchSpacesNames) as? [String: String] ?? [:]
        let identifiers = SpaceWindowBridge.displayIDsByUUID()
        let allDisplays = UserDefaults.standard.bool(forKey: DefaultsKey.notchSpacesAllDisplays)
        var offset = 0
        var rows: [NotchSpace] = []
        for owner in topology.displays {
            defer { offset += owner.spaces.filter { !owner.fullscreenSpaces.contains($0) }.count }
            guard let ownerID = NSScreen.screensHaveSeparateSpaces ? owner.displayID : displayID else { continue }
            let ownerName = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == ownerID
            }?.localizedName ?? ""
            rows += NotchSpacesSupport.row(ids: owner.spaces, fullscreen: owner.fullscreenSpaces,
                                          current: owner.currentSpace, uuids: owner.spaceUUIDs,
                                          names: names, desktopOffset: offset,
                                          displayIdentifier: identifiers.first { $0.value == ownerID }?.key)
                .map { space in
                    var space = space
                    space.displayID = ownerID
                    space.displayName = ownerName
                    return space
                }
        }
        let frames = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, CGRect)? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
            else { return nil }
            return (id, screen.frame)
        })
        let ordered = NotchSpacesSupport.orderedByDisplayPosition(rows, frames: frames)
        let next = Snapshot(displayID: displayID, displayName: screen?.localizedName ?? "",
                            spaces: NotchSpacesSupport.visibleSpaces(ordered, on: displayID,
                                                                    allDisplays: allDisplays))
        if snapshot != next { snapshot = next }
    }

    func rename(_ space: NotchSpace, to name: String) {
        guard running, NotchSpacesSupport.isEnabled(),
              let live = snapshot.spaces.first(where: { $0.id == space.id }),
              let key = live.nameKey, key == space.nameKey else { return }
        var names = UserDefaults.standard.dictionary(forKey: DefaultsKey.notchSpacesNames) as? [String: String] ?? [:]
        names[key] = NotchSpacesSupport.normalizedName(name)
        UserDefaults.standard.set(names, forKey: DefaultsKey.notchSpacesNames)
        refresh()
    }

    func step(forward: Bool) {
        guard !switching else { return }
        refresh()
        guard let target = NotchSpacesSupport.adjacent(to: snapshot.current?.id,
                                                      in: snapshot.spaces, forward: forward) else { return }
        NotchService.shared.switchSpace(target)
    }

    func select(_ id: UInt64) {
        guard running, NotchSpacesSupport.isEnabled(), AXIsProcessTrusted() else { return }
        refresh()
        guard let selected = snapshot.spaces.first(where: { $0.id == id && !$0.current }),
              let displayID = selected.displayID ?? snapshot.displayID,
              let current = snapshot.spaces(on: displayID).first(where: \.current)?.id else { return }
        cancelTravel()
        SpaceHop.cancelPending()
        guard focusDisplay(displayID) else { return }
        shortcutUnavailable = false
        switching = true
        if let shortcut = SpaceWindowBridge.desktopShortcut(number: selected.desktopNumber) {
            SpaceWindowBridge.pressSpaceShortcut(shortcut)
            waitForArrival(from: current, to: id, displayID: displayID,
                           remaining: SpaceHopSupport.maximumArrowSteps, deadline: .now() + 1.2,
                           generation: generation, fallbackToArrows: true)
        } else {
            advance(to: id, displayID: displayID, remaining: SpaceHopSupport.maximumArrowSteps, generation: generation)
        }
    }

    private func focusDisplay(_ displayID: CGDirectDisplayID) -> Bool {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) else { return false }
        guard !NSMouseInRect(NSEvent.mouseLocation, screen.frame, false) else { return true }
        guard let original = CGEvent(source: nil)?.location else { return false }
        let bounds = CGDisplayBounds(displayID)
        let target = CGPoint(x: bounds.midX, y: bounds.midY)
        guard CGWarpMouseCursorPosition(target) == .success else { return false }
        originalCursorLocation = original
        warpedCursorLocation = target
        return true
    }

    private func restoreCursorIfNeeded() {
        defer { originalCursorLocation = nil; warpedCursorLocation = nil }
        guard let original = originalCursorLocation, let warped = warpedCursorLocation,
              let current = CGEvent(source: nil)?.location,
              abs(current.x - warped.x) < 2, abs(current.y - warped.y) < 2 else { return }
        CGWarpMouseCursorPosition(original)
    }

    private func cancelTravel() {
        restoreCursorIfNeeded()
        generation = UUID()
        travel?.cancel(); travel = nil
        switching = false
    }

    private func advance(to target: UInt64, displayID: CGDirectDisplayID, remaining: Int, generation: UUID) {
        guard generation == self.generation, running, NotchSpacesSupport.isEnabled(), AXIsProcessTrusted() else {
            cancelTravel(); return
        }
        refresh()
        guard snapshot.displayID == displayID,
              let current = snapshot.spaces(on: displayID).first(where: \.current)?.id,
              let steps = SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [snapshot.spaces(on: displayID).map(\.id)],
                                                    visibleSpaces: [current], target: target) else {
            cancelTravel(); return
        }
        guard steps != 0, remaining > 0 else { cancelTravel(); return }
        guard let shortcut = SpaceWindowBridge.spaceShortcut(steps > 0 ? .right : .left) else {
            shortcutUnavailable = true
            cancelTravel(); return
        }
        SpaceWindowBridge.pressSpaceShortcut(shortcut)
        waitForArrival(from: current, to: target, displayID: displayID, remaining: remaining - 1,
                       deadline: .now() + 1.2, generation: generation)
    }

    private func waitForArrival(from previous: UInt64, to target: UInt64, displayID: CGDirectDisplayID,
                                remaining: Int, deadline: DispatchTime, generation: UUID, fallbackToArrows: Bool = false) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == generation else { return }
            guard self.running, NotchSpacesSupport.isEnabled(), AXIsProcessTrusted() else { self.cancelTravel(); return }
            self.refresh()
            guard self.snapshot.displayID == displayID,
                  self.snapshot.spaces.contains(where: { $0.id == target }),
                  let current = self.snapshot.spaces(on: displayID).first(where: \.current)?.id else { self.cancelTravel(); return }
            if current == target { self.cancelTravel() }
            else if current != previous {
                self.advance(to: target, displayID: displayID, remaining: remaining, generation: generation)
            } else if .now() < deadline {
                self.waitForArrival(from: previous, to: target, displayID: displayID, remaining: remaining,
                                    deadline: deadline, generation: generation, fallbackToArrows: fallbackToArrows)
            } else if fallbackToArrows {
                self.advance(to: target, displayID: displayID, remaining: remaining, generation: generation)
            } else {
                self.shortcutUnavailable = true
                self.cancelTravel()
            }
        }
        travel = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }
}
