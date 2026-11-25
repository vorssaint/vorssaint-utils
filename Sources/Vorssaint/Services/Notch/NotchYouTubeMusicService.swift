// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Reads YouTube Music's page in Safari, or in a web app added from Safari to
/// the Dock, through Accessibility: the songs up next while one plays, and
/// the home page's Listen again shelf while nothing does. Pressing a row
/// presses the page's own button, so the page plays it as a click would.
/// Nothing is stored: with no YouTube Music page open there is nothing to show.
final class NotchYouTubeMusicService: ObservableObject {
    typealias Row = NotchYouTubeMusicSupport.Row
    static let shared = NotchYouTubeMusicService()

    /// The songs after the playing one, or nil when no open page plays it.
    @Published private(set) var upcoming: [Row]?
    @Published private(set) var listenAgain: [Row] = []
    @Published private(set) var images: [URL: NSImage] = [:]
    @Published private(set) var loading = false
    @Published private(set) var actionPending = false
    @Published private(set) var actionFailed = false

    private enum Mode: Equatable {
        case off
        case queue(title: String)
        case listenAgain
    }
    private var mode = Mode.off
    private var timer: Timer?
    private var generation = 0
    private var imageLoads = Set<URL>()
    private lazy var session = URLSession(configuration: .ephemeral)

    /// Reads run one at a time, away from the main thread; the elements they
    /// found are kept there too, until the next read replaces them.
    private let work = DispatchQueue(label: "com.vorssaint.notch-youtube-music", qos: .userInitiated)
    private var elements: [AXUIElement] = []
    private var elementsGeneration = 0
    private var reading = false

    private init() {}

    static let refreshInterval: TimeInterval = 4
    static let maximumNodes = 12_000
    static let maximumImageBytes = 512 * 1_024

    // MARK: What is shown

    /// While the queue is shown for a song, the page that plays it is followed.
    func followQueue(title: String?) {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        set(title.isEmpty ? .off : .queue(title: title))
    }

    /// While nothing plays, the home page's Listen again shelf is followed.
    func followListenAgain(_ visible: Bool) {
        if visible { set(.listenAgain) } else if mode == .listenAgain { set(.off) }
    }

    func stopFollowingQueue() {
        if case .queue = mode { set(.off) }
    }

    func refresh() {
        guard mode != .off else { return }
        read()
    }

    private func set(_ next: Mode) {
        guard next != mode else { return }
        let wasQueue: Bool = { if case .queue = mode { return true }; return false }()
        mode = next
        generation += 1
        actionFailed = false
        actionPending = false
        timer?.invalidate()
        timer = nil
        switch next {
        case .off:
            upcoming = nil
            listenAgain = []
            loading = false
            trimImages()
            return
        case .queue:
            // A new song keeps the old list until the page is read again,
            // so the list does not flash empty between songs.
            if !wasQueue { upcoming = nil }
            listenAgain = []
        case .listenAgain:
            upcoming = nil
        }
        loading = true
        read()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in self?.read() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Playing a row

    func play(_ row: Row) {
        guard !actionPending, row.action >= 0 else { return }
        actionPending = true
        actionFailed = false
        let requested = generation
        work.async { [weak self] in
            guard let self else { return }
            let ok = self.elementsGeneration == requested && self.elements.indices.contains(row.action)
                && AXUIElementPerformAction(self.elements[row.action], kAXPressAction as CFString) == .success
            DispatchQueue.main.async {
                guard self.generation == requested else { return }
                self.actionPending = false
                self.actionFailed = !ok
                // The page takes a moment to move on to the song.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
            }
        }
    }

    // MARK: Reading the page

    private func read() {
        guard mode != .off, !reading else { return }
        guard AXIsProcessTrusted() else {
            loading = false
            upcoming = nil
            listenAgain = []
            return
        }
        reading = true
        let requested = generation
        let mode = self.mode
        work.async { [weak self] in
            guard let self else { return }
            var table: [AXUIElement] = []
            var queue: [Row]?
            var again: [Row] = []
            if let area = Self.webArea() {
                switch mode {
                case .queue(let title):
                    var parser = NotchYouTubeMusicSupport.QueueParser()
                    Self.walk(area, into: &table) { parser.feed($0); return false }
                    queue = parser.upcoming(after: title)
                case .listenAgain:
                    var parser = NotchYouTubeMusicSupport.ListenAgainParser()
                    Self.walk(area, into: &table) { parser.feed($0) }
                    again = parser.playable
                case .off:
                    break
                }
            }
            DispatchQueue.main.async {
                self.reading = false
                guard self.generation == requested else { return }
                self.loading = false
                if case .queue = mode { if self.upcoming != queue { self.upcoming = queue } }
                if mode == .listenAgain, self.listenAgain != again { self.listenAgain = again }
                self.loadImages()
            }
            self.elements = table
            self.elementsGeneration = requested
        }
    }

    /// A web app keeps the site it opens in its own bundle.
    private static func webAppOpensYouTubeMusic(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier, id.hasPrefix("com.apple.Safari.WebApp."),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
              let manifest = Bundle(url: url)?.object(forInfoDictionaryKey: "Manifest") as? [String: Any] else { return false }
        return ["start_url", "scope", "id"].contains { key in
            (manifest[key] as? String).flatMap(URL.init(string:))?.host?.lowercased() == NotchYouTubeMusicSupport.host
        }
    }

    /// The first open YouTube Music page: a web app's before Safari's tabs.
    private static func webArea() -> AXUIElement? {
        let apps = NSWorkspace.shared.runningApplications.filter { NotchYouTubeMusicSupport.isCandidate(bundleIdentifier: $0.bundleIdentifier) }
            .sorted { ($0.bundleIdentifier?.hasPrefix("com.apple.Safari.WebApp.") == true ? 0 : 1)
                < ($1.bundleIdentifier?.hasPrefix("com.apple.Safari.WebApp.") == true ? 0 : 1) }
        for app in apps where !app.isTerminated {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.5)
            let trustsBundle = webAppOpensYouTubeMusic(app)
            for window in (copy(element, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
                for area in webAreas(in: window) {
                    let url = copy(area, kAXURLAttribute).flatMap { $0 as? URL }
                    if NotchYouTubeMusicSupport.isYouTubeMusic(url) || (url == nil && trustsBundle) { return area }
                }
            }
        }
        return nil
    }

    /// The web pages in a window: Safari shows each window's front tab.
    private static func webAreas(in window: AXUIElement) -> [AXUIElement] {
        var found: [AXUIElement] = []
        var level = [window]
        var visited = 0
        for _ in 0..<12 where !level.isEmpty && visited < 600 {
            var next: [AXUIElement] = []
            for element in level {
                visited += 1
                if copy(element, kAXRoleAttribute) as? String == "AXWebArea" { found.append(element); continue }
                next += (copy(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
            }
            level = next
        }
        return found
    }

    private static let walkAttributes = [kAXRoleAttribute, kAXChildrenAttribute, "AXDOMClassList", kAXValueAttribute,
                                         kAXTitleAttribute, kAXDescriptionAttribute, kAXURLAttribute] as CFArray

    /// Walks the page in reading order, each element after the ones inside
    /// it, until `visit` says it has what it needs or the page grows too large.
    private static func walk(_ root: AXUIElement, into table: inout [AXUIElement],
                             visit: (NotchYouTubeMusicSupport.Entry) -> Bool) {
        var budget = maximumNodes
        var stop = false
        let deadline = Date().addingTimeInterval(3)
        @discardableResult
        func visitNode(_ element: AXUIElement, depth: Int) -> String {
            guard !stop, budget > 0, depth < 90 else { return "" }
            budget -= 1
            if budget % 256 == 0, Date() > deadline { stop = true; return "" }
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, walkAttributes, [], &raw) == .success,
                  let values = raw as? [AnyObject], values.count == 7 else { return "" }
            func value(_ index: Int) -> AnyObject? {
                let item = values[index]
                return CFGetTypeID(item) == AXValueGetTypeID() && AXValueGetType(item as! AXValue) == .axError ? nil : item
            }
            let role = value(0) as? String ?? ""
            var inner = ""
            for child in (value(1) as? [AXUIElement]) ?? [] {
                inner += visitNode(child, depth: depth + 1)
                if stop { return "" }
            }
            let own = value(3) as? String
            let label = [value(5) as? String, value(4) as? String].compactMap { $0 }.first { !$0.isEmpty }
            let text: String
            switch role {
            case "AXStaticText": text = own ?? ""
            case "AXButton", "AXLink", "AXImage": text = label ?? inner
            default: text = inner.isEmpty ? (label ?? "") : inner
            }
            let classes = Set((value(2) as? [String]) ?? [])
            let url = role == "AXImage" ? value(6).flatMap { $0 as? URL } : nil
            if role == "AXStaticText" || !classes.isEmpty || ["AXButton", "AXLink", "AXImage", "AXHeading"].contains(role) {
                table.append(element)
                let entry = NotchYouTubeMusicSupport.Entry(role: role, classes: classes,
                                                           text: text.split(whereSeparator: \.isNewline).joined(separator: " "),
                                                           url: url, ref: table.count - 1)
                if visit(entry) { stop = true }
            }
            return text
        }
        visitNode(root, depth: 0)
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    // MARK: Covers

    private func loadImages() {
        let rows = (upcoming ?? []) + listenAgain
        for url in Set(rows.compactMap(\.imageURL)) where images[url] == nil && !imageLoads.contains(url) {
            guard NotchYouTubeMusicSupport.isCoverURL(url) else { continue }
            imageLoads.insert(url)
            session.dataTask(with: url) { [weak self] data, response, _ in
                let image = data.flatMap { data -> NSImage? in
                    guard data.count <= Self.maximumImageBytes,
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                    return NSImage(data: data)
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.imageLoads.remove(url)
                    if let image { self.images[url] = image }
                }
            }.resume()
        }
        trimImages()
    }

    /// Only the covers of rows on show are kept.
    private func trimImages() {
        let shown = Set(((upcoming ?? []) + listenAgain).compactMap(\.imageURL))
        let kept = images.filter { shown.contains($0.key) }
        if kept.count != images.count { images = kept }
    }
}
