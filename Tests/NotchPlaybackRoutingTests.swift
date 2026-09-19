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
        var itemIdentifier: String? = "fixture"
        var allowsDirectCommands = true
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
    static var sendError: UInt32 = 0
    static var sendResponses: [NSNumber]? = [0]
    static let lock = NSLock()
    static var selected: Target?
    static var identity: Identity?
    static var context: NotchPlaybackContext?
    static var metadata: [ObjectIdentifier: [String: Any]] = [:]
    static var beforeRead: (() -> Void)?
    static var reply: [String: Any] = [:]
    typealias NotchNativePlayback = NotchPlaybackRoutingContract
    enum NotchNativeQueue {
        static var request: UUID?
        static var selection: NotchQueueSelection?
        static func configure(_ id: UUID?) { request = id }
        static func play(_ item: NotchQueueSelection) { selection = item }
    }
    static func emit(_ value: [String: Any]) { reply = value }
    static func stringConstant(_ name: String) -> String? { name }

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
                NotchPlaybackRoutingContract.beforeRead?()
                completion((NotchPlaybackRoutingContract.metadata[ObjectIdentifier(path)]
                            ?? ["kMRMediaRemoteNowPlayingInfoTitle": "Selected track"]) as NSDictionary, nil)
            }
            return unsafeBitCast(read, to: T.self)
        case "MRMediaRemoteSendCommandToPlayer":
            let send: Send = { value, settings, path, _, _, completion in
                NotchPlaybackRoutingContract.destination = path
                NotchPlaybackRoutingContract.command = value
                NotchPlaybackRoutingContract.options = settings
                completion(NotchPlaybackRoutingContract.sendError, NotchPlaybackRoutingContract.sendResponses as NSArray?)
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
                   && (Adapter.options as? [String: Any])?["position"] as? Int == 37
                   && (Adapter.options as? [String: Any])?["kMRMediaRemoteOptionNowPlayingContentItemID"] as? String == "fixture",
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
        Adapter.sendError = 7
        expect(!Adapter.send(2, to: music), "a rejected native command is not reported as delivered")
        Adapter.sendError = 0
        Adapter.sendResponses = nil
        expect(!Adapter.send(2, to: music), "a native send without a handler result cannot claim delivery")
        Adapter.sendResponses = [0]
        var unavailable = music
        unavailable.allowsDirectCommands = false
        Adapter.command = nil
        expect(!Adapter.send(2, to: unavailable) && Adapter.command == nil,
               "an unsupported native target never falls back to the global player's transport")
        var unidentified = music
        unidentified.itemIdentifier = nil
        expect(!Adapter.send(2, to: unidentified) && Adapter.command == nil,
               "native commands require the receiver's content identity")
        recordingContext(expect: expect)
    }

    private static func recordingContext(expect: (Bool, String) -> Void) {
        typealias Adapter = NotchPlaybackRoutingContract
        let musicPath = NSObject(), otherPath = NSObject()
        let music = Adapter.Target(pid: 10, path: musicPath)
        let other = Adapter.Target(pid: 20, path: otherPath)
        func info(_ item: String?, title: String = "Same visible title") -> [String: Any] {
            var value: [String: Any] = ["kMRMediaRemoteNowPlayingInfoTitle": title,
                                       "kMRMediaRemoteNowPlayingInfoDuration": 180]
            value["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] = item
            return value
        }
        func prepare(_ target: Adapter.Target, _ value: [String: Any]) -> NotchPlaybackContext {
            Adapter.metadata[ObjectIdentifier(target.path)] = value
            return Adapter.publish(target, info: value)!
        }
        func send(_ command: NotchPlaybackCommand, _ context: NotchPlaybackContext) -> Bool {
            Adapter.command = nil
            Adapter.sendPlaybackCommand(NotchPlaybackRequest(command: command, context: context))
            return Adapter.command != nil
        }
        defer {
            Adapter.beforeRead = nil
            Adapter.metadata = [:]
            Adapter.publish(nil)
        }
        let first = prepare(music, info("A"))
        let validation = UUID()
        Adapter.command = nil
        Adapter.sendPlaybackCommand(NotchPlaybackRequest(command: .validate(validation, first)))
        expect(Adapter.reply["validationRequest"] as? String == validation.uuidString
               && Adapter.reply["validationOK"] as? Bool == true && Adapter.command == nil,
               "automation validation checks context without sending a playback command")
        expect(Adapter.publish(music, info: info("A")) == first,
               "ordinary updates of an identified recording keep its control revision stable")
        for command in [NotchPlaybackCommand.toggle, .next, .previous, .seek(75)] {
            expect(send(command, first) && Adapter.destination === musicPath,
                   "stable commands validate and reach the displayed recording without selecting another source")
        }
        let otherContext = prepare(other, info("B"))
        for command in [NotchPlaybackCommand.toggle, .next, .previous, .seek(75)] {
            expect(!send(command, first), "pending controls cannot be redirected after the chosen process changes")
        }
        expect(send(.toggle, otherContext), "a deliberate new snapshot can control its own process")
        let current = prepare(music, info("A"))
        let next = prepare(music, info("C"))
        expect(current != next && !send(.seek(90), current),
               "a new item with identical title and process cannot inherit an old scrub")

        let beforeNativeChange = prepare(music, info("A"))
        Adapter.metadata[ObjectIdentifier(musicPath)] = info("C")
        expect(!send(.seek(90), beforeNativeChange),
               "a player change preceding its notification is detected by fresh metadata before sending")
        Adapter.metadata[ObjectIdentifier(musicPath)] = info("A")
        Adapter.beforeRead = { _ = prepare(other, info("B")) }
        expect(!send(.next, beforeNativeChange), "a selection changed during validation cannot authorize the old action")
        Adapter.beforeRead = nil

        let noID = prepare(music, info(nil))
        expect(Adapter.validatedTarget(for: noID) != nil && !send(.seek(30), noID),
               "a player without content identifiers can be validated for automation but is not sent an unsafe native command")
        var progress = info(nil)
        progress["kMRMediaRemoteNowPlayingInfoElapsedTime"] = 45
        progress["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 0
        let refreshed = prepare(music, progress)
        expect(noID == refreshed && Adapter.validatedTarget(for: noID) != nil,
               "position and play/pause updates without an item ID preserve an ongoing scrub")
        Adapter.metadata[ObjectIdentifier(musicPath)] = info(nil, title: "Changed recording")
        expect(!send(.seek(30), refreshed), "unidentified playback also compares fresh recording metadata")
        let changedNoID = prepare(music, info(nil, title: "Changed recording"))
        expect(changedNoID != refreshed && Adapter.validatedTarget(for: refreshed) == nil
               && Adapter.validatedTarget(for: changedNoID) != nil,
               "an observable recording change without an item ID advances the revision and rejects an old gesture")
        let stopped = prepare(Adapter.Target(pid: 10, path: musicPath, isRunning: false), info("A"))
        expect(!send(.toggle, stopped), "terminated players cannot receive a validated action")

        let request = UUID()
        let selection = NotchQueueSelection(requestID: request, pid: 10, currentIdentifier: "A", itemIdentifier: "B", offset: 1)
        Adapter.sendPlaybackCommand(NotchPlaybackRequest(command: .queue(request)))
        Adapter.sendPlaybackCommand(NotchPlaybackRequest(command: .queuePlay(selection)))
        expect(Adapter.NotchNativeQueue.request == request && Adapter.NotchNativeQueue.selection == selection,
               "queue queries and their immutable selections retain their existing native route")
        Adapter.sendPlaybackCommand(NotchPlaybackRequest(command: .queueStop))
        expect(Adapter.NotchNativeQueue.request == nil, "queue-stop still cancels without requiring a playing track")
    }
}
