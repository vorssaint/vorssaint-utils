// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Drives the production observer with simulated AX replies and manually delivered queue work.
enum SwitcherWindowTitleTests {
    final class AXUIElement: NSObject {
        let item: SwitcherItem
        var attempts = 0
        let reply: (Int) -> AXError
        var notify: (() -> Void)?

        init(_ id: CGWindowID, owner: pid_t = 11, reply: @escaping (Int) -> AXError = { _ in .success }) {
            item = .window(id: id, title: "Document", appName: "Editor", pid: 10, windowOwnerPID: owner,
                           isOnScreen: true, isMinimized: false, isFullscreen: false, frame: .zero)
            self.reply = reply
        }
    }

    final class AXObserver {
        let callback: AXObserverCallback
        init(_ callback: @escaping AXObserverCallback) { self.callback = callback }
    }
    typealias AXObserverCallback = (AXObserver, AXUIElement, CFString, UnsafeMutableRawPointer?) -> Void

    struct DispatchQueue {
        static let main = SwitcherActivationTests.DeferredQueue()
        static let worker = SwitcherActivationTests.DeferredQueue()
        init(label: String, qos: DispatchQoS) {}
        func async(execute work: @escaping () -> Void) { Self.worker.async(execute: work) }
    }

    static var createAttempts = 0
    static var createReply: (Int) -> AXError = { _ in .success }
    static var attached: Set<ObjectIdentifier> = []

    @discardableResult
    static func AXUIElementGetPid(_ window: AXUIElement, _ pid: inout pid_t) -> AXError {
        pid = window.item.windowOwnerPID
        return .success
    }

    @discardableResult
    static func AXUIElementSetMessagingTimeout(_ window: AXUIElement, _ seconds: Float) -> AXError { .success }

    static func AXObserverCreate(_ pid: pid_t, _ callback: @escaping AXObserverCallback,
                                 _ observer: inout AXObserver?) -> AXError {
        createAttempts += 1
        let result = createReply(createAttempts)
        observer = result == .success ? AXObserver(callback) : nil
        return result
    }

    static func AXObserverAddNotification(_ observer: AXObserver, _ window: AXUIElement,
                                          _ name: CFString, _ context: UnsafeMutableRawPointer?) -> AXError {
        guard name as String == kAXTitleChangedNotification as String else { return .notificationUnsupported }
        window.attempts += 1
        let result = window.reply(window.attempts)
        if result == .success || result == .notificationAlreadyRegistered {
            window.notify = { [weak window] in
                if let window { observer.callback(observer, window, name, context) }
            }
        }
        return result
    }

    static func AXObserverGetRunLoopSource(_ observer: AXObserver) -> AXObserver { observer }
    static func CFRunLoopAddSource(_ loop: CFRunLoop?, _ source: AXObserver, _ mode: CFRunLoopMode) {
        attached.insert(ObjectIdentifier(source))
    }
    static func CFRunLoopRemoveSource(_ loop: CFRunLoop?, _ source: AXObserver, _ mode: CFRunLoopMode) {
        attached.remove(ObjectIdentifier(source))
    }

    static func deliver() {
        DispatchQueue.worker.drain()
        DispatchQueue.main.drain()
    }

    private static func checkWindowServerTitles(_ suite: TestSuite) {
        let document = SwitcherItem.window(id: 9, title: "Draft", appName: "Editor", pid: 10, windowOwnerPID: 11,
                                           isOnScreen: true, isMinimized: false, isFullscreen: false, frame: .zero)
        var renamed = document
        renamed.title = "Budget"
        let ownWindow = SwitcherItem.window(id: 8, title: "Settings", appName: "Vorssaint",
                                            pid: ProcessInfo.processInfo.processIdentifier, isOnScreen: true,
                                            isMinimized: false, isFullscreen: false, frame: .zero)
        let windowless = SwitcherItem.appOnly(appName: "Finder", pid: 20)
        let healthy = AXUIElement(1, owner: 21)
        let service = SwitcherHoverSelectionTests.Service()
        service.sessionActive = true
        service.sessionItems = [document, healthy.item, ownWindow, windowless]
        service.windows = service.sessionItems
        service.appendSearchText("Budget")
        let watcher = SwitcherWindowTitles()
        defer { watcher.stop() }
        var reads: [pid_t] = []
        var attachedAtRead = 0
        watcher.onChange = { owner in
            reads.append(owner)
            attachedAtRead = attached.count
            if owner == document.windowOwnerPID {
                DispatchQueue.main.async { service.updateSessionTitles(from: [renamed]) }
            }
        }

        watcher.update([:])
        watcher.refreshUnobserved(in: service.sessionItems, accessibilityGranted: false)
        watcher.refreshUnobserved(in: [ownWindow, windowless], accessibilityGranted: true)
        deliver()
        suite.expect(reads.isEmpty && service.windows.isEmpty && createAttempts == 0,
                     "no permission, a local window, and a windowless app require no title reads")
        watcher.refreshUnobserved(in: [document], accessibilityGranted: true)
        suite.expect(reads == [11] && service.windows.isEmpty, "a CG-only title requests its owner without waiting")
        deliver()
        suite.expect(service.searchQuery == "Budget" && service.windows == [renamed],
                     "the reread WindowServer title satisfies the existing search without reopening the switcher")

        reads = []
        watcher.update([1: healthy])
        deliver()
        watcher.refreshUnobserved(in: service.sessionItems, accessibilityGranted: true)
        deliver()
        suite.expect(reads == [21, 11], "the new watch reconciles once and only the CG-only window rereads on demand")
        reads = []
        let appeared = AXUIElement(9)
        let elements: [CGWindowID: AXUIElement] = [1: healthy, 9: appeared]
        watcher.update(elements)
        service.appendSearchText(" final")
        renamed.title = "Budget final"
        DispatchQueue.worker.drain()
        suite.expect(appeared.attempts == 1 && reads.isEmpty && service.windows.isEmpty,
                     "a rename before the first subscription leaves the typed query waiting for reconciliation")
        DispatchQueue.main.drain()
        suite.expect(reads == [11] && attachedAtRead == 2 && service.searchQuery == "Budget final"
                     && service.windows == [renamed] && service.selectedItemID == renamed.id,
                     "attaching the first successful subscription finds and selects the renamed document without an event")

        reads = []
        watcher.update(elements)
        watcher.refreshUnobserved(in: service.sessionItems, accessibilityGranted: true)
        deliver()
        suite.expect(createAttempts == 2 && healthy.attempts == 1 && appeared.attempts == 1 && reads.isEmpty,
                     "readopting the same elements and opening again reuses both watches without another title read")

        let replacement = AXUIElement(9)
        watcher.update([1: healthy, 9: AXUIElement(9)])
        watcher.update([1: healthy, 9: replacement])
        deliver()
        suite.expect(replacement.attempts == 1 && attached.count == 2 && reads.isEmpty,
                     "replacing a pending AX handle for a covered window cannot attach twice or start another reread")
    }

    static func run(_ suite: TestSuite) {
        let watcher = SwitcherWindowTitles()
        var changes: [pid_t] = []
        watcher.onChange = { changes.append($0) }
        func reset() {
            watcher.stop()
            deliver()
            changes = []
            createAttempts = 0
            createReply = { _ in .success }
        }
        defer { reset() }

        checkWindowServerTitles(suite)
        reset()

        let healthy = AXUIElement(1)
        createReply = { $0 == 1 ? .cannotComplete : .success }
        watcher.update([1: healthy])
        watcher.refreshUnobserved(in: [healthy.item], accessibilityGranted: true)
        suite.expect(changes == [11] && createAttempts == 0,
                     "a pending subscription requests an owner refresh without waiting for AX")
        changes = []
        deliver()
        suite.expect(createAttempts == 2 && healthy.attempts == 1 && attached.count == 1 && changes == [11],
                     "a transient observer creation failure retries once and reconciles the missed interval")
        changes = []
        watcher.update([1: healthy])
        watcher.refreshUnobserved(in: [healthy.item], accessibilityGranted: true)
        deliver()
        suite.expect(changes.isEmpty && createAttempts == 2, "a recovered watch needs no shortcut refresh")
        reset()
        suite.expect(attached.isEmpty, "disabling the watcher detaches its observer")

        createReply = { _ in .cannotComplete }
        watcher.update([1: healthy])
        deliver()
        watcher.update([1: healthy])
        deliver()
        suite.expect(createAttempts == 2 && changes.isEmpty && attached.isEmpty,
                     "a permanent creation failure exhausts its retry without invalidating in a loop")
        watcher.refreshUnobserved(in: [healthy.item], accessibilityGranted: true)
        watcher.refreshUnobserved(in: [healthy.item], accessibilityGranted: true)
        suite.expect(changes == [11, 11] && createAttempts == 2,
                     "successive sessions reread the owner of a permanently unobserved title")
        reset()

        let accepted = AXUIElement(1) { _ in .notificationAlreadyRegistered }
        let refused = AXUIElement(2) { _ in .notificationUnsupported }
        let transient = AXUIElement(3) { $0 == 1 ? .cannotComplete : .success }
        let elements: [CGWindowID: AXUIElement] = [1: accepted, 2: refused, 3: transient]
        watcher.update(elements)
        deliver()
        suite.expect(accepted.attempts == 1 && refused.attempts == 1 && transient.attempts == 2
                     && changes == [11] && attached.count == 1,
                     "each window registers independently and only a transient failure is retried")
        changes = []
        watcher.refreshUnobserved(in: [accepted.item, transient.item], accessibilityGranted: true)
        suite.expect(changes.isEmpty, "a sibling's refusal leaves the accepted titles covered")
        let previousNotification = accepted.notify
        previousNotification?()
        suite.expect(changes == [11], "the accepted sibling still delivers title changes through its observer")
        changes = []
        watcher.refreshUnobserved(in: [accepted.item, refused.item, transient.item], accessibilityGranted: true)
        watcher.update(elements)
        deliver()
        watcher.refreshUnobserved(in: [refused.item], accessibilityGranted: true)
        suite.expect(changes == [11, 11] && createAttempts == 1 && refused.attempts == 1,
                     "a refused window stays eligible on each shortcut without replacing healthy subscriptions")
        watcher.update([1: accepted])
        deliver()
        changes = []
        previousNotification?()
        watcher.refreshUnobserved(in: [accepted.item], accessibilityGranted: true)
        suite.expect(changes.isEmpty, "a detached observer and the remaining covered window cannot request a reread")
        reset()

        let first = AXUIElement(1) { $0 == 1 ? .cannotComplete : .success }
        watcher.update([1: first])
        DispatchQueue.worker.drain()
        watcher.stop()
        let replacement = AXUIElement(1) { _ in .cannotComplete }
        watcher.update([1: replacement])
        DispatchQueue.main.drain()
        suite.expect(changes.isEmpty && attached.isEmpty,
                     "a registration finishing after stop cannot attach or invalidate the restarted watcher")
        deliver()
        watcher.refreshUnobserved(in: [replacement.item], accessibilityGranted: true)
        suite.expect(changes == [11] && replacement.attempts == 2,
                     "after restart a replacement that keeps timing out exhausts its retry and stays eligible")
        watcher.stop()
        changes = []
        watcher.refreshUnobserved(in: [replacement.item], accessibilityGranted: true)
        deliver()
        suite.expect(changes.isEmpty && attached.isEmpty, "stopping clears outstanding title recovery")

        let attemptsBeforeStop = createAttempts
        let abandoned = AXUIElement(4)
        watcher.update([4: abandoned])
        watcher.stop()
        deliver()
        suite.expect(createAttempts == attemptsBeforeStop && abandoned.attempts == 0 && changes.isEmpty,
                     "registration work still queued at stop performs no AX requests")
    }
}
