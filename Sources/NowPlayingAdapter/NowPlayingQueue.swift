// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ObjectiveC

/// The queue stays inside the existing isolated adapter. No request, timer or
/// retained player object survives closing the queue surface.
enum NotchNativeQueue {
    private static let work = DispatchQueue(label: "com.vorssaint.now-playing-queue")
    private static let callbacks = DispatchQueue(label: "com.vorssaint.now-playing-queue-callbacks")
    private static var requestID: UUID?
    private static var identity: Identity?
    private static var revision = UUID()
    private static let lifetimeLock = NSLock()
    private static var desiredRequest: UUID?
    private static var refreshPending = false
    private static var refreshGeneration = UUID()
    private static var observer: NSObjectProtocol?
    private static let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)

    private struct Identity: Equatable {
        let pid: Int32
        let item: String
    }
    private struct Snapshot {
        let target: NotchNativePlayback.Target
        let identity: Identity
        let items: [[String: Any]]
        let canPlay: Bool
    }

    static func configure(_ id: UUID?) {
        lifetimeLock.lock()
        desiredRequest = id
        lifetimeLock.unlock()
        work.async {
            lifetimeLock.lock()
            let current = desiredRequest == id
            lifetimeLock.unlock()
            guard current else { return }
            requestID = id
            revision = UUID()
            if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
            if id != nil {
                observer = NotificationCenter.default.addObserver(
                    forName: Notification.Name("kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification"),
                    object: nil, queue: nil) { _ in refresh() }
                refreshNow()
            }
        }
    }

    static func observe(_ info: [String: Any]) {
        lifetimeLock.lock()
        let active = desiredRequest != nil
        lifetimeLock.unlock()
        guard active else { return }
        let next = (info["pid"] as? Int32).flatMap { pid in
            (info["itemIdentifier"] as? String).map { Identity(pid: pid, item: $0) }
        }
        work.async {
            guard identity != next else { return }
            identity = next
            revision = UUID()
            if requestID != nil { refreshNow() }
        }
    }

    static func refresh() {
        lifetimeLock.lock()
        guard desiredRequest != nil else { lifetimeLock.unlock(); return }
        refreshGeneration = UUID()
        guard !refreshPending else { lifetimeLock.unlock(); return }
        refreshPending = true
        lifetimeLock.unlock()
        work.async { drainRefresh() }
    }

    private static func drainRefresh() {
        lifetimeLock.lock()
        let requested = refreshGeneration
        lifetimeLock.unlock()
        if requestID != nil { refreshNow() }
        lifetimeLock.lock()
        let again = desiredRequest != nil && requested != refreshGeneration
        if !again { refreshPending = false }
        lifetimeLock.unlock()
        if again { work.async { drainRefresh() } }
    }

    private static func refreshNow() {
        guard let requestID, isCurrent(requestID) else { return }
        revision = UUID()
        let snapshot = readSnapshot()
        guard isCurrent(requestID) else { return }
        var reply: [String: Any] = ["queueRequest": requestID.uuidString, "queueAvailable": snapshot != nil]
        if let snapshot {
            reply["currentIdentifier"] = snapshot.identity.item
            reply["pid"] = snapshot.identity.pid
            reply["queueItems"] = snapshot.items
            reply["queueCanPlay"] = snapshot.canPlay
        }
        emit(reply)
    }

    static func play(_ selected: NotchQueueSelection) {
        work.async {
            let request = selected.requestID
            let identifier = selected.itemIdentifier
            guard selected.isValid, requestID == request, isCurrent(request),
                  let fresh = readSnapshot(), fresh.canPlay,
                  let current = fresh.items.first(where: { $0["id"] as? String == identifier }),
                  let offset = current["offset"] as? Int,
                  selected.matches(pid: fresh.identity.pid, currentIdentifier: fresh.identity.item,
                                   itemIdentifier: identifier, offset: offset),
                  let offsetKey = NotchNativePlayback.stringConstant("kMRMediaRemoteOptionPlaybackQueueOffset"),
                  let itemKey = NotchNativePlayback.stringConstant("kMRMediaRemoteOptionContentItemID"), isCurrent(request) else {
                emit(["queueAction": request.uuidString, "queueActionOK": false])
                return
            }
            guard NotchNativePlayback.target?.pid == fresh.target.pid,
                  NotchNativePlayback.send(131, options: [offsetKey: offset, itemKey: identifier] as CFDictionary, to: fresh.target) else {
                emit(["queueAction": request.uuidString, "queueActionOK": false])
                return
            }
            // A transport acceptance is not proof that a player changed songs.
            // Observe the target identifier before reporting the action as done.
            let token = revision
            verify(request: request, target: identifier, pid: fresh.identity.pid, token: token, attempts: 3)
        }
    }

    private static func verify(request: UUID, target: String, pid: Int32, token: UUID, attempts: Int) {
        work.asyncAfter(deadline: .now() + 0.5) {
            guard requestID == request, isCurrent(request) else { return }
            let current = currentIdentity()
            if current == Identity(pid: pid, item: target) {
                emit(["queueAction": request.uuidString, "queueActionOK": true])
                refreshNow()
            } else if attempts > 1, revision == token, current?.pid == pid {
                verify(request: request, target: target, pid: pid, token: token, attempts: attempts - 1)
            } else {
                emit(["queueAction": request.uuidString, "queueActionOK": false])
                refreshNow()
            }
        }
    }

    private static func currentIdentity(target: NotchNativePlayback.Target? = NotchNativePlayback.target) -> Identity? {
        guard let target, target.isRunning else { return nil }
        let group = DispatchGroup()
        let lock = NSLock()
        var item: String?
        group.enter()
        NotchNativePlayback.readInfo(target, artwork: false, queue: callbacks) { value in
            lock.lock()
            item = value?["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] as? String
            lock.unlock()
            group.leave()
        }
        guard group.wait(timeout: .now() + 1) == .success else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let item, NotchPlaybackCommand.validIdentifier(item) else { return nil }
        return Identity(pid: target.pid, item: item)
    }

    private static func readSnapshot() -> Snapshot? {
        typealias Create = @convention(c) (AnyObject, Selector, NSRange) -> Unmanaged<AnyObject>?
        typealias Read = @convention(c) (AnyObject, AnyObject, DispatchQueue, @escaping @convention(block) (AnyObject?, NSError?) -> Void) -> Void
        guard let target = NotchNativePlayback.target, let before = currentIdentity(target: target),
              let read = function(handle, "MRMediaRemoteRequestNowPlayingPlaybackQueueForPlayerSync", as: Read.self),
              let factory = NSClassFromString("MRPlaybackQueueRequest"),
              let method = class_getClassMethod(factory, NSSelectorFromString("defaultPlaybackQueueRequestWithRange:")),
              let encoding = method_getTypeEncoding(method), String(cString: encoding).contains("{_NSRange=QQ}"),
              let request = unsafeBitCast(method_getImplementation(method), to: Create.self)(
                factory, NSSelectorFromString("defaultPlaybackQueueRequestWithRange:"), NSRange(location: 0, length: NotchQueueSelection.maximumItems + 1))?
                .takeUnretainedValue() as? NSObject,
              setFlag(request, "setIncludeMetadata:"), setFlag(request, "setIncludeInfo:") else { return nil }
        let group = DispatchGroup()
        let lock = NSLock()
        var received: NSObject?
        group.enter()
        read(request, target.path, callbacks) { queue, error in
            lock.lock()
            if error == nil { received = queue as? NSObject }
            lock.unlock()
            group.leave()
        }
        guard group.wait(timeout: .now() + 1.5) == .success else { return nil }
        lock.lock()
        let answer = received
        lock.unlock()
        guard let answer, let items = object(answer, "contentItems") as? [NSObject],
              !items.isEmpty, items.count <= NotchQueueSelection.maximumItems + 1,
              object(items[0], "identifier") as? String == before.item,
              currentIdentity(target: target) == before, NotchNativePlayback.target?.pid == target.pid else { return nil }
        var rows: [[String: Any]] = []
        for (offset, item) in items.enumerated().dropFirst() {
            guard let identifier = object(item, "identifier") as? String, NotchPlaybackCommand.validIdentifier(identifier),
                  let metadata = object(item, "metadata") as? NSObject,
                  let title = object(metadata, "title") as? String, !title.isEmpty else { continue }
            // Retain the native offset when an incomplete entry is omitted.
            // Reindexing filtered metadata could play a different song.
            rows.append(["id": identifier, "offset": offset, "title": String(title.prefix(1024)),
                         "artist": String((object(metadata, "trackArtistName") as? String ?? "").prefix(1024))])
        }
        let canPlay = supportsPlayItem(target: target)
        guard currentIdentity(target: target) == before, NotchNativePlayback.target?.pid == target.pid else { return nil }
        return Snapshot(target: target, identity: before, items: rows, canPlay: canPlay)
    }

    private static func supportsPlayItem(target: NotchNativePlayback.Target) -> Bool {
        typealias ID = @convention(c) (AnyObject) -> Int32
        typealias Enabled = @convention(c) (AnyObject) -> Bool
        guard let id = function(handle, "MRMediaRemoteCommandInfoGetCommand", as: ID.self),
              let enabled = function(handle, "MRMediaRemoteCommandInfoGetEnabled", as: Enabled.self) else { return false }
        let group = DispatchGroup()
        let lock = NSLock()
        var supported = false
        group.enter()
        NotchNativePlayback.supportedCommands(target, queue: callbacks) { commands in
            let value = commands?.contains(where: { id($0 as AnyObject) == 131 && enabled($0 as AnyObject) }) == true
            lock.lock(); supported = value; lock.unlock(); group.leave()
        }
        guard group.wait(timeout: .now() + 0.3) == .success else { return false }
        lock.lock()
        defer { lock.unlock() }
        return supported
    }

    private static func object(_ value: NSObject, _ name: String) -> AnyObject? {
        let selector = NSSelectorFromString(name)
        guard value.responds(to: selector) else { return nil }
        return value.perform(selector)?.takeUnretainedValue()
    }

    private static func setFlag(_ object: NSObject, _ name: String) -> Bool {
        typealias Set = @convention(c) (AnyObject, Selector, Bool) -> Void
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(type(of: object), selector),
              let encoding = method_getTypeEncoding(method), String(cString: encoding).hasPrefix("v20@0:8B16") else { return false }
        unsafeBitCast(method_getImplementation(method), to: Set.self)(object, selector, true)
        return true
    }

    private static func isCurrent(_ request: UUID) -> Bool {
        lifetimeLock.lock()
        defer { lifetimeLock.unlock() }
        return desiredRequest == request
    }
}
