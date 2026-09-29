// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices

/// Only the permission system, scheduling and final Apple Event delivery are
/// doubles. The production command/validation/cancellation bodies are generated.
enum NotchMusicAutomationFlowContract {
    typealias Scheduler = NotchMusicCommandContract.Scheduler
    enum DispatchQueue {
        static var main = Scheduler()
        static var worker = Scheduler()
        static func global(qos: DispatchQoS.QoSClass) -> Scheduler { worker }
    }
    enum AppleScriptRunner {
        static var prompts: [String] = []
        static func consentToAutomate(bundleID: String) -> Bool { prompts.append(bundleID); return true }
    }
    enum NotchMusicAutomation {
        enum Access { case granted, consent, denied, unavailable }
        struct Target: Equatable {
            let pid: Int32
            var bundleIdentifier = "local.test.player"
            var isCurrent: Bool { alive }
        }
        struct Availability {
            let target: Target
            let capabilities: NotchMusicAutomationCapabilities
            let access: Access
        }
        static var alive = true
        static var permission = Access.granted
        static var deliveries: [(NotchPlaybackCommand, Int32)] = []
        static func access(to target: Target) -> Access { permission }
        static var capabilities: NotchMusicAutomationCapabilities?
        static var inspections = 0
        static func inspect(_ target: Target) -> Availability? {
            inspections += 1
            return capabilities.map { Availability(target: target, capabilities: $0, access: permission) }
        }
        struct Event {
            enum Option { case waitForReply, neverInteract, dontRecord }
            let command: NotchPlaybackCommand
            let pid: Int32
            func sendEvent(options: [Option], timeout: TimeInterval) throws -> NSAppleEventDescriptor {
                deliveries.append((command, pid))
                return NSAppleEventDescriptor.record()
            }
        }
        static func event(_ command: NotchPlaybackCommand, playback: NotchPlayback,
                          capabilities: NotchMusicAutomationCapabilities, pid: Int32) -> Event? {
            Event(command: command, pid: pid)
        }
    }
    static func reset() {
        DispatchQueue.main = Scheduler(); DispatchQueue.worker = Scheduler()
        AppleScriptRunner.prompts = []
        NotchMusicAutomation.alive = true
        NotchMusicAutomation.permission = .granted
        NotchMusicAutomation.deliveries = []
        NotchMusicAutomation.capabilities = nil
        NotchMusicAutomation.inspections = 0
    }
}

extension NotchMusicAutomationFlowContract.NotchMusicAutomation.Target {
    init?(_ playback: NotchPlayback) {
        guard let pid = playback.track.appPID else { return nil }
        self.init(pid: pid)
    }
}

enum NotchMusicAutomationTests {
    private static let dictionary = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
    <dictionary><suite name="Playback" code="TEST">
      <command name="playpause" code="ABCDtogl"/>
      <command name="next track" code="EFGHnext"/>
      <command name="previous track" code="IJKLprev"/>
      <class name="application" code="capp"><property name="player position" code="time" type="real"/></class>
    </suite></dictionary>
    """

    private static func playback() -> NotchPlayback {
        let track = RadialNowPlayingSnapshot(title: "Recording", artist: "Artist", album: "Album", artworkData: nil,
                                            appBundleIdentifier: "local.test.player", appPID: 42)
        return NotchPlayback(track: track, isPlaying: true, elapsed: 3, duration: 180, rate: 1, sampledAt: Date(),
                             canSeek: false, itemIdentifier: "one", commandContext: .init(pid: 42, revision: UUID()))
    }

    static func run(_ suite: TestSuite) {
        parsing(suite)
        descriptors(suite)
        lifecycle(suite)
        refresh(suite)
    }

    private static func parsing(_ suite: TestSuite) {
        func parse(_ source: String) -> NotchMusicAutomationCapabilities? { .parse(Data(source.utf8)) }
        let result = parse(dictionary)
        suite.expect(result?.commands["playpause"] == .init(eventClass: 0x41424344, eventID: 0x746F676C),
               "event codes come from the installed dictionary instead of a product-specific table")
        suite.expect(result?.canToggle == true && result?.position?.code == 0x74696D65,
               "declared playback controls and a writable application position are discoverable")
        let required = dictionary.replacingOccurrences(of: "<command name=\"next track\" code=\"EFGHnext\"/>",
            with: "<command name=\"next track\" code=\"EFGHnext\"><direct-parameter type=\"file\"/></command>")
        suite.expect(parse(required)?.commands["next track"] == nil, "commands requiring an argument cannot receive an incomplete playback action")
        let unrelated = dictionary.replacingOccurrences(of: "name=\"playpause\"", with: "name=\"delete\"")
        suite.expect(parse(unrelated)?.canToggle == false, "unrelated commands never become playback controls")
        for changed in [dictionary.replacingOccurrences(of: "type=\"real\"", with: "type=\"file\""),
                        dictionary.replacingOccurrences(of: "type=\"real\"", with: "type=\"real\" access=\"r\""),
                        dictionary.replacingOccurrences(of: "class name=\"application\"", with: "class name=\"track\"")] {
            suite.expect(parse(changed)?.position == nil, "only a numeric writable property of the application can seek")
        }
        let duplicate = dictionary.replacingOccurrences(of: "</suite>", with: "<command name=\"playpause\" code=\"abcdabcd\"/></suite>")
        suite.expect(parse(duplicate)?.commands["playpause"] == nil, "ambiguous command names fail closed")
        let playPause = dictionary.replacingOccurrences(of: "<command name=\"playpause\" code=\"ABCDtogl\"/>",
            with: "<command name=\"play\" code=\"abcdplay\"><direct-parameter optional=\"yes\"/></command><command name=\"pause\" code=\"abcdpaus\"/>")
        suite.expect(parse(playPause)?.canToggle == true
               && parse(playPause)?.event(for: .toggle, isPlaying: true)?.eventID == 0x70617573,
               "optional play arguments are omitted and a playing snapshot chooses its declared pause operation")
        suite.expect(parse(playPause)?.playCommand?.eventID == 0x706C6179
               && result?.playCommand?.eventID == 0x746F676C
               && parse(unrelated)?.playCommand == nil,
               "starting playback prefers the declared play command and falls back to the toggle alone")
        suite.expect(MusicLaunchSupport.playbackNeverArrived(-600)
               && MusicLaunchSupport.playbackNeverArrived(-609)
               && !MusicLaunchSupport.playbackNeverArrived(-1712)
               && !MusicLaunchSupport.playbackNeverArrived(-1743)
               && !MusicLaunchSupport.playbackNeverArrived(0),
               "a play command is asked again only when the player was not listening yet")
        let entity = "<!DOCTYPE dictionary [<!ENTITY payload 'private'>]><dictionary>&payload;</dictionary>"
        suite.expect(parse(entity) == nil && parse(String(repeating: "x", count: NotchMusicAutomationCapabilities.maximumBytes + 1)) == nil,
               "entity expansion and oversized dictionaries are rejected without external reads")
        suite.expect(parse("<dictionary><suite><command name='playpause' code='bad'/></suite></dictionary>") == nil,
               "invalid native event identifiers never reach the sender")
    }

    private static func descriptors(_ suite: TestSuite) {
        let capabilities = NotchMusicAutomationCapabilities.parse(Data(dictionary.utf8))!
        let pid = ProcessInfo.processInfo.processIdentifier
        let value = playback()
        let event = NotchMusicAutomation.event(.seek(72.5), playback: value, capabilities: capabilities, pid: pid)
        suite.expect(event?.eventClass == kAECoreSuite && event?.eventID == kAESetData,
               "seeking uses the native property setter rather than evaluated script text")
        suite.expect(event?.paramDescriptor(forKeyword: keyDirectObject)?.descriptorType == typeObjectSpecifier
               && event?.paramDescriptor(forKeyword: keyAEData)?.doubleValue == 72.5,
               "the declared property and numeric position are encoded as descriptors")
        let address = NSAppleEventDescriptor(processIdentifier: pid)
        suite.expect(event?.attributeDescriptor(forKeyword: keyAddressAttr)?.data == address.data
               && event?.attributeDescriptor(forKeyword: keyAddressAttr)?.descriptorType == address.descriptorType,
               "the Apple Event is addressed to the requested process, independently of global playback")
        let toggle = NotchMusicAutomation.event(.toggle, playback: value, capabilities: capabilities, pid: pid)
        suite.expect(toggle?.eventClass == 0x41424344 && toggle?.eventID == 0x746F676C,
               "the transport encodes the dictionary's actual command identifiers")
        suite.expect(NotchMusicAutomation.event(.seek(.nan), playback: value, capabilities: capabilities, pid: pid) == nil
               && NotchMusicAutomation.event(.queueStop, playback: value, capabilities: capabilities, pid: pid) == nil,
               "non-finite positions and queue operations cannot become unrelated Apple Events")
    }

    private static func lifecycle(_ suite: TestSuite) {
        typealias Context = NotchMusicAutomationFlowContract
        typealias Automation = Context.NotchMusicAutomation
        Context.reset()
        defer { Context.reset() }
        let capabilities = NotchMusicAutomationCapabilities.parse(Data(dictionary.utf8))!
        let service = Context.Service()
        let current = playback()
        let native = NotchPlayback(track: current.track, isPlaying: true, elapsed: 3, duration: 180, rate: 1,
            sampledAt: Date(), canSeek: true, commandContext: current.commandContext, canSendCommandsDirectly: true)
        service.playback = native
        suite.expect(service.canSeek && service.canPerform(.seek(20)), "direct native playback keeps its existing seeking capability")
        suite.expect(service.canPerform(.next) && !service.lacksTrackSkipping(.next),
               "a player whose commands are unknown keeps its skip buttons")
        var video = native; video.canSkipNext = false; video.canSkipPrevious = false
        service.playback = video
        suite.expect(service.lacksTrackSkipping(.next) && service.lacksTrackSkipping(.previous)
               && !service.canPerform(.next) && service.canPerform(.toggle),
               "a player without next or previous commands keeps only play and pause")
        service.playback = current
        let target = Automation.Target(pid: 42)
        service.automationTarget = target
        service.automationAvailability = .init(target: target, capabilities: capabilities, access: .granted)
        suite.expect(service.canSeek && current.seekPosition(20, allowed: service.canSeek) == 20,
               "authorized scripting position enables effective seek without a native seeking capability")
        var readonly = capabilities; readonly.position = nil
        service.automationAvailability = .init(target: target, capabilities: readonly, access: .granted)
        suite.expect(!service.canSeek, "authorization cannot make an undeclared or read-only position writable")
        service.automationAvailability = .init(target: target, capabilities: capabilities, access: .granted)
        var noPosition = current; noPosition.hasPosition = false; service.playback = noPosition
        suite.expect(!service.canSeek, "a missing observed position never exposes an editable timeline")
        service.playback = current
        service.automationAvailability = .init(target: target, capabilities: capabilities, access: .consent)
        suite.expect(!service.canSeek && !service.beginAutomation(.next, playback: current) && Context.AppleScriptRunner.prompts.isEmpty,
               "an ordinary gesture cannot request permission or send before authorization")
        service.requestAutomationAccess()
        Context.DispatchQueue.worker.drain(); Context.DispatchQueue.main.drain()
        suite.expect(Context.AppleScriptRunner.prompts.count == 1 && Automation.deliveries.isEmpty && service.refreshes == 1,
               "consent refreshes capabilities but never replays the gesture that preceded it")
        service.automationAvailability = .init(target: target, capabilities: capabilities, access: .granted)
        suite.expect(service.beginAutomation(.seek(20), playback: current) && !service.beginAutomation(.next, playback: current),
               "only one fallback action waits for validation or execution")
        let id = service.automationAction!.id
        suite.expect(service.validationRequests.count == 1 && Automation.deliveries.isEmpty,
               "the first operation only asks the adapter to validate the selected recording")
        service.receiveValidation(["validationRequest": id.uuidString, "validationOK": true])
        service.receiveValidation(["validationRequest": id.uuidString, "validationOK": true])
        service.queue.drain(); Context.DispatchQueue.main.drain()
        suite.expect(Automation.deliveries.count == 1 && Automation.deliveries.first?.1 == 42 && !service.commandPending,
               "a fresh validation permits exactly one event to the captured process")

        for interruption in 0..<4 {
            Automation.deliveries = []
            Automation.alive = true; Automation.permission = .granted
            service.playback = current
            _ = service.beginAutomation(.next, playback: current)
            let action = service.automationAction!
            if interruption == 0 { service.playback?.commandContext = .init(pid: 42, revision: UUID()) }
            service.receiveValidation(["validationRequest": action.id.uuidString, "validationOK": interruption != 1])
            if interruption == 2 { service.cancelAutomationAction() }
            if interruption == 3 { Automation.permission = .denied }
            service.queue.drain(); Context.DispatchQueue.main.drain()
            suite.expect(Automation.deliveries.isEmpty, "track replacement, failed validation, cancellation and revoked consent block event delivery")
        }
        service.automationAvailability = .init(target: target, capabilities: capabilities, access: .consent)
        service.playback = current
        Context.AppleScriptRunner.prompts = []
        service.requestAutomationAccess()
        service.automationConsentCancellation.cancel()
        Context.DispatchQueue.worker.drain(); Context.DispatchQueue.main.drain()
        suite.expect(Context.AppleScriptRunner.prompts.isEmpty && !service.requestingAutomation,
               "stopping before a queued consent request suppresses the prompt and releases pending state")
    }

    /// Each page that shows the controls checks the player again when it
    /// appears. Until that check lands, the controls keep the player's last
    /// answer instead of flashing the fallback row on every open.
    private static func refresh(_ suite: TestSuite) {
        typealias Context = NotchMusicAutomationFlowContract
        typealias Automation = Context.NotchMusicAutomation
        Context.reset()
        defer { Context.reset() }
        Automation.capabilities = NotchMusicAutomationCapabilities.parse(Data(dictionary.utf8))
        let service = Context.RefreshService()
        func land() { service.queue.drain(); Context.DispatchQueue.main.drain() }
        service.playback = playback()
        service.refreshAutomation()
        suite.expect(service.automationAvailability == nil,
               "a player seen for the first time shows no access until its check lands")
        land()
        suite.expect(service.automationAvailability?.access == .granted && Automation.inspections == 1,
               "the first check fills in the player's access")
        Automation.permission = .denied
        service.refreshAutomation()
        suite.expect(service.automationAvailability?.access == .granted,
               "opening the page again keeps the last answer on screen while the player is checked again")
        land()
        suite.expect(service.automationAvailability?.access == .denied && Automation.inspections == 2,
               "the fresh check still replaces the kept answer, so a revoked permission shows")
        let track = RadialNowPlayingSnapshot(title: "Other", artist: "Artist", album: "Album", artworkData: nil,
                                            appBundleIdentifier: "local.test.player", appPID: 43)
        let other = NotchPlayback(track: track, isPlaying: true, elapsed: 3, duration: 180, rate: 1, sampledAt: Date(),
                                  canSeek: false, itemIdentifier: "two", commandContext: .init(pid: 43, revision: UUID()))
        service.playback = other
        service.updateAutomation(for: other)
        suite.expect(service.automationAvailability == nil && service.automationTarget?.pid == 43,
               "another player never shows the previous player's access")
        land()
        suite.expect(service.automationAvailability?.target.pid == 43, "the new player gets its own answer")
    }
}
