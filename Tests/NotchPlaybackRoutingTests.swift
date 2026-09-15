// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ObjectiveC

/// The production adapter's read and send bodies are compiled here with a
/// recording transport. These tests never send commands to a real player.
enum NotchPlaybackRoutingContract {
    struct Target {
        var pid: Int32 = 10
        var bundleIdentifier = "test.player"
        let path: NSObject
        var isRunning = true
    }
    struct NSRunningApplication {
        let bundleIdentifier: String?
        let processIdentifier: Int32
        var isTerminated = false
    }
    static let handle: UnsafeMutableRawPointer? = nil
    static let callbacks = DispatchQueue(label: "notch-routing-test")
    static var available = true
    static var destination: AnyObject?
    static var command: Int32?
    static var options: CFDictionary?
    static var requestedArtwork = false

    typealias Read = @convention(c) (AnyObject, Bool, DispatchQueue,
        @escaping @convention(block) (NSDictionary?, UnsafeRawPointer?) -> Void) -> Void
    typealias Send = @convention(c) (Int32, CFDictionary?, AnyObject, UInt32, DispatchQueue,
        @escaping @convention(block) (UInt32, NSArray?) -> Void) -> Bool
    typealias Commands = @convention(c) (AnyObject, DispatchQueue, @escaping @convention(block) (NSArray?) -> Void) -> Void

    static func function<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
        guard available else { return nil }
        switch name {
        case "MRMediaRemoteGetNowPlayingInfoForPlayer":
            let read: Read = { path, artwork, _, completion in
                NotchPlaybackRoutingContract.destination = path
                NotchPlaybackRoutingContract.requestedArtwork = artwork
                completion(["kMRMediaRemoteNowPlayingInfoTitle": "Selected track"], nil)
            }
            return unsafeBitCast(read, to: T.self)
        case "MRMediaRemoteSendCommandToPlayer":
            let send: Send = { value, settings, path, _, _, completion in
                NotchPlaybackRoutingContract.destination = path
                NotchPlaybackRoutingContract.command = value
                NotchPlaybackRoutingContract.options = settings
                completion(0, nil)
                return true
            }
            return unsafeBitCast(send, to: T.self)
        case "MRMediaRemoteGetSupportedCommandsForPlayer":
            let commands: Commands = { path, _, completion in
                NotchPlaybackRoutingContract.destination = path
                completion([])
            }
            return unsafeBitCast(commands, to: T.self)
        default: return nil
        }
    }
}

enum NotchPlaybackRoutingTests {
    static func run(expect: (Bool, String) -> Void) {
        typealias Adapter = NotchPlaybackRoutingContract
        let musicPath = NSObject()
        let otherPath = NSObject()
        let music = Adapter.Target(path: musicPath)
        let other = Adapter.Target(path: otherPath)
        _ = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        let first = Adapter.makeTarget(Adapter.NSRunningApplication(bundleIdentifier: "test.music", processIdentifier: 101))
        let second = Adapter.makeTarget(Adapter.NSRunningApplication(bundleIdentifier: "test.video", processIdentifier: 202))
        expect(first != nil && second != nil && first?.path !== second?.path,
               "constructing a second destination never mutates the native path of the first player")
        let firstClient = first?.path.perform(NSSelectorFromString("client"))?.takeUnretainedValue() as? NSObject
        expect(firstClient?.value(forKey: "processIdentifier") as? Int == 101,
               "the first destination retains its process after another candidate is created")
        Adapter.available = true
        var title: String?
        Adapter.readInfo(music, artwork: true, queue: Adapter.callbacks) { info in
            title = info?["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        }
        expect(Adapter.destination === musicPath && title == "Selected track" && Adapter.requestedArtwork,
               "metadata and artwork are requested from the selected music path")
        Adapter.supportedCommands(music, queue: Adapter.callbacks) { _ in }
        expect(Adapter.destination === musicPath, "seek availability belongs to the selected player")
        for command: Int32 in [2, 4, 5, 24, 131] {
            let options = ["position": 37] as CFDictionary
            expect(Adapter.send(command, options: options, to: music), "the selected player accepts the transport request")
            expect(Adapter.destination === musicPath && Adapter.command == command
                   && (Adapter.options as? [String: Int])?["position"] == 37,
                   "playback, seeking and queue commands retain their selected destination and options")
        }
        _ = Adapter.send(2, to: other)
        expect(Adapter.destination === otherPath, "an explicit new selection changes the command destination")
        Adapter.destination = nil
        expect(!Adapter.send(2, to: Adapter.Target(path: musicPath, isRunning: false)) && Adapter.destination == nil,
               "a closed or replaced process never receives a command or falls back to the system player")
        Adapter.available = false
        expect(!Adapter.send(2, to: music) && Adapter.destination == nil,
               "a missing targeted transport never sends a global media command")
        var cleared = false
        Adapter.readInfo(music, artwork: false, queue: Adapter.callbacks) { cleared = $0 == nil }
        expect(cleared && Adapter.destination == nil, "an unavailable targeted reader clears the result without reading another player")
        Adapter.available = true
    }
}
