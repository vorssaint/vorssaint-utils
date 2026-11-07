// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint Audio contributors
import CoreAudio
import Foundation

enum VirtualOutputSupport {
    struct OutputLayout: Equatable {
        let labels: [UInt32]
        var isStereo: Bool {
            labels.count == 2 && Set(labels) == Set([kAudioChannelLabel_Left, kAudioChannelLabel_Right])
        }
        var notation: String? {
            guard !labels.isEmpty, labels.allSatisfy({
                $0 >= kAudioChannelLabel_Left && $0 < kAudioChannelLabel_UseCoordinates
            }) else { return nil }
            // 62 is Core Audio's LFE3 label, also recognized with older SDKs.
            let lfe = labels.filter { $0 == kAudioChannelLabel_LFEScreen || $0 == kAudioChannelLabel_LFE2 || $0 == 62 }.count
            let floor = labels.count - lfe - heightChannels
            return heightChannels > 0 ? "\(floor).\(lfe).\(heightChannels)" : "\(floor).\(lfe)"
        }
        var heightChannels: Int {
            labels.filter {
                (kAudioChannelLabel_TopCenterSurround...kAudioChannelLabel_TopBackRight).contains($0)
                    || [kAudioChannelLabel_LeftTopMiddle, kAudioChannelLabel_RightTopMiddle,
                        kAudioChannelLabel_LeftTopRear, kAudioChannelLabel_CenterTopRear, kAudioChannelLabel_RightTopRear,
                        kAudioChannelLabel_LeftTopSurround, kAudioChannelLabel_RightTopSurround].contains($0)
            }.count
        }
        var systemImage: String {
            if heightChannels > 0 { return "square.3.layers.3d" }
            return labels.count == 1 ? "speaker.fill" : isStereo ? "hifispeaker.2.fill" : "dot.radiowaves.left.and.right"
        }
    }
    /// Synchronizes the latest UI request with the serial HAL queue. No lock is
    /// held while calling Core Audio or while dispatching to the main queue.
    final class OutputRequests {
        private let lock = NSLock()
        private var latest = UUID()
        func next() -> UUID {
            lock.lock(); defer { lock.unlock() }
            latest = UUID()
            return latest
        }
        func isCurrent(_ request: UUID) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return latest == request
        }
    }
    static let deviceUID = "VorssaintAudio_UID"
    static let loopbackUID = "VorssaintAudio_2_UID"
    // Compatibility with the local prototype already installed on this Mac.
    // Public builds/installers use Vorssaint Audio exclusively.
    static let legacyDeviceUID = "VorssaintAudioFork_UID"
    static func isSoftwareOutput(_ uid: String?) -> Bool { uid == deviceUID || uid == legacyDeviceUID }
    static func isSoftwareDevice(_ uid: String?) -> Bool {
        isSoftwareOutput(uid) || uid == loopbackUID
            || uid?.hasPrefix("com.vorssaint.utils.software-volume.bridge.") == true
    }
    static func logicalOutputUID(current: String?, physical: String?, requested: String? = nil) -> String? {
        requested ?? (isSoftwareOutput(current) ? physical : current)
    }
    static func migratedOutputSelection(_ uids: [String], physical: String?) -> [String] {
        var seen = Set<String>()
        return uids.compactMap { uid in
            let target = isSoftwareOutput(uid) ? physical : uid
            guard let target, !target.isEmpty, !isSoftwareDevice(target), seen.insert(target).inserted else { return nil }
            return target
        }
    }
    static let ownerSelector: AudioObjectPropertySelector = 0x766f776e
    static let activeSelector: AudioObjectPropertySelector = 0x76616374

    static func usesVirtualOutput(enabled: Bool, hardwareVolume: Bool) -> Bool { enabled && !hardwareVolume }

    static func restoreUID(current: String?, virtual: String, previous: String?, available: [String], fallback: [String]? = nil, owned: Bool = true) -> String? {
        guard owned, current == virtual else { return nil }
        if let previous, available.contains(previous) { return previous }
        return (fallback ?? available).first
    }

    /// The bundle stamps the exact optional-driver build it ships. Keep the
    /// output-only protocol floor even if that metadata is absent or invalid.
    static func requiredComponentBuild(bundledBuild: Int?) -> Int { max(5, bundledBuild ?? 5) }
    static func needsComponentUpdate(installed: Bool, build: Int?, required: Int) -> Bool {
        installed && (build ?? 0) < required
    }
    static func shouldOfferComponentUpdate(enabled: Bool, needsUpdate: Bool, offered: Bool, installing: Bool, removing: Bool) -> Bool {
        enabled && needsUpdate && !offered && !installing && !removing
    }

    static func shouldOpenBundledInstaller(installedBuild: Int?, bundledBuild: Int, ready: Bool) -> Bool {
        guard let installedBuild else { return true }
        return installedBuild < bundledBuild || (installedBuild == bundledBuild && !ready)
    }

    enum EnableAction { case enable, disable, install }
    static func enableAction(requested: Bool, componentReady: Bool) -> EnableAction {
        if !requested { return .disable }
        return componentReady ? .enable : .install
    }
    enum Issue { case outputUnavailable, setupFailed, privacyUnverified, inUse, stopped, installerMissing, removalFailed }

    enum InputSource { case physicalOutput(streams: Int), processTap(physicalStreams: Int) }
    static func inputMask(streamCount: Int, source: InputSource) -> [UInt32]? {
        guard streamCount >= 0 else { return nil }
        switch source {
        case .physicalOutput(let streams):
            guard streams >= 0, streamCount == streams else { return nil }
            return [UInt32](repeating: 0, count: streams)
        case .processTap(let physicalStreams):
            guard physicalStreams >= 0, streamCount == physicalStreams + 1 else { return nil }
            return (0..<streamCount).map { $0 == streamCount - 1 ? 1 : 0 }
        }
    }

}
