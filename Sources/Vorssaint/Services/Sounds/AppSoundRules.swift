// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreAudio

/// Where the app's sounds come out.
enum AppSoundOutput: String, CaseIterable, Identifiable {
    /// Wherever the Mac's sound goes now, following it when it moves.
    case current
    /// The device the Mac plays its alerts on, in Sound settings.
    case alerts

    var id: String { rawValue }
}

/// What a moment knows about where it came from, for the rules that hold
/// a sound back. An agent's moment names its agent, and where its session
/// runs when that is known.
struct AppSoundContext: Equatable {
    var provider: AgentProvider?
    var place: AgentSessionPlace?

    static let none = AppSoundContext()
}

/// The page-wide rules every moment's sound passes before it plays. A
/// preview always plays: it is asked for.
enum AppSoundRules {
    /// Apps an agent's command line runs in.
    static let terminals: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "dev.warp.Warp", "dev.warp.Warp-Preview",
        "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm", "co.zeit.hyper",
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium",
        "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "dev.zed.Zed",
    ]

    /// An agent's own app, as `AgentClaudeAppUsage` and `AgentCodexServer`
    /// know them.
    static func apps(of provider: AgentProvider) -> Set<String> {
        switch provider {
        case .claude: return ["com.anthropic.claudefordesktop"]
        case .codex: return ["com.openai.codex", "com.openai.chat"]
        case .opencode, .copilot: return []
        }
    }

    /// The apps an agent's session shows in. Where it runs is not always
    /// known when its moment comes, so then either counts.
    static func windows(of provider: AgentProvider, place: AgentSessionPlace?) -> Set<String> {
        switch place {
        case .terminal: return terminals
        case .app: return apps(of: provider)
        case nil: return terminals.union(apps(of: provider))
        }
    }

    /// Whether the person is already looking at the agent this moment is
    /// about, so a sound would only tell them what they see.
    static func isLooking(at context: AppSoundContext, frontmost: String?) -> Bool {
        guard let provider = context.provider, let frontmost else { return false }
        return windows(of: provider, place: context.place).contains(frontmost)
    }

    /// Whether a moment's sound plays now, after its own switch and spacing.
    static func allows(_ sound: AppSound, context: AppSoundContext, quietWhileSharing: Bool, sharing: Bool,
                       onlyWhenAway: Bool, frontmost: String?) -> Bool {
        if quietWhileSharing, sharing, !sound.ringsThroughQuiet { return false }
        if onlyWhenAway, sound.isAgentMoment, isLooking(at: context, frontmost: frontmost) { return false }
        return true
    }

    static func allows(_ sound: AppSound, context: AppSoundContext, in defaults: UserDefaults = .standard,
                       sharing: () -> Bool = AppSoundSituation.isSharing,
                       frontmost: () -> String? = AppSoundSituation.frontmost) -> Bool {
        let quiet = defaults.object(forKey: DefaultsKey.soundsQuietWhileSharing) as? Bool ?? true
        let away = defaults.bool(forKey: DefaultsKey.soundsOnlyWhenAway) && sound.isAgentMoment
        return allows(sound, context: context, quietWhileSharing: quiet, sharing: quiet && sharing(),
                      onlyWhenAway: away, frontmost: away ? frontmost() : nil)
    }

    static func output(in defaults: UserDefaults = .standard) -> AppSoundOutput {
        defaults.string(forKey: DefaultsKey.soundsOutput).flatMap(AppSoundOutput.init(rawValue:)) ?? .current
    }

    /// Whether a process other than this one records from a microphone,
    /// from Core Audio's process list. On a Mac that does not list them, any
    /// microphone running counts, which may include this app's own.
    static func othersRecord(_ inputs: [(pid: pid_t, recording: Bool)], own: pid_t) -> Bool {
        inputs.contains { $0.recording && $0.pid != own }
    }
}

extension AppSound {
    /// A moment about one agent's session, which "only when you're not
    /// looking" holds back while that session is in front.
    var isAgentMoment: Bool { feature == .notchAgents }
    /// An alarm someone set rings through a call or a shared screen, as it
    /// always has: missing it costs more than hearing it.
    var ringsThroughQuiet: Bool { self == .timerFinished || self == .watchFinished }
}

/// What the Mac is doing now, read when a sound is about to play.
enum AppSoundSituation {
    static func frontmost() -> String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

    /// In a call or showing the screen: some app records from a microphone,
    /// or the window server says something watches the screen, as sharing,
    /// recording and mirroring do. Neither asks for a permission.
    static func isSharing() -> Bool { screenIsWatched() || microphoneInUse() }

    private typealias WatcherPresent = @convention(c) () -> Bool

    /// SkyLight's screen watcher flag, resolved once; false where it is gone.
    private static let watcherPresent: WatcherPresent? = {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        for name in ["SLSIsScreenWatcherPresent", "CGSIsScreenWatcherPresent"] {
            if let symbol = dlsym(handle, name) { return unsafeBitCast(symbol, to: WatcherPresent.self) }
        }
        return nil
    }()

    static func screenIsWatched() -> Bool { watcherPresent?() ?? false }

    static func microphoneInUse() -> Bool {
        if let inputs = processInputs() {
            return AppSoundRules.othersRecord(inputs, own: ProcessInfo.processInfo.processIdentifier)
        }
        return defaultInputRuns()
    }

    /// Each audio client's process and whether it records, or nil when the
    /// list cannot be read.
    private static func processInputs() -> [(pid: pid_t, recording: Bool)]? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return nil }
        return ids.map { id in
            var pid: pid_t = 0
            var recording: UInt32 = 0
            _ = read(id, kAudioProcessPropertyPID, &pid)
            _ = read(id, kAudioProcessPropertyIsRunningInput, &recording)
            return (pid, recording != 0)
        }
    }

    private static func defaultInputRuns() -> Bool {
        var device = AudioObjectID(kAudioObjectUnknown)
        guard read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, &device),
              device != kAudioObjectUnknown else { return false }
        var running: UInt32 = 0
        return read(device, kAudioDevicePropertyDeviceIsRunningSomewhere, &running) && running != 0
    }

    /// The device sounds should go to for `output`, or nil when there is none.
    static func device(for output: AppSoundOutput) -> AudioDeviceID? {
        let selector = output == .alerts ? kAudioHardwarePropertyDefaultSystemOutputDevice
                                         : kAudioHardwarePropertyDefaultOutputDevice
        var device = AudioDeviceID(kAudioObjectUnknown)
        guard read(AudioObjectID(kAudioObjectSystemObject), selector, &device), device != kAudioObjectUnknown else {
            return nil
        }
        return device
    }

    @discardableResult
    static func read<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutableBytes(of: &value) { bytes in
            guard let base = bytes.baseAddress else { return false }
            return AudioObjectGetPropertyData(object, &address, 0, nil, &size, base) == noErr
        }
    }
}
