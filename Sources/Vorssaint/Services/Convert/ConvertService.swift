// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// The island's file tools: the files dropped on "Convert here" or dragged with a
/// key held, what they can become (Convert), what can be done to them (Tools and
/// Actions), the options for the choice, and the run. ConvertPanelView draws it.
@MainActor
final class ConvertService: ObservableObject {
    static let shared = ConvertService()

    enum Mode: String, CaseIterable, Identifiable {
        case convert, tools, actions
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .convert: return "arrow.triangle.2.circlepath"
            case .tools: return "wand.and.stars"
            case .actions: return "bolt.fill"
            }
        }
    }

    enum Tile: Hashable {
        case format(FileFormat)
        case tool(ToolID)
        case action(ConvertAction)
    }

    enum Stage: Equatable { case tiles, options(FileFormat), tool(ToolID), running }

    struct Session: Identifiable {
        let id = UUID()
        let urls: [URL]
        let sources: [FileFormat]
        let targets: [FileFormat]
        let tools: [ToolID]
        var category: FormatCategory { sources.first?.category ?? .document }
    }

    @Published private(set) var dragging = false
    @Published private(set) var hoverTile: Tile?
    @Published private(set) var session: Session?
    @Published private(set) var stage: Stage = .tiles
    @Published private(set) var mode: Mode = .convert
    /// Which way the last change of page went: +1 toward Actions, -1 toward Convert.
    @Published private(set) var modeStep = 1
    @Published var options = ConvertOptions()
    @Published var toolValues = ToolValues()
    /// A short line after an action that finishes at once, such as "Paths copied".
    @Published private(set) var note: String?
    private var noteWork: DispatchWorkItem?

    /// The page's height while it is open, as the island sizes its files page.
    static let pageHeight: CGFloat = 312
    /// The extra height a tool with a live preview gives the island, for the picture under its controls.
    static let previewHeight: CGFloat = 196

    /// The page's height now: taller while a tool that shows a live preview is open.
    var currentPageHeight: CGFloat {
        if case .tool(let tool) = stage, let session, ConvertPreview.supports(tool, category: session.category) {
            return Self.pageHeight + Self.previewHeight
        }
        return Self.pageHeight
    }

    private var autoCloseWork: DispatchWorkItem?
    private var pointerInside = false
    private var batchSubscription: AnyCancellable?

    private init() {
        // A finished batch starts the clock that puts the island back to normal.
        batchSubscription = JobRunner.shared.finishedBatch.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.rearmAutoClose() }
    }

    var isOpen: Bool { session != nil }

    // MARK: Returning to the normal island

    /// How long the page waits before it closes itself, or nil while work is under way or a
    /// drag is in progress. Results go after a few seconds, a failure after longer so its
    /// message can be read, and a page nobody touched after a while.
    private var autoCloseDelay: TimeInterval? {
        guard session != nil, !dragging else { return nil }
        let jobs = JobRunner.shared.jobs
        if case .running = stage {
            guard !jobs.isEmpty, jobs.allSatisfy({ $0.status.isFinished }) else { return nil }
            let failed = jobs.contains { if case .failed = $0.status { return true } else { return false } }
            return failed ? 12 : 6
        }
        return 25
    }

    /// Restarts the countdown. The pointer on the island holds it off, so a result being read is not taken away.
    func rearmAutoClose() {
        autoCloseWork?.cancel()
        autoCloseWork = nil
        guard let delay = autoCloseDelay, !pointerInside else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.session != nil, !self.pointerInside, self.autoCloseDelay != nil else { return }
            self.close()
        }
        autoCloseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func setPointerInside(_ inside: Bool) {
        pointerInside = inside
        rearmAutoClose()
    }

    /// Shows the results in Finder and puts the island back.
    func showFile(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.close() }
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.close() }
    }

    var tiles: [Tile] {
        guard let session else { return [] }
        switch mode {
        case .convert: return session.targets.map(Tile.format)
        case .tools: return session.tools.map(Tile.tool)
        case .actions: return ConvertAction.allCases.map(Tile.action)
        }
    }

    // MARK: Dragging over the island

    func canConvert(_ urls: [URL]) -> Bool {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.convertEnabled),
              !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { return false }
        let sources = urls.compactMap(FileFormat.detect)
        // Anything can be acted on; only known types convert or take tools.
        return sources.count != urls.count || !Self.targets(for: sources).isEmpty || !ConvertTools.available(for: sources).isEmpty
    }

    func canConvert(_ pasteboard: NSPasteboard) -> Bool {
        let urls = ShelfService.shared.fileURLs(from: pasteboard)
        guard urls.count >= (pasteboard.pasteboardItems?.count ?? 0) else { return false }
        return canConvert(urls)
    }

    /// The formats the files can become, less those the person hid in settings.
    nonisolated static func targets(for sources: [FileFormat]) -> [FileFormat] {
        let hidden = Set((UserDefaults.standard.string(forKey: DefaultsKey.convertHiddenFormats) ?? "")
            .split(separator: ",").map(String.init))
        return ConversionMatrix.targets(for: sources).filter { !hidden.contains($0.rawValue) }
    }

    // MARK: Session

    @discardableResult
    func begin(_ urls: [URL], mode start: Mode = .convert) -> Bool {
        guard canConvert(urls) else { return false }
        let sources = urls.compactMap(FileFormat.detect)
        let known = sources.count == urls.count
        options = ConvertOptions()
        session = Session(urls: urls, sources: sources,
                          targets: known ? Self.targets(for: sources) : [],
                          tools: known ? ConvertTools.available(for: sources) : [])
        stage = .tiles
        note = nil
        rearmAutoClose()
        // A mode with nothing to offer falls back to the next that has something.
        setMode(start)
        if tiles.isEmpty, let other = Mode.allCases.first(where: { modeHasTiles($0) }) { setMode(other) }
        return true
    }

    @discardableResult
    func begin(_ pasteboard: NSPasteboard) -> Bool {
        begin(ShelfService.shared.fileURLs(from: pasteboard))
    }

    func modeHasTiles(_ candidate: Mode) -> Bool {
        guard let session else { return false }
        switch candidate {
        case .convert: return !session.targets.isEmpty
        case .tools: return !session.tools.isEmpty
        case .actions: return true
        }
    }

    /// A swipe: the next page in that direction that has something to offer. False at either end.
    @discardableResult
    func stepMode(by step: Int) -> Bool {
        guard session != nil, stage == .tiles, let index = Mode.allCases.firstIndex(of: mode) else { return false }
        var candidate = index + step
        while Mode.allCases.indices.contains(candidate) {
            if modeHasTiles(Mode.allCases[candidate]) { setMode(Mode.allCases[candidate]); return true }
            candidate += step
        }
        return false
    }

    func setMode(_ next: Mode) {
        defer { rearmAutoClose() }
        guard mode != next || stage != .tiles else { return }
        if mode != next, let from = Mode.allCases.firstIndex(of: mode), let to = Mode.allCases.firstIndex(of: next) { modeStep = to > from ? 1 : -1 }
        mode = next
        if case .running = stage {} else { stage = .tiles }
        hoverTile = nil
    }

    // MARK: Dragging with a key held

    @discardableResult
    func beginDrag(_ urls: [URL], mode start: Mode) -> Bool {
        guard begin(urls, mode: start) else { return false }
        dragging = true
        hoverTile = nil
        return true
    }

    func setHover(_ tile: Tile?) {
        if hoverTile != tile { hoverTile = tile }
    }

    func cancelDrag() {
        guard dragging else { return }
        dragging = false
        hoverTile = nil
        session = nil
        stage = .tiles
    }

    /// Dropped on a tile: it behaves as if clicked.
    func dropOnHover() -> Bool {
        guard dragging, let tile = hoverTile else { return false }
        dragging = false
        hoverTile = nil
        choose(tile)
        return true
    }

    // MARK: Choosing

    func choose(_ tile: Tile) {
        switch tile {
        case .format(let format): choose(format)
        case .tool(let tool): chooseTool(tool)
        case .action(let action): perform(action)
        }
    }

    func choose(_ format: FileFormat) {
        guard session != nil else { return }
        options = ConvertOptions()
        if ConvertOptionCatalog.hasOptions(for: format, from: session?.category ?? .document) { stage = .options(format); rearmAutoClose() } else { run(format) }
    }

    func chooseTool(_ tool: ToolID) {
        guard let session else { return }
        var values = ConvertTools.defaults(for: tool, formats: session.sources)
        if ConvertTools.fields(for: tool, formats: session.sources).isEmpty {
            toolValues = values
            runTool(tool)
            return
        }
        toolValues = values
        stage = .tool(tool)
        rearmAutoClose()
        Task { [urls = session.urls] in
            await ConvertTools.prepare(tool, urls: urls, values: &values)
            if case .tool(tool) = stage { toolValues = values }
        }
    }

    func perform(_ action: ConvertAction) {
        guard let session else { return }
        let text = action.run(session.urls)
        if !text.isEmpty { showNote(text) } else if JobRunner.shared.hasWork { stage = .running }
    }

    func showNote(_ text: String) {
        note = text
        noteWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.note = nil }
        noteWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    func back() {
        if stage != .tiles, stage != .running { stage = .tiles }
        rearmAutoClose()
    }

    func run(_ format: FileFormat) {
        guard let session else { return }
        stage = .running
        rearmAutoClose()
        JobRunner.shared.convert(session.urls, to: format, options: options)
    }

    func runTool(_ tool: ToolID) {
        guard let session else { return }
        stage = .running
        rearmAutoClose()
        ConvertToolRunner.run(tool, urls: session.urls, values: toolValues)
    }

    /// Back to the tiles, for another go with the same files.
    func again() {
        JobRunner.shared.dismissAll()
        stage = .tiles
        rearmAutoClose()
    }

    /// Ends the page and puts the island back to its normal state.
    func close() {
        autoCloseWork?.cancel()
        autoCloseWork = nil
        pointerInside = false
        dragging = false
        hoverTile = nil
        JobRunner.shared.cancelAll()
        session = nil
        stage = .tiles
        options = ConvertOptions()
        NotchService.shared.closeConvertPage()
    }
}

/// Which options a target offers, so the pane skips itself for the rest.
enum ConvertOptionCatalog {
    static let lossyImages: Set<FileFormat> = [.jpg, .webp, .heic, .avif]
    static let imageTargets: Set<FileFormat> = [.jpg, .png, .webp, .heic, .tiff, .avif, .bmp, .pdf]
    static let videoTargets: Set<FileFormat> = [.mp4, .mov, .mkv, .webm, .avi, .wmv]
    static let audioTargets: Set<FileFormat> = [.mp3, .m4a, .ogg, .opus, .wma]

    static func hasOptions(for target: FileFormat, from category: FormatCategory) -> Bool {
        switch category {
        case .image: return imageTargets.contains(target)
        case .video: return videoTargets.contains(target) || target == .gif || target == .mp3
        case .audio: return audioTargets.contains(target)
        default: return false
        }
    }
}

/// Where the tiles sit. The page draws them here and the island hit-tests a drag
/// against the same rectangles, so what lights up is what is dropped on.
enum ConvertLayout {
    static let headerHeight: CGFloat = 36
    /// Space between the header and the tiles.
    static let spacing: CGFloat = 10
    static let gap: CGFloat = 8
    static let tileHeight: CGFloat = 62

    static func columns(width: CGFloat, count: Int) -> Int {
        max(2, min(5, Int(width / 92), max(count, 2)))
    }

    static func frame(index: Int, count: Int, width: CGFloat) -> CGRect {
        let cols = columns(width: width, count: count)
        let tileWidth = (width - gap * CGFloat(cols - 1)) / CGFloat(cols)
        return CGRect(x: CGFloat(index % cols) * (tileWidth + gap), y: CGFloat(index / cols) * (tileHeight + gap),
                      width: tileWidth, height: tileHeight)
    }

    static func rows(width: CGFloat, count: Int) -> Int {
        let cols = columns(width: width, count: count)
        return (count + cols - 1) / cols
    }
}
