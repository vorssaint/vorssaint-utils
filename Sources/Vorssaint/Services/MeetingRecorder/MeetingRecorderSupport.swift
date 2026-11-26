// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// A process Core Audio reports as currently capturing microphone input.
struct MeetingMicConsumer: Equatable, Sendable {
    let pid: pid_t
    let bundleID: String
}

/// Pure Stalkrr-style meeting detection, auto-record state machine, stream
/// liveness watchdog, level ring buffer, and recording-folder helpers. Kept
/// free of AppKit and AVFoundation so unit tests pin every edge case.
enum MeetingRecorderSupport {
    /// Known conferencing and call apps: instant auto-record start when auto-
    /// record is enabled.
    static let knownCallBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.tinyspeck.slackmacgap",
        "com.apple.FaceTime",
        "Cisco-Systems.Spark",
        "com.hnc.Discord",
        "com.google.Chrome",
        "com.apple.Safari",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.webex.meetingmanager",
        "com.microsoft.edgemac",
        "net.whatsapp.WhatsApp",
        "com.apple.Phone",
        "com.apple.Telephony",
        "com.apple.ScreenContinuity",
        "com.apple.avconferenced",
        "com.skype.skype",
        "org.whispersystems.signal-desktop",
        "ru.keepcoder.Telegram",
        "org.telegram.desktop",
    ]

    /// Friendly display names for known call bundle identifiers.
    static let callAppDisplayNames: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.apple.FaceTime": "FaceTime",
        "Cisco-Systems.Spark": "Webex",
        "com.hnc.Discord": "Discord",
        "com.google.Chrome": "Chrome",
        "com.apple.Safari": "Safari",
        "company.thebrowser.Browser": "Arc",
        "org.mozilla.firefox": "Firefox",
        "com.brave.Browser": "Brave",
        "com.webex.meetingmanager": "Webex",
        "com.microsoft.edgemac": "Edge",
        "net.whatsapp.WhatsApp": "WhatsApp",
        "com.apple.Phone": "Phone",
        "com.apple.Telephony": "Phone",
        "com.apple.ScreenContinuity": "iPhone Mirroring",
        "com.apple.avconferenced": "Phone / FaceTime",
        "com.skype.skype": "Skype",
        "org.whispersystems.signal-desktop": "Signal",
        "ru.keepcoder.Telegram": "Telegram",
        "org.telegram.desktop": "Telegram",
    ]

    /// Never treat Vorssaint itself, always-on audio utilities, or macOS
    /// speech/Siri daemons as an active meeting.
    static let defaultDenyList: Set<String> = [
        "com.vorssaint.utils",
        "com.vorssaint.utils.developer",
        "com.bearisland.BackgroundMusic",
        "com.rogueamoeba.SoundSource",
        "com.apple.controlcenter",
        "com.apple.Siri",
        "com.apple.CoreSpeech",
        "com.apple.corespeechd",
        "com.apple.assistantd",
        "com.apple.SiriNCService",
        "com.apple.dictationd",
        "com.apple.speechrecognitiond",
    ]

    static func displayName(for consumer: MeetingMicConsumer,
                            localizedAppName: String? = nil) -> String {
        if let known = callAppDisplayNames[consumer.bundleID] { return known }
        if let localizedAppName, !localizedAppName.isEmpty { return localizedAppName }
        return consumer.bundleID == "(unknown)" ? "Meeting" : consumer.bundleID
    }

    static func defaultFolderURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("Vorssaint Meetings", isDirectory: true)
    }

    static func resolvedFolderURL(storedPath: String,
                                  homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let trimmed = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultFolderURL(homeDirectory: homeDirectory) }
        let expanded = (trimmed as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    /// Safe filesystem stem for a meeting session, e.g. `2026-11-26_14-30-00-Zoom`.
    static func sessionStem(date: Date, appName: String?, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = formatter.string(from: date)
        let suffix = sanitizedLabel(appName)
        return suffix.isEmpty ? stamp : "\(stamp)-\(suffix)"
    }

    static func sanitizedLabel(_ raw: String?) -> String {
        guard let raw else { return "" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = raw.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(cleaned)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return String(collapsed.prefix(32))
    }

    /// Formats recorded duration as `M:SS` or `H:MM:SS`.
    static func elapsedLabel(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Threshold below which a mic track is considered digitally silent (dBFS).
    static let silentMicThresholdDb: Double = -75.0

    static func isMicSilent(peakDb: Double) -> Bool {
        peakDb < silentMicThresholdDb
    }

    /// A saved dual-track (or single-track) meeting recording paired by stem.
    struct RecordingSummary: Identifiable, Equatable, Sendable {
        let id: String
        let stem: String
        let label: String
        let createdAt: Date
        let systemFileName: String?
        let micFileName: String?
        let totalBytes: Int64

        var hasSystemTrack: Bool { systemFileName != nil }
        var hasMicTrack: Bool { micFileName != nil }
    }

    /// Groups `<stem>-system.wav` and `<stem>-mic.wav` files in a folder into
    /// paired session summaries, newest first, excluding an active stem.
    static func scanRecordings(fileNames: [String],
                               sizes: [String: Int64],
                               dates: [String: Date],
                               excludingStem activeStem: String? = nil) -> [RecordingSummary] {
        struct Pair {
            var system: String?
            var mic: String?
            var size: Int64 = 0
            var date: Date = .distantPast
        }
        var grouped: [String: Pair] = [:]
        for name in fileNames {
            let stem: String
            let isSystem: Bool
            if name.hasSuffix("-system.wav") {
                stem = String(name.dropLast("-system.wav".count))
                isSystem = true
            } else if name.hasSuffix("-mic.wav") {
                stem = String(name.dropLast("-mic.wav".count))
                isSystem = false
            } else {
                continue
            }
            guard !stem.isEmpty, stem != activeStem else { continue }
            var pair = grouped[stem] ?? Pair()
            if isSystem { pair.system = name } else { pair.mic = name }
            pair.size += max(0, sizes[name] ?? 0)
            if let d = dates[name], d > pair.date { pair.date = d }
            grouped[stem] = pair
        }

        return grouped.map { stem, pair in
            RecordingSummary(
                id: stem,
                stem: stem,
                label: displayLabel(fromStem: stem),
                createdAt: pair.date,
                systemFileName: pair.system,
                micFileName: pair.mic,
                totalBytes: pair.size
            )
        }.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.stem > rhs.stem
        }
    }

    static func displayLabel(fromStem stem: String) -> String {
        // Expected stem format: yyyy-MM-dd_HH-mm-ss[-AppName]
        guard stem.count >= 19 else { return stem }
        let prefixEnd = stem.index(stem.startIndex, offsetBy: 19)
        if stem.count > 20, stem[prefixEnd] == "-" {
            let suffixStart = stem.index(after: prefixEnd)
            let app = stem[suffixStart...].replacingOccurrences(of: "-", with: " ")
            if !app.isEmpty { return app }
        }
        return stem.replacingOccurrences(of: "_", with: " ")
    }
}

/// Auto-record state machine adapted from Stalkrr's `AutoRecordDecider`.
/// Keys solely off per-process Core Audio mic consumers excluding our own PID
/// and denied system daemons, with quiet-grace stop smoothing and post-manual-
/// stop suppression so an ongoing call never re-triggers.
struct MeetingAutoRecordDecider: Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case active(trigger: MeetingMicConsumer, quietTicks: Int)
        case suppressed(quietTicks: Int)
    }

    enum Action: Equatable, Sendable {
        case none
        case begin(trigger: MeetingMicConsumer)
        case stop
    }

    private(set) var phase: Phase = .idle

    private let ownPID: pid_t
    private let knownCallApps: Set<String>
    private let denyList: Set<String>
    private let gracePolls: Int

    init(ownPID: pid_t,
         knownCallApps: Set<String> = MeetingRecorderSupport.knownCallBundleIDs,
         denyList: Set<String> = MeetingRecorderSupport.defaultDenyList,
         gracePolls: Int = 3) {
        self.ownPID = ownPID
        self.knownCallApps = knownCallApps
        self.denyList = denyList
        self.gracePolls = max(1, gracePolls)
    }

    mutating func tick(consumers: [MeetingMicConsumer]) -> Action {
        let knownPresent = consumers.first { consumer in
            consumer.pid != ownPID
                && !denyList.contains(consumer.bundleID)
                && knownCallApps.contains(consumer.bundleID)
        }

        switch phase {
        case .idle:
            guard let trigger = knownPresent else { return .none }
            phase = .active(trigger: trigger, quietTicks: 0)
            return .begin(trigger: trigger)

        case .active(let trigger, let quiet):
            if knownPresent == nil {
                let nextQuiet = quiet + 1
                if nextQuiet >= gracePolls {
                    phase = .idle
                    return .stop
                }
                phase = .active(trigger: trigger, quietTicks: nextQuiet)
            } else {
                phase = .active(trigger: trigger, quietTicks: 0)
            }
            return .none

        case .suppressed(let quiet):
            if knownPresent == nil {
                let nextQuiet = quiet + 1
                phase = nextQuiet >= gracePolls ? .idle : .suppressed(quietTicks: nextQuiet)
            } else {
                phase = .suppressed(quietTicks: 0)
            }
            return .none
        }
    }

    /// Manual stop or failed start: stay quiet until the current call ends.
    mutating func noteRecordingStopped() {
        phase = .suppressed(quietTicks: 0)
    }

    /// Resets suppression and active state when auto-record is toggled off.
    mutating func reset() {
        phase = .idle
    }
}

/// Per-stream capture-health watchdog driven by persisted bytes on disk
/// (adapted from Stalkrr's `StreamHealth`).
struct MeetingStreamHealth: Sendable {
    enum Verdict: Equatable, Sendable {
        case ok, pending, neverStarted, stalled, wedged, quiet
    }

    private let kickAfter: Int
    private let wedgedAfter: Int
    private let neverStartedAfter: Int
    private var lastBytes: Int64 = -1
    private var flatTicks = 0
    private var everGrew = false
    private var reportedNeverStarted = false
    private var reportedStalled = false
    private var reportedWedged = false

    private(set) var isWedged = false

    init(kickAfter: Int = 2, wedgedAfter: Int = 4, neverStartedAfter: Int = 4) {
        self.kickAfter = kickAfter
        self.wedgedAfter = wedgedAfter
        self.neverStartedAfter = neverStartedAfter
    }

    mutating func observe(bytes: Int64) -> Verdict {
        defer { lastBytes = bytes }
        if bytes > lastBytes, lastBytes >= 0 {
            everGrew = true
            flatTicks = 0
            reportedStalled = false
            reportedWedged = false
            isWedged = false
            return .ok
        }
        if lastBytes < 0 { return .pending }
        flatTicks += 1
        if !everGrew {
            if flatTicks >= neverStartedAfter, !reportedNeverStarted {
                reportedNeverStarted = true
                isWedged = true
                return .neverStarted
            }
            return .pending
        }
        if flatTicks >= wedgedAfter, !reportedWedged {
            reportedWedged = true
            isWedged = true
            return .wedged
        }
        if flatTicks >= kickAfter, !reportedStalled {
            reportedStalled = true
            return .stalled
        }
        return .quiet
    }
}

/// Lock-guarded ~50 ms rolling audio peak history for live UI meters, kept
/// independent from the watchdog's consumable window.
final class MeetingLevelHistory: @unchecked Sendable {
    static let blockSeconds = 0.05

    private let lock = NSLock()
    private var ring: [Float]
    private var head = 0
    private var count = 0
    private var blockPeak: Float = 0
    private var blockFrames = 0
    private let capacity: Int

    init(capacity: Int = 64) {
        self.capacity = max(8, capacity)
        ring = Array(repeating: 0, count: self.capacity)
    }

    func ingest(peak: Float, frames: Int, sampleRate: Double) {
        guard sampleRate > 0, frames > 0 else { return }
        let framesPerBlock = Int(sampleRate * Self.blockSeconds)
        guard framesPerBlock > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        blockPeak = max(blockPeak, peak)
        blockFrames += frames
        while blockFrames >= framesPerBlock {
            ring[head] = blockPeak
            head = (head + 1) % capacity
            count = min(count + 1, capacity)
            blockFrames -= framesPerBlock
            blockPeak = peak
        }
    }

    func snapshot(_ n: Int) -> [Float] {
        guard n > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        var out = [Float](repeating: 0, count: n)
        let take = min(n, count)
        for i in 0..<take {
            out[n - take + i] = ring[(head - take + i + 2 * capacity) % capacity]
        }
        return out
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        ring = Array(repeating: 0, count: capacity)
        head = 0
        count = 0
        blockPeak = 0
        blockFrames = 0
    }
}
