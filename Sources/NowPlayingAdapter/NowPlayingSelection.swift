// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import ObjectiveC

/// The watched surface owns its destination independently of the system's
/// latest player. Reads and commands use this same path, without changing the
/// system-wide player or requesting automation permission.
enum NotchNativePlayback {
    struct Target {
        let pid: Int32
        let bundleIdentifier: String
        let path: NSObject
        var itemIdentifier: String?
        var allowsDirectCommands = false
        var applicationBundleIdentifier: String?

        var isRunning: Bool {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
            return app.bundleIdentifier == bundleIdentifier
        }
    }

    private static let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    private static let callbacks = DispatchQueue(label: "com.vorssaint.now-playing-selection-callbacks")
    private static let lock = NSLock()
    private static var selected: Target?
    private static var identity: Identity?
    private static var context: NotchPlaybackContext?
    private static var sources: [NotchPlaybackSource] = []
    private static var selection: NotchPlaybackSource.Selection?

    static var sourceReply: [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["sources": sources.map(\.reply), "sourceIsAutomatic": selection == nil]
    }

    static func choose(_ requested: NotchPlaybackSource.Selection?) {
        lock.lock(); defer { lock.unlock() }
        guard requested == nil || sources.contains(where: { $0.selection == requested && $0.hasTrack }) else { return }
        selection = requested
    }

    private struct Identity: Equatable {
        let item: String?
        let metadata: [String]

        init?(_ info: [String: Any]) {
            let title = (info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let identifier = info["itemIdentifier"] as? String
                ?? info["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] as? String
            item = identifier.flatMap { NotchPlaybackCommand.validIdentifier($0) ? $0 : nil }
            if item != nil { metadata = []; return }
            let duration = (info["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue
            metadata = [title, info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
                        info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
                        duration.flatMap { $0.isFinite ? String($0.rounded()) : nil } ?? ""]
        }
    }

    static var target: Target? {
        lock.lock()
        defer { lock.unlock() }
        return selected
    }

    static func select() -> Target? {
        var discovered = false
        defer {
            if !discovered {
                // A failed scan is not evidence that the chosen player ended.
                lock.lock(); sources = []; lock.unlock()
            }
        }
        typealias ReadClient = @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void
        typealias ReadClients = @convention(c) (DispatchQueue, @escaping @convention(block) (NSArray?) -> Void) -> Void
        typealias PID = @convention(c) (AnyObject) -> Int32
        typealias ClientString = @convention(c) (AnyObject) -> Unmanaged<CFString>?
        guard let getClient = function(handle, "MRMediaRemoteGetNowPlayingClient", as: ReadClient.self),
              let getPID = function(handle, "MRNowPlayingClientGetProcessIdentifier", as: PID.self) else { return nil }
        let group = DispatchGroup()
        let clientsGroup = DispatchGroup()
        let resultsLock = NSLock()
        var systemPID: Int32?
        var clientPIDs: [Int32] = []
        var clientPresentation: [Int32: (name: String?, application: String?)] = [:]
        let getName = function(handle, "MRNowPlayingClientGetDisplayName", as: ClientString.self)
        let getParent = function(handle, "MRNowPlayingClientGetParentAppBundleIdentifier", as: ClientString.self)
        group.enter()
        getClient(callbacks) { client in
            resultsLock.lock()
            systemPID = client.map(getPID)
            resultsLock.unlock()
            group.leave()
        }
        // Browsers need to remain discoverable when a music app owns the
        // system's current player. Enumerate registered clients, not all apps.
        if let getClients = function(handle, "MRMediaRemoteGetNowPlayingClients", as: ReadClients.self) {
            clientsGroup.enter()
            getClients(callbacks) { clients in
                resultsLock.lock()
                clientPIDs = (clients as? [AnyObject] ?? []).prefix(16).map(getPID)
                for client in (clients as? [AnyObject] ?? []).prefix(16) {
                    clientPresentation[getPID(client)] = (getName?(client)?.takeUnretainedValue() as String?,
                                                         getParent?(client)?.takeUnretainedValue() as String?)
                }
                resultsLock.unlock()
                clientsGroup.leave()
            }
        }
        guard group.wait(timeout: .now() + 0.5) == .success else { return nil }
        // Failure to enumerate extra sources must not hide the known player.
        _ = clientsGroup.wait(timeout: .now() + 0.2)
        resultsLock.lock()
        let currentPID = systemPID
        let registeredPIDs = clientPIDs
        let presentation = clientPresentation
        resultsLock.unlock()
        let chosenPID = lock.withLock { selection?.pid }
        let musicPIDs = NSWorkspace.shared.runningApplications.filter(isMusicApp).map(\.processIdentifier)
        var applications: [NSRunningApplication] = []
        // A bounded fan-out; no timers or queries survive the adapter process.
        // Past the bound, only the least likely clients are skipped: chosen,
        // current and followed players first, then music apps, then the rest.
        for pid in [chosenPID, currentPID, target?.pid].compactMap({ $0 }) + musicPIDs + registeredPIDs {
            guard applications.count < 16 else { break }
            if pid > 0, !applications.contains(where: { $0.processIdentifier == pid }),
               let current = NSRunningApplication(processIdentifier: pid) {
                applications.append(current)
            }
        }
        var candidates: [(Target, NotchPlaybackSource)] = []
        for app in applications {
            guard var candidate = makeTarget(app) else { continue }
            // A browser can publish through a web content helper. Keep its exact
            // process for routing, and use the parent app only for presentation/opening.
            candidate.applicationBundleIdentifier = presentation[candidate.pid]?.application
                .flatMap { NotchPlaybackCommand.validIdentifier($0) ? $0 : nil }
            group.enter()
            readInfo(candidate, artwork: false, queue: callbacks) { info in
                let source = NotchPlaybackSource(pid: candidate.pid, bundleIdentifier: candidate.bundleIdentifier,
                    isMusicApp: isMusicApp(app),
                    isPlaying: (info?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0 > 0,
                    hasTrack: (info?["kMRMediaRemoteNowPlayingInfoTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                    displayName: presentation[candidate.pid]?.name ?? app.localizedName)
                resultsLock.lock()
                candidates.append((candidate, source))
                resultsLock.unlock()
                group.leave()
            }
        }
        // Keep completed reads when an unrelated client misses the deadline.
        _ = group.wait(timeout: .now() + 1)
        resultsLock.lock()
        let ready = candidates
        resultsLock.unlock()
        lock.lock()
        sources = ready.map(\.1).filter(\.hasTrack).sorted { $0.pid < $1.pid }
        if let selection {
            let app = NSRunningApplication(processIdentifier: selection.pid)
            let ended = app == nil || app?.isTerminated == true || app?.bundleIdentifier != selection.bundleIdentifier
            let lostTrack = ready.contains { $0.1.selection == selection && !$0.1.hasTrack }
            if ended || lostTrack { self.selection = nil }
        }
        let requested = selection
        lock.unlock()
        discovered = true
        // An unanswered selected player stays selected, but exposes no stale
        // controls. The empty surface still lets the user choose another one.
        if let requested, !ready.contains(where: { $0.1.selection == requested && $0.1.hasTrack }) { return nil }
        let source = NotchPlaybackSource.preferred(in: ready.map(\.1), previousPID: target?.pid,
                                                   systemPID: currentPID, selection: requested)
        guard var chosen = ready.first(where: { $0.1 == source })?.0 else { return nil }
        typealias IsSystemPlayer = @convention(c) (AnyObject, Selector) -> Bool
        let systemPlayer = ["isSystemMediaApplication", "isSystemPodcastsApplication", "isSystemBooksApplication"].contains { name in
            let selector = NSSelectorFromString(name)
            guard chosen.path.responds(to: selector) else { return false }
            return unsafeBitCast(chosen.path.method(for: selector), to: IsSystemPlayer.self)(chosen.path, selector)
        }
        // A third-party client can stop being the global player while a command
        // is in flight. Its declared per-process automation avoids that race.
        chosen.allowsDirectCommands = systemPlayer
            && stringConstant("kMRMediaRemoteOptionNowPlayingContentItemID") != nil
        return chosen
    }

    @discardableResult
    static func publish(_ target: Target?, info: [String: Any] = [:]) -> NotchPlaybackContext? {
        lock.lock()
        defer { lock.unlock() }
        guard var target, let next = Identity(info) else {
            selected = target; identity = nil; context = nil
            return nil
        }
        // Position and play/pause updates do not end a recording. Without an
        // item ID, use only observable recording metadata for its revision.
        if selected?.pid != target.pid || selected?.bundleIdentifier != target.bundleIdentifier
            || identity != next {
            context = NotchPlaybackContext(pid: target.pid, revision: UUID())
        }
        target.itemIdentifier = next.item
        selected = target
        identity = next
        return context
    }

    static func validatedTarget(for requested: NotchPlaybackContext) -> Target? {
        lock.lock()
        let target = context == requested ? selected : nil
        let expected = identity
        lock.unlock()
        guard let target, let expected, target.isRunning else { return nil }
        // The actual player can advance before its change notification reaches
        // our reader. Re-read this path without changing music source selection.
        let group = DispatchGroup()
        let resultLock = NSLock()
        var fresh: Identity?
        group.enter()
        readInfo(target, artwork: false, queue: callbacks) { info in
            resultLock.lock()
            fresh = (info as? [String: Any]).flatMap(Identity.init)
            resultLock.unlock()
            group.leave()
        }
        guard group.wait(timeout: .now() + 1) == .success else { return nil }
        resultLock.lock()
        let matches = fresh == expected
        resultLock.unlock()
        lock.lock()
        defer { lock.unlock() }
        guard matches, context == requested, identity == expected, target.isRunning else { return nil }
        return target
    }

    static func readInfo(_ target: Target, artwork: Bool, queue: DispatchQueue,
                         completion: @escaping (NSDictionary?) -> Void) {
        typealias Read = @convention(c) (AnyObject, Bool, DispatchQueue,
            @escaping @convention(block) (NSDictionary?, UnsafeRawPointer?) -> Void) -> Void
        typealias CopyArtwork = @convention(c) (UnsafeRawPointer) -> Unmanaged<CFData>?
        guard target.isRunning,
              let read = function(handle, "MRMediaRemoteGetNowPlayingInfoForPlayer", as: Read.self) else {
            completion(nil); return
        }
        read(target.path, artwork, queue) { info, cover in
            guard let info else { completion(nil); return }
            let result = info.mutableCopy() as! NSMutableDictionary
            if let cover, let copy = function(handle, "MRNowPlayingArtworkCopyImageData", as: CopyArtwork.self),
               let data = copy(cover)?.takeRetainedValue() {
                result["kMRMediaRemoteNowPlayingInfoArtworkData"] = data as Data
            }
            completion(result)
        }
    }

    static func supportedCommands(_ target: Target, queue: DispatchQueue, completion: @escaping (NSArray?) -> Void) {
        typealias Read = @convention(c) (AnyObject, DispatchQueue, @escaping @convention(block) (NSArray?) -> Void) -> Void
        guard let read = function(handle, "MRMediaRemoteGetSupportedCommandsForPlayer", as: Read.self) else {
            completion(nil); return
        }
        read(target.path, queue, completion)
    }

    @discardableResult
    static func send(_ command: Int32, options: CFDictionary? = nil, to target: Target) -> Bool {
        typealias Send = @convention(c) (Int32, CFDictionary?, AnyObject, UInt32, DispatchQueue,
            @escaping @convention(block) (UInt32, NSArray?) -> Void) -> Bool
        guard target.isRunning, target.allowsDirectCommands, let item = target.itemIdentifier,
              let itemKey = stringConstant("kMRMediaRemoteOptionNowPlayingContentItemID"),
              let send = function(handle, "MRMediaRemoteSendCommandToPlayer", as: Send.self) else { return false }
        // The service may redirect unprivileged requests to the global player.
        // The receiver must reject a different item instead of acting on it.
        var scoped = (options as? [String: Any]) ?? [:]
        scoped[itemKey] = item
        let group = DispatchGroup()
        let resultLock = NSLock()
        var delivered = false
        group.enter()
        guard send(command, scoped as CFDictionary, target.path, 0, callbacks, { error, responses in
            resultLock.lock()
            delivered = error == 0 && (responses as? [NSNumber])?.contains(where: { $0.intValue == 0 }) == true
            resultLock.unlock()
            group.leave()
        }) else { return false }
        guard group.wait(timeout: .now() + 2) == .success else { return false }
        return resultLock.withLock { delivered }
    }

    static func stringConstant(_ name: String) -> String? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return symbol.assumingMemoryBound(to: NSString?.self).pointee as String?
    }

    private static func isMusicApp(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL else { return false }
        return Bundle(url: url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String == "public.app-category.music"
    }

    private static func makeTarget(_ app: NSRunningApplication) -> Target? {
        guard !app.isTerminated, let identifier = app.bundleIdentifier,
              let pathClass = NSClassFromString("MRPlayerPath"),
              let clientClass = NSClassFromString("MRClient"),
              class_getClassMethod(pathClass, NSSelectorFromString("localPlayerPath")) != nil,
              class_getInstanceMethod(clientClass, NSSelectorFromString("initWithBundleIdentifier:")) != nil,
              let localPath = (pathClass as AnyObject).perform(NSSelectorFromString("localPlayerPath"))?.takeUnretainedValue() as? NSObject,
              let path = localPath.copy() as? NSObject,
              let allocation = (clientClass as AnyObject).perform(NSSelectorFromString("alloc"))?.takeRetainedValue(),
              let client = allocation.perform(NSSelectorFromString("initWithBundleIdentifier:"), with: identifier)?.takeUnretainedValue() as? NSObject else { return nil }
        // The native local path is shared. Only mutate our own copy, otherwise
        // constructing the next candidate redirects previously selected paths.
        typealias SetPID = @convention(c) (AnyObject, Selector, Int32) -> Void
        let setPID = NSSelectorFromString("setProcessIdentifier:")
        guard client.responds(to: setPID), path.responds(to: NSSelectorFromString("setClient:")),
              path.responds(to: NSSelectorFromString("setPlayer:")) else { return nil }
        unsafeBitCast(client.method(for: setPID), to: SetPID.self)(client, setPID, app.processIdentifier)
        path.perform(NSSelectorFromString("setClient:"), with: client)
        // Nil resolves this app's active player; "default" is a different player
        // for apps which publish multiple sessions.
        path.perform(NSSelectorFromString("setPlayer:"), with: nil)
        return Target(pid: app.processIdentifier, bundleIdentifier: identifier, path: path)
    }
}
