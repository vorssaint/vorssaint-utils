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
        var requiresCurrentPlayer = false
        var applicationBundleIdentifier: String?
    }
    struct NSRunningApplication {
        let bundleIdentifier: String?
        let processIdentifier: Int32
        var isTerminated = false
        var localizedName: String? { bundleIdentifier }
        init(bundleIdentifier: String?, processIdentifier: Int32) {
            self.bundleIdentifier = bundleIdentifier
            self.processIdentifier = processIdentifier
        }
        init?(processIdentifier: Int32) {
            guard let app = NotchPlaybackRoutingContract.applications.first(where: { $0.processIdentifier == processIdentifier }) else { return nil }
            self = app
        }
    }
    struct NSWorkspace {
        static let shared = Self()
        var runningApplications: [NSRunningApplication] { NotchPlaybackRoutingContract.applications }
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
    static var sources: [NotchPlaybackSource] = []
    static var selection: NotchPlaybackSource.Selection?
    static var releaseAt: TimeInterval?
    /// Stands in for the system uptime read by the extracted selection.
    static var uptime: TimeInterval = 0
    static var refreshes = 0
    static var discovering = false
    static var applications: [NSRunningApplication] = []
    static var registeredPIDs: [Int32] = []
    static var systemPID: Int32 = 10
    static var sourceMetadata: [Int32: [String: Any]] = [:]
    static var silentPIDs: Set<Int32> = []
    static var lateReads: [() -> Void] = []
    static func isMusicApp(_ app: NSRunningApplication) -> Bool { app.processIdentifier == 10 }
    static func vorssaintNowPlayingGet() { refreshes += 1 }
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
        case "MRMediaRemoteGetNowPlayingClient":
            let read: @convention(c) (DispatchQueue, @escaping @convention(block) (AnyObject?) -> Void) -> Void = { _, completion in
                completion(NSNumber(value: NotchPlaybackRoutingContract.systemPID))
            }
            return unsafeBitCast(read, to: T.self)
        case "MRMediaRemoteGetNowPlayingClients":
            let read: @convention(c) (DispatchQueue, @escaping @convention(block) (NSArray?) -> Void) -> Void = { _, completion in
                completion(NotchPlaybackRoutingContract.registeredPIDs.map { NSNumber(value: $0) } as NSArray)
            }
            return unsafeBitCast(read, to: T.self)
        case "MRNowPlayingClientGetProcessIdentifier":
            let pid: @convention(c) (AnyObject) -> Int32 = { ($0 as! NSNumber).int32Value }
            return unsafeBitCast(pid, to: T.self)
        case "MRMediaRemoteGetNowPlayingInfoForPlayer":
            let read: Read = { path, artwork, _, completion in
                if NotchPlaybackRoutingContract.discovering {
                    let client = path.perform(NSSelectorFromString("client"))?.takeUnretainedValue() as? NSObject
                    let pid = (client?.value(forKey: "processIdentifier") as? NSNumber)?.int32Value ?? 0
                    let info = (NotchPlaybackRoutingContract.sourceMetadata[pid] ?? [:]) as NSDictionary
                    if NotchPlaybackRoutingContract.silentPIDs.contains(pid) {
                        NotchPlaybackRoutingContract.lateReads.append { completion(info, nil) }
                    } else { completion(info, nil) }
                    return
                }
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
    static func run(_ suite: TestSuite) {
        typealias Adapter = NotchPlaybackRoutingContract
        let musicPath = NSObject()
        let otherPath = NSObject()
        let music = Adapter.Target(path: musicPath)
        let other = Adapter.Target(path: otherPath)
        _ = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        let first = Adapter.makeTarget(Adapter.NSRunningApplication(bundleIdentifier: "test.music", processIdentifier: 101))
        let second = Adapter.makeTarget(Adapter.NSRunningApplication(bundleIdentifier: "test.video", processIdentifier: 202))
        suite.expect(first != nil && second != nil && first?.path !== second?.path,
               "constructing a second destination never mutates the native path of the first player")
        let firstClient = first?.path.perform(NSSelectorFromString("client"))?.takeUnretainedValue() as? NSObject
        suite.expect(firstClient?.value(forKey: "processIdentifier") as? Int == 101,
               "the first destination retains its process after another candidate is created")
        Adapter.available = true
        var title: String?
        Adapter.readInfo(music, artwork: true, queue: Adapter.callbacks) { info in
            title = info?["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        }
        suite.expect(Adapter.destination === musicPath && title == "Selected track" && Adapter.requestedArtwork,
               "metadata and artwork are requested from the selected music path")
        Adapter.supportedCommands(music, queue: Adapter.callbacks) { _ in }
        suite.expect(Adapter.destination === musicPath, "seek availability belongs to the selected player")
        for command: Int32 in [2, 4, 5, 24, 131] {
            let options = ["position": 37] as CFDictionary
            suite.expect(Adapter.send(command, options: options, to: music), "the selected player accepts the transport request")
            suite.expect(Adapter.destination === musicPath && Adapter.command == command
                   && (Adapter.options as? [String: Any])?["position"] as? Int == 37
                   && (Adapter.options as? [String: Any])?["kMRMediaRemoteOptionNowPlayingContentItemID"] as? String == "fixture",
                   "playback, seeking and queue commands retain their selected destination and options")
        }
        _ = Adapter.send(2, to: other)
        suite.expect(Adapter.destination === otherPath, "an explicit new selection changes the command destination")
        Adapter.destination = nil
        suite.expect(!Adapter.send(2, to: Adapter.Target(path: musicPath, isRunning: false)) && Adapter.destination == nil,
               "a closed or replaced process never receives a command or falls back to the system player")
        Adapter.available = false
        suite.expect(!Adapter.send(2, to: music) && Adapter.destination == nil,
               "a missing targeted transport never sends a global media command")
        var cleared = false
        Adapter.readInfo(music, artwork: false, queue: Adapter.callbacks) { cleared = $0 == nil }
        suite.expect(cleared && Adapter.destination == nil, "an unavailable targeted reader clears the result without reading another player")
        Adapter.available = true
        Adapter.sendError = 7
        suite.expect(!Adapter.send(2, to: music), "a rejected native command is not reported as delivered")
        Adapter.sendError = 0
        Adapter.sendResponses = nil
        suite.expect(!Adapter.send(2, to: music), "a native send without a handler result cannot claim delivery")
        Adapter.sendResponses = [0]
        var unavailable = music
        unavailable.allowsDirectCommands = false
        Adapter.command = nil
        suite.expect(!Adapter.send(2, to: unavailable) && Adapter.command == nil,
               "an unsupported native target never falls back to the global player's transport")
        var unidentified = music
        unidentified.itemIdentifier = nil
        suite.expect(!Adapter.send(2, to: unidentified) && Adapter.command == nil,
               "native commands require the receiver's content identity")
        unidentified.requiresCurrentPlayer = true
        suite.expect(Adapter.send(2, to: unidentified) && Adapter.destination === musicPath
                     && Adapter.options == nil,
                     "the current video can receive play/pause without a content identifier")
        Adapter.systemPID = 20
        Adapter.command = nil
        suite.expect(!Adapter.send(2, to: unidentified) && Adapter.command == nil,
                     "a video that lost the system session cannot send to the new global player")
        Adapter.systemPID = 10
        replyEncoding(suite)
        recordingContext(suite)
    }

    /// JSONSerialization raises an exception `try?` cannot catch on NaN or
    /// infinity, which would end the adapter mid-reply.
    private static func replyEncoding(_ suite: TestSuite) {
        typealias Adapter = NotchPlaybackRoutingContract
        let reply: [String: Any] = ["kMRMediaRemoteNowPlayingInfoDuration": Double.infinity,
                                    "kMRMediaRemoteNowPlayingInfoElapsedTime": Double.nan,
                                    "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1.0,
                                    "pid": Int32(20)]
        let decoded = (try? JSONSerialization.jsonObject(with: Adapter.encodedReply(reply))) as? [String: Any]
        suite.expect(decoded?.count == 2 && decoded?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double == 1,
                     "a live stream's non-finite duration or position is left out of an otherwise intact reply")
        let nested: [String: Any] = ["sources": [["pid": -Double.infinity]]]
        let fallback = String(data: Adapter.encodedReply(nested), encoding: .utf8)
        suite.expect(fallback == "{\"error\":\"json\"}", "any other invalid value reads as an error instead of ending the adapter")
    }

    private static func recordingContext(_ suite: TestSuite) {
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
        suite.expect(Adapter.reply["validationRequest"] as? String == validation.uuidString
               && Adapter.reply["validationOK"] as? Bool == true && Adapter.command == nil,
               "automation validation checks context without sending a playback command")
        suite.expect(Adapter.publish(music, info: info("A")) == first,
               "ordinary updates of an identified recording keep its control revision stable")
        for command in [NotchPlaybackCommand.toggle, .next, .previous, .seek(75)] {
            suite.expect(send(command, first) && Adapter.destination === musicPath,
                   "stable commands validate and reach the displayed recording without selecting another source")
        }
        let otherContext = prepare(other, info("B"))
        for command in [NotchPlaybackCommand.toggle, .next, .previous, .seek(75)] {
            suite.expect(!send(command, first), "pending controls cannot be redirected after the chosen process changes")
        }
        suite.expect(send(.toggle, otherContext), "a deliberate new snapshot can control its own process")
        let current = prepare(music, info("A"))
        let next = prepare(music, info("C"))
        suite.expect(current != next && !send(.seek(90), current),
               "a new item with identical title and process cannot inherit an old scrub")

        let beforeNativeChange = prepare(music, info("A"))
        Adapter.metadata[ObjectIdentifier(musicPath)] = info("C")
        suite.expect(!send(.seek(90), beforeNativeChange),
               "a player change preceding its notification is detected by fresh metadata before sending")
        Adapter.metadata[ObjectIdentifier(musicPath)] = info("A")
        Adapter.beforeRead = { _ = prepare(other, info("B")) }
        suite.expect(!send(.next, beforeNativeChange), "a selection changed during validation cannot authorize the old action")
        Adapter.beforeRead = nil

        let noID = prepare(music, info(nil))
        suite.expect(Adapter.validatedTarget(for: noID) != nil && !send(.seek(30), noID),
               "a player without content identifiers can be validated for automation but is not sent an unsafe native command")
        var progress = info(nil)
        progress["kMRMediaRemoteNowPlayingInfoElapsedTime"] = 45
        progress["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 0
        let refreshed = prepare(music, progress)
        suite.expect(noID == refreshed && Adapter.validatedTarget(for: noID) != nil,
               "position and play/pause updates without an item ID preserve an ongoing scrub")
        Adapter.metadata[ObjectIdentifier(musicPath)] = info(nil, title: "Changed recording")
        suite.expect(!send(.seek(30), refreshed), "unidentified playback also compares fresh recording metadata")
        let changedNoID = prepare(music, info(nil, title: "Changed recording"))
        suite.expect(changedNoID != refreshed && Adapter.validatedTarget(for: refreshed) == nil
               && Adapter.validatedTarget(for: changedNoID) != nil,
               "an observable recording change without an item ID advances the revision and rejects an old gesture")
        let stopped = prepare(Adapter.Target(pid: 10, path: musicPath, isRunning: false), info("A"))
        suite.expect(!send(.toggle, stopped), "terminated players cannot receive a validated action")

        let request = UUID()
        let selection = NotchQueueSelection(requestID: request, pid: 10, currentIdentifier: "A", itemIdentifier: "B", offset: 1)
        Adapter.sendPlaybackCommand(NotchPlaybackRequest(command: .queue(request)))
        Adapter.sendPlaybackCommand(NotchPlaybackRequest(command: .queuePlay(selection)))
        suite.expect(Adapter.NotchNativeQueue.request == request && Adapter.NotchNativeQueue.selection == selection,
               "queue queries and their immutable selections retain their existing native route")
        Adapter.sendPlaybackCommand(NotchPlaybackRequest(command: .queueStop))
        suite.expect(Adapter.NotchNativeQueue.request == nil, "queue-stop still cancels without requiring a playing track")

        let browser = NotchPlaybackSource(pid: 202, bundleIdentifier: "test.browser", isMusicApp: false,
                                          isPlaying: true, hasTrack: true)
        Adapter.sources = [browser]
        Adapter.NotchNativeQueue.request = UUID()
        Adapter.command = nil
        Adapter.sendPlaybackCommand(NotchPlaybackRequest(command: .source(browser.selection)))
        suite.expect(Adapter.selection == browser.selection && Adapter.refreshes == 1
                     && Adapter.NotchNativeQueue.request == nil && Adapter.command == nil,
                     "choosing a source refreshes metadata and retires its old queue without changing playback")
        Adapter.choose(.init(pid: 202, bundleIdentifier: "unrelated.app"))
        suite.expect(Adapter.selection == browser.selection, "a reused PID cannot select an undiscovered application")
        Adapter.sendPlaybackCommand(NotchPlaybackRequest(command: .source(nil)))
        suite.expect(Adapter.selection == nil && Adapter.refreshes == 2,
                     "automatic source selection can be restored without sending a transport command")
        Adapter.sources = []
        sourceDiscovery(suite)
    }

    private static func sourceDiscovery(_ suite: TestSuite) {
        typealias Adapter = NotchPlaybackRoutingContract
        Adapter.discovering = true
        Adapter.selected = nil
        Adapter.selection = nil
        Adapter.available = true
        Adapter.applications = [10, 20, 30].map {
            Adapter.NSRunningApplication(bundleIdentifier: "test.player.\($0)", processIdentifier: $0)
        }
        Adapter.registeredPIDs = [10, 20, 30]
        Adapter.systemPID = 10
        Adapter.sourceMetadata = Dictionary(uniqueKeysWithValues: [Int32(10), 20, 30].map {
            ($0, ["kMRMediaRemoteNowPlayingInfoTitle": "Track \($0)", "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1] as [String: Any])
        })
        defer {
            Adapter.lateReads.forEach { $0() }
            Adapter.lateReads = []
            Adapter.silentPIDs = []
            Adapter.discovering = false
            Adapter.sources = []
            Adapter.selection = nil
            Adapter.selected = nil
            Adapter.releaseAt = nil
            Adapter.uptime = 0
        }
        _ = Adapter.select()
        let browser = NotchPlaybackSource.Selection(pid: 20, bundleIdentifier: "test.player.20")
        Adapter.sourceMetadata[10]?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 0
        Adapter.systemPID = 20
        suite.expect(Adapter.select()?.requiresCurrentPlayer == true && Adapter.select()?.allowsDirectCommands == true,
                     "the active video exposes native controls without Automation")
        Adapter.systemPID = 10
        Adapter.choose(browser)
        suite.expect(Adapter.select()?.requiresCurrentPlayer == false && Adapter.select()?.allowsDirectCommands == false,
                     "a chosen video outside the system session does not expose redirected native controls")
        Adapter.sourceMetadata[10]?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 1
        Adapter.selected = Adapter.select()
        Adapter.silentPIDs = [30]
        suite.expect(Adapter.select()?.pid == 20 && Adapter.selection == browser && Adapter.sources.count == 2,
                     "an unrelated client timeout preserves the chosen source and other completed reads")
        Adapter.silentPIDs = [20]
        suite.expect(Adapter.select() == nil && Adapter.selection == browser
                     && Adapter.sourceReply["sourceIsAutomatic"] as? Bool == false,
                     "a chosen source timeout exposes no stale controls and keeps the manual choice")
        Adapter.publish(nil)
        Adapter.silentPIDs = []
        Adapter.registeredPIDs = [10, 30]
        suite.expect(Adapter.select()?.pid == 20,
                     "a manual source is queried again after a timeout even if enumeration omits it")
        Adapter.lateReads.forEach { $0() }
        Adapter.lateReads = []
        suite.expect(Adapter.selection == browser && Adapter.sources.contains(where: { $0.selection == browser }),
                     "late callbacks cannot replace a completed discovery or its choice")
        Adapter.available = false
        suite.expect(Adapter.select() == nil && Adapter.selection == browser && Adapter.sources.isEmpty,
                     "a failed discovery clears unavailable rows without resetting the manual choice")
        Adapter.available = true
        suite.expect(Adapter.select()?.pid == 20, "discovery recovery restores the chosen source")
        // A browser clears its track between videos.
        Adapter.sourceMetadata[20] = [:]
        suite.expect(Adapter.select()?.pid == 10 && Adapter.selection == browser,
                     "a chosen source without a track keeps the choice while the automatic player shows")
        suite.expect(Adapter.sources.contains(where: { $0.pid == 20 && !$0.hasTrack })
                     && Adapter.sourceReply["selectedPID"] as? Int32 == 20,
                     "the chooser keeps the chosen row and its mark while it waits for a track")
        Adapter.uptime = 4
        Adapter.sourceMetadata[20] = ["kMRMediaRemoteNowPlayingInfoTitle": "Next video"]
        suite.expect(Adapter.select()?.pid == 20 && Adapter.selection == browser,
                     "the chosen source shows again with its next track")
        Adapter.sourceMetadata[20] = [:]
        _ = Adapter.select()
        Adapter.uptime = 8
        suite.expect(Adapter.select()?.pid == 10 && Adapter.selection == browser,
                     "a track seen again restarts the five-second wait")
        Adapter.uptime = 9
        suite.expect(Adapter.select()?.pid == 10 && Adapter.selection == nil
                     && !Adapter.sources.contains(where: { $0.pid == 20 }),
                     "a chosen source still without a track after five seconds releases the choice")
        Adapter.registeredPIDs = [10, 20, 30]
        Adapter.sourceMetadata[20] = ["kMRMediaRemoteNowPlayingInfoTitle": "Browser track"]
        _ = Adapter.select()
        Adapter.choose(browser)
        Adapter.sourceMetadata[20] = [:]
        suite.expect(Adapter.select()?.pid == 10 && Adapter.selection == browser,
                     "choosing a released source again starts a fresh wait")
        Adapter.uptime = 13
        Adapter.choose(.init(pid: 30, bundleIdentifier: "test.player.30"))
        Adapter.sourceMetadata[30] = [:]
        Adapter.uptime = 15
        suite.expect(Adapter.select()?.pid == 10 && Adapter.selection?.pid == 30,
                     "a new choice starts its own wait instead of inheriting the previous one")
        Adapter.sourceMetadata[30] = ["kMRMediaRemoteNowPlayingInfoTitle": "Track 30", "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1]
        Adapter.sourceMetadata[20] = ["kMRMediaRemoteNowPlayingInfoTitle": "Browser track"]
        Adapter.registeredPIDs = [10, 20, 30]
        _ = Adapter.select()
        Adapter.choose(browser)
        Adapter.applications[1] = .init(bundleIdentifier: "test.reused.pid", processIdentifier: 20)
        suite.expect(Adapter.select()?.pid == 10 && Adapter.selection == nil,
                     "a reused process identifier cannot retain another application's manual selection")
        Adapter.applications[1] = .init(bundleIdentifier: browser.bundleIdentifier, processIdentifier: browser.pid)
        _ = Adapter.select()
        Adapter.choose(browser)
        Adapter.applications.removeAll { $0.processIdentifier == 20 }
        suite.expect(Adapter.select()?.pid == 10 && Adapter.selection == nil,
                     "closing the selected application restores automatic selection")
        Adapter.applications.removeAll { $0.processIdentifier == 10 }
        Adapter.systemPID = 99
        Adapter.applications.append(.init(bundleIdentifier: "test.private.browser", processIdentifier: 99))
        suite.expect(Adapter.select() == nil && Adapter.sources.map(\.pid) == [30],
                     "discovered sources remain available when the global player has no metadata")
        Adapter.choose(.init(pid: 30, bundleIdentifier: "test.player.30"))
        suite.expect(Adapter.select()?.pid == 30, "an empty automatic result can be recovered by choosing a discovered source")

        // Sixteen registered clients plus one music app exceed the bound.
        let crowd = (Int32(100)...115).map { $0 }
        Adapter.selection = nil
        Adapter.applications = ([10] + crowd).map {
            Adapter.NSRunningApplication(bundleIdentifier: "test.player.\($0)", processIdentifier: $0)
        }
        Adapter.registeredPIDs = crowd
        Adapter.systemPID = 10
        Adapter.sourceMetadata = Dictionary(uniqueKeysWithValues: ([10] + crowd).map {
            ($0, ["kMRMediaRemoteNowPlayingInfoTitle": "Track \($0)"] as [String: Any])
        })
        Adapter.sourceMetadata[10]?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 1
        suite.expect(Adapter.select()?.pid == 10 && Adapter.sources.count == 16,
                     "more candidates than the bound still yield the playing music app")
        Adapter.selection = .init(pid: 115, bundleIdentifier: "test.player.115")
        suite.expect(Adapter.select()?.pid == 115, "a chosen source enumerated last keeps its place in the bound")
        Adapter.selection = nil
        Adapter.systemPID = 115
        Adapter.sourceMetadata[10]?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 0
        Adapter.sourceMetadata[115]?["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 1
        suite.expect(Adapter.select()?.pid == 115,
                     "the system's current player enumerated last keeps its place in the bound")
    }
}
