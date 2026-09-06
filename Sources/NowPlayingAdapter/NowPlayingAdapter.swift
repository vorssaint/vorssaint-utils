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

private func function<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
    guard let handle, let symbol = dlsym(handle, name) else { return nil }
    return unsafeBitCast(symbol, to: type)
}

private func emit(_ reply: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{\"error\":\"json\"}".utf8)
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
        for key in ["kMRMediaRemoteNowPlayingInfoTitle",
                    "kMRMediaRemoteNowPlayingInfoArtist",
                    "kMRMediaRemoteNowPlayingInfoAlbum"] {
            set(key, info[key] as? String)
        }
        set("kMRMediaRemoteNowPlayingInfoPlaybackRate",
            (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? NSNumber)?.doubleValue)
        if let artwork = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
           !artwork.isEmpty, artwork.count <= maximumArtworkBytes {
            set("artworkBase64", artwork.base64EncodedString())
        }
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

    // Blocks until every callback has fired. The only deadline is the app's:
    // the bridge kills perl at its own timeout, and a killed run reads as
    // nothing playing, so a second clock here would only shorten that budget.
    group.wait()
    lock.lock()
    let snapshot = reply
    lock.unlock()
    emit(snapshot)
}
