// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import CoreImage
import SwiftUI

/// What changes as Launchpad opens and closes. Kept apart from the service
/// so the backdrop and the entrance never redraw the icons.
final class LaunchpadMotion: ObservableObject {
    static let shared = LaunchpadMotion()
    @Published var shown = false
    @Published var wallpaper: NSImage?
}

/// The page and the strip of pages sliding to it, apart from everything
/// else. The pager moves the strip itself, one frame at a time, rather than
/// through SwiftUI's animations, so fingers can catch it anywhere in a glide
/// and carry on from exactly where it is on screen.
final class LaunchpadPager: NSObject, ObservableObject {
    static let shared = LaunchpadPager()

    /// Where the strip is, in points from the first page, published apart
    /// from the page so each frame redraws only the strip, not the dots.
    final class Strip: ObservableObject {
        @Published fileprivate(set) var position: CGFloat = 0
    }

    /// The page settled on or gliding to.
    @Published private(set) var page = 0
    let strip = Strip()
    /// The width of one page, reported by the grid. The strip keeps its place
    /// on the page when it changes.
    var pageWidth: CGFloat = 1000 {
        didSet {
            guard pageWidth != oldValue, oldValue > 0 else { return }
            strip.position *= pageWidth / oldValue
        }
    }
    /// The view whose screen paces the glide.
    weak var host: NSView?
    private var velocity: CGFloat = 0
    private var link: CADisplayLink?
    private var lastFrame: CFTimeInterval?
    private var swipeBegan: CGFloat?
    private var lastSwipeEvent: TimeInterval = 0
    /// Where the pointer was at the last step of a mouse drag; nil while
    /// the mouse is not dragging the strip.
    private var pointerX: CGFloat?

    /// Turns to a page at once, as the grid opens.
    func reset(to next: Int = 0) {
        stop()
        swipeBegan = nil
        pointerX = nil
        velocity = 0
        page = next
        strip.position = CGFloat(next) * pageWidth
    }

    /// Glides to a page from wherever the strip is and however fast it is
    /// already moving.
    func glide(to next: Int, pageCount: Int) {
        page = min(max(next, 0), max(pageCount - 1, 0))
        let distance = CGFloat(page) * pageWidth - strip.position
        // A throw faster than the spring would carry it on past the page.
        let most = 2 * .pi / 0.32 * abs(distance)
        if velocity * distance > 0 { velocity = min(max(velocity, -most), most) }
        // Fingers on the strip keep it until they lift.
        guard link == nil, swipeBegan == nil, let host else { return }
        let link = host.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Fingers on the trackpad hold the strip still where it is.
    func catchSwipe(at time: TimeInterval) {
        guard swipeBegan == nil else { return }
        stop()
        swipeBegan = strip.position
        velocity = 0
        lastSwipeEvent = time
    }

    /// The strip follows the fingers point for point, and only gives a
    /// little past the first and last page.
    func swipe(by delta: CGFloat, at time: TimeInterval, pageCount: Int) {
        guard swipeBegan != nil else { return }
        let step = -delta
        let limit = CGFloat(max(pageCount - 1, 0)) * pageWidth
        let position = strip.position
        let overshoot = position < 0 ? position : max(position - limit, 0)
        let next = position + step
        strip.position = overshoot == 0 && (0...limit).contains(next)
            ? next : position + LaunchpadSupport.rubberBand(step, overshoot: overshoot, pageWidth: pageWidth)
        let elapsed = time - lastSwipeEvent
        if elapsed > 0 {
            // Smoothed, since the trackpad's steps arrive unevenly.
            velocity = velocity * 0.4 + (strip.position - position) / elapsed * 0.6
        }
        lastSwipeEvent = time
    }

    /// Fingers lifting let the strip glide on to the page the swipe chose.
    func releaseSwipe(at time: TimeInterval, pageCount: Int) {
        guard let began = swipeBegan else { return }
        swipeBegan = nil
        // Fingers that rested before lifting throw nothing.
        if time - lastSwipeEvent > 0.06 { velocity = 0 }
        glide(to: LaunchpadSupport.settledPage(began: began, position: strip.position, velocity: velocity,
                                               pageWidth: pageWidth, pageCount: pageCount),
              pageCount: pageCount)
    }

    /// A mouse grabbing empty space drags the strip as fingers do, once it
    /// has moved past a click. The pointer is read on screen, since the
    /// page it grabbed slides away under it.
    func drag(_ value: DragGesture.Value, pageCount: Int) {
        let x = NSEvent.mouseLocation.x
        let now = ProcessInfo.processInfo.systemUptime
        if let pointerX {
            swipe(by: x - pointerX, at: now, pageCount: pageCount)
        } else if hypot(value.translation.width, value.translation.height) > 4 {
            catchSwipe(at: now)
        } else {
            return
        }
        pointerX = x
    }

    /// Lets go of a mouse drag; false when the press never moved, so it
    /// still counts as a click.
    func drop(pageCount: Int) -> Bool {
        guard pointerX != nil else { return false }
        pointerX = nil
        releaseSwipe(at: ProcessInfo.processInfo.systemUptime, pageCount: pageCount)
        return true
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastFrame = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let elapsed = lastFrame.map { link.targetTimestamp - $0 } ?? link.duration
        lastFrame = link.targetTimestamp
        let rest = CGFloat(page) * pageWidth
        let next = LaunchpadSupport.springStep(offset: strip.position - rest, velocity: velocity,
                                               elapsed: CGFloat(elapsed))
        // Within a fraction of a point and nearly still, it is at rest.
        if abs(next.offset) < 0.25, abs(next.velocity) < 5 {
            strip.position = rest
            velocity = 0
            stop()
        } else {
            strip.position = rest + next.offset
            velocity = next.velocity
        }
    }
}

/// The grid of every app that macOS 26 took away with Launchpad. It opens from
/// a global shortcut, an icon in the Dock or the Dynamic Island, and keeps one
/// arrangement of pages, folders and hidden apps between openings. Nothing
/// runs while it is closed except the hotkey.
final class LaunchpadService: NSObject, ObservableObject {
    static let shared = LaunchpadService()

    struct App: Identifiable, Equatable {
        let path: String
        let name: String
        let category: LaunchpadCategory
        /// Not part of macOS and in a folder the person can change, so the
        /// wiggling icon offers to move it to the Trash.
        let deletable: Bool
        var id: String { path }
        var url: URL { URL(fileURLWithPath: path) }
    }

    /// A folder being made from the toolbar (no id yet) or edited.
    struct FolderEditor: Equatable {
        var folderID: String?
        var name: String
        var apps: [String]
    }

    @Published private(set) var isVisible = false
    @Published private(set) var shortcutRegistrationFailed = false
    @Published private(set) var layout: LaunchpadLayout
    /// Every installed app, sorted by name once per scan rather than on
    /// every keystroke of a search.
    @Published private(set) var sortedApps: [App] = []
    private(set) var apps: [String: App] = [:]
    @Published var query = "" {
        didSet { if query != oldValue { selection = 0 } }
    }
    /// The search result Return opens; the arrow keys move it.
    @Published var selection = 0
    @Published private(set) var openFolderID: String?
    /// Where the open folder grew from, so it shrinks back there.
    private(set) var folderAnchor = UnitPoint.center
    /// A folder just made by a drop opens with its name ready to type.
    var focusFolderName = false
    @Published var openCategory: LaunchpadCategory?
    @Published var folderEditor: FolderEditor?
    /// Holding an icon makes every icon wiggle, as on the iPhone: apps can
    /// be dragged around and the ones that are not part of macOS can go.
    @Published var isEditing = false
    @Published var pendingDelete: String?
    /// Cells on one page, reported by the grid for the screen it was laid out on.
    var perPage = 35
    /// Where the grid's and the open folder's cells sit, reported by the
    /// views, so a drag is read from the pointer alone.
    var gridGeometry = LaunchpadGridGeometry()
    var folderGeometry = LaunchpadGridGeometry()
    var folderCardFrame = CGRect.zero
    static let searchColumns = 7

    private let hotkey = QuickToolHotkey(id: 82)
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var outsideClickMonitor: Any?
    /// A spun mouse wheel turns a page at a time, not one per notch.
    private var wheelTurnsAfter = Date.distantPast
    private var isScanning = false
    private let motion = LaunchpadMotion.shared
    private let pager = LaunchpadPager.shared

    var page: Int { pager.page }

    private override init() {
        let defaults = UserDefaults.standard
        layout = LaunchpadLayout.decode(defaults.data(forKey: DefaultsKey.launchpadLayout))
        super.init()
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let available = AppFeature.launchpad.isAvailable
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.launchpadShortcut, fallback: .launchpadDefault)
        shortcutRegistrationFailed = !hotkey.sync(
            enabled: available && defaults.bool(forKey: DefaultsKey.launchpadShortcutEnabled),
            shortcut: shortcut, storageKey: DefaultsKey.launchpadShortcut)
        if available {
            // The first opening should not wait for the folders to be read.
            if apps.isEmpty { refreshApps() }
        } else {
            hide()
            panel = nil
        }
    }

    func suspend() {
        hotkey.unregister()
        hide()
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard AppFeature.launchpad.isAvailable, !isVisible else { return }
        query = ""
        openFolderID = nil
        LaunchpadDrag.shared.cancel()
        openCategory = nil
        folderEditor = nil
        isEditing = false
        pendingDelete = nil
        pager.reset()
        motion.shown = false
        refreshApps()
        let panel = ensurePanel()
        let screen = place(panel)
        pager.host = panel.contentView
        if let screen { loadWallpaper(for: screen) }
        installMonitors(for: panel)
        isVisible = true
        panel.orderFrontRegardless()
        panel.makeKey()
        // One turn later, so the first frame is drawn in the starting state
        // and the grid settles in from slightly large, as Launchpad did.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            withAnimation(.spring(duration: 0.32, bounce: 0.08), completionCriteria: .logicallyComplete) {
                self.motion.shown = true
            } completion: { [weak self] in
                // Opaque only once it covers the screen, so the fade in shows
                // the desktop going, not a black frame.
                guard let self, self.isVisible, self.style == .fullScreen else { return }
                panel.isOpaque = true
            }
        }
    }

    /// A click on empty space ends the wiggle first, then closes.
    func dismissFromBackground() {
        isEditing ? toggleEditing(false) : hide()
    }

    func hide() {
        guard isVisible, let panel else { return }
        isVisible = false
        LaunchpadDrag.shared.cancel()
        removeMonitors()
        pager.stop()
        panel.isOpaque = false
        withAnimation(.easeIn(duration: 0.18)) { motion.shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard self?.isVisible == false else { return }
            panel.orderOut(nil)
        }
    }

    // MARK: - Apps

    func name(of path: String) -> String {
        apps[path]?.name ?? ""
    }

    func isDeletable(_ item: LaunchpadItem) -> Bool {
        if case .app(let path) = item { return apps[path]?.deletable == true }
        return false
    }

    /// Reads the application folders off the main thread and folds what it
    /// finds into the layout, so apps installed or removed since the last
    /// opening appear or leave without a relaunch.
    private func refreshApps() {
        guard !isScanning else { return }
        isScanning = true
        let helperID = LaunchpadDockIcon.bundleIdentifier
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = InstalledApps.installedApplications(includeSystemApplications: true)
                .filter { $0.bundleID != helperID }
                .map { app in
                    App(path: app.id, name: app.name,
                        category: LaunchpadCategory(applicationCategoryType:
                            Bundle(url: app.url)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String),
                        deletable: !app.isSystem && FileManager.default.isDeletableFile(atPath: app.id))
                }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isScanning = false
                let apps = Dictionary(found.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
                // An unchanged Mac must not redraw the grid on every opening.
                if apps != self.apps {
                    self.apps = apps
                    self.sortedApps = apps.values.sorted {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
                }
                self.commit(self.layout.reconciled(with: self.sortedApps.map(\.path)))
            }
        }
    }

    // MARK: - Actions

    func toggleEditing(_ on: Bool) {
        guard on != isEditing else { return }
        withAnimation(.smooth(duration: 0.2)) { isEditing = on }
    }

    /// Moves the app to the Trash, where it can be put back, and takes it
    /// off the grid at once. An app the system refuses (owned by another
    /// user, still running from a protected place) stays and says why.
    func deleteApp(_ path: String) {
        pendingDelete = nil
        let name = name(of: path)
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            edit { $0 = $0.reconciled(with: sortedApps.map(\.path).filter { $0 != path }) }
            refreshApps()
        } catch {
            QuickToolHUD.show(icon: "exclamationmark.triangle",
                              message: String(format: FeatureStrings.launchpad(L10n.shared.language).deleteFailedFormat, name))
        }
    }

    func launch(_ path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                           configuration: NSWorkspace.OpenConfiguration())
        hide()
    }

    func showInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        hide()
    }

    func move(_ id: String, toPosition position: Int, animated: Bool = true) {
        edit(animated: animated) { $0.move(id, toPosition: position) }
    }

    func openFolder(_ id: String, from point: CGPoint? = nil) {
        if let point, let size = panel?.contentView?.bounds.size, size.width > 0, size.height > 0 {
            folderAnchor = UnitPoint(x: point.x / size.width, y: point.y / size.height)
        } else {
            folderAnchor = .center
        }
        openFolderID = id
    }

    func closeFolder() {
        openFolderID = nil
    }

    /// The pointer in the coordinates the views lay themselves out in: the
    /// window's content, from its top left corner.
    func rootPoint(_ event: NSEvent? = nil) -> CGPoint {
        guard let panel, let content = panel.contentView else { return .zero }
        let inWindow = event?.locationInWindow ?? panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        return CGPoint(x: inWindow.x, y: content.bounds.height - inWindow.y)
    }

    var rootSize: CGSize { panel?.contentView?.bounds.size ?? .zero }

    var panelWindow: NSWindow? { panel }

    /// Dropping an app on another names the new folder after the target's
    /// category, as Launchpad did, or Untitled when it declares none. A
    /// folder made this way opens at once, its name ready to change.
    func drop(_ id: String, onto targetID: String) {
        let category = apps[targetID]?.category ?? .other
        let strings = FeatureStrings.launchpad(L10n.shared.language)
        let name = category == .other ? strings.untitledFolder : strings.title(category)
        let madeFolder = layout.folder(targetID) == nil
        var folderID: String?
        edit { folderID = $0.drop(id, onto: targetID, folderName: name) }
        if madeFolder, let folderID {
            focusFolderName = true
            let slot = (layout.items.firstIndex { $0.id == folderID } ?? 0) - page * perPage
            openFolder(folderID, from: gridGeometry.iconCenter(of: max(slot, 0)))
        }
    }

    func moveInFolder(_ path: String, toPosition position: Int, animated: Bool = true) {
        edit(animated: animated) { $0.moveInFolder(path, toPosition: position) }
    }

    func takeOutOfFolder(_ path: String) {
        edit { $0.takeOutOfFolder(path) }
    }

    func hideApp(_ path: String) {
        edit { $0.hide(path) }
    }

    func unhideApp(_ path: String) {
        edit { $0.unhide(path) }
    }

    func renameFolder(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        edit { $0.renameFolder(id, to: trimmed) }
    }

    func deleteFolder(_ id: String) {
        if openFolderID == id { closeFolder() }
        edit { $0.deleteFolder(id) }
    }

    func beginNewFolder() {
        folderEditor = FolderEditor(name: "", apps: [])
    }

    func beginEditing(_ folderID: String) {
        guard let folder = layout.folder(folderID) else { return }
        folderEditor = FolderEditor(folderID: folderID, name: folder.name, apps: folder.apps)
    }

    func commitFolderEditor() {
        guard let editor = folderEditor else { return }
        folderEditor = nil
        let trimmed = editor.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? FeatureStrings.launchpad(L10n.shared.language).untitledFolder : trimmed
        if let id = editor.folderID {
            edit { $0.editFolder(id, name: name, apps: editor.apps) }
        } else {
            edit { $0.createFolder(named: name, apps: editor.apps) }
        }
    }

    func resetLayout() {
        commit(LaunchpadLayout().reconciled(with: sortedApps.map(\.path)))
    }

    /// A glide with no bounce, as the system's pages settle.
    func setPage(_ next: Int, pageCount: Int) {
        pager.glide(to: next, pageCount: pageCount)
    }

    /// The app pages, then the categories page at the end, as the App
    /// Library sits after the last home screen on the iPhone.
    var pageCount: Int {
        LaunchpadSupport.pageCount(items: layout.items.count, perPage: perPage) + 1
    }

    private func edit(animated: Bool = true, _ change: (inout LaunchpadLayout) -> Void) {
        var next = layout
        change(&next)
        if animated {
            withAnimation(.smooth(duration: 0.3)) { commit(next) }
        } else {
            commit(next)
        }
        if let id = openFolderID, layout.folder(id) == nil { openFolderID = nil }
        if pager.page >= pageCount { setPage(pageCount - 1, pageCount: pageCount) }
    }

    private func commit(_ next: LaunchpadLayout) {
        guard next != layout else { return }
        layout = next
        UserDefaults.standard.set(next.encoded, forKey: DefaultsKey.launchpadLayout)
    }

    // MARK: - Panel

    private final class KeyableLaunchpadPanel: OverlayPanel {
        override var canBecomeKey: Bool { true }
    }

    private var style: LaunchpadSupport.Style {
        LaunchpadSupport.Style.sanitized(UserDefaults.standard.string(forKey: DefaultsKey.launchpadStyle))
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = KeyableLaunchpadPanel(contentRect: .zero,
                                          styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
        panel.title = FeatureStrings.launchpad(L10n.shared.language).pageTitle
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        // A see-through window lets clicks fall to whatever is behind its
        // clear pixels; Launchpad owns every point it covers.
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: LaunchpadView())
        host.sizingOptions = []
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    /// Full screen covers the Dock and the menu bar as Launchpad did; the
    /// panel sits in the middle of the visible area with the desktop around it.
    @discardableResult
    private func place(_ panel: NSPanel) -> NSScreen? {
        let screen = NSScreen.withMouse ?? NSScreen.main ?? NSScreen.screens.first
        let full = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        switch style {
        case .fullScreen:
            // Opaque once shown (see show()), so the window server never
            // treats any point of it as see-through: the cursor stays in
            // Launchpad, not on the apps behind.
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .statusBar
            panel.hasShadow = false
            panel.setFrame(full, display: true)
        case .panel:
            let visible = screen?.visibleFrame ?? full
            let size = CGSize(width: min(visible.width - 80, max(720, visible.width * 0.72)),
                              height: min(visible.height - 60, max(520, visible.height * 0.78)))
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = true
            panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                  width: size.width, height: size.height), display: true)
        }
        return screen
    }

    /// Launchpad sat on a blurred copy of the desktop picture, not on the
    /// open windows. The workspace names the default picture once a
    /// wallpaper is an Aerial or comes from the newer wallpaper settings, so
    /// the choice is read from the system's own wallpaper store; an Aerial
    /// gives its still thumbnail. The blur is made small, once per picture,
    /// off the main thread. A picture that cannot be read leaves a plain
    /// dark backdrop, never the windows behind.
    private func loadWallpaper(for screen: NSScreen) {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return }
        let displayUUID = CFUUIDCreateString(nil, uuid) as String
        let width = screen.frame.width
        DispatchQueue.global(qos: .userInitiated).async {
            let support = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.apple.wallpaper", isDirectory: true)
            let store = (try? Data(contentsOf: support.appendingPathComponent("Store/Index.plist")))
                .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
            let file = store.flatMap {
                LaunchpadSupport.wallpaperFile(inStore: $0, displayUUID: displayUUID,
                                               aerialThumbnails: support.appendingPathComponent("aerials/thumbnails"))
            }
            let image = file.flatMap { Self.blurred($0, width: width) }
            DispatchQueue.main.async { LaunchpadMotion.shared.wallpaper = image }
        }
    }

    private static func blurred(_ url: URL, width: CGFloat) -> NSImage? {
        guard let source = CIImage(contentsOf: url), source.extent.width > 0 else { return nil }
        // A quarter of the screen is plenty under a blur this strong.
        let scale = min(1, width / 4 / source.extent.width)
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 14).cropped(to: small.extent)
        guard let image = CIContext().createCGImage(blurred, from: small.extent) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }

    // MARK: - Monitors

    /// Esc steps back one layer at a time: the folder editor, an open folder
    /// or category, the search, then Launchpad itself. Arrows turn pages
    /// while nothing is typed, and Return opens the best search match.
    private func installMonitors(for panel: NSPanel) {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            switch Int(event.keyCode) {
            case kVK_Escape:
                // An icon in the hand goes back where it came from.
                if LaunchpadDrag.shared.item != nil { withAnimation(.smooth(duration: 0.25)) { LaunchpadDrag.shared.cancel() } }
                else if self.pendingDelete != nil { self.pendingDelete = nil }
                else if self.folderEditor != nil { self.folderEditor = nil }
                else if self.openFolderID != nil { self.closeFolder() }
                else if self.openCategory != nil { self.openCategory = nil }
                else if self.isEditing { self.toggleEditing(false) }
                else if !self.query.isEmpty { self.query = "" }
                else { self.hide() }
                return nil
            case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow:
                let key = Int(event.keyCode)
                if !self.query.isEmpty, self.folderEditor == nil {
                    // Arrows walk the results the way they walk the system's.
                    let step = [kVK_LeftArrow: -1, kVK_RightArrow: 1,
                                kVK_UpArrow: -Self.searchColumns, kVK_DownArrow: Self.searchColumns][key] ?? 0
                    let count = self.searchResults.count
                    if count > 0 { self.selection = min(max(self.selection + step, 0), count - 1) }
                    return nil
                }
                guard self.browsingGrid, key == kVK_LeftArrow || key == kVK_RightArrow else { return event }
                self.setPage(self.page + (key == kVK_LeftArrow ? -1 : 1), pageCount: self.pageCount)
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                let results = self.searchResults
                guard self.folderEditor == nil, !self.query.isEmpty, results.indices.contains(self.selection)
                else { return event }
                self.launch(results[self.selection].path)
                return nil
            default:
                return event
            }
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel, self.browsingGrid,
                  LaunchpadDrag.shared.item == nil else { return event }
            self.handleScroll(event)
            return nil
        }
        // A click in another app (the panel style leaves the desktop around
        // it) puts Launchpad away, as clicking past any popover does.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel,
                  !panel.frame.contains(NSEvent.mouseLocation),
                  !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) else { return }
            self.hide()
        }
    }

    var browsingGrid: Bool {
        query.isEmpty && openFolderID == nil && openCategory == nil && folderEditor == nil
    }

    var searchResults: [App] {
        LaunchpadSupport.search(query, in: sortedApps, name: \.name)
    }

    /// A trackpad swipe drags the pages under the fingers, from wherever
    /// they are, even mid-glide, and on release glides on to the page it was
    /// pulled or flicked towards; past the first and last page it only gives
    /// a little. A mouse wheel turns one page per notch, with a short pause
    /// so a spun wheel does not race.
    private func handleScroll(_ event: NSEvent) {
        // Only fingers carry a phase. A wheel can arrive precise too, from
        // Smooth Scrolling's glide or a mouse driver, and is still a wheel.
        if event.hasPreciseScrollingDeltas, !(event.phase.isEmpty && event.momentumPhase.isEmpty) {
            // The fling after the fingers lift is ours to animate, not the system's.
            guard event.momentumPhase.isEmpty else { return }
            let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY
            switch event.phase {
            case .mayBegin, .began:
                pager.catchSwipe(at: event.timestamp)
            case .changed:
                pager.swipe(by: delta, at: event.timestamp, pageCount: pageCount)
            case .ended, .cancelled:
                pager.releaseSwipe(at: event.timestamp, pageCount: pageCount)
            default:
                break
            }
        } else {
            let delta = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
                ? event.scrollingDeltaY : event.scrollingDeltaX
            guard delta != 0 else { return }
            let now = Date()
            // A glide's stream of small steps is one notch, not many.
            defer { wheelTurnsAfter = max(wheelTurnsAfter, now.addingTimeInterval(0.15)) }
            guard now >= wheelTurnsAfter else { return }
            wheelTurnsAfter = now.addingTimeInterval(0.3)
            setPage(page + (delta > 0 ? -1 : 1), pageCount: pageCount)
        }
    }

    private func removeMonitors() {
        for monitor in [keyMonitor, scrollMonitor, outsideClickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        scrollMonitor = nil
        outsideClickMonitor = nil
    }
}
