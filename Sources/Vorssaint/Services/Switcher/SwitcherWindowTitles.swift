// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

final class SwitcherWindowTitles {
    private var observers: [pid_t: AXObserver] = [:]
    private var elements: [pid_t: [CGWindowID: AXUIElement]] = [:]
    private var pending: [pid_t: UUID] = [:]
    private let queue = DispatchQueue(label: "com.vorssaint.switcher.titles", qos: .utility)
    private let lifecycleLock = NSLock()
    private var generation = UUID()
    var onChange: ((pid_t) -> Void)?

    private static let callback: AXObserverCallback = { _, element, _, context in
        guard let context else { return }
        let watcher = Unmanaged<SwitcherWindowTitles>.fromOpaque(context).takeUnretainedValue()
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        watcher.onChange?(pid)
    }

    func update(_ current: [CGWindowID: AXUIElement]) {
        var grouped: [pid_t: [CGWindowID: AXUIElement]] = [:]
        for (id, element) in current {
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            grouped[pid, default: [:]][id] = element
        }
        for pid in Set(elements.keys).subtracting(grouped.keys) { remove(pid: pid) }
        for (pid, windows) in grouped {
            if let previous = elements[pid], observers[pid] != nil || pending[pid] != nil,
               previous.count == windows.count,
               windows.allSatisfy({ id, element in previous[id].map { CFEqual($0, element) } == true }) {
                continue
            }
            elements[pid] = windows
            let request = UUID()
            let generation = generation
            pending[pid] = request
            queue.async { [self] in
                guard lifecycleLock.withLock({ self.generation == generation }) else { return }
                var created: AXObserver?
                let result = AXObserverCreate(pid, Self.callback, &created)
                if result == .success, let created {
                    let context = Unmanaged.passUnretained(self).toOpaque()
                    for element in windows.values {
                        AXUIElementSetMessagingTimeout(element, 0.1)
                        _ = AXObserverAddNotification(created, element, kAXTitleChangedNotification as CFString, context)
                    }
                }
                let observer = created
                DispatchQueue.main.async { [self] in
                    guard self.generation == generation, pending[pid] == request else { return }
                    detach(pid: pid)
                    pending.removeValue(forKey: pid)
                    if let observer {
                        observers[pid] = observer
                        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                    }
                }
            }
        }
    }

    func stop() {
        lifecycleLock.withLock { generation = UUID() }
        for pid in Array(elements.keys) { remove(pid: pid) }
    }

    private func remove(pid: pid_t) {
        pending.removeValue(forKey: pid)
        elements.removeValue(forKey: pid)
        detach(pid: pid)
    }

    private func detach(pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }
}
