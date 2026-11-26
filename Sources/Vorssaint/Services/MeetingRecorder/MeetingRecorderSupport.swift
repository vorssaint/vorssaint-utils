// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

/// A process Core Audio reports as currently capturing microphone input.
struct MeetingMicConsumer: Equatable, Sendable {
    let pid: pid_t
    let bundleID: String
}

/// Pure meeting detection, auto-record state machine, stream
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
        "com.apple.SafariTechnologyPreview",
        "company.thebrowser.Browser",
        "company.thebrowser.dia",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.webex.meetingmanager",
        "com.microsoft.edgemac",
        "app.zen-browser.zen",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "com.kagi.kagimacOS",
        "org.chromium.Chromium",
        "io.island.Island",
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
        "com.apple.SafariTechnologyPreview": "Safari",
        "company.thebrowser.Browser": "Arc",
        "company.thebrowser.dia": "Dia",
        "org.mozilla.firefox": "Firefox",
        "com.brave.Browser": "Brave",
        "com.webex.meetingmanager": "Webex",
        "com.microsoft.edgemac": "Edge",
        "app.zen-browser.zen": "Zen",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.operasoftware.Opera": "Opera",
        "com.kagi.kagimacOS": "Orion",
        "org.chromium.Chromium": "Chromium",
        "io.island.Island": "Island",
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

    /// Normalizes browser and Electron helper subprocess bundle IDs (such as
    /// `com.google.Chrome.helper`, `com.google.Chrome.helper.renderer`,
    /// `com.apple.WebKit.GPU`, `org.mozilla.plugincontainer`, `us.zoom.*`) to
    /// their parent app bundle ID so web calls like WhatsApp Web or Google Meet
    /// in Chrome are recognized reliably.
    static func normalizedCallBundleID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let lower = trimmed.lowercased()

        if lower.hasPrefix("com.google.chrome") { return "com.google.Chrome" }
        if lower.hasPrefix("com.apple.webkit") { return "com.apple.Safari" }
        if lower.hasPrefix("com.apple.safaritechnologypreview") { return "com.apple.SafariTechnologyPreview" }
        if lower.hasPrefix("org.mozilla.firefox") || lower == "org.mozilla.plugincontainer" {
            return "org.mozilla.firefox"
        }
        if lower.hasPrefix("company.thebrowser.browser") { return "company.thebrowser.Browser" }
        if lower.hasPrefix("company.thebrowser.dia") { return "company.thebrowser.dia" }
        if lower.hasPrefix("com.brave.browser") { return "com.brave.Browser" }
        if lower.hasPrefix("com.microsoft.edgemac") { return "com.microsoft.edgemac" }
        if lower.hasPrefix("app.zen-browser.zen") { return "app.zen-browser.zen" }
        if lower.hasPrefix("com.vivaldi.vivaldi") { return "com.vivaldi.Vivaldi" }
        if lower.hasPrefix("com.operasoftware.opera") { return "com.operasoftware.Opera" }
        if lower.hasPrefix("org.chromium.chromium") { return "org.chromium.Chromium" }
        if lower.hasPrefix("io.island.island") { return "io.island.Island" }
        if lower.hasPrefix("us.zoom.") { return "us.zoom.xos" }
        if lower.hasPrefix("com.microsoft.teams2") { return "com.microsoft.teams2" }
        if lower.hasPrefix("com.tinyspeck.slackmacgap") { return "com.tinyspeck.slackmacgap" }
        if lower.hasPrefix("com.hnc.discord") { return "com.hnc.Discord" }
        if lower.hasPrefix("net.whatsapp.whatsapp") { return "net.whatsapp.WhatsApp" }

        for suffix in [".helper.renderer", ".helper.audio", ".helper.gpu", ".helper.plugin",
                       ".helper", ".webcontent"] {
            if lower.hasSuffix(suffix) {
                return String(trimmed.dropLast(suffix.count))
            }
        }
        return trimmed
    }

    static func isKnownCallBundleID(_ bundleID: String,
                                    knownCallApps: Set<String> = knownCallBundleIDs) -> Bool {
        if knownCallApps.contains(bundleID) { return true }
        let normalized = normalizedCallBundleID(bundleID)
        return knownCallApps.contains(normalized)
    }

    /// Refines a browser call label when an active browser window title
    /// clearly names a web call surface (e.g. WhatsApp Web or Google Meet).
    static func browserCallLabel(baseName: String, windowTitles: [String]) -> String {
        let hints: [(needle: String, label: String)] = [
            ("whatsapp", "WhatsApp"),
            ("google meet", "Google Meet"),
            ("meet - ", "Google Meet"),
            ("zoom", "Zoom"),
            ("microsoft teams", "Teams"),
            ("huddle", "Slack Huddle"),
            ("discord", "Discord"),
            ("messenger", "Messenger"),
            ("webex", "Webex"),
        ]
        for title in windowTitles {
            let lower = title.lowercased()
            for hint in hints where lower.contains(hint.needle) {
                return "\(hint.label) (\(baseName))"
            }
        }
        return baseName
    }

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
        let normalized = normalizedCallBundleID(consumer.bundleID)
        if let known = callAppDisplayNames[consumer.bundleID] ?? callAppDisplayNames[normalized] {
            return known
        }
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

    /// Reserves a non-colliding session stem against existing files in the
    /// output folder, delegating to `fileExists` (which queries the actual
    /// filesystem in production so APFS case-folding and Unicode normalization
    /// such as `σ` vs `ς` are matched exactly).
    static func uniqueSessionStem(baseStem: String,
                                  existingFileNames: Set<String> = [],
                                  fileExists: ((String) -> Bool)? = nil) -> String {
        let lowerExisting = Set(existingFileNames.map { $0.lowercased() })
        func collides(_ candidate: String) -> Bool {
            let sys = "\(candidate)-system.wav"
            let mic = "\(candidate)-mic.wav"
            if let fileExists, fileExists(sys) || fileExists(mic) {
                return true
            }
            return lowerExisting.contains(sys.lowercased())
                || lowerExisting.contains(mic.lowercased())
        }
        guard collides(baseStem) else { return baseStem }
        var counter = 2
        while collides("\(baseStem)-\(counter)") {
            counter += 1
        }
        return "\(baseStem)-\(counter)"
    }

    /// Returns true only for recorder-generated stems (`yyyy-MM-dd_HH-mm-ss`
    /// with an optional sanitized `-<label>` suffix, including Unicode app
    /// names) so unrelated `*-mic.wav` or `*-system.wav` files are ignored.
    static func isRecorderStem(_ stem: String) -> Bool {
        let chars = Array(stem)
        guard chars.count >= 19 else { return false }
        let digitPositions: Set<Int> = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
        for idx in 0..<19 {
            let c = chars[idx]
            if digitPositions.contains(idx) {
                guard c >= "0", c <= "9" else { return false }
            } else if idx == 10 {
                guard c == "_" else { return false }
            } else {
                guard c == "-" else { return false }
            }
        }
        if chars.count == 19 { return true }
        guard chars[19] == "-", chars.count > 20 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let suffix = String(chars[20...])
        return suffix.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Returns the number of silent PCM frames to pad before an incoming buffer
    /// so the system-audio track stays time-aligned with the microphone track
    /// across idle Core Audio tap gaps (> 150 ms), excluding deliberate pauses.
    static func silenceGapFrames(activeElapsedSeconds: Double,
                                 writtenFrames: Int64,
                                 incomingFrames: Int64,
                                 sampleRate: Double,
                                 thresholdSeconds: Double = 0.15) -> Int64 {
        guard sampleRate > 0, activeElapsedSeconds > 0, incomingFrames >= 0 else { return 0 }
        let expectedBefore = Int64((activeElapsedSeconds * sampleRate).rounded()) - incomingFrames
        let gap = expectedBefore - writtenFrames
        let threshold = Int64((thresholdSeconds * sampleRate).rounded())
        return gap > threshold ? gap : 0
    }

    /// Pure guard ensuring an automatic detector stop only ends a session that
    /// was started automatically, never a manual recording.
    static func shouldApplyDetectorStop(isRecording: Bool, sessionIsAutomatic: Bool) -> Bool {
        isRecording && sessionIsAutomatic
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

    /// Filesystem identity `(st_dev, st_ino)` captured when scanning a file so
    /// delete/cleanup never touches a different file that replaced the same path.
    struct FileIdentity: Codable, Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
    }

    /// A saved dual-track (or single-track) meeting recording paired by stem.
    struct RecordingSummary: Identifiable, Equatable, Sendable {
        let id: String
        let stem: String
        let label: String
        let createdAt: Date
        let systemFileName: String?
        let micFileName: String?
        let systemFileIdentity: FileIdentity?
        let micFileIdentity: FileIdentity?
        let totalBytes: Int64

        var hasSystemTrack: Bool { systemFileName != nil }
        var hasMicTrack: Bool { micFileName != nil }
    }

    /// Groups `<stem>-system.wav` and `<stem>-mic.wav` files in a folder into
    /// paired session summaries, newest first, excluding an active stem.
    static func scanRecordings(fileNames: [String],
                               sizes: [String: Int64],
                               dates: [String: Date],
                               identities: [String: FileIdentity] = [:],
                               excludingStem activeStem: String? = nil) -> [RecordingSummary] {
        struct Pair {
            var system: String?
            var mic: String?
            var systemIdentity: FileIdentity?
            var micIdentity: FileIdentity?
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
            guard !stem.isEmpty, isRecorderStem(stem), stem != activeStem else { continue }
            var pair = grouped[stem] ?? Pair()
            if isSystem {
                pair.system = name
                pair.systemIdentity = identities[name]
            } else {
                pair.mic = name
                pair.micIdentity = identities[name]
            }
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
                systemFileIdentity: pair.systemIdentity,
                micFileIdentity: pair.micIdentity,
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

/// Auto-record state machine for automatic call detection.
/// Keys solely off per-process Core Audio mic consumers excluding our own PID
/// and denied system daemons, with quiet-grace stop smoothing and post-manual-
/// stop suppression so an ongoing call never re-triggers.
struct MeetingAutoRecordDecider: Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case pending(trigger: MeetingMicConsumer, ticks: Int)
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
    private let confirmPolls: Int
    private let gracePolls: Int
    private let anyAppMode: Bool
    private var baselinePIDs: Set<pid_t> = []
    private var sawFirstTick = false

    init(ownPID: pid_t,
         knownCallApps: Set<String> = MeetingRecorderSupport.knownCallBundleIDs,
         denyList: Set<String> = MeetingRecorderSupport.defaultDenyList,
         confirmPolls: Int = 2,
         gracePolls: Int = 3,
         anyAppMode: Bool = true) {
        self.ownPID = ownPID
        self.knownCallApps = knownCallApps
        self.denyList = denyList
        self.confirmPolls = max(1, confirmPolls)
        self.gracePolls = max(1, gracePolls)
        self.anyAppMode = anyAppMode
    }

    mutating func tick(consumers: [MeetingMicConsumer]) -> Action {
        let external = consumers.filter { consumer in
            guard consumer.pid != ownPID else { return false }
            let normalized = MeetingRecorderSupport.normalizedCallBundleID(consumer.bundleID)
            return !denyList.contains(consumer.bundleID) && !denyList.contains(normalized)
        }
        // Startup baseline: unknown apps already holding the mic at
        // launch (always-on utilities) are ignored until they release once;
        // known call apps and browser helpers are never baselined.
        if !sawFirstTick {
            sawFirstTick = true
            baselinePIDs = Set(
                external
                    .filter { !MeetingRecorderSupport.isKnownCallBundleID($0.bundleID, knownCallApps: knownCallApps) }
                    .map(\.pid)
            )
        } else {
            baselinePIDs.formIntersection(Set(external.map(\.pid)))
        }

        var relevant = external.filter { !baselinePIDs.contains($0.pid) }
        if !anyAppMode {
            relevant = relevant.filter {
                MeetingRecorderSupport.isKnownCallBundleID($0.bundleID, knownCallApps: knownCallApps)
            }
        }
        let knownPresent = relevant.first {
            MeetingRecorderSupport.isKnownCallBundleID($0.bundleID, knownCallApps: knownCallApps)
        }

        switch phase {
        case .idle:
            if let trigger = knownPresent {
                phase = .active(trigger: trigger, quietTicks: 0)
                return .begin(trigger: trigger)
            }
            if anyAppMode, let candidate = relevant.first {
                if confirmPolls <= 1 {
                    phase = .active(trigger: candidate, quietTicks: 0)
                    return .begin(trigger: candidate)
                }
                phase = .pending(trigger: candidate, ticks: 1)
            }
            return .none

        case .pending(let candidate, let ticks):
            if let trigger = knownPresent {
                phase = .active(trigger: trigger, quietTicks: 0)
                return .begin(trigger: trigger)
            }
            let stillThere = relevant.contains { same($0, as: candidate) }
            guard stillThere else {
                phase = .idle
                return .none
            }
            let nextTicks = ticks + 1
            if nextTicks >= confirmPolls {
                phase = .active(trigger: candidate, quietTicks: 0)
                return .begin(trigger: candidate)
            }
            phase = .pending(trigger: candidate, ticks: nextTicks)
            return .none

        case .active(let trigger, let quiet):
            if relevant.isEmpty {
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
            if relevant.isEmpty {
                let nextQuiet = quiet + 1
                phase = nextQuiet >= gracePolls ? .idle : .suppressed(quietTicks: nextQuiet)
            } else {
                phase = .suppressed(quietTicks: 0)
            }
            return .none
        }
    }

    private func same(_ lhs: MeetingMicConsumer, as rhs: MeetingMicConsumer) -> Bool {
        rhs.bundleID == "(unknown)" ? lhs.pid == rhs.pid : lhs.bundleID == rhs.bundleID
    }

    /// Manual stop or failed start: stay quiet until the current call ends.
    mutating func noteRecordingStopped() {
        phase = .suppressed(quietTicks: 0)
    }

    /// Resets suppression and active state when auto-record is toggled off.
    mutating func reset() {
        phase = .idle
        baselinePIDs.removeAll()
        sawFirstTick = false
    }
}

/// Per-stream capture-health watchdog driven by persisted bytes on disk.
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
            if flatTicks >= kickAfter, !reportedStalled {
                reportedStalled = true
                return .stalled
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
