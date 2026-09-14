// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

// Reads the system Now Playing session and prints it as one JSON line.
//
// Since macOS 15.4 MediaRemote answers `MRMediaRemoteGetNowPlayingInfo` with
// nothing unless the calling process carries Apple's own signature, so the
// app cannot read it in-process any more. `/usr/bin/perl` is a platform
// binary and can; `Resources/now-playing.pl` loads this library into perl
// with DynaLoader and calls `vorssaint_now_playing_get`. The app runs that
// through `BoundedProcessRunner` and parses the line
// (`RadialNowPlayingSupport.adapterReply`). Nothing here is linked into the
// app: the library is built and signed on its own by build.sh.

import Foundation

private typealias InfoCallback = @convention(block) (NSDictionary?) -> Void
private typealias InfoFunction = @convention(c) (DispatchQueue, @escaping InfoCallback) -> Void
private typealias PIDCallback = @convention(block) (Int32) -> Void
private typealias PIDFunction = @convention(c) (DispatchQueue, @escaping PIDCallback) -> Void
private typealias DisplayIDCallback = @convention(block) (NSString?) -> Void
private typealias DisplayIDFunction = @convention(c) (DispatchQueue, @escaping DisplayIDCallback) -> Void
private typealias IsPlayingCallback = @convention(block) (Bool) -> Void
private typealias IsPlayingFunction = @convention(c) (DispatchQueue, @escaping IsPlayingCallback) -> Void

/// Artwork travels base64-encoded on one line; anything past this is dropped
/// rather than pushed through the pipe. Same cap as
/// `RadialNowPlayingSupport.maximumArtworkBytes`, which the app applies to
/// the decoded bytes; the bridge's pipe cap is sized from it (base64 is 4/3
/// of the bytes) and has to move with it.
private let maximumArtworkBytes = 12 * 1_024 * 1_024
// Only the watch process enables this cache. Its reads run serially.
private var watching = false
private var previousArtwork: Data?

func function<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
    guard let handle, let symbol = dlsym(handle, name) else { return nil }
    return unsafeBitCast(symbol, to: type)
}

private let emissionLock = NSLock()

func emit(_ reply: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{\"error\":\"json\"}".utf8)
    emissionLock.lock()
    defer { emissionLock.unlock() }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

/// Entry point called from perl. Prints exactly one line and returns.
@_cdecl("vorssaint_now_playing_get")
public func vorssaintNowPlayingGet() {
    let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    guard let getInfo = function(handle, "MRMediaRemoteGetNowPlayingInfo", as: InfoFunction.self) else {
        emit(["error": "MRMediaRemoteGetNowPlayingInfo unavailable"])
        return
    }
    let queue = DispatchQueue(label: "com.vorssaint.now-playing-adapter")
    let group = DispatchGroup()
    let lock = NSLock()
    var reply: [String: Any] = [:]
    func set(_ key: String, _ value: Any?) {
        guard let value else { return }
        lock.lock()
        reply[key] = value
        lock.unlock()
    }

    group.enter()
    getInfo(queue) { info in
        let info = (info as? [String: Any]) ?? [:]
        if watching { set("itemIdentifier", info["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] as? String) }
        for key in ["kMRMediaRemoteNowPlayingInfoTitle",
                    "kMRMediaRemoteNowPlayingInfoArtist",
                    "kMRMediaRemoteNowPlayingInfoAlbum"] {
            set(key, info[key] as? String)
        }
        set("kMRMediaRemoteNowPlayingInfoDuration",
            (info["kMRMediaRemoteNowPlayingInfoDuration"] as? NSNumber)?.doubleValue)
        if let elapsed = (info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? NSNumber)?.doubleValue {
            let timestamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date
            let rate = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue ?? 0
            let age = timestamp.map { max(0, Date().timeIntervalSince($0)) } ?? 0
            set("kMRMediaRemoteNowPlayingInfoElapsedTime", elapsed + age * max(0, rate))
        }
        set("kMRMediaRemoteNowPlayingInfoPlaybackRate",
            (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue)
        let artwork = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        if watching, artwork != nil, artwork == previousArtwork {
            set("artworkUnchanged", true)
        } else if let artwork, !artwork.isEmpty, artwork.count <= maximumArtworkBytes {
            set("artworkBase64", artwork.base64EncodedString())
        }
        if watching { previousArtwork = artwork }
        group.leave()
    }
    if let getPID = function(handle, "MRMediaRemoteGetNowPlayingApplicationPID", as: PIDFunction.self) {
        group.enter()
        getPID(queue) { pid in
            set("pid", pid)
            group.leave()
        }
    }
    if let getDisplayID = function(handle, "MRMediaRemoteGetNowPlayingApplicationDisplayID",
                                   as: DisplayIDFunction.self) {
        group.enter()
        getDisplayID(queue) { identifier in
            set("displayID", identifier as String?)
            group.leave()
        }
    }
    if let getIsPlaying = function(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying",
                                   as: IsPlayingFunction.self) {
        group.enter()
        getIsPlaying(queue) { isPlaying in
            set("isPlaying", isPlaying)
            group.leave()
        }
    }
    // Only expose seeking when the current player advertises that command.
    // Missing symbols keep the timeline read-only without affecting playback.
    typealias CommandsCallback = @convention(block) (NSArray?) -> Void
    typealias CopyCommands = @convention(c) (DispatchQueue, @escaping CommandsCallback) -> Void
    typealias CommandID = @convention(c) (AnyObject) -> Int32
    typealias CommandEnabled = @convention(c) (AnyObject) -> Bool
    let capabilities = DispatchGroup()
    if watching,
       let copyCommands = function(handle, "MRMediaRemoteCopySupportedCommands", as: CopyCommands.self),
       let commandID = function(handle, "MRMediaRemoteCommandInfoGetCommand", as: CommandID.self),
       let commandEnabled = function(handle, "MRMediaRemoteCommandInfoGetEnabled", as: CommandEnabled.self),
       dlsym(handle, "MRMediaRemoteSetElapsedTime") != nil {
        capabilities.enter()
        copyCommands(queue) { commands in
            set("canSeek", commands?.contains(where: {
                commandID($0 as AnyObject) == 24 && commandEnabled($0 as AnyObject)
            }) == true)
            capabilities.leave()
        }
    }

    // One-shot callers already have an external deadline. A watched session
    // also needs a bound: a missing callback must not leave stale playback
    // visible indefinitely or accumulate further requests behind it.
    if watching {
        guard group.wait(timeout: .now() + 2) == .success else {
            emit(["error": "metadata timeout"])
            exit(1)
        }
    } else { group.wait() }
    if watching { _ = capabilities.wait(timeout: .now() + 0.2) }
    lock.lock()
    let snapshot = reply
    lock.unlock()
    emit(snapshot)
    if watching { NotchNativeQueue.observe(snapshot) }
}

/// One adapter process while a music surface is subscribed. Native change
/// notifications replace polling; closing stdin also ends it if the app exits.
@_cdecl("vorssaint_now_playing_watch")
public func vorssaintNowPlayingWatch() {
    typealias Register = @convention(c) (DispatchQueue) -> Void
    let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    guard let register = function(handle, "MRMediaRemoteRegisterForNowPlayingNotifications", as: Register.self) else {
        emit(["error": "notifications unavailable"])
        return
    }
    watching = true
    register(.main)
    let reader = DispatchQueue(label: "com.vorssaint.now-playing-watch")
    var pending: DispatchWorkItem?
    let names = ["kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                 "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
                 "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"]
    let observers = names.map { name in
        NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
            pending?.cancel()
            let work = DispatchWorkItem { vorssaintNowPlayingGet() }
            pending = work
            reader.asyncAfter(deadline: .now() + 0.12, execute: work)
        }
    }
    var commandFramer = NotchPlaybackCommandFramer()
    FileHandle.standardInput.readabilityHandler = { input in
        let data = input.availableData
        if data.isEmpty { exit(0) }
        DispatchQueue.main.async {
            for command in commandFramer.append(data) {
                guard let command else { emit(["sent": false]); continue }
                sendPlaybackCommand(command)
            }
        }
    }
    reader.async { vorssaintNowPlayingGet() }
    withExtendedLifetime(observers) { RunLoop.main.run() }
}

private func sendPlaybackCommand(_ command: NotchPlaybackCommand) {
    switch command {
    case .queue(let request): NotchNativeQueue.configure(request); return
    case .queueStop: NotchNativeQueue.configure(nil); return
    case .queuePlay(let selected): NotchNativeQueue.play(selected); return
    default: break
    }
    typealias Send = @convention(c) (Int32, CFDictionary?) -> Bool
    typealias Seek = @convention(c) (Double) -> Void
    let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    if case .seek(let position) = command {
        guard let seek = function(handle, "MRMediaRemoteSetElapsedTime", as: Seek.self) else {
            emit(["sent": false])
            return
        }
        seek(position)
        emit(["sent": true])
        return
    }
    let identifier: Int32
    switch command {
    case .toggle: identifier = 2
    case .next: identifier = 4
    case .previous: identifier = 5
    case .seek, .queue, .queueStop, .queuePlay: return
    }
    let send = function(handle, "MRMediaRemoteSendCommand", as: Send.self)
    emit(["sent": send?(identifier, nil) ?? false])
}
