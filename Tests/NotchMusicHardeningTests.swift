// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import UniformTypeIdentifiers

private typealias ProductionLyricsParser = NotchLyricsSupport

/// Production lifecycle bodies are extracted by generate_sources.py. Only the
/// session, chooser, preference source and network entry point are test doubles.
enum NotchLyricsContract {
    enum State { case idle, consent, loading, unavailable, failed, ready }
    enum Preferences {
        static var enabled = true
        static var online = false
        static func isEnabled() -> Bool { enabled }
        static func onlineEnabled() -> Bool { enabled && online }
        static let maximumBytes = ProductionLyricsParser.maximumBytes
        static func parse(_ source: String, duration: Double) -> [NotchLyricLine] {
            ProductionLyricsParser.parse(source, duration: duration)
        }
    }
    typealias NotchLyricsSupport = Preferences
    final class Session {
        var cancelled = false
        func invalidateAndCancel() { cancelled = true }
    }
    final class Window {
        struct Level { let rawValue: Int }
        var level = Level(rawValue: 26)
        var isVisible = true
        var attached = false
        var focused = false
        var focusReturns = 0
    }
    typealias NSWindow = Window
    enum NSApplication { enum ModalResponse { case OK, cancel } }
    final class Panel {
        static weak var current: Panel?
        var level = Window.Level(rawValue: 0)
        var cancelled = false
        var focused = false
        var allowedContentTypes: [UTType] = []
        var allowsMultipleSelection = true
        var canChooseDirectories = true
        var message = ""
        var url: URL?
        weak var parent: Window?
        private var completed: ((NSApplication.ModalResponse) -> Void)?
        func begin(completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
            Self.current = self
            completed = completionHandler
        }
        func makeKeyAndOrderFront(_ sender: Any?) { focused = true }
        func finish(_ response: NSApplication.ModalResponse) {
            Self.current = nil
            completed?(response)
            parent?.focused = false
        }
        func cancel(_ sender: Any?) { cancelled = true; finish(.cancel) }
    }
    typealias NSOpenPanel = Panel
    enum L10n {
        static let shared = Localization()
        final class Localization { let language: AppLanguage = .enUS }
    }
    enum DispatchQueue {
        static var main = Queue()
        static var worker = Queue()
        static func global(qos: DispatchQoS.QoSClass) -> Queue { worker }
        final class Queue {
            var jobs: [() -> Void] = []
            func async(execute action: @escaping () -> Void) { jobs.append(action) }
            func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
        }
    }
    final class NotchService {
        static var shared = NotchService()
        var presentationWindow: Window? = Window()
        var acceptsSystemFeedback = true
        var expanded = true
        var selected: NotchModule = .music
        var showingAppPanel = false
        var selectedMetric: Bool?
        var captureControls: Bool?
        var pinned = false
        func open(_ module: NotchModule, feedback: Bool) {
            selected = module
            presentationWindow?.focused = true
            presentationWindow?.focusReturns += 1
        }
    }
    static let NSApp = Application()
    final class Application {
        func activate(ignoringOtherApps: Bool) {
            let notch = NotchService.shared
            if Panel.current == nil, !notch.pinned { notch.expanded = false }
        }
    }
    static func resetPresentation() {
        NotchService.shared = NotchService()
        DispatchQueue.main = DispatchQueue.Queue()
        DispatchQueue.worker = DispatchQueue.Queue()
    }
}

enum NotchQueueContract {
    enum Preferences { static func isEnabled() -> Bool { true } }
    typealias NotchQueueSupport = Preferences
}

/// Production control and recovery methods run with a deterministic scheduler
/// and a recording pipe, without a player process or a window.
enum NotchMusicCommandContract {
    enum NotchQueueSupport { static func isEnabled() -> Bool { true } }
    enum NotchLyricsService {
        static let shared = Reader()
        final class Reader { func playbackChanged(_ playback: NotchPlayback?) {} }
    }
    final class Scheduler {
        var jobs: [() -> Void] = []
        func async(execute action: @escaping () -> Void) { jobs.append(action) }
        func asyncAfter(deadline: DispatchTime, execute work: DispatchWorkItem) { jobs.append { work.perform() } }
        func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
    }
    enum DispatchQueue { static var main = Scheduler() }
    final class Process { var isRunning = true }
    final class Pipe {
        let fileHandleForWriting = Handle()
        final class Handle {
            var written: [Data] = []
            func write(contentsOf data: Data) throws { written.append(data) }
        }
    }
}

enum NotchMusicHardeningTests {
    private final class Scheduler {
        var work: [() -> Void] = []
        func enqueue(_ action: @escaping () -> Void) { work.append(action) }
        func drain() { while !work.isEmpty { work.removeFirst()() } }
    }

    static func run(_ suite: TestSuite) {
        sourcePriority(suite)
        sourceSwitching(suite)
        NotchPlaybackRoutingTests.run(suite)
        lyricExpansion(suite)
        lyricLifecycle(suite)
        lyricPicker(suite)
        queueSelection(suite)
        framing(suite)
        pendingCommands(suite)
        controlLifecycle(suite)
        NotchMusicAutomationTests.run(suite)
    }

    private static func sourceSwitching(_ suite: TestSuite) {
        let service = NotchMusicCommandContract.Service()
        service.start()
        var current = playback("music")
        current.commandContext = NotchPlaybackContext(pid: 42, revision: UUID())
        current.canSendCommandsDirectly = true
        service.playback = current
        let browser = NotchPlaybackSource(pid: 202, bundleIdentifier: "test.browser", isMusicApp: false,
                                          isPlaying: true, hasTrack: true)
        service.sources = [browser]
        service.selectSource(.init(pid: 202, bundleIdentifier: "missing.app"))
        suite.expect(service.playback == current && service.queue.jobs.isEmpty,
                     "an obsolete source menu cannot clear playback or queue a selection")
        service.selectSource(browser.selection)
        suite.expect(service.playback == nil && service.awaitingPlayback && !service.queueVisible,
                     "source switching retires the old controls and queue until new playback arrives")
        suite.expect(!service.send(.toggle, context: current.commandContext),
                     "a control rendered before the source switch cannot send to the old player")
        service.queue.drain()
        let request = service.input?.fileHandleForWriting.written.last.flatMap {
            String(data: $0, encoding: .utf8).flatMap { NotchPlaybackRequest(message: $0.trimmingCharacters(in: .newlines)) }
        }
        suite.expect(request == NotchPlaybackRequest(command: .source(browser.selection)),
                     "the production writer preserves the exact source chosen by the user")
        service.awaitingPlayback = false
        let count = service.input?.fileHandleForWriting.written.count ?? 0
        service.selectSource(browser.selection)
        service.queue.drain()
        suite.expect(service.awaitingPlayback && service.input?.fileHandleForWriting.written.count == count + 1,
                     "a discovered source is selectable from the empty playback state")
        suite.expect(!service.send(.toggle) && !service.send(.next) && !service.send(.seek(10)),
                     "allowing source selection without playback never enables transport commands")
        service.selectSource(nil)
        service.queue.drain()
        let automatic = service.input?.fileHandleForWriting.written.last.flatMap {
            String(data: $0, encoding: .utf8).flatMap { NotchPlaybackRequest(message: $0.trimmingCharacters(in: .newlines)) }
        }
        suite.expect(automatic == NotchPlaybackRequest(command: .source(nil)),
                     "a selected source that is not responding can be released from the empty state")
        service.stop()
    }

    private static func sourcePriority(_ suite: TestSuite) {
        func source(_ pid: Int32, music: Bool, playing: Bool = true, track: Bool = true) -> NotchPlaybackSource {
            NotchPlaybackSource(pid: pid, bundleIdentifier: "test.player.\(pid)", isMusicApp: music,
                                isPlaying: playing, hasTrack: track)
        }
        let music = source(10, music: true)
        let paused = source(10, music: true, playing: false)
        let browser = source(20, music: false)
        let other = source(30, music: true)
        func choose(_ sources: [NotchPlaybackSource], previous: Int32? = nil, system: Int32? = 20) -> NotchPlaybackSource? {
            NotchPlaybackSource.preferred(in: sources, previousPID: previous, systemPID: system)
        }
        suite.expect(choose([browser, music]) == music, "a browser video cannot take controls from playing music")
        suite.expect(choose([music, browser]) == music, "source discovery order does not change music priority")
        suite.expect(choose([browser, paused], previous: 10) == browser,
               "a video playing takes the island from music paused in the background")
        suite.expect(choose([browser, paused]) == browser,
               "the same holds on a first read, with nothing remembered")
        let idleBrowser = source(20, music: false, playing: false)
        suite.expect(NotchPlaybackSource.preferred(in: [music, browser], previousPID: 10, systemPID: 10,
                                                   selection: browser.selection) == browser,
                     "an explicit browser selection overrides simultaneous music playback")
        suite.expect(NotchPlaybackSource.preferred(in: [music, idleBrowser], previousPID: 20, systemPID: 10,
                                                   selection: browser.selection) == idleBrowser,
                     "pausing a chosen browser keeps its resume control reachable")
        suite.expect(NotchPlaybackSource.preferred(in: [music], previousPID: 20, systemPID: 10,
                                                   selection: browser.selection) == music,
                     "closing the chosen source restores automatic selection")
        suite.expect(NotchPlaybackSource.preferred(in: [music, source(20, music: false, track: false)],
                                                   previousPID: 20, systemPID: 10, selection: browser.selection) == music,
                     "a chosen source that loses its track no longer hides available playback")
        let decoded = NotchPlaybackSource.decode([browser.reply, music.reply, browser.reply])
        suite.expect(decoded == [music, browser], "source replies have stable ordering and reject duplicate processes")
        var helper = browser
        helper.displayName = "Safari"
        suite.expect(NotchPlaybackSource.decode([helper.reply]) == [helper] && helper.selection == browser.selection,
                     "a browser helper displays its owning app without changing the command destination")
        helper.displayName = String(repeating: "x", count: 257)
        suite.expect(NotchPlaybackSource.decode([helper.reply]).first?.displayName == nil,
                     "unbounded source names fall back to the local application name")
        var malformed = browser.reply
        malformed["pid"] = true
        suite.expect(NotchPlaybackSource.decode([malformed]).isEmpty
                     && NotchPlaybackSource.decode(Array(repeating: browser.reply, count: 17)).isEmpty,
                     "invalid and unbounded source replies cannot populate the chooser")
        for command in [NotchPlaybackCommand.source(browser.selection), .source(nil)] {
            let request = NotchPlaybackRequest(command: command)
            suite.expect(request.message.flatMap(NotchPlaybackRequest.init(message:)) == request,
                         "source selection round-trips without borrowing a playback revision")
        }
        for message in ["source 0 YXBw", "source 20 !!!", "source 20 ", "source-auto extra"] {
            suite.expect(NotchPlaybackRequest(message: message) == nil, "malformed source choices are rejected")
        }
        suite.expect(choose([idleBrowser, paused], previous: 10) == paused,
               "pausing music keeps its resume control reachable once nothing is playing")
        suite.expect(choose([idleBrowser, paused]) == paused, "reopening the music surface can still reach paused music")
        suite.expect(choose([browser, paused, other], previous: 10) == other,
               "playing music still outranks a playing browser and a paused music app")
        // A music app open but stopped, a video playing in the browser: the
        // island used to go blank, since paused music outranked everything.
        suite.expect(choose([paused, browser], previous: nil, system: 20) == browser,
               "a stopped music app left open never blanks the island over a playing video")
        suite.expect(choose([browser, source(10, music: true, track: false)]) == browser,
               "an empty music app does not hide browser playback")
        suite.expect(choose([browser], previous: 10) == browser, "closing the music app releases its priority")
        suite.expect(choose([source(10, music: true, track: false)], previous: 10) == nil,
               "clearing the track never preserves a stale music selection")
        suite.expect(choose([music, other, browser], previous: 30) == other,
               "two playing music apps keep the previously controlled app")
        suite.expect(choose([paused, other, browser], previous: 10) == other,
               "newly playing music takes priority over another app's paused track")
        suite.expect(choose([music, other], system: 30) == other,
               "the system's choice breaks an initial tie between playing music apps")
        suite.expect(choose([browser], system: 99) == nil, "an unrelated remembered video never becomes a fallback")
        suite.expect(choose([source(0, music: true), browser]) == browser, "invalid process identities are not controllable")
        suite.expect(choose([], previous: 10) == nil, "no surviving session leaves no command destination")
    }

    private static func lyricExpansion(_ suite: TestSuite) {
        let repeated = String(repeating: "[00:01]", count: 2000) + String(repeating: "x", count: 110_000)
        suite.expect(repeated.utf8.count < NotchLyricsSupport.maximumBytes,
               "the expansion regression fixture fits inside the transport's input bound")
        suite.expect(NotchLyricsSupport.parse(repeated, duration: 180).isEmpty,
               "many timestamps cannot amplify a small response into hundreds of megabytes")
        let voices = (0..<2000).map { "[00:01]voice \($0)" }.joined(separator: "\n")
        let grouped = NotchLyricsSupport.parse(voices, duration: 180)
        suite.expect(grouped.count == 1 && grouped.first?.text.hasPrefix("voice 0\nvoice 1\n") == true
               && grouped.first?.text.hasSuffix("voice 1999") == true,
               "grouping equal timestamps preserves ordered voices with one final join")
        suite.expect(grouped.reduce(0) { $0 + $1.text.utf8.count } <= NotchLyricsSupport.maximumBytes,
               "the expanded display text stays within the same byte budget")
        let distinct = (0..<2000).map { "[\($0 / 60):\($0 % 60)]" }.joined() + String(repeating: "界", count: 30)
        suite.expect(distinct.utf8.count < NotchLyricsSupport.maximumBytes
               && NotchLyricsSupport.parse(distinct, duration: 2200).isEmpty,
               "the expansion bound counts UTF-8 bytes across distinct timestamps as well")
        let normal = NotchLyricsSupport.parse("[00:01][00:03]Chorus\n[00:02]", duration: 10)
        suite.expect(normal.map(\.text) == ["Chorus", "", "Chorus"], "normal repeated verses and timed instrumental gaps still work")
    }

    private static func playback(_ item: String) -> NotchPlayback {
        let track = RadialNowPlayingSnapshot(title: item, artist: "Example", album: "Recording",
            artworkData: nil, appBundleIdentifier: "org.example.player", appPID: 42)
        return NotchPlayback(track: track, isPlaying: true, elapsed: 0, duration: 180, rate: 1,
            sampledAt: Date(timeIntervalSinceReferenceDate: 0), canSeek: false, itemIdentifier: item)
    }

    private static func lyricLifecycle(_ suite: TestSuite) {
        NotchLyricsContract.Preferences.enabled = true
        NotchLyricsContract.Preferences.online = false
        defer { NotchLyricsContract.Preferences.enabled = true; NotchLyricsContract.Preferences.online = false }
        let current = playback("current"), next = playback("next")
        let identity = NotchMusicIdentity(current)
        let imported = NotchLyrics(lines: [NotchLyricLine(time: 1, text: "Imported")], plain: "", instrumental: false)
        let service = NotchLyricsContract.Service()
        service.update(playback: current, visible: true)
        _ = service.memory.replace(imported, for: identity)
        service.memory.adjustOffset(by: 0.75)
        let generation = service.generation
        service.hide()
        suite.expect(!service.visible && service.generation != generation && service.lyrics == imported
               && service.memory.offset == 0.75, "the real hide path cancels work without discarding this song's imported lyrics or adjustment")
        service.update(playback: current, visible: true)
        suite.expect(service.state == .ready && service.lyrics == imported && service.loads.isEmpty
               && service.memory.offset == 0.75, "returning to the same song reuses its import without a network request")
        service.update(playback: current, visible: false)
        service.update(playback: nil, visible: false)
        suite.expect(service.lyrics == imported, "hiding or stopping the metadata consumer is not evidence that the song changed")
        service.playbackChanged(next)
        suite.expect(service.track == NotchMusicIdentity(next) && service.lyrics == nil && service.memory.offset == 0,
               "an observed track change clears the one-song cache while hidden")
        suite.expect(!service.memory.replace(imported, for: identity), "a late result cannot replace the new recording's lyrics")
        service.playbackChanged(nil)
        suite.expect(service.track == nil && service.lyrics == nil, "an actual empty playback snapshot clears the cache")
        NotchLyricsContract.Preferences.online = true
        service.update(playback: current, visible: true)
        let download = service.session
        let panel = NotchLyricsContract.Panel(); service.importPanel = panel
        let requested = service.generation
        service.hide()
        suite.expect(download?.cancelled == true && panel.cancelled && service.session == nil && service.importPanel == nil
               && service.generation != requested, "hiding executes the real cancellation path for both remote lookup and file selection")
        service.update(playback: current, visible: false)
        suite.expect(service.loads.count == 1, "a hidden song never starts an online lookup")
        service.update(playback: current, visible: true)
        suite.expect(service.loads.count == 2, "reopening an uncached song starts one fresh lookup")
        _ = service.memory.replace(imported, for: identity)
        service.memory.adjustOffset(by: 1)
        service.stop()
        suite.expect(service.track == nil && service.lyrics == nil && service.memory.offset == 0 && !service.visible,
               "explicit shutdown releases the retained song, lyrics and offset")
        service.update(playback: current, visible: true)
        _ = service.memory.replace(imported, for: identity)
        NotchLyricsContract.Preferences.enabled = false
        service.hide()
        suite.expect(service.lyrics == nil && service.track == nil, "feature removal clears the cache even when it arrives through the hide path")
    }

    private static func lyricPicker(_ suite: TestSuite) {
        typealias Context = NotchLyricsContract
        Context.Preferences.enabled = true
        Context.Preferences.online = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notch-lyrics-picker-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder); Context.resetPresentation() }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("selected.lrc")
            try "[00:01]Selected verse".write(to: file, atomically: true, encoding: .utf8)
            for pinned in [false, true] {
                Context.resetPresentation()
                let service = Context.Service()
                let notch = Context.NotchService.shared
                let parent = notch.presentationWindow!
                notch.pinned = pinned
                service.update(playback: playback("same-song"), visible: true)
                service.importLyrics()
                guard let panel = service.importPanel else { suite.expect(false, "a visible lyrics surface can choose a file"); continue }
                suite.expect(panel.parent == nil && !parent.attached && panel.focused && panel.level.rawValue > parent.level.rawValue
                       && notch.expanded && notch.pinned == pinned,
                       "lyrics imports focus a standalone chooser above the island without moving it or changing its pin")
                panel.url = file
                panel.finish(.OK)
                suite.expect(!parent.focused && service.lyrics == nil,
                       "the picker waits for native dismissal and imports off the presentation lane")
                Context.DispatchQueue.main.drain()
                suite.expect(parent.focused && parent.focusReturns == 1 && notch.selected == .music && notch.pinned == pinned,
                       "dismissal returns to the same music and lyrics surface without pinning it")
                Context.DispatchQueue.worker.drain()
                Context.DispatchQueue.main.drain()
                suite.expect(service.lyrics?.lines.first?.text == "Selected verse" && service.visible,
                       "the real bounded import and parser retain the chosen lyrics for the unchanged song")
            }
            for interruption in 0..<6 {
                Context.resetPresentation()
                let service = Context.Service()
                let parent = Context.NotchService.shared.presentationWindow!
                service.update(playback: playback("same-song"), visible: true)
                service.importLyrics()
                let panel = service.importPanel!
                panel.url = file
                switch interruption {
                case 0: service.hide()
                case 1: service.playbackChanged(playback("next-song"))
                case 2: Context.NotchService.shared.acceptsSystemFeedback = false
                case 3: Context.NotchService.shared.selected = .downloads
                case 4: Context.NotchService.shared.presentationWindow = Context.Window()
                default: Context.Preferences.enabled = false
                }
                panel.finish(.OK)
                Context.DispatchQueue.worker.drain()
                Context.DispatchQueue.main.drain()
                suite.expect(parent.focusReturns == 0 && service.lyrics == nil,
                       "hide, track change, lock, another section, replacement or disable rejects the old import and focus")
                Context.Preferences.enabled = true
            }
            Context.resetPresentation()
            let cancelled = Context.Service()
            cancelled.update(playback: playback("same-song"), visible: true)
            let old = NotchLyrics(lines: [NotchLyricLine(time: 1, text: "Existing verse")], plain: "", instrumental: false)
            _ = cancelled.memory.replace(old, for: NotchMusicIdentity(playback("same-song")))
            cancelled.memory.adjustOffset(by: 0.5)
            cancelled.importLyrics()
            cancelled.importPanel?.finish(.cancel)
            Context.DispatchQueue.main.drain()
            suite.expect(cancelled.lyrics == old && cancelled.memory.offset == 0.5
                   && Context.DispatchQueue.worker.jobs.isEmpty && Context.NotchService.shared.presentationWindow?.focused == true,
                   "Cancel keeps the current lyrics and adjustment and returns without reading a file")
            cancelled.importLyrics()
            cancelled.importPanel?.url = file
            cancelled.importPanel?.finish(.OK)
            let returns = Context.NotchService.shared.presentationWindow!.focusReturns
            cancelled.hide()
            Context.DispatchQueue.worker.drain()
            Context.DispatchQueue.main.drain()
            suite.expect(Context.NotchService.shared.presentationWindow!.focusReturns == returns && cancelled.lyrics == old,
                   "leaving after dismissal cancels both the queued focus return and a late file result")
        } catch { suite.expect(false, "lyrics picker fixture failed: \(error)") }
    }

    private static func selection(_ request: UUID, item: String = "next") -> NotchQueueSelection {
        NotchQueueSelection(requestID: request, pid: 42, currentIdentifier: "current", itemIdentifier: item, offset: 2)
    }

    private static func queueSelection(_ suite: TestSuite) {
        let selected = selection(UUID())
        suite.expect(selected.matches(pid: 42, currentIdentifier: "current", itemIdentifier: "next", offset: 2),
               "the native action can match exactly the immutable row the user chose")
        suite.expect(!selected.matches(pid: 43, currentIdentifier: "current", itemIdentifier: "next", offset: 2)
               && !selected.matches(pid: 42, currentIdentifier: "changed", itemIdentifier: "next", offset: 2)
               && !selected.matches(pid: 42, currentIdentifier: "current", itemIdentifier: "different", offset: 2)
               && !selected.matches(pid: 42, currentIdentifier: "current", itemIdentifier: "next", offset: 3),
               "a refreshed native cache cannot retarget a queued click to another player, track, entry or offset")
        let command = NotchPlaybackCommand.queuePlay(selected)
        suite.expect(command.message.flatMap(NotchPlaybackCommand.init(message:)) == command,
               "process, anchor track and native offset all survive the command transport")
        suite.expect(NotchPlaybackCommand(message: "queue-play \(selected.requestID.uuidString) bmV4dA==") == nil,
               "the old unbound command shape is rejected")
        suite.expect(!selection(UUID(), item: "bad\0item").isValid,
               "the row, writer and native bridge share rejection of NUL identifiers")

        let service = NotchQueueContract.Service()
        let row = NotchQueueItem(id: "next", offset: 2, title: "Next", artist: "", duration: 0)
        service.queueRequest = selected.requestID
        service.playback = playback("current")
        service.upcoming = NotchQueueSnapshot(requestID: selected.requestID, currentIdentifier: "current", pid: 42,
            items: [row], canPlay: true)
        service.sendAllowed = false
        service.playQueued(row)
        suite.expect(!service.queueActionPending && service.queueActionFailed,
               "the real row action releases pending state when the writer rejects a command")
        service.commands.removeAll()
        service.sendAllowed = true
        service.playQueued(row)
        suite.expect(service.commands == [.queuePlay(selected)] && service.queueActionPending,
               "the real UI action captures its displayed process, current song, requested item and native offset")
        service.queueVisible = false
        service.queueActionPending = false
        service.playQueued(row)
        suite.expect(service.commands.count == 1, "a hidden queue cannot enqueue another row action")
    }

    private static func framing(_ suite: TestSuite) {
        let request = UUID()
        let large = NotchQueueSelection(requestID: request, pid: 42,
            currentIdentifier: String(repeating: "c", count: 512), itemIdentifier: String(repeating: "n", count: 512), offset: 20)
        let context = NotchPlaybackContext(pid: 42, revision: UUID())
        let commands = [NotchPlaybackCommand.queue(request), .queuePlay(large), .queueStop, .previous, .next]
            .map { NotchPlaybackRequest(command: $0, context: context) }
        let batch = Data(commands.compactMap(\.message).map { $0 + "\n" }.joined().utf8)
        suite.expect(batch.count > 1024, "the framing fixture exceeds the old combined-buffer limit")
        var framer = NotchPlaybackCommandFramer()
        suite.expect(framer.append(batch).compactMap { $0 } == commands, "one pipe delivery preserves every complete command, including queue-stop")
        var split = NotchPlaybackCommandFramer()
        var decoded: [NotchPlaybackRequest] = []
        for byte in batch { decoded += split.append(Data([byte])).compactMap { $0 } }
        suite.expect(decoded == commands, "commands survive arbitrary byte boundaries")
        var bad = NotchPlaybackCommandFramer()
        let next = NotchPlaybackRequest(command: .next, context: context)
        let oversized = Data((String(repeating: "x", count: NotchPlaybackCommand.maximumMessageBytes + 1) + "\nqueue-stop\n" + next.message! + "\n").utf8)
        let recovered = bad.append(oversized)
        suite.expect(recovered.count == 3 && recovered[0] == nil && recovered[1]?.command == .queueStop && recovered[2] == next,
               "an oversized frame cannot swallow the following cancellation or valid command")
        var unterminated = NotchPlaybackCommandFramer()
        suite.expect(unterminated.append(Data(String(repeating: "x", count: 100_000).utf8)).isEmpty,
               "a long unterminated frame is discarded without retaining the growing input")
        suite.expect(unterminated.append(Data("\nqueue-stop\n".utf8)).compactMap { $0?.command } == [.queueStop],
               "the framer resumes at the next newline after a rejected partial frame")
        for message in ["toggle", "next", "previous", "seek 75", "play 0 \(context.revision) next",
                        "play 42 invalid next", "play 42 \(context.revision) queue-stop"] {
            suite.expect(NotchPlaybackRequest(message: message) == nil, "unbound or malformed playback context cannot reach native dispatch")
        }
    }

    private static func pendingCommands(_ suite: TestSuite) {
        let scheduler = Scheduler()
        let writer = NotchMusicCommandWriter(schedule: scheduler.enqueue)
        var written: [NotchPlaybackCommand] = []
        var failures = 0
        func write(_ data: Data) throws {
            let message = String(data: data, encoding: .utf8)!.trimmingCharacters(in: .newlines)
            if let request = NotchPlaybackRequest(message: message) { written.append(request.command) }
        }
        let first = UUID(), second = UUID()
        writer.start(); writer.setQueueRequest(first)
        suite.expect(writer.submit(.queue(first), write: write, failed: { failures += 1 }), "an active query is accepted for scheduling")
        writer.setQueueRequest(nil)
        _ = writer.submit(.queueStop, write: write, failed: { failures += 1 })
        scheduler.drain()
        suite.expect(written == [.queueStop] && failures == 0, "closing the queue cancels an unsent query while preserving its native stop")
        written.removeAll()
        writer.setQueueRequest(first)
        _ = writer.submit(.queuePlay(selection(first)), write: write, failed: { failures += 1 })
        writer.setQueueRequest(second)
        _ = writer.submit(.queue(second), write: write, failed: { failures += 1 })
        scheduler.drain()
        suite.expect(written == [.queue(second)], "replacing the queue request cancels an unsent play from the previous surface")
        written.removeAll()
        let context = NotchPlaybackContext(pid: 42, revision: UUID())
        _ = writer.submit(.previous, context: context, write: write, failed: { failures += 1 })
        writer.stop(); writer.start()
        scheduler.drain()
        suite.expect(written.isEmpty, "a new adapter process cannot inherit an old pending transport command")
        writer.setQueueRequest(first)
        suite.expect(!writer.submit(.queuePlay(selection(first, item: "bad\0item")), write: write, failed: { failures += 1 })
               && scheduler.work.isEmpty, "invalid identifiers are rejected synchronously so the UI can release its pending state")
        _ = writer.submit(.queue(first), write: { _ in throw NSError(domain: "Test", code: 1) }, failed: { failures += 1 })
        scheduler.drain()
        suite.expect(failures == 1, "an actual write failure is delivered to its still-active request")
        _ = writer.submit(.queue(first), write: { _ in writer.stop(); throw NSError(domain: "Test", code: 1) }, failed: { failures += 1 })
        scheduler.drain()
        suite.expect(failures == 1, "a retired request's write failure cannot alter its replacement")
        suite.expect(!writer.submit(.next, context: context, write: write, failed: { failures += 1 }), "stopped transports reject new commands immediately")
    }

    private static func controlLifecycle(_ suite: TestSuite) {
        typealias Contract = NotchMusicCommandContract
        typealias Adapter = NotchPlaybackRoutingContract
        Contract.DispatchQueue.main = Contract.Scheduler()
        defer {
            Contract.DispatchQueue.main = Contract.Scheduler()
            Adapter.metadata = [:]
            Adapter.publish(nil)
        }
        let service = Contract.Service()
        let nativePath = NSObject()
        let native = Adapter.Target(pid: 42, path: nativePath)
        var metadata: [String: Any] = ["kMRMediaRemoteNowPlayingInfoTitle": "same-title",
                                      "kMRMediaRemoteNowPlayingInfoContentItemIdentifier": "A"]
        Adapter.metadata[ObjectIdentifier(nativePath)] = metadata
        let context = Adapter.publish(native, info: metadata)!
        var current = playback("same-title")
        current.commandContext = context
        current.canSendCommandsDirectly = true
        service.start()
        service.playback = current
        service.seek(to: 75, in: current.track, context: context)
        service.queue.drain()
        func requests() -> [NotchPlaybackRequest] {
            (service.input?.fileHandleForWriting.written ?? []).compactMap {
                String(data: $0, encoding: .utf8).flatMap {
                    NotchPlaybackRequest(message: $0.trimmingCharacters(in: .newlines))
                }
            }
        }
        // The shared playback helper disables seeking; explicitly enable it for this control fixture.
        suite.expect(requests().isEmpty, "read-only native playback cannot enqueue a seek")
        current = NotchPlayback(track: current.track, isPlaying: true, elapsed: 0, duration: 180, rate: 1,
                                sampledAt: Date(), canSeek: true, itemIdentifier: "A", commandContext: context,
                                canSendCommandsDirectly: true)
        service.playback = current
        service.seek(to: 75, in: current.track, context: context)
        service.queue.drain()
        suite.expect(requests().last == NotchPlaybackRequest(command: .seek(75), context: context),
               "the production seek and writer preserve the gesture's process and recording revision")
        Adapter.command = nil
        Adapter.sendPlaybackCommand(requests().last!)
        suite.expect(Adapter.command == 24 && Adapter.destination === nativePath,
               "a stable gesture traverses the real writer, decoder, validation and native dispatch")
        var changed = current
        metadata["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] = "B"
        Adapter.metadata[ObjectIdentifier(nativePath)] = metadata
        changed.commandContext = Adapter.publish(native, info: metadata)
        Adapter.command = nil
        Adapter.sendPlaybackCommand(requests().last!)
        suite.expect(Adapter.command == nil,
               "a written gesture from the old recording is rejected when native playback changes before dispatch")
        service.playback = changed
        let before = requests().count
        service.seek(to: 90, in: current.track, context: context)
        suite.expect(!service.send(.toggle, context: context) && !service.send(.next, context: nil),
               "an obsolete rendered control or missing revision cannot borrow the current recording")
        service.queue.drain()
        suite.expect(requests().count == before,
               "identical visible metadata cannot retarget an earlier gesture after the recording revision changes")
        _ = service.send(.previous)
        service.queue.drain()
        suite.expect(requests().last?.context == changed.commandContext,
               "the gesture route captures its current playback context at submission")
        _ = service.send(.next)
        let pipe = service.input!
        service.stop()
        service.queue.drain()
        suite.expect(pipe.fileHandleForWriting.written.count == before + 1,
               "closing the last music consumer cancels its still-unwritten controls")

        suite.expect(!service.awaitingPlayback, "a stopped subscription is not waiting for a reading")
        service.start()
        let launches = service.launches
        suite.expect(service.awaitingPlayback, "a fresh subscription waits for the adapter's first reply before reporting nothing playing")
        service.connectionEnded()
        for _ in 0..<100 { service.start() }
        suite.expect(service.launches == launches && Contract.DispatchQueue.main.jobs.count == 1,
               "preference updates cannot bypass a pending recovery or launch extra helpers")
        suite.expect(service.awaitingPlayback, "a pending recovery keeps the first reading outstanding")
        Contract.DispatchQueue.main.drain()
        suite.expect(service.launches == launches + 1, "unexpected termination receives one delayed recovery while music is wanted")
        service.connectionEnded()
        Contract.DispatchQueue.main.drain()
        service.connectionEnded()
        for _ in 0..<100 { service.start() }
        suite.expect(service.launches == launches + 2 && Contract.DispatchQueue.main.jobs.isEmpty,
               "persistent failure stops after two retries even if preferences continue changing")
        suite.expect(!service.awaitingPlayback, "giving up on the adapter ends the wait so the empty state can show")
        service.stop()
        service.start()
        service.connectionEnded()
        let cancelledLaunches = service.launches
        service.stop()
        Contract.DispatchQueue.main.drain()
        suite.expect(service.launches == cancelledLaunches && !service.wantsPlayback && !service.awaitingPlayback,
               "disabling, hiding the last consumer or suspending cancels delayed recovery")
        service.start()
        service.connectionEnded()
        service.stop()
        service.start()
        let replacementLaunches = service.launches
        Contract.DispatchQueue.main.drain()
        suite.expect(service.launches == replacementLaunches,
               "a delayed recovery from an ended subscription cannot launch inside its replacement")

        for raw: Any in [true, 0, -1, 42.5, Double(Int32.max) + 1] {
            suite.expect(NotchPlaybackContext(reply: ["pid": raw, "playbackRevision": UUID().uuidString]) == nil,
                   "metadata cannot bind controls to malformed process identities")
        }
        let raw: [String: Any] = ["pid": 42, "playbackRevision": context.revision.uuidString]
        suite.expect(NotchPlaybackContext(reply: raw) == context,
               "the recording revision survives the adapter reply without depending on UUID letter case")
    }
}
