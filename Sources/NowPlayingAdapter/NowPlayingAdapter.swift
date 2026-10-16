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

import AppKit
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
let maximumArtworkBytes = 12 * 1_024 * 1_024
// Only the watch process enables this cache. Its reads run serially.
private var watching = false
private var previousArtwork: Data?
/// Watch only: where the last reply put its recording, by the sample it read.
private var lastPosition: (revision: UUID, sample: Double, timestamp: Date?, elapsed: Double, rate: Double, at: Date)?
/// Set by the watch process: schedules another read at a system uptime.
private var readAt: ((TimeInterval) -> Void)?

func function<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
    guard let handle, let symbol = dlsym(handle, name) else { return nil }
    return unsafeBitCast(symbol, to: type)
}

private let emissionLock = NSLock()

/// JSONSerialization raises an Objective-C exception on NaN or infinity,
/// which `try?` cannot catch. A player can report either for a live stream,
/// so such a number is left out; any other invalid value reads as an error.
func encodedReply(_ reply: [String: Any]) -> Data {
    let finite = reply.filter { ($0.value as? Double)?.isFinite != false }
    guard JSONSerialization.isValidJSONObject(finite),
          let data = try? JSONSerialization.data(withJSONObject: finite) else {
        return Data("{\"error\":\"json\"}".utf8)
    }
    return data
}

/// Where a song sampled `age` seconds ago is now, and the rate the island
/// moves it at. A player can update its rate a step late or never, so its own
/// playing state, when known, wins over a rate that contradicts it. The song
/// then holds still at the sample, or at `continuing`, where the last reply
/// had it while the player kept the same sample. A playing song without a
/// rate may be buffering, so it moves only once the player reports one.
func playbackPosition(elapsed: Double, age: TimeInterval, rate: Double, isPlaying: Bool?,
                      continuing: Double? = nil) -> (elapsed: Double, rate: Double) {
    let rate = max(0, rate)
    guard let isPlaying, isPlaying != (rate > 0) else { return (elapsed + age * rate, rate) }
    return (continuing ?? elapsed, 0)
}

/// Writes where `sample` puts the song into the reply. Any player's change
/// reads the followed one again, and a sample it has not replaced must not
/// send its song back to where that sample was taken.
func settlePosition(_ reply: inout [String: Any], sample: (elapsed: Double, timestamp: Date?),
                    revision: UUID?, now: Date = Date()) {
    let isPlaying = reply["isPlaying"] as? Bool
    let continuing = lastPosition.flatMap { last -> Double? in
        guard last.revision == revision, last.sample == sample.elapsed, last.timestamp == sample.timestamp else { return nil }
        return last.elapsed + max(0, now.timeIntervalSince(last.at)) * last.rate
    }
    let settled = playbackPosition(elapsed: sample.elapsed,
                                   age: sample.timestamp.map { max(0, now.timeIntervalSince($0)) } ?? 0,
                                   rate: reply["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0,
                                   isPlaying: isPlaying, continuing: continuing)
    reply["kMRMediaRemoteNowPlayingInfoElapsedTime"] = settled.elapsed
    if isPlaying != nil { reply["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = settled.rate }
    lastPosition = revision.map { ($0, sample.elapsed, sample.timestamp, settled.elapsed, settled.rate, now) }
}

func emit(_ reply: [String: Any]) {
    let data = encodedReply(reply)
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
    let selected = watching ? NotchNativePlayback.select() : nil
    // No player may report a change while the chosen source waits for its
    // next track. Read again when that wait ends, so the release shows.
    if watching, let release = NotchNativePlayback.pendingRelease { readAt?(release) }
    if watching, selected == nil {
        NotchNativePlayback.publish(nil)
        previousArtwork = nil
        emit(NotchNativePlayback.sourceReply.merging(["isPlaying": false]) { _, new in new })
        NotchNativeQueue.observe([:])
        return
    }
    let queue = DispatchQueue(label: "com.vorssaint.now-playing-adapter")
    let group = DispatchGroup()
    let lock = NSLock()
    var reply: [String: Any] = [:]
    var sample: (elapsed: Double, timestamp: Date?)?
    func set(_ key: String, _ value: Any?) {
        guard let value else { return }
        lock.lock()
        reply[key] = value
        lock.unlock()
    }

    group.enter()
    let receiveInfo: InfoCallback = { info in
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
            lock.lock()
            sample = (elapsed, info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date)
            lock.unlock()
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
    // The followed player's own state, which the system's Now Playing shows.
    // Some players update their rate a step late or never, so the rate alone
    // can read a paused song as playing. A missing answer only falls back to
    // the rate, so it gets its own short wait.
    let state = DispatchGroup()
    if let selected {
        NotchNativePlayback.readInfo(selected, artwork: true, queue: queue, completion: receiveInfo)
        set("pid", selected.pid)
        set("displayID", selected.applicationBundleIdentifier ?? selected.bundleIdentifier)
        state.enter()
        NotchNativePlayback.readPlaybackState(selected, queue: queue) { isPlaying in
            set("isPlaying", isPlaying)
            state.leave()
        }
    } else { getInfo(queue, receiveInfo) }
    if selected == nil, let getPID = function(handle, "MRMediaRemoteGetNowPlayingApplicationPID", as: PIDFunction.self) {
        group.enter()
        getPID(queue) { pid in
            set("pid", pid)
            group.leave()
        }
    }
    if selected == nil, let getDisplayID = function(handle, "MRMediaRemoteGetNowPlayingApplicationDisplayID",
                                   as: DisplayIDFunction.self) {
        group.enter()
        getDisplayID(queue) { identifier in
            set("displayID", identifier as String?)
            group.leave()
        }
    }
    if selected == nil, let getIsPlaying = function(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying",
                                   as: IsPlayingFunction.self) {
        group.enter()
        getIsPlaying(queue) { isPlaying in
            set("isPlaying", isPlaying)
            group.leave()
        }
    }
    // Only expose seeking when the current player advertises that command.
    // Missing symbols keep the timeline read-only without affecting playback.
    // Track skipping is reported the same way, so a player without a next or
    // previous command (a video, say) does not show buttons that do nothing.
    typealias CommandID = @convention(c) (AnyObject) -> Int32
    typealias CommandEnabled = @convention(c) (AnyObject) -> Bool
    let capabilities = DispatchGroup()
    if watching,
       let selected,
       let commandID = function(handle, "MRMediaRemoteCommandInfoGetCommand", as: CommandID.self),
       let commandEnabled = function(handle, "MRMediaRemoteCommandInfoGetEnabled", as: CommandEnabled.self) {
        capabilities.enter()
        NotchNativePlayback.supportedCommands(selected, queue: queue) { commands in
            func supports(_ command: Int32) -> Bool {
                commands?.contains(where: {
                    commandID($0 as AnyObject) == command && commandEnabled($0 as AnyObject)
                }) == true
            }
            if commands != nil {
                set("canPlay", supports(0))
                set("canPause", supports(1))
                set("canSeek", NotchNativePlayback.stringConstant("kMRMediaRemoteOptionPlaybackPosition") != nil && supports(24))
                set("canSkipNext", supports(4))
                set("canSkipPrevious", supports(5))
            }
            capabilities.leave()
            if commands != nil {
                lock.lock()
                let latest = reply
                lock.unlock()
                NotchNativePlayback.updatePlayPauseCommand(for: selected, info: latest)
            }
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
    _ = state.wait(timeout: .now() + 0.2)
    lock.lock()
    var snapshot = reply
    let position = sample
    lock.unlock()
    var revision: UUID?
    if watching, let context = NotchNativePlayback.publish(selected, info: snapshot) {
        revision = context.revision
        snapshot["playbackRevision"] = context.revision.uuidString
        snapshot["canSendCommandsDirectly"] = NotchNativePlayback.target.map {
            $0.allowsDirectCommands && ($0.itemIdentifier != nil || $0.requiresCurrentPlayer)
        } == true
    }
    if let position { settlePosition(&snapshot, sample: position, revision: revision) } else { lastPosition = nil }
    // Cover a callback that completed after the snapshot copy but before publish.
    if watching, let selected {
        lock.lock()
        let latest = reply
        lock.unlock()
        NotchNativePlayback.updatePlayPauseCommand(for: selected, info: latest)
    }
    if watching { snapshot.merge(NotchNativePlayback.sourceReply) { _, new in new } }
    emit(snapshot)
    if watching { NotchNativeQueue.observe(snapshot) }
}

/// One adapter process while a music surface is subscribed. Native change
/// notifications replace polling; closing stdin also ends it if the app exits.
@_cdecl("vorssaint_now_playing_watch_all")
public func vorssaintNowPlayingWatchAll() {
    NotchNativePlayback.includeOtherPlayers = true
    vorssaintNowPlayingWatch()
}

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
                 "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                 "kMRMediaRemotePlayerNowPlayingInfoDidChangeNotification",
                 "kMRMediaRemoteNowPlayingPlayerStateDidChange",
                 "kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
                 // Play and pause of any player, not only the system's current one.
                 "kMRMediaRemotePlayerIsPlayingDidChangeNotification"]
        // Its name differs from the symbol's (a leading underscore on 27.2).
        + [NotchNativePlayback.stringConstant("kMRMediaRemotePlayerPlaybackStateDidChangeNotification")].compactMap { $0 }
    func refresh() {
        pending?.cancel()
        let work = DispatchWorkItem { vorssaintNowPlayingGet() }
        pending = work
        reader.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
    readAt = { uptime in
        let delay = max(0, uptime - ProcessInfo.processInfo.systemUptime)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { refresh() }
    }
    let observers = names.map { name in
        NotificationCenter.default.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in refresh() }
    }
    let termination = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { _ in refresh() }
    var commandFramer = NotchPlaybackCommandFramer()
    FileHandle.standardInput.readabilityHandler = { input in
        let data = input.availableData
        if data.isEmpty { exit(0) }
        DispatchQueue.main.async {
            for command in commandFramer.append(data) {
                guard let command else { emit(["sent": false]); continue }
                reader.async { sendPlaybackCommand(command) }
            }
        }
    }
    reader.async { vorssaintNowPlayingGet() }
    withExtendedLifetime((observers, termination)) { RunLoop.main.run() }
}

private func sendPlaybackCommand(_ request: NotchPlaybackRequest) {
    let command = request.command
    switch command {
    case .source(let selection):
        NotchNativeQueue.configure(nil)
        NotchNativePlayback.choose(selection)
        vorssaintNowPlayingGet()
        return
    case .validate(let id, let context):
        emit(["validationRequest": id.uuidString,
              "validationOK": NotchNativePlayback.validatedTarget(for: context) != nil])
        return
    case .queue(let request): NotchNativeQueue.configure(request); return
    case .queueStop: NotchNativeQueue.configure(nil); return
    case .queuePlay(let selected): NotchNativeQueue.play(selected); return
    default: break
    }
    guard let context = request.context,
          let target = NotchNativePlayback.validatedTarget(for: context) else { emit(["sent": false]); return }
    let identifier: Int32
    var options: CFDictionary?
    switch command {
    case .toggle: identifier = target.playPauseCommand
    case .next: identifier = 4
    case .previous: identifier = 5
    case .seek(let position):
        guard let key = NotchNativePlayback.stringConstant("kMRMediaRemoteOptionPlaybackPosition") else {
            emit(["sent": false]); return
        }
        identifier = 24
        options = [key: position] as CFDictionary
    case .queue, .queueStop, .queuePlay, .validate, .source: return
    }
    emit(["sent": NotchNativePlayback.send(identifier, options: options, to: target)])
}
