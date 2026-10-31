// SPDX-License-Identifier: GPL-3.0-or-later
import CoreAudio
import Foundation

@main struct BridgeTests {
    static func main() {
        var failures = 0, checks = 0
        func expect(_ value: Bool, _ label: String) { checks += 1; if !value { failures += 1; print("FAIL: \(label)") } }
        expect(VirtualOutputSupport.usesVirtualOutput(enabled: true, hardwareVolume: false), "Samsung fixed DisplayPort uses software fallback")
        expect(!VirtualOutputSupport.usesVirtualOutput(enabled: true, hardwareVolume: true), "AirPods native volume bypasses virtual processing")
        expect(!VirtualOutputSupport.usesVirtualOutput(enabled: false, hardwareVolume: false), "disabled fallback leaves native routing alone")
        expect(VirtualOutputSupport.restoreUID(current: "virtual", virtual: "virtual", previous: "monitor", available: ["monitor"]) == "monitor", "restore physical output we replaced")
        expect(VirtualOutputSupport.restoreUID(current: "headset", virtual: "virtual", previous: "monitor", available: ["monitor", "headset"]) == nil, "preserve external output choice")
        expect(VirtualOutputSupport.restoreUID(current: "virtual", virtual: "virtual", previous: "missing", available: ["speakers"]) == "speakers", "disconnected previous output falls back to available physical")
        expect(VirtualOutputSupport.restoreUID(current: "virtual", virtual: "virtual", previous: "monitor", available: ["monitor"], owned: false) == nil, "failed owner must not reroute another instance")
        expect(VirtualOutputSupport.restoreUID(current: "virtual", virtual: "virtual", previous: "aggregate", available: ["aggregate", "monitor"], fallback: ["monitor"]) == "aggregate", "restore existing nonphysical system-sound route")
        expect(VirtualOutputSupport.restoreUID(current: "virtual", virtual: "virtual", previous: "gone", available: ["aggregate", "monitor"], fallback: ["monitor"]) == "monitor", "only fallback destinations must be physical")
        expect(VirtualOutputSupport.inputMask(streamCount: 3, source: .physicalOutput(streams: 3)) == [0, 0, 0], "output callback disables every physical microphone stream")
        expect(VirtualOutputSupport.inputMask(streamCount: 3, source: .processTap(physicalStreams: 2)) == [0, 0, 1], "per-app mixer enables only process tap and disables hardware microphone streams")
        expect(VirtualOutputSupport.inputMask(streamCount: 1, source: .physicalOutput(streams: 2)) == nil, "uncertain physical input mapping must not enable any capture")
        expect(VirtualOutputSupport.inputMask(streamCount: 1, source: .processTap(physicalStreams: 1)) == nil, "a not-yet-published process tap cannot be mistaken for a physical microphone")
        expect(MicMuteSupport.isOwnDevice(name: "Vorssaint Audio"), "microphone mute must exclude the playback loopback")
        expect(MicMuteSupport.isOwnDevice(name: "Vorssaint Audio playback bridge"), "microphone mute must exclude the playback bridge")
        expect(VirtualOutputSupport.enableAction(requested: true, componentReady: false) == .install, "only enabling fallback without a component requests installation")
        expect(VirtualOutputSupport.enableAction(requested: false, componentReady: false) == .disable, "normal mixer/disabled fallback does not request installation")
        expect(VirtualOutputSupport.enableAction(requested: true, componentReady: true) == .enable, "installed component enables without another installer")
        expect(VirtualOutputSupport.isSoftwareDevice(VirtualOutputSupport.loopbackUID), "legacy loopback is still excluded during migration")
        expect(VirtualOutputSupport.inputMask(streamCount: 0, source: .physicalOutput(streams: 0)) == [], "output-only hardware needs no capture streams")
        expect(VirtualOutputSupport.requiredComponentBuild(bundledBuild: 5) == 5, "a future app requires its bundled driver build")
        expect(VirtualOutputSupport.requiredComponentBuild(bundledBuild: 1) >= 4, "metadata cannot lower the output-only driver requirement")
        expect(VirtualOutputSupport.needsComponentUpdate(installed: true, build: 3, required: 4), "an installed duplex driver needs the output-only upgrade")
        expect(VirtualOutputSupport.needsComponentUpdate(installed: true, build: 4, required: 5), "a future bundled driver prompts an older installed build to update")
        expect(!VirtualOutputSupport.needsComponentUpdate(installed: true, build: 5, required: 5), "a current driver needs no reinstall")
        expect(!VirtualOutputSupport.needsComponentUpdate(installed: true, build: 6, required: 5), "an older app does not downgrade a newer installed driver")
        expect(VirtualOutputSupport.needsComponentUpdate(installed: true, build: nil, required: 4), "invalid version metadata cannot masquerade as an updated driver")
        expect(!VirtualOutputSupport.needsComponentUpdate(installed: false, build: nil, required: 4), "users without the optional driver do not receive update prompts")
        expect(VirtualOutputSupport.shouldOfferComponentUpdate(enabled: true, needsUpdate: true, offered: false, installing: false, removing: false), "enabled fallback offers a required driver update at startup")
        for state in [(false,true,false,false,false), (true,false,false,false,false), (true,true,true,false,false), (true,true,false,true,false), (true,true,false,false,true)] {
            expect(!VirtualOutputSupport.shouldOfferComponentUpdate(enabled: state.0, needsUpdate: state.1, offered: state.2, installing: state.3, removing: state.4), "disabled, current, declined or in-progress driver operations never cause repeated installation prompts")
        }
        expect(!VirtualOutputSupport.shouldOpenBundledInstaller(installedBuild: 6, bundledBuild: 5, ready: true), "a stale update alert cannot downgrade a newer driver")
        expect(!VirtualOutputSupport.shouldOpenBundledInstaller(installedBuild: 5, bundledBuild: 5, ready: true), "another completed update makes the old install request a no-op")
        expect(VirtualOutputSupport.shouldOpenBundledInstaller(installedBuild: 5, bundledBuild: 5, ready: false), "an unavailable current driver can still be repaired")
        expect(VirtualOutputSupport.shouldOpenBundledInstaller(installedBuild: 4, bundledBuild: 5, ready: false), "the required bundled upgrade opens for an older driver")
        expect(VirtualOutputSupport.shouldOpenBundledInstaller(installedBuild: nil, bundledBuild: 5, ready: false), "a missing optional driver can be installed")
        print("VORSSAINT AUDIO BRIDGE: \(checks) checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
