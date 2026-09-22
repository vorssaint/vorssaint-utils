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
        var expanded = false
        var notice: NotchNotice?
        var presented: [NotchNotice] = []
        func show(_ incoming: NotchNotice) {
            guard NotchSupport.shouldReplace(notice?.event, with: incoming.event) else { return }
            notice = incoming
            presented.append(incoming)
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
            suite.expect(service.presented.isEmpty, "the open controls do not retain a hidden volume notice")
            service.subscriptions.removeAll()
            mixer.publish(device: "stopped-output", volume: 0.1, muted: false)
            drain()
            suite.expect(service.presented.isEmpty, "stopping observation cancels volume feedback")
        }
    }
}
