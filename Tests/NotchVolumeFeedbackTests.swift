// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Runs the production subscription and notice selection with real Combine
/// delivery and a controlled audio source, without changing hardware volume.
enum NotchVolumeFeedbackTests {
    final class AppVolumeMixer {
        static var shared = AppVolumeMixer()
        @Published var currentOutputDeviceUID: String? = "speakers"
        @Published var systemOutputVolume: Double? = 0.3
        @Published var systemOutputMuted: Bool? = false

        func publish(device: String?, volume: Double?, muted: Bool?, identityFirst: Bool = true) {
            if identityFirst { currentOutputDeviceUID = device }
            systemOutputVolume = volume
            systemOutputMuted = muted
            if !identityFirst { currentOutputDeviceUID = device }
        }
    }

    class State {
        var subscriptions = Set<AnyCancellable>()
        var volumeDeviceUID: String?
        var volumeBaseline: Double?
        var muteBaseline: Bool?
        var ownVolumeAdjustmentUntil: TimeInterval = 0
        var lastVolumeRide: TimeInterval = -.infinity
        var expanded = false
        var showsSystemFeedback = true
        var notice: NotchNotice?
        var presented: [NotchNotice] = []
        @discardableResult
        func show(_ incoming: NotchNotice) -> Bool {
            guard showsSystemFeedback,
                  NotchSupport.shouldReplace(notice?.event, with: incoming.event) else { return false }
            notice = incoming
            presented.append(incoming)
            return true
        }
    }

    static func run(_ suite: TestSuite) {
        func drain() {
            var delivered = false
            DispatchQueue.main.async { delivered = true }
            let deadline = Date().addingTimeInterval(1)
            while !delivered && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.005))
            }
            suite.expect(delivered, "queued volume publications settle within the test deadline")
        }
        defer { AppVolumeMixer.shared = AppVolumeMixer() }
        let connection = NotchNotice(event: .accessory, title: "Wireless Headphones",
                                     detail: "Connected", symbol: "headphones")
        for identityFirst in [false, true] {
            let mixer = AppVolumeMixer()
            AppVolumeMixer.shared = mixer
            let service = Service()
            service.bindVolumeEvents()
            drain()
            suite.expect(service.presented.isEmpty, "starting volume observation establishes a silent baseline")
            service.notice = connection
            mixer.publish(device: "headphones", volume: 0.75, muted: true, identityFirst: identityFirst)
            drain()
            suite.expect(service.notice == connection && service.presented.isEmpty,
                   "switching output never replaces its connection notice with stored volume or mute")
            mixer.systemOutputVolume = 0.8
            mixer.systemOutputMuted = false
            drain()
            suite.expect(service.notice?.event == .volume && service.notice?.level == 0.8 && service.presented.count == 1,
                   "a real adjustment on the new output appears once with its final mute state")
            service.presented.removeAll()
            service.notice = connection
            mixer.publish(device: "another-output", volume: 0.8, muted: false, identityFirst: identityFirst)
            drain()
            suite.expect(service.notice == connection && service.presented.isEmpty,
                   "an output switch at the same level is also silent")
            mixer.systemOutputMuted = true
            drain()
            suite.expect(service.notice?.event == .volume && service.notice?.level == 0,
                   "the first real mute change after an equal-volume switch is not swallowed")
            service.presented.removeAll()
            service.notice = connection
            mixer.publish(device: nil, volume: nil, muted: nil)
            mixer.publish(device: "headphones", volume: nil, muted: nil)
            drain()
            mixer.publish(device: "headphones", volume: 0.5, muted: false)
            drain()
            suite.expect(service.notice == connection && service.presented.isEmpty,
                   "disconnecting and receiving a delayed initial reading remain silent")
            mixer.publish(device: "old-output", volume: 0.9, muted: true)
            mixer.publish(device: "latest-output", volume: 0.2, muted: false)
            drain()
            suite.expect(service.notice == connection && service.presented.isEmpty,
                   "queued publications from superseded outputs cannot flash a volume notice")
            mixer.publish(device: nil, volume: nil, muted: nil)
            mixer.publish(device: "latest-output", volume: 0.4, muted: false)
            drain()
            suite.expect(service.notice == connection && service.presented.isEmpty,
                   "a quick reconnect to the same output invalidates its old baseline before queued delivery")
            service.showCurrentVolume()
            suite.expect(service.notice?.event == .volume && service.notice?.level == 0.4,
                   "an explicit volume key still shows feedback even when the level has not changed")
            service.expanded = true
            service.presented.removeAll()
            mixer.systemOutputVolume = 0.6
            drain()
            suite.expect(service.notice?.level == 0.6 && service.presented.count == 1,
                   "volume changes supply header feedback while the island is open on any page")
            service.presented.removeAll()
            // Each step of the island's slider or mute button marks its change.
            service.noteOwnVolumeAdjustment()
            mixer.systemOutputVolume = 0.35
            drain()
            service.noteOwnVolumeAdjustment()
            mixer.systemOutputMuted = true
            drain()
            suite.expect(service.presented.isEmpty,
                   "the island's own level and mute controls leave the open header's title alone")
            service.showCurrentVolume()
            suite.expect(service.presented.count == 1 && service.notice?.level == 0,
                   "a volume key right after an own adjustment still shows feedback")
            service.presented.removeAll()
            service.ownVolumeAdjustmentUntil = 0
            mixer.systemOutputMuted = false
            drain()
            suite.expect(service.presented.count == 1 && service.notice?.level == 0.35,
                   "a change after the own adjustment's moment shows in the open header again")
            service.presented.removeAll()
            service.expanded = false
            service.noteOwnVolumeAdjustment()
            mixer.systemOutputVolume = 0.5
            drain()
            suite.expect(service.presented.count == 1,
                   "a closed island keeps its volume feedback whatever changed the level")
            service.presented.removeAll()
            service.subscriptions.removeAll()
            mixer.publish(device: "stopped-output", volume: 0.1, muted: false)
            drain()
            suite.expect(service.presented.isEmpty, "stopping observation cancels volume feedback")
        }

        // The command bar writes a level and then reports it, because the
        // observer can have nothing new to show for that write.
        let mixer = AppVolumeMixer()
        AppVolumeMixer.shared = mixer
        let service = Service()
        service.bindVolumeEvents()
        drain()
        mixer.systemOutputVolume = 0.3
        drain()
        suite.expect(service.presented.isEmpty, "rewriting the current level gives the observer nothing to show")
        suite.expect(service.showVolume(0.3) && service.notice?.level == 0.3,
               "a level set outside the island shows even when it matches the current one")
        service.presented.removeAll()
        mixer.publish(device: "headphones", volume: 0.6, muted: false)
        drain()
        suite.expect(service.presented.isEmpty && service.showVolume(0.6) && service.notice?.level == 0.6,
               "a level set outside the island shows when it is a new output's silent first reading")
        service.expanded = true
        suite.expect(service.showVolume(0.2) && service.notice?.level == 0.2,
               "a level set outside the open island supplies its header feedback")
        service.showsSystemFeedback = false
        suite.expect(!service.showVolume(0.9) && service.notice?.level == 0.2,
               "an island that cannot show volume leaves the confirmation to the caller")
        service.subscriptions.removeAll()

        // An output that adapts its own level, measured from AirPods Pro
        // reacting to the room: a hundredth at a time, a ramp up and back
        // down, steps 0.2 to 0.6 s apart, each ramp closing with a coarser
        // correction about 1.7 s after its last fine step.
        suite.expect(NotchSupport.volumeChangeOrigin(from: 0.43, to: 0.44, sinceRide: .infinity) == .rides,
               "a hundredth of the scale is finer than any volume key can press")
        suite.expect(NotchSupport.volumeChangeOrigin(from: 0.47, to: 0.45, sinceRide: 0.5) == .rides,
               "the coarser correction that closes a ramp belongs to the ramp")
        suite.expect(NotchSupport.volumeChangeOrigin(from: 0.47, to: 0.45, sinceRide: 10) == .announces,
               "the same two hundredths announce themselves when no ramp is under way")
        suite.expect(NotchSupport.volumeChangeOrigin(from: 0.42, to: 0.42 + 1.0 / 16, sinceRide: 0.1) == .announces,
               "a full key step reports however busy the output is")
        suite.expect(NotchSupport.volumeChangeOrigin(from: 0.41, to: 0.47, sinceRide: 0.1) == .announces,
               "a full key step rounded into hundredths by the output still reports")
        suite.expect(NotchSupport.volumeChangeOrigin(from: 0.42, to: 0.42 + 1.0 / 64,
                                                     sinceRide: .infinity) == .announces,
               "the keyboard's fine step reports when the output is still")
        suite.expect(NotchSupport.volumeChangeOrigin(from: 0.005, to: 0, sinceRide: 0.1) == .announces
               && NotchSupport.volumeChangeOrigin(from: 0.995, to: 1, sinceRide: 0.1) == .announces,
               "a level pressed against either end reports however little it moved")
        suite.expect(NotchSupport.volumeChangeOrigin(from: .nan, to: 0.5, sinceRide: 0) == .announces,
               "an unreadable previous level leaves the change to the caller's judgement")

        let adaptive = AppVolumeMixer()
        AppVolumeMixer.shared = adaptive
        let island = Service()
        island.bindVolumeEvents()
        drain()
        // The level the person left it at, which reports as it always did.
        adaptive.systemOutputVolume = 0.43
        drain()
        suite.expect(island.presented.count == 1, "the level a person sets still reports before any ramp")
        island.presented.removeAll()
        island.notice = nil
        // The levels this Mac recorded over one ramp, including the two
        // hundredths that turn it around.
        for level in [0.44, 0.45, 0.46, 0.47, 0.45, 0.44, 0.43, 0.42] {
            adaptive.systemOutputVolume = level
            drain()
        }
        suite.expect(island.presented.isEmpty && island.notice == nil,
               "a ramp the output drives itself never raises the volume indicator")
        adaptive.systemOutputMuted = true
        drain()
        suite.expect(island.presented.count == 1 && island.notice?.level == 0,
               "muting during such a ramp still reports")
        island.presented.removeAll()
        adaptive.systemOutputMuted = false
        drain()
        adaptive.systemOutputVolume = 0.42 + 1.0 / 16
        drain()
        suite.expect(island.presented.count == 2 && island.notice?.level == 0.42 + 1.0 / 16,
               "a key press after the ramp reports from the level the ramp left behind")
        island.subscriptions.removeAll()
    }
}
