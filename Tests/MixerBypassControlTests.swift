// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// The mixer's real opt-in for apps that manage their own audio (issue #390),
/// run against an in-memory mixer. Nothing is tapped.
enum MixerBypassControlContract {
    static func run(_ suite: TestSuite) {
        let key = DefaultsKey.mixerControlledBypassApps
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)

        func row(_ objects: [AudioObjectID], bypassed: Bool, overridden: Bool) -> MixerApp {
            MixerApp(id: "us.zoom.xos", persistenceID: "us.zoom.xos", ownerPid: 1, name: "zoom.us",
                     audioObjects: objects, isPlaying: false, isBypassed: bypassed,
                     isBypassOverridden: overridden, selectedOutputDeviceUID: nil,
                     effectiveOutputDeviceUID: "BuiltInSpeakerDevice",
                     outputDeviceUnavailable: false, volume: 1.5)
        }
        let path = MixerEngineRecovery.Configuration(objects: [41], outputDeviceUID: "BuiltInSpeakerDevice")
        func failTwice(_ mixer: Mixer) {
            _ = mixer.engineRecovery.recordFailure("us.zoom.xos", configuration: path)
            _ = mixer.engineRecovery.recordFailure("us.zoom.xos", configuration: path)
        }

        // Two failed taps leave the row on the fallback with no engine. Giving
        // the audio back to the app, or asking for control again, is the user
        // retrying on purpose and must not stay blocked by those failures.
        let mixer = Mixer()
        failTwice(mixer)
        suite.expect(!mixer.engineRecovery.allowsBuild("us.zoom.xos", configuration: path),
                     "two failed taps block another build of the same audio path")
        mixer.setMixerControl(false, for: row([41], bypassed: false, overridden: true))
        suite.expect(mixer.engineRecovery.allowsBuild("us.zoom.xos", configuration: path)
                     && mixer.savedControlledBypassApps().isEmpty && mixer.refreshes == 1,
                     "handing the audio back to the app forgets the failed taps")
        failTwice(mixer)
        mixer.setMixerControl(true, for: row([41], bypassed: true, overridden: false))
        suite.expect(mixer.engineRecovery.allowsBuild("us.zoom.xos", configuration: path)
                     && mixer.savedControlledBypassApps() == ["us.zoom.xos"],
                     "opting in again after failed taps is allowed to build the tap")

        // Two running instances share one row. The merged row keeps what the
        // user chose, so both menus still offer the way back.
        let optedIn = Mixer.coalescingAppsWithDuplicateIDs([row([41], bypassed: false, overridden: true),
                                                            row([42], bypassed: false, overridden: true)])
        suite.expect(optedIn.count == 1 && optedIn[0].isBypassOverridden && !optedIn[0].isBypassed
                     && optedIn[0].audioObjects == [41, 42],
                     "an opted-in app running twice stays one opted-in row")
        let untouched = Mixer.coalescingAppsWithDuplicateIDs([row([41], bypassed: true, overridden: false),
                                                             row([42], bypassed: true, overridden: false)])
        suite.expect(untouched.count == 1 && untouched[0].isBypassed && !untouched[0].isBypassOverridden,
                     "an app that manages its own audio stays bypassed when it runs twice")
    }
}
