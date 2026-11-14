// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// A Claude Code session waiting for its person: it asked a question or needs
/// a permission. Claude Code's session logs cannot tell this apart from work
/// going on, so a hook Claude Code runs on those moments drops one small file
/// per waiting session in `AgentInputSupport.folder` and removes it when the
/// person answers or the turn ends.
struct AgentInputRequest: Equatable, Identifiable {
    enum Reason: String, Equatable {
        case question, permission
    }

    /// Claude's session id, which is also its log's file name.
    let session: String
    let reason: Reason
    let tool: String?
    /// The folder the session works in, for its name.
    let cwd: String
    let since: Date
    /// The app the session runs in, brought forward from the notice.
    let app: String?

    var id: String { session }
    var project: String { (cwd as NSString).lastPathComponent }
}

enum AgentInputSupport {
    /// Next to Claude Code's own files, where its hook can write without
    /// knowing which Vorssaint build reads it.
    static func folder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: ".claude/vorssaint/needs-input", directoryHint: .isDirectory)
    }

    /// A request left behind, as by a session that was killed mid-question,
    /// stops counting after this long.
    static let staleAfter: TimeInterval = 6 * 3600
    static let claudeAppBundleID = "com.anthropic.claudefordesktop"

    /// One file as the hook writes it: JSON with `session_id`, `reason`,
    /// `tool`, `cwd`, `app` and `since` (seconds since 1970). The file is
    /// named after the session, which wins when the two disagree.
    static func parse(_ data: Data, fileName: String) -> AgentInputRequest? {
        guard fileName.hasSuffix(".json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let session = String(fileName.dropLast(".json".count))
        guard isSessionID(session),
              let reason = (json["reason"] as? String).flatMap(AgentInputRequest.Reason.init(rawValue:)),
              let seconds = (json["since"] as? NSNumber)?.doubleValue, seconds.isFinite, seconds > 0 else { return nil }
        let tool = (json["tool"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let app = (json["app"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return AgentInputRequest(session: session, reason: reason, tool: tool,
                                 cwd: json["cwd"] as? String ?? "",
                                 since: Date(timeIntervalSince1970: seconds), app: app)
    }

    /// Claude's ids are UUIDs; anything else in the folder is not a request
    /// and never becomes a path.
    static func isSessionID(_ text: String) -> Bool {
        UUID(uuidString: text) != nil
    }

    static func isStale(_ request: AgentInputRequest, now: Date) -> Bool {
        now.timeIntervalSince(request.since) > staleAfter
    }

    /// The session a live turn belongs to: its log's file name.
    static func sessionID(forLog path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// The current requests, oldest first, and the files of stale ones to
    /// remove.
    static func read(folder: URL, now: Date,
                     fileManager: FileManager = .default) -> (requests: [AgentInputRequest], stale: [URL]) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return ([], []) }
        var requests: [AgentInputRequest] = []
        var stale: [URL] = []
        for name in names where name.hasSuffix(".json") {
            let url = folder.appending(path: name)
            guard let data = try? Data(contentsOf: url), data.count < 8192,
                  let request = parse(data, fileName: name) else { continue }
            if isStale(request, now: now) { stale.append(url) } else { requests.append(request) }
        }
        return (requests.sorted { $0.since < $1.since }, stale)
    }

    /// Requests that were not there before, for the notice.
    static func arrivals(_ requests: [AgentInputRequest], after previous: [AgentInputRequest]) -> [AgentInputRequest] {
        let known = Dictionary(previous.map { ($0.session, $0.since) }, uniquingKeysWith: { $1 })
        return requests.filter { known[$0.session] != $0.since }
    }
}

/// Watches the hook's folder while the AI section shows live activity and
/// publishes the sessions waiting for an answer.
final class AgentInputMonitor: ObservableObject {
    static let shared = AgentInputMonitor()

    @Published private(set) var requests: [AgentInputRequest] = []
    /// A session that has just started waiting.
    let arrived = PassthroughSubject<AgentInputRequest, Never>()

    private let folder: URL
    private var source: DispatchSourceFileSystemObject?
    private var sweep: Timer?
    private var pendingReload: DispatchWorkItem?

    init(folder: URL = AgentInputSupport.folder()) {
        self.folder = folder
    }

    var isRunning: Bool { source != nil }

    /// Starts watching; harmless when already watching.
    func start() {
        guard source == nil else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                               eventMask: [.write, .delete, .rename],
                                                               queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        // Stale requests age out with no file event to say so.
        let sweep = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.reload(announce: false) }
        sweep.tolerance = 10
        RunLoop.main.add(sweep, forMode: .common)
        self.sweep = sweep
        // What was already waiting at launch is the current state, not news.
        reload(announce: false)
    }

    func stop() {
        source?.cancel()
        source = nil
        sweep?.invalidate()
        sweep = nil
        pendingReload?.cancel()
        if !requests.isEmpty { requests = [] }
    }

    /// The hook writes a file in a few steps; one read after they settle.
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload(announce: true) }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func reload(announce: Bool) {
        let (current, stale) = AgentInputSupport.read(folder: folder, now: Date())
        for url in stale { try? FileManager.default.removeItem(at: url) }
        let arrivals = announce ? AgentInputSupport.arrivals(current, after: requests) : []
        if current != requests { requests = current }
        for request in arrivals { arrived.send(request) }
    }

    /// Brings forward the app the session runs in, the Claude app when the
    /// hook could not tell.
    static func bringForward(_ request: AgentInputRequest?) {
        let bundleID = request?.app ?? AgentInputSupport.claudeAppBundleID
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}
