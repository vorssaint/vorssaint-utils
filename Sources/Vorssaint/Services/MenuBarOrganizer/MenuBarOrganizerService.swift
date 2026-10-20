// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import os

/// Hides the menu bar icons left of the collapser, shows them again on a click,
/// keeps the never-shown ones out of the bar altogether and reorders icons on
/// request. macOS 27 or later only.
///
/// The physical order of the bar is the only truth for hiding: whatever sits
/// left of the collapser when the bar collapses is hidden, so a native ⌘-drag
/// across the collapser changes membership and no separate list can drift
/// from the bar. Never-shown icons have no place in the bar to tell them by,
/// so they are the one list that is stored, and they stay out while the bar
/// is expanded too. Hiding works per app (the system allowlist takes bundle
/// ids), which is why Vorssaint's own icons and helper processes without a
/// bundle id are never hidden. The system items the allowlist knows by index
/// hide and move like an app's; the clock and Control Center, which macOS
/// pins, and the agent's other items are left alone.
///
/// With the shelf chosen as the reveal, a click on the collapsed collapser
/// drops a shelf listing the hidden icons instead of expanding the bar. Picking
/// one peeks: only that icon's host returns to the bar, its menu is opened
/// with an Accessibility press, and it hides again once the menu has closed.
///
/// Every doubt resolves towards a visible bar: an empty walk, a missing
/// collapser, a refused activation or a revoked permission drops the
/// restriction, never-shown icons included. Main thread only, like the other
/// services; the Accessibility walks, the presses and the drags run on
/// background queues.
///
/// Every inventory, activation and release is logged, at the level the
/// system keeps on disk. To read what the organizer saw and decided (the
/// subsystem is the bundle id, `com.vorssaint.utils.dev` in a Developer build):
///
///     log show --last 10m --predicate 'subsystem == "com.vorssaint.utils" AND category == "menu-bar-organizer"' --style compact
final class MenuBarOrganizerService: ObservableObject {
    static let shared = MenuBarOrganizerService()

    enum State: Equatable { case off, expanded, collapsed, applying }
    enum Problem: Equatable {
        case accessibilityMissing
        case collapserNotFound
        case activationFailed(String)
        case nothingToHide
        /// The shelf could not open this item; it names the item.
        case peekFailed(String)
    }

    @Published private(set) var state: State = .off
    @Published private(set) var problem: Problem?
    /// The last walk of an expanded bar, in visual order. Kept while
    /// collapsed, when the hidden items are gone from Accessibility.
    @Published private(set) var inventory: [MenuBarItemSnapshot] = []
    /// The last partition at the collapser; the hidden list survives a collapse.
    @Published private(set) var layout: MenuBarLayout?
    /// Localized names of other running menu bar managers.
    @Published private(set) var runningManagers: [String] = []
    @Published private(set) var lastApplyReport: (moved: Int, failed: Int)?
    /// What the last collapse hid, also across a relaunch.
    @Published private(set) var lastHidden: [MenuBarHiddenRecord]
    /// The icons kept out of the bar for good, in the order of the editor.
    @Published private(set) var neverShown: [MenuBarHiddenRecord]

    /// Why hiding cannot work on this Mac, nil when it can. The private API is
    /// only looked up on macOS 27 or later.
    static let unsupportedReason: MenuBarOrganizerAvailability.Unsupported? = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return MenuBarOrganizerAvailability.unsupportedReason(
            majorVersion: version.majorVersion,
            versionString: "\(version.majorVersion).\(version.minorVersion)",
            bridgeAvailable: version.majorVersion >= 27 && MenuBarVisibilityAssertion.isAvailable)
    }()

    var unsupportedReason: MenuBarOrganizerAvailability.Unsupported? { Self.unsupportedReason }
    var isSupported: Bool { Self.unsupportedReason == nil }

    private static let quietWalkInterval: TimeInterval = 1
    private static let quietWaitLimit: TimeInterval = 60
    private static let launchPollInterval: TimeInterval = 0.2
    private static let launchRevealWindow: TimeInterval = 2.5
    /// Launches in a burst share one reveal, which may stretch this far.
    private static let launchRevealLimit: TimeInterval = 6
    private static let peekLocateInterval: TimeInterval = 0.2
    private static let peekLocateWindow: TimeInterval = 2.5
    private static let peekWatchInterval: TimeInterval = 0.25
    /// The menu must have appeared this long after the press, or there is none.
    private static let peekMenuGrace: TimeInterval = 1.5
    /// A menu left open this long is given up on; the icon hides again.
    private static let peekLimit: TimeInterval = 90
    /// Some status menus hold the reply to a press until they close; waiting
    /// longer than this would only delay the watch.
    private static let peekPressTimeout: Float = 1
    private static let logBundlesPerLine = 15
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "menu-bar-organizer")
    private static let moverQueue = DispatchQueue(label: "com.vorssaint.menu-bar-organizer.mover",
                                                  qos: .userInitiated)

    private let assertion = MenuBarVisibilityAssertion()
    private let collapser = MenuBarOrganizerCollapser()
    private let shelf = MenuBarOrganizerShelf()
    private let ownBundleID = Bundle.main.bundleIdentifier ?? ""
    /// Advances whenever the user or the system changes course, so a walk or
    /// timer that answers late knows it has been overtaken.
    private var epoch = 0
    private var quietGate = MenuBarQuietGate()
    private var rehideTimer: Timer?
    /// Watches the menu a peek opened, to hide its icon again.
    private var peekTimer: Timer?
    private var peekSawMenu = false
    /// What the last collapse hid, kept for the wake re-assert.
    private var hidden = MenuBarHiddenSet()
    /// Bundles launched while icons were hidden whose icons the open bar is
    /// waiting for.
    private var awaitedLaunches = Set<String>()
    private var launchRevealStarted: TimeInterval = 0
    private var launchRevealDeadline: TimeInterval = 0
    private var applyCancellation: Cancellation?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var launchObserver: NSKeyValueObservation?
    private var accessibilityObserver: AnyCancellable?

    private init() {
        lastHidden = MenuBarHiddenRecord.decode(UserDefaults.standard.data(forKey: DefaultsKey.menuBarOrganizerLastHidden))
        neverShown = MenuBarHiddenRecord.decode(UserDefaults.standard.data(forKey: DefaultsKey.menuBarOrganizerNeverShown))
        collapser.onToggle = { [weak self] in self?.toggle() }
        collapser.onOpenSettings = {
            SettingsRouter.shared.page = .menuBarOrganizer
            (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
        }
        shelf.onSelect = { [weak self] in self?.peek($0) }
        shelf.onClosed = { [weak self] in self?.refreshIcon() }
        shelf.collapserWindow = { [weak self] in self?.collapser.buttonWindow }
    }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        let enabled = isSupported
            && AppFeature.menuBarOrganizer.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerEnabled)
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard state == .off else { return }
        state = .expanded
        problem = nil
        // In the bar before any assertion: an item registered while icons are
        // hidden parks off screen until they are shown again.
        collapser.install(collapsed: false)

        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.refreshManagers()
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.reassertAfterWake()
            }
        ]
        // Not didLaunchApplicationNotification: it stays silent for accessory
        // apps, the very ones that own menu bar icons. The change carries the
        // whole list or only the insertions, and either way what was not
        // there before has launched.
        launchObserver = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new]) { [weak self] _, change in
            let known = Set(change.oldValue ?? [])
            let launched = (change.newValue ?? []).filter { !known.contains($0) }
            guard !launched.isEmpty else { return }
            DispatchQueue.main.async { launched.forEach { self?.applicationLaunched($0) } }
        }
        accessibilityObserver = Permissions.shared.$accessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in self?.accessibilityChanged(granted) }
        refreshManagers()
        collapseWhenQuiet()
    }

    /// Shows every icon, the never-shown ones too, closes the shelf and
    /// removes the collapser. Safe to call at any time, including on quit and
    /// while a reorder pass is running.
    func stop() {
        advance()
        release("stop")
        guard state != .off else { return }
        workspaceTokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceTokens = []
        launchObserver = nil
        accessibilityObserver = nil
        collapser.remove()
        state = .off
        problem = nil
    }

    // MARK: - Showing and hiding

    /// The collapser's click. With the shelf as the reveal a collapsed bar
    /// stays collapsed and the shelf opens or closes instead.
    func toggle() {
        switch state {
        case .collapsed:
            guard reveal == .shelf else {
                expand()
                return
            }
            shelf.toggle(anchor: collapser.anchorFrame)
            refreshIcon()
        case .expanded: collapse()
        case .off, .applying: break
        }
    }

    /// Redraws the collapser after its icon or the reveal was changed in
    /// Settings, or the shelf opened or closed. Leaving the shelf for the bar
    /// closes it.
    func refreshIcon() {
        if reveal == .menuBar { shelf.close() }
        collapser.setCollapsed(state == .collapsed, shelfOpen: shelf.isOpen)
    }

    private var reveal: MenuBarOrganizerReveal {
        MenuBarOrganizerReveal.stored(UserDefaults.standard.string(forKey: DefaultsKey.menuBarOrganizerReveal))
    }

    /// Hides the icons left of the collapser, reading the boundary afresh.
    func collapse() {
        guard state == .expanded else { return }
        walkAndCollapse(token: advance())
    }

    /// Shows the hidden icons where they were. Also calls off a collapse that
    /// is still waiting for the bar to settle.
    func expand() {
        guard state == .collapsed || state == .expanded else { return }
        let wasCollapsed = state == .collapsed
        advance()
        state = .expanded
        collapser.setCollapsed(false, shelfOpen: false)
        // A collapse that was still waiting never restricted the bar, and a
        // bar that is still settling must stay unrestricted.
        guard wasCollapsed else {
            release("expand while settling")
            return
        }
        restrictExpanded()
        restoreOrderAfterReveal(token: epoch, collapseAfterwards: false)
    }

    /// An expanded bar still keeps the never-shown apps out; without any the
    /// restriction is dropped. A restriction already held stays until the new
    /// one is live, so never-shown icons do not flash when the bar expands.
    private func restrictExpanded() {
        let restricted = activate(hiding: MenuBarHiddenSet(), for: "expanded") { [weak self] failure in
            guard let failure else { return }
            self?.failOpen(.activationFailed(failure))
        }
        if !restricted { release("nothing is never shown") }
    }

    /// Restricts the bar to everything but `hidden` and the never-shown apps
    /// and system items, judged by the last inventory. False, with nothing
    /// done, when that hides nothing. `completion` is skipped when the course
    /// changed before the answer.
    private func activate(hiding hidden: MenuBarHiddenSet, for purpose: String,
                          completion: @escaping (String?) -> Void) -> Bool {
        let never = MenuBarOrganizerLayout.neverShown(
            in: MenuBarLayout(hidden: [], visible: [], neverShown: neverShown.map(\.identity)),
            items: inventory, known: neverShown, ownBundleID: ownBundleID)
        guard let allowed = MenuBarOrganizerLayout.allowlist(hidden: hidden, neverShown: never,
                                                             observed: inventory, running: runningBundles(),
                                                             ownBundleID: ownBundleID) else {
            Self.log.notice("activate (\(purpose, privacy: .public)): nothing to hide")
            return false
        }
        Self.log.notice("""
            activate (\(purpose, privacy: .public)): \
            hidden bundles \(hidden.bundles.sorted(), privacy: .public) \
            system \(Self.indices(hidden.systemItems), privacy: .public); \
            never-shown bundles \(never.bundles.sorted(), privacy: .public) \
            system \(Self.indices(never.systemItems), privacy: .public); \
            allowed system \(allowed.systemItems, privacy: .public); \
            allowed \(allowed.bundles.count, privacy: .public) bundles
            """)
        // The log cuts a message at about 1024 bytes, and every running app
        // is allowed: the list goes out in lines short enough to stay whole.
        let lines = stride(from: 0, to: allowed.bundles.count, by: Self.logBundlesPerLine).map {
            allowed.bundles[$0..<min($0 + Self.logBundlesPerLine, allowed.bundles.count)].joined(separator: ", ")
        }
        for (index, line) in lines.enumerated() {
            Self.log.notice("allowed bundles \(index + 1, privacy: .public)/\(lines.count, privacy: .public): \(line, privacy: .public)")
        }
        let token = epoch
        assertion.activate(bundles: allowed.bundles, systemItems: allowed.systemItems) { [weak self] failure in
            Self.log.notice("activate (\(purpose, privacy: .public)) result: \(failure ?? "ok", privacy: .public)")
            guard let self, self.epoch == token else { return }
            completion(failure)
        }
        return true
    }

    private func release(_ reason: String) {
        Self.log.notice("release (\(reason, privacy: .public)), was active: \(self.assertion.isActive, privacy: .public)")
        assertion.release()
    }

    private static func indices(_ items: Set<MenuBarSystemItem>) -> [Int] {
        items.map(\.rawValue).sorted()
    }

    /// Re-reads the bar for the editor. Only an expanded bar is read: while
    /// icons are hidden they are gone from Accessibility and the frames of
    /// the rest are stale. The never-shown ones are missing from an expanded
    /// bar as well, and no reader needs them.
    func refreshInventory() {
        refreshManagers()
        guard canReadLayout else { return }
        let token = epoch
        MenuBarAccessibilityInventory.walk { [weak self] items in
            guard let self, self.epoch == token, self.canReadLayout else { return }
            self.adopt(items)
        }
    }

    private var canReadLayout: Bool {
        (state == .expanded || state == .off) && awaitedLaunches.isEmpty
    }

    /// Collapses once three walks a second apart agree, so icons of login
    /// items that are still starting are in place before the boundary is read.
    private func collapseWhenQuiet() {
        let token = advance()
        guard AXIsProcessTrusted() else {
            problem = .accessibilityMissing
            return
        }
        quietGate = MenuBarQuietGate()
        quietWalk(token: token, started: ProcessInfo.processInfo.systemUptime)
    }

    private func quietWalk(token: Int, started: TimeInterval) {
        MenuBarAccessibilityInventory.walk { [weak self] items in
            guard let self, self.epoch == token, self.state == .expanded else { return }
            let waited = ProcessInfo.processInfo.systemUptime - started
            if self.quietGate.observe(items.map(\.identity)) || waited >= Self.quietWaitLimit {
                self.collapse(with: items)
                return
            }
            self.adopt(items)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.quietWalkInterval) { [weak self] in
                guard let self, self.epoch == token else { return }
                self.quietWalk(token: token, started: started)
            }
        }
    }

    /// Walks and collapses. The bar must be expanded when this is called.
    private func walkAndCollapse(token: Int) {
        guard AXIsProcessTrusted() else {
            failOpen(.accessibilityMissing)
            return
        }
        MenuBarAccessibilityInventory.walk { [weak self] items in
            guard let self, self.epoch == token else { return }
            self.collapse(with: items)
        }
    }

    /// Collapses a bar that was just walked. Callers have checked that the
    /// walk was not overtaken.
    private func collapse(with items: [MenuBarItemSnapshot]) {
        guard !items.isEmpty else {
            failOpen(AXIsProcessTrusted() ? .collapserNotFound : .accessibilityMissing)
            return
        }
        adopt(items)
        guard let layout else {
            failOpen(.collapserNotFound)
            return
        }
        let toHide = MenuBarOrganizerLayout.hidden(in: layout, items: items, ownBundleID: ownBundleID)
        let restricted = activate(hiding: toHide, for: "collapse") { [weak self] failure in
            guard let self else { return }
            if let failure {
                self.failOpen(.activationFailed(failure))
                return
            }
            self.problem = nil
            self.state = .collapsed
            self.collapser.setCollapsed(true, shelfOpen: false)
        }
        guard restricted else {
            failOpen(.nothingToHide)
            return
        }
        hidden = toHide
        remember(MenuBarHiddenRecord.records(for: layout, items: items, neverShown: neverShown,
                                             ownBundleID: ownBundleID))
    }

    /// Shows the whole bar, never-shown icons included, and says why hiding
    /// is paused. The shelf has nothing left to show.
    private func failOpen(_ reason: Problem) {
        release("fail open: \(reason)")
        problem = reason
        if state == .collapsed { state = .expanded }
        shelf.close()
        collapser.setCollapsed(false, shelfOpen: false)
    }

    private func adopt(_ items: [MenuBarItemSnapshot]) {
        if inventory != items {
            inventory = items
            Self.logInventory(items)
        }
        let partition = MenuBarOrganizerCollapser.identity.flatMap {
            MenuBarOrganizerLayout.partition(items, collapser: $0)
        }
        if layout != partition { layout = partition }
    }

    /// One line per item, left to right:
    /// bundle | identity | pid | bundleless | signature | system index.
    private static func logInventory(_ items: [MenuBarItemSnapshot]) {
        log.notice("inventory: \(items.count, privacy: .public) items")
        for item in items {
            let system = MenuBarSystemItem.item(for: item.identity).map { String($0.rawValue) } ?? "-"
            log.notice("""
                  \(item.identity.bundleID, privacy: .public) | \(item.identity.title, privacy: .public) | \
                \(item.pid, privacy: .public) | \(item.hostIsBundleless ? "bundleless" : "bundled", privacy: .public) | \
                \(item.hostIsAppleSigned ? "apple-signed" : "unsigned", privacy: .public) | \(system, privacy: .public)
                """)
        }
    }

    private func remember(_ records: [MenuBarHiddenRecord]) {
        guard records != lastHidden else { return }
        lastHidden = records
        UserDefaults.standard.set(MenuBarHiddenRecord.encode(records), forKey: DefaultsKey.menuBarOrganizerLastHidden)
    }

    private func rememberNeverShown(_ records: [MenuBarHiddenRecord]) {
        guard records != neverShown else { return }
        neverShown = records
        UserDefaults.standard.set(MenuBarHiddenRecord.encode(records), forKey: DefaultsKey.menuBarOrganizerNeverShown)
    }

    /// A new delay starts now for an expanded bar; Never cancels the old
    /// timer. Shelf peeks already end when their menu closes.
    func refreshAutoRehide() {
        rehideTimer?.invalidate()
        rehideTimer = nil
        if state == .expanded { scheduleAutoRehide() }
    }

    private func scheduleAutoRehide() {
        let seconds = UserDefaults.standard.integer(forKey: DefaultsKey.menuBarOrganizerAutoRehideSeconds)
        guard seconds > 0, reveal == .menuBar else { return }
        Self.log.notice("auto re-hide in \(seconds, privacy: .public) seconds")
        let timer = Timer(timeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            self?.collapse()
        }
        RunLoop.main.add(timer, forMode: .common)
        rehideTimer = timer
    }

    /// Invalidates everything still pending, a peek included, and returns the
    /// new epoch. Nothing that changes course wants the shelf open.
    @discardableResult
    private func advance() -> Int {
        epoch += 1
        rehideTimer?.invalidate()
        rehideTimer = nil
        peekTimer?.invalidate()
        peekTimer = nil
        shelf.close()
        awaitedLaunches.removeAll()
        applyCancellation?.cancel()
        applyCancellation = nil
        return epoch
    }

    // MARK: - Peeking from the shelf

    /// Reveals one hidden icon, opens its menu and hides it again when the menu
    /// closes. The rest of the bar stays as it is, and the state stays
    /// collapsed throughout.
    func peek(_ identity: MenuBarItemIdentity) {
        guard state == .collapsed, assertion.isActive, AXIsProcessTrusted() else { return }
        let token = advance()
        let name = peekName(identity)
        Self.log.notice("peek starts for \(identity.bundleID, privacy: .public) | \(identity.title, privacy: .public)")
        // Swapped without a gap: the others never flash into the bar.
        let restricted = activate(hiding: hidden.excluding(identity), for: "peek") { [weak self] failure in
            guard let self else { return }
            if let failure {
                self.failOpen(.activationFailed(failure))
                return
            }
            self.locateForPeek(identity, name: name, token: token,
                               deadline: ProcessInfo.processInfo.systemUptime + Self.peekLocateWindow)
        }
        guard !restricted else { return }
        release("peek: nothing else hidden")
        locateForPeek(identity, name: name, token: token,
                      deadline: ProcessInfo.processInfo.systemUptime + Self.peekLocateWindow)
    }

    /// The icon returns a moment after the restriction changed, so it is
    /// looked for until the deadline.
    private func locateForPeek(_ identity: MenuBarItemIdentity, name: String, token: Int, deadline: TimeInterval) {
        MenuBarAccessibilityInventory.locate(identity) { [weak self] element in
            guard let self, self.epoch == token else { return }
            if let element {
                self.pressForPeek(element, isSystem: identity.bundleID == MenuBarOrganizerPolicy.agentBundleID,
                                  name: name, token: token)
                return
            }
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                Self.log.notice("peek: \(identity.bundleID, privacy: .public) did not return to the bar")
                self.endPeek(problem: .peekFailed(name))
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.peekLocateInterval) { [weak self] in
                guard let self, self.epoch == token else { return }
                self.locateForPeek(identity, name: name, token: token, deadline: deadline)
            }
        }
    }

    /// Presses the icon off the main thread. A status menu that holds the
    /// reply until it closes answers `.cannotComplete`, which counts as opened.
    /// A refused press shows the whole bar, so the real icon can be clicked.
    private func pressForPeek(_ element: AXUIElement, isSystem: Bool, name: String, token: Int) {
        var owner: pid_t = 0
        guard AXUIElementGetPid(element, &owner) == .success else {
            expand()
            problem = .peekFailed(name)
            return
        }
        let ownerPID = owner
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let pressed = ProcessInfo.processInfo.systemUptime
            AXUIElementSetMessagingTimeout(element, Self.peekPressTimeout)
            let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
            DispatchQueue.main.async { [weak self] in
                Self.log.notice("peek press result: \(result.rawValue, privacy: .public)")
                guard let self, self.epoch == token else { return }
                guard result == .success || result == .cannotComplete else {
                    self.expand()
                    self.problem = .peekFailed(name)
                    return
                }
                self.watchPeek(ownerPID: ownerPID, isSystem: isSystem, pressed: pressed, token: token)
            }
        }
    }

    /// Hides the icon again once its menu has come and gone, when no menu
    /// showed within the grace (the click did something else, such as opening
    /// a window), or when the menu stayed open past the limit.
    private func watchPeek(ownerPID: pid_t, isSystem: Bool, pressed: TimeInterval, token: Int) {
        peekSawMenu = false
        let timer = Timer(timeInterval: Self.peekWatchInterval, repeats: true) { [weak self] timer in
            guard let self, self.epoch == token else {
                timer.invalidate()
                return
            }
            let open = MenuBarPopupWatch.hasPopup(ownerPID: ownerPID, systemItem: isSystem)
            let age = ProcessInfo.processInfo.systemUptime - pressed
            self.peekSawMenu = self.peekSawMenu || open
            let done = self.peekSawMenu ? !open : age >= Self.peekMenuGrace
            guard done || age >= Self.peekLimit else { return }
            Self.log.notice("peek ends, menu seen: \(self.peekSawMenu, privacy: .public), after \(age, privacy: .public) s")
            self.endPeek()
        }
        RunLoop.main.add(timer, forMode: .common)
        peekTimer = timer
    }

    /// Hides the peeked icon again with the set the bar collapsed with, then
    /// shows `problem`, nil once all went well.
    private func endPeek(problem: Problem? = nil) {
        peekTimer?.invalidate()
        peekTimer = nil
        let restricted = activate(hiding: hidden, for: "peek end") { [weak self] failure in
            guard let self else { return }
            if let failure {
                self.failOpen(.activationFailed(failure))
                return
            }
            self.problem = problem
        }
        guard !restricted else { return }
        expand()
        if let problem { self.problem = problem }
    }

    /// The item's name for a problem line: the last walk, then what was
    /// remembered, then its own title, as the editor names it.
    private func peekName(_ identity: MenuBarItemIdentity) -> String {
        inventory.first { $0.identity == identity }?.appName
            ?? lastHidden.first { $0.identity == identity }?.appName
            ?? identity.title
    }

    // MARK: - System events

    /// An icon registered while others are hidden parks off screen and never
    /// reaches the bar. So a launch lifts the restriction briefly, waits for
    /// the new icon and restores what it lifted: a collapsed bar collapses
    /// again, which also puts the icon on its side of the collapser, and an
    /// expanded one takes the never-shown icons back out. Called for every
    /// new process the workspace lists, whatever its activation policy: the
    /// apps that own menu bar icons are mostly accessory apps.
    private func applicationLaunched(_ app: NSRunningApplication) {
        Self.log.notice("""
            launch seen: \(app.bundleIdentifier ?? "-", privacy: .public) \
            pid \(app.processIdentifier, privacy: .public) policy \(app.activationPolicy.rawValue, privacy: .public)
            """)
        refreshManagers()
        guard let bundleID = app.bundleIdentifier,
              MenuBarOrganizerPolicy.launchMayAddIcon(bundleID: bundleID,
                                                      backgroundOnly: app.activationPolicy == .prohibited,
                                                      ownBundleID: ownBundleID) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if !awaitedLaunches.isEmpty {
            // Already open for an earlier launch of the same burst.
            awaitedLaunches.insert(bundleID)
            launchRevealDeadline = min(now + Self.launchRevealWindow,
                                       launchRevealStarted + Self.launchRevealLimit)
            return
        }
        guard state == .collapsed || (state == .expanded && assertion.isActive) else { return }
        // An expanded bar does not change course: its auto re-hide timer
        // keeps running, and whatever advances the epoch ends the wait.
        let token = state == .collapsed ? advance() : epoch
        awaitedLaunches = [bundleID]
        launchRevealStarted = now
        launchRevealDeadline = now + Self.launchRevealWindow
        Self.log.notice("launch reveal starts for \(bundleID, privacy: .public)")
        release("launch reveal")
        pollForLaunchedItems(token: token)
    }

    private func pollForLaunchedItems(token: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.launchPollInterval) { [weak self] in
            guard let self, self.epoch == token else { return }
            MenuBarAccessibilityInventory.walk { [weak self] items in
                guard let self, self.epoch == token else { return }
                let present = Set(items.map(\.identity.bundleID))
                let expired = ProcessInfo.processInfo.systemUptime >= self.launchRevealDeadline
                guard expired || self.awaitedLaunches.isSubset(of: present) else {
                    self.pollForLaunchedItems(token: token)
                    return
                }
                let missing = self.awaitedLaunches.subtracting(present).sorted()
                Self.log.notice("launch reveal ends, expired: \(expired, privacy: .public), no icon from \(missing, privacy: .public)")
                self.awaitedLaunches.removeAll()
                self.restoreOrderAfterReveal(token: token, collapseAfterwards: self.state == .collapsed)
            }
        }
    }

    /// Sleep can drop the restriction. The bar may still be restricted, so the
    /// boundary cannot be read again: the remembered set is asserted anew, and
    /// the old restriction is only released once the new one is live. An
    /// expanded bar gets its never-shown restriction back the same way.
    private func reassertAfterWake() {
        guard state == .collapsed || (state == .expanded && assertion.isActive),
              awaitedLaunches.isEmpty else { return }
        let restricted = activate(hiding: state == .collapsed ? hidden : MenuBarHiddenSet(),
                                  for: "wake") { [weak self] failure in
            guard let failure else { return }
            self?.failOpen(.activationFailed(failure))
        }
        if !restricted { expand() }
    }

    private func accessibilityChanged(_ granted: Bool) {
        guard state != .off else { return }
        if !granted {
            // Without it the bar can be neither read nor trusted.
            if state == .collapsed || assertion.isActive {
                advance()
                failOpen(.accessibilityMissing)
            }
        } else if state == .expanded, problem == .accessibilityMissing {
            problem = nil
            collapseWhenQuiet()
        }
    }

    private func refreshManagers() {
        var names: [String] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  MenuBarManagerDetection.isKnownManager(bundleIdentifier: bundleID),
                  let name = app.localizedName, !names.contains(name) else { continue }
            names.append(name)
        }
        if runningManagers != names { runningManagers = names }
    }

    private func runningBundles() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    // MARK: - Reordering

    /// The visibility assertion does not preserve placement on every macOS
    /// version: a returning icon can land at the left end or across the
    /// collapser. Restore the last unrestricted order before adopting a new
    /// partition, otherwise showing icons would change which ones hide.
    /// New icons retain the planner's usual position at the left end.
    private func restoreOrderAfterReveal(token: Int, collapseAfterwards: Bool) {
        let order = inventory.map(\.identity)
        let cancellation = Cancellation()
        applyCancellation = cancellation
        state = .applying
        Self.moverQueue.async { [weak self] in
            let report = Self.reorder(to: order, afterReveal: true, cancellation: cancellation)
            Self.log.notice("restore order: \(report.moved, privacy: .public) moved, \(report.failed, privacy: .public) failed")
            DispatchQueue.main.async {
                guard let self, self.epoch == token, self.state == .applying else { return }
                self.applyCancellation = nil
                if report.failed > 0 { self.lastApplyReport = report }
                self.state = .expanded
                if collapseAfterwards {
                    self.walkAndCollapse(token: token)
                } else {
                    self.restrictExpanded()
                    self.refreshInventory()
                    self.scheduleAutoRehide()
                }
            }
        }
    }

    /// Stores the drawn never-shown list, drags the icons into the drawn
    /// order, then reports how many moves landed. Every icon is shown for the
    /// pass, because only an icon that is in the bar can be dragged, and the
    /// bar is restricted again afterwards. Never-shown icons are not part of
    /// the order; the planner leaves them at the left end. The system items
    /// macOS does not pin are dragged like any other icon.
    func apply(_ target: MenuBarLayout, collapseAfterApplying: Bool = false) {
        guard state == .expanded || state == .collapsed,
              let collapserIdentity = MenuBarOrganizerCollapser.identity else { return }
        guard AXIsProcessTrusted() else {
            problem = .accessibilityMissing
            return
        }
        let wasCollapsed = state == .collapsed
        let wasRestricted = assertion.isActive
        let token = advance()
        // Names come from the inventory, then from what was remembered.
        rememberNeverShown(MenuBarHiddenRecord.records(for: target.neverShown, items: inventory,
                                                       known: neverShown + lastHidden, ownBundleID: ownBundleID))
        Self.log.notice("apply starts, was collapsed: \(wasCollapsed, privacy: .public), restricted: \(wasRestricted, privacy: .public)")
        release("apply")
        state = .applying
        collapser.setCollapsed(false, shelfOpen: false)
        lastApplyReport = nil

        let order = target.hidden + [collapserIdentity] + target.visible
        let cancellation = Cancellation()
        applyCancellation = cancellation
        Self.moverQueue.async { [weak self] in
            let report = Self.reorder(to: order, afterReveal: wasRestricted, cancellation: cancellation)
            Self.log.notice("apply report: \(report.moved, privacy: .public) moved, \(report.failed, privacy: .public) failed")
            DispatchQueue.main.async {
                guard let self, self.epoch == token, self.state == .applying else { return }
                self.applyCancellation = nil
                self.lastApplyReport = report
                self.state = .expanded
                if wasCollapsed || collapseAfterApplying {
                    self.walkAndCollapse(token: token)
                } else {
                    self.restrictExpanded()
                    self.refreshInventory()
                    self.scheduleAutoRehide()
                }
            }
        }
    }

    /// Lets a pass that is being abandoned stop between two drags.
    private final class Cancellation {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    /// The reorder pass, off the main thread. Every move is verified by a
    /// fresh walk and retried once, re-aimed at the frames as they sit then.
    private static func reorder(to target: [MenuBarItemIdentity], afterReveal: Bool,
                                cancellation: Cancellation) -> (moved: Int, failed: Int) {
        func movableItems() -> [MenuBarItemSnapshot] {
            MenuBarAccessibilityInventory.walkNow().filter { MenuBarOrganizerPolicy.isMovable($0.identity) }
        }
        if afterReveal { waitForReturningItems() }
        var items = movableItems()
        let bar = CGDisplayBounds(CGMainDisplayID())
        var moved = 0
        var failed = 0
        for move in MenuBarMovePlanner.plan(current: items.map(\.identity), target: target) {
            for _ in 0..<2 {
                let order = items.map(\.identity)
                guard !cancellation.isCancelled, !MenuBarMovePlanner.isSatisfied(move, in: order) else { break }
                let frames = Dictionary(items.map { ($0.identity, $0.frame) }, uniquingKeysWith: { first, _ in first })
                guard let frame = frames[move.item],
                      let drop = MenuBarMovePlanner.dropPoint(for: move, frames: frames, order: order) else { break }
                let aim = CGPoint(x: min(max(drop.x, bar.minX + 1), bar.maxX - 1), y: drop.y)
                MenuBarItemMover.commandDrag(from: CGPoint(x: frame.midX, y: frame.midY), to: aim)
                // The agent animates the reflow before the tree settles.
                Thread.sleep(forTimeInterval: 0.35)
                items = movableItems()
            }
            if MenuBarMovePlanner.isSatisfied(move, in: items.map(\.identity)) {
                moved += 1
            } else {
                failed += 1
            }
            if cancellation.isCancelled { break }
        }
        return (moved, failed)
    }

    /// Icons return one by one after the restriction lifts; a plan made from
    /// half a bar would be wrong.
    private static func waitForReturningItems() {
        var gate = MenuBarQuietGate()
        let deadline = ProcessInfo.processInfo.systemUptime + 2.5
        Thread.sleep(forTimeInterval: 0.3)
        while ProcessInfo.processInfo.systemUptime < deadline {
            let items = MenuBarAccessibilityInventory.walkNow()
            if !items.isEmpty, gate.observe(items.map(\.identity)) { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }
}
