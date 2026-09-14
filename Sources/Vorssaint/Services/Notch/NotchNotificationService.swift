// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine

/// Keeps only notifications received during this unlocked, opted-in session.
/// Native banners are preserved; no notification databases or message stores are read.
final class NotchNotificationService: ObservableObject {
    static let shared = NotchNotificationService()
    @Published private var inbox = NotchNotificationInbox()
    var items: [NotchSystemNotification] { inbox.items }
    @Published private(set) var monitoring = false
    @Published private(set) var openingID: UUID?
    let received = PassthroughSubject<NotchSystemNotification, Never>()
    private let queue = DispatchQueue(label: "com.vorssaint.notch-notifications", qos: .utility)
    private var appIcons: [String: NSImage] = [:]
    private var sourceApplications: [UUID: String] = [:]
    @Published private(set) var unavailableID: UUID?
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var pid: pid_t?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var reader: NotchNotificationReader?
    private var cancellation = DispatchWorkItem {}
    private var pendingScan: DispatchWorkItem?
    private var generation = UUID()
    private var reading = false
    private var rescan = false
    private var running = false
    private let notifications = [kAXWindowCreatedNotification, kAXLayoutChangedNotification,
                                 kAXUIElementDestroyedNotification, kAXFocusedWindowChangedNotification]

    private init() {}

    func syncWithPreferences() {
        guard NotchNotificationSupport.isEnabled(), Permissions.shared.accessibility else { stop(); return }
        running = true
        if workspaceObservers.isEmpty {
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in self?.attach()
                })
            }
        }
        attach()
    }

    private func attach() {
        guard running else { return }
        guard NotchNotificationSupport.isEnabled(), Permissions.shared.accessibility else { stop(); return }
        let nextPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui")
            .first?.processIdentifier
        guard nextPID != pid || observer == nil else { return }
        detach()
        guard let nextPID else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            Unmanaged<NotchNotificationService>.fromOpaque(context).takeUnretainedValue().scheduleScan()
        }
        guard AXObserverCreate(nextPID, callback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(nextPID)
        AXUIElementSetMessagingTimeout(app, 0.1)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var attached = false
        for name in notifications {
            if AXObserverAddNotification(created, app, name as CFString, context) == .success { attached = true }
        }
        guard attached else { return }
        pid = nextPID; application = app; observer = created
        cancellation = DispatchWorkItem {}
        reader = NotchNotificationReader(pid: nextPID, cancellation: cancellation)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        monitoring = true
        scan()
    }

    private func scheduleScan() {
        guard monitoring else { return }
        if reading { rescan = true; return }
        guard pendingScan == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.pendingScan = nil; self?.scan() }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func scan() {
        guard monitoring, !reading, let reader else { return }
        reading = true
        let requested = generation
        queue.async { [weak self] in
            let snapshot = reader.read()
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { return }
                self.reading = false
                if let snapshot { self.accept(snapshot.items) }
                if self.rescan { self.rescan = false; self.scheduleScan() }
            }
        }
    }

    func icon(for app: String) -> NSImage? { appIcons[app] }

    private func accept(_ live: [NotchSystemNotification]) {
        let applications = NSWorkspace.shared.runningApplications
        let identities = applications.compactMap { app -> (name: String, bundleIdentifier: String)? in
            guard let name = app.localizedName, let identifier = app.bundleIdentifier else { return nil }
            return (name, identifier)
        }
        for name in Set(live.map { $0.content.app }) {
            guard let identifier = NotchNotificationSupport.sourceBundleIdentifier(for: [name], applications: identities) else {
                appIcons[name] = nil
                continue
            }
            appIcons[name] = applications.first(where: { $0.bundleIdentifier == identifier })?.icon
        }
        for item in live {
            if let identifier = NotchNotificationSupport.sourceBundleIdentifier(for: [item.content.app], applications: identities) {
                sourceApplications[item.id] = identifier
            }
        }
        let arrivals = inbox.update(live)
        trimIcons()
        for item in arrivals { received.send(item) }
    }

    private func trimIcons() {
        let sources = Set(items.map { $0.content.app })
        appIcons = appIcons.filter { sources.contains($0.key) }
        let ids = Set(items.map(\.id))
        sourceApplications = sourceApplications.filter { ids.contains($0.key) }
    }

    func dismiss(_ id: UUID) {
        inbox.dismiss(id)
        trimIcons()
    }

    func closeNative(_ id: UUID) {
        guard monitoring, NotchNotificationSupport.dismissesNative(), let reader,
              items.contains(where: { $0.id == id }) else { return }
        queue.async { _ = reader.closeNative(id) }
    }

    func canOpen(_ item: NotchSystemNotification) -> Bool {
        item.canOpen || sourceApplications[item.id] != nil
    }

    func open(_ id: UUID, completion: @escaping (NotchNotificationReader.ActionResult) -> Void) {
        guard openingID == nil, monitoring, NotchNotificationSupport.isEnabled(),
              items.contains(where: { $0.id == id }), let reader else { completion(.unavailable); return }
        openingID = id
        unavailableID = nil
        let requested = generation
        queue.async { [weak self] in
            let result = reader.open(id)
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { completion(.unavailable); return }
                if result == .unavailable, let identifier = self.sourceApplications[id],
                   let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
                   Bundle(url: url)?.bundleIdentifier == identifier {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] app, _ in
                        DispatchQueue.main.async {
                            guard let self, self.generation == requested else { completion(.unavailable); return }
                            self.openingID = nil
                            if app == nil { self.unavailableID = id }
                            completion(app == nil ? .unavailable : .openedApplication)
                        }
                    }
                } else {
                    self.openingID = nil
                    if result == .unavailable || result == .uncertain { self.unavailableID = id }
                    completion(result)
                }
                self.scheduleScan()
            }
        }
    }

    private func detach() {
        cancellation.cancel()
        generation = UUID()
        pendingScan?.cancel(); pendingScan = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            if let application {
                for name in notifications { AXObserverRemoveNotification(observer, application, name as CFString) }
            }
        }
        observer = nil; application = nil; pid = nil; reader = nil
        monitoring = false; reading = false; rescan = false; openingID = nil
        appIcons.removeAll()
        sourceApplications.removeAll()
        unavailableID = nil
        inbox = NotchNotificationInbox()
    }

    func stop() {
        running = false
        detach()
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
    }
}
