// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

final class SwitcherWindowTitles {
    private var observers: [pid_t: AXObserver] = [:]
    private var elements: [pid_t: [CGWindowID: AXUIElement]] = [:]
    private var pending: [pid_t: UUID] = [:]
    private var observed: [pid_t: Set<CGWindowID>] = [:]
    private let queue = DispatchQueue(label: "com.vorssaint.switcher.titles", qos: .utility)
    private let lifecycleLock = NSLock()
    private var generation: UUID?
    var onChange: ((pid_t) -> Void)?

    private static let callback: AXObserverCallback = { observer, element, _, context in
        guard let context else { return }
        let watcher = Unmanaged<SwitcherWindowTitles>.fromOpaque(context).takeUnretainedValue()
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, watcher.observers[pid] === observer else { return }
        watcher.onChange?(pid)
    }

    func update(_ current: [CGWindowID: AXUIElement]) {
        if generation == nil { lifecycleLock.withLock { generation = UUID() } }
        var grouped: [pid_t: [CGWindowID: AXUIElement]] = [:]
        for (id, element) in current {
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success else { continue }
            grouped[pid, default: [:]][id] = element
        }
        for pid in Set(elements.keys).subtracting(grouped.keys) { remove(pid: pid) }
        for (pid, windows) in grouped {
            if let previous = elements[pid], previous.count == windows.count,
               windows.allSatisfy({ id, element in previous[id].map { CFEqual($0, element) } == true }) {
                continue
            }
            elements[pid] = windows
            let request = UUID()
            let generation = generation
            pending[pid] = request
            queue.async { [self] in
                func active() -> Bool { lifecycleLock.withLock { self.generation == generation } }
                guard active() else { return }
                func register(_ operation: () -> AXError) -> AXError {
                    let result = operation()
                    guard result == .cannotComplete, active() else { return result }
                    return operation()
                }
                var created: AXObserver?
                let result = register { AXObserverCreate(pid, Self.callback, &created) }
                let observer = result == .success ? created : nil
                var accepted = Set<CGWindowID>()
                if let observer {
                    let context = Unmanaged.passUnretained(self).toOpaque()
                    for (id, element) in windows {
                        guard active() else { return }
                        AXUIElementSetMessagingTimeout(element, 0.1)
                        let added = register {
                            AXObserverAddNotification(observer, element, kAXTitleChangedNotification as CFString, context)
                        }
                        if added == .success || added == .notificationAlreadyRegistered { accepted.insert(id) }
                    }
                }
                DispatchQueue.main.async { [self, accepted] in
                    guard self.generation == generation, pending[pid] == request else { return }
                    detach(pid: pid)
                    pending.removeValue(forKey: pid)
                    let previouslyObserved = observed.updateValue(accepted, forKey: pid) ?? []
                    if let observer, !accepted.isEmpty {
                        observers[pid] = observer
                        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                        // A newly covered window may have been renamed since the snapshot.
                        // Compare window IDs so fresh AX handles from that reread cannot trigger another.
                        if !accepted.isSubset(of: previouslyObserved) { onChange?(pid) }
                    }
                }
            }
        }
    }

    /// WindowServer can list a window before AX supplies an element for it.
    /// Reread its owner on demand, just as for a refused or pending subscription.
    func refreshUnobserved(in items: [SwitcherItem], accessibilityGranted: Bool) {
        guard generation != nil, accessibilityGranted else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let owners = Set(items.compactMap { item -> pid_t? in
            let owner = item.windowOwnerPID
            guard let id = item.windowID, item.pid != ownPID, owner != ownPID,
                  pending[owner] != nil || observed[owner]?.contains(id) != true else { return nil }
            return owner
        })
        for pid in owners { onChange?(pid) }
    }

    func stop() {
        lifecycleLock.withLock { generation = nil }
        for pid in Array(elements.keys) { remove(pid: pid) }
    }

    private func remove(pid: pid_t) {
        pending.removeValue(forKey: pid)
        observed.removeValue(forKey: pid)
        elements.removeValue(forKey: pid)
        detach(pid: pid)
    }

    private func detach(pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }
}
