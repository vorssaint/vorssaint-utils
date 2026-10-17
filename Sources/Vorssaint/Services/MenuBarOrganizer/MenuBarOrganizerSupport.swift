// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

// The pure half of the Menu Bar Organizer: everything that can be decided from
// an inventory without touching Accessibility, AppKit or the private API.

/// Stable identity of one menu bar item: owning bundle + a name picked from
/// the AX identifier, then the AX description. Never the AX title: that is
/// display text an app rewrites at will (a usage percentage, the input
/// source), and an identity that changes between walks matches nothing that
/// was remembered. An item with neither is "Item-N", N counting the unnamed
/// items of its app from the left. `title` is the stored name of that field.
struct MenuBarItemIdentity: Hashable, Codable {
    let bundleID: String
    let title: String

    /// Identity for an item with these Accessibility strings; there is no
    /// parameter for the title on purpose. Two items of one app that would
    /// share a name get a numeric suffix, so an identity always names exactly
    /// one item of a walk.
    static func make(bundleID: String, identifier: String?, description: String?,
                     taken: Set<MenuBarItemIdentity>) -> MenuBarItemIdentity {
        let named = [identifier, description].lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let named {
            let plain = MenuBarItemIdentity(bundleID: bundleID, title: named)
            if !taken.contains(plain) { return plain }
        }
        // Unnamed items count from zero; a repeated name counts from one, the
        // unnumbered one being the first.
        var index = named == nil ? 0 : 1
        while true {
            let candidate = MenuBarItemIdentity(bundleID: bundleID, title: "\(named ?? "Item")-\(index)")
            if !taken.contains(candidate) { return candidate }
            index += 1
        }
    }
}

struct MenuBarItemSnapshot: Equatable {
    let identity: MenuBarItemIdentity
    /// CG global coordinates, top-left origin, main display.
    let frame: CGRect
    let pid: pid_t
    let appName: String?
    /// The host process has no LaunchServices bundle id of its own, so the
    /// allowlist cannot address it and the item cannot be hidden.
    let hostIsBundleless: Bool
    /// The host's code signature chains to an Apple-issued certificate. Only
    /// then does the menu bar agent record which app owns the item; an item
    /// without an owner matches no allowlist entry, so macOS hides it under
    /// any restriction and nothing in the allowlist can bring it back.
    let hostIsAppleSigned: Bool

    /// Drawn by the menu bar agent itself.
    var isSystem: Bool { identity.bundleID == MenuBarOrganizerPolicy.agentBundleID }
}

/// The system items the allowlist addresses one by one. The raw value is the
/// index the private API takes: an index left out of the list hides the item.
/// Other system items (Focus, Spotlight, Siri, Now Playing) have no index and
/// vanish under any restriction.
enum MenuBarSystemItem: Int, CaseIterable {
    case battery = 0, bluetooth, clock, displays, keyboard, sound, wifi, screenMirroring, controlCenter

    private static let identifierPrefix = "com.apple.menuextra."
    /// The input menu is drawn by a process of its own, not by the agent.
    static let textInputBundleID = "com.apple.TextInputMenuAgent"

    /// The system item an identity names, nil for anything else.
    static func item(for identity: MenuBarItemIdentity) -> MenuBarSystemItem? {
        if identity.bundleID == textInputBundleID { return .keyboard }
        guard identity.bundleID == MenuBarOrganizerPolicy.agentBundleID,
              identity.title.hasPrefix(identifierPrefix) else { return nil }
        switch identity.title.dropFirst(identifierPrefix.count) {
        case "battery": return .battery
        case "bluetooth": return .bluetooth
        case "clock": return .clock
        case "display", "displays": return .displays
        case "textinput", "keyboard": return .keyboard
        case "sound": return .sound
        case "wifi": return .wifi
        case "screen-mirroring": return .screenMirroring
        case "controlcenter": return .controlCenter
        default: return nil
        }
    }

    /// macOS keeps the clock and Control Center at the end of the bar: no
    /// drag moves them, so the organizer leaves them alone altogether.
    var isPinned: Bool { self == .clock || self == .controlCenter }

    /// SF Symbol for the editor row. Bluetooth has no symbol of its own.
    var symbol: String {
        switch self {
        case .battery: return "battery.100"
        case .bluetooth: return "wave.3.right"
        case .clock: return "clock"
        case .displays: return "display"
        case .keyboard: return "keyboard"
        case .sound: return "speaker.wave.2"
        case .wifi: return "wifi"
        case .screenMirroring: return "airplayvideo"
        case .controlCenter: return "switch.2"
        }
    }
}

/// What a restriction keeps out of the bar: apps by bundle id, system items
/// by index.
struct MenuBarHiddenSet: Equatable {
    var bundles = Set<String>()
    var systemItems = Set<MenuBarSystemItem>()

    init() {}

    /// The set that hides `identities`. An item of the input menu's process
    /// counts as the keyboard system item, not as a bundle.
    init(_ identities: some Sequence<MenuBarItemIdentity>) {
        for identity in identities {
            if let system = MenuBarSystemItem.item(for: identity) {
                systemItems.insert(system)
            } else {
                bundles.insert(identity.bundleID)
            }
        }
    }

    /// The set without the host of `identity`: its bundle, or its system
    /// item. What a peek keeps hidden while that one icon is in the bar.
    func excluding(_ identity: MenuBarItemIdentity) -> MenuBarHiddenSet {
        var rest = self
        if let system = MenuBarSystemItem.item(for: identity) {
            rest.systemItems.remove(system)
        } else {
            rest.bundles.remove(identity.bundleID)
        }
        return rest
    }
}

enum MenuBarOrganizerAvailability {
    enum Unsupported: Equatable {
        case requiresMacOS27(current: String)
        case apiMissing
    }

    /// Why hiding cannot work on this Mac, or nil when it can. The version is
    /// judged first: below macOS 27 the private API is never even looked up.
    static func unsupportedReason(majorVersion: Int, versionString: String,
                                  bridgeAvailable: Bool) -> Unsupported? {
        guard majorVersion >= 27 else { return .requiresMacOS27(current: versionString) }
        return bridgeAvailable ? nil : .apiMissing
    }
}

enum MenuBarOrganizerPolicy {
    static let agentBundleID = "com.apple.MenuBarAgent"

    /// Accessory processes macOS starts for a moment that never own a status
    /// item. The screenshot shortcuts start the first one, and opening the
    /// bar for it showed every hidden icon right in the capture.
    static let iconlessHelpers: Set<String> = ["com.apple.screencaptureui"]

    /// Whether a launch may bring a new icon, so the bar opens to let it in.
    /// Not for Vorssaint itself, not for a background-only process (it cannot
    /// own a status item) and not for a helper known to come without one.
    static func launchMayAddIcon(bundleID: String?, backgroundOnly: Bool, ownBundleID: String) -> Bool {
        guard let bundleID, bundleID != ownBundleID, !backgroundOnly else { return false }
        return !iconlessHelpers.contains(bundleID)
    }

    /// A system item hides through its index unless macOS pins it; the
    /// agent's other items have no index. For apps the allowlist works per
    /// bundle id, so an item can only be hidden when its host has one, and
    /// Vorssaint's own bundle must stay because the collapser lives in it.
    static func canHide(_ item: MenuBarItemSnapshot, ownBundleID: String) -> Bool {
        if let system = MenuBarSystemItem.item(for: item.identity) { return !system.isPinned }
        return !item.isSystem && !item.hostIsBundleless
            && !item.identity.bundleID.isEmpty && item.identity.bundleID != ownBundleID
    }

    /// Whether a ⌘-drag may move the item: not the pinned system items, and
    /// not the agent's items the organizer does not know.
    static func isMovable(_ identity: MenuBarItemIdentity) -> Bool {
        if let system = MenuBarSystemItem.item(for: identity) { return !system.isPinned }
        return identity.bundleID != agentBundleID
    }

    /// Whether hiding one hides the other: two icons of one app, or the same
    /// system item. Each system item hides alone although the agent draws
    /// them all.
    static func hideTogether(_ first: MenuBarItemIdentity, _ second: MenuBarItemIdentity) -> Bool {
        let systems = (MenuBarSystemItem.item(for: first), MenuBarSystemItem.item(for: second))
        return systems == (nil, nil) ? first.bundleID == second.bundleID : systems.0 == systems.1
    }
}

/// The icon of the collapser, the organizer's own status item.
enum MenuBarOrganizerIcon: String, CaseIterable {
    case chevron, dots, lines, grid

    /// SF Symbol for the state. Only the chevron changes: in the bar it points
    /// at the hidden icons while they are hidden, with a shelf it points at
    /// the shelf, down while it is closed and up while it is open.
    func symbol(collapsed: Bool, reveal: MenuBarOrganizerReveal, shelfOpen: Bool) -> String {
        switch self {
        case .chevron:
            switch reveal {
            case .menuBar: return collapsed ? "chevron.left" : "chevron.right"
            case .shelf: return shelfOpen ? "chevron.up" : "chevron.down"
            }
        case .dots: return "ellipsis"
        case .lines: return "line.3.horizontal"
        case .grid: return "circle.grid.2x2"
        }
    }

    /// The icon a stored preference names, the chevron when it names none.
    static func stored(_ raw: String?) -> MenuBarOrganizerIcon {
        raw.flatMap(MenuBarOrganizerIcon.init(rawValue:)) ?? .chevron
    }
}

/// Where the hidden icons show when the collapser is clicked: back in the
/// bar, or in a shelf below the collapser while the bar stays collapsed.
enum MenuBarOrganizerReveal: String, CaseIterable {
    case menuBar, shelf

    /// The reveal a stored preference names, the bar when it names none.
    static func stored(_ raw: String?) -> MenuBarOrganizerReveal {
        raw.flatMap(MenuBarOrganizerReveal.init(rawValue:)) ?? .menuBar
    }
}

/// Items left of the collapser are hidden, right of it visible, in visual
/// order. Never-shown items have no place in the bar; theirs is the order of
/// the editor.
struct MenuBarLayout: Equatable {
    var hidden: [MenuBarItemIdentity]
    var visible: [MenuBarItemIdentity]
    var neverShown: [MenuBarItemIdentity] = []
}

enum MenuBarOrganizerLayout {
    /// Splits an inventory at the collapser. Purely positional: items that can
    /// never be hidden still land on the side they sit on. nil when the
    /// collapser is not in the inventory (fail open).
    static func partition(_ items: [MenuBarItemSnapshot], collapser: MenuBarItemIdentity) -> MenuBarLayout? {
        let ordered = items.sorted { $0.frame.minX < $1.frame.minX }.map(\.identity)
        guard let boundary = ordered.firstIndex(of: collapser) else { return nil }
        return MenuBarLayout(hidden: Array(ordered[..<boundary]),
                             visible: Array(ordered[(boundary + 1)...]))
    }

    /// What the assertion should hide for a layout: the hosts of the hidden
    /// items that can be hidden at all, and the hidden system items.
    static func hidden(in layout: MenuBarLayout, items: [MenuBarItemSnapshot],
                       ownBundleID: String) -> MenuBarHiddenSet {
        let hidden = Set(layout.hidden)
        return MenuBarHiddenSet(items.lazy
            .filter { hidden.contains($0.identity) && MenuBarOrganizerPolicy.canHide($0, ownBundleID: ownBundleID) }
            .map(\.identity))
    }

    /// What the assertion keeps out of the bar even while it is expanded.
    /// A never-shown item is gone from Accessibility, so one the inventory
    /// lacks counts when it is among the `known` records, which only ever
    /// hold items that can be hidden.
    static func neverShown(in layout: MenuBarLayout, items: [MenuBarItemSnapshot],
                           known: [MenuBarHiddenRecord], ownBundleID: String) -> MenuBarHiddenSet {
        MenuBarHiddenSet(MenuBarHiddenRecord.records(for: layout.neverShown, items: items, known: known,
                                                     ownBundleID: ownBundleID).map(\.identity))
    }

    /// Allowlist for the assertion: everything but the hidden and the
    /// never-shown bundles and system items. `nil` when neither names
    /// anything that can be hidden (drop the assertion instead). Every running
    /// app stays allowed, not only the ones seen in the bar: an extra allowed
    /// bundle costs nothing, and a missing one would swallow an icon nobody
    /// asked to hide. The pinned system items always stay allowed.
    static func allowlist(hidden: MenuBarHiddenSet, neverShown: MenuBarHiddenSet,
                          observed: [MenuBarItemSnapshot], running: Set<String>,
                          ownBundleID: String) -> (bundles: [String], systemItems: [Int])? {
        let protected = Set(observed.lazy.filter(\.hostIsBundleless).map(\.identity.bundleID))
            .union([ownBundleID, MenuBarOrganizerPolicy.agentBundleID, ""])
        var hiddenBundles = hidden.bundles.union(neverShown.bundles).subtracting(protected)
        let hiddenSystem = hidden.systemItems.union(neverShown.systemItems).filter { !$0.isPinned }
        guard !(hiddenBundles.isEmpty && hiddenSystem.isEmpty), !ownBundleID.isEmpty else { return nil }
        // The input menu's own process must not vouch for an icon whose
        // index is being withheld.
        if hiddenSystem.contains(.keyboard) { hiddenBundles.insert(MenuBarSystemItem.textInputBundleID) }
        let allowed = running
            .union(observed.lazy.filter { !$0.isSystem }.map(\.identity.bundleID))
            .union([ownBundleID])
            .subtracting(hiddenBundles)
            .subtracting([""])
        let systemItems = MenuBarSystemItem.allCases.filter { !hiddenSystem.contains($0) }.map(\.rawValue)
        return (allowed.sorted(), systemItems)
    }
}

/// One ⌘-drag: put `item` immediately after `after` (nil = leftmost of the movable run).
struct MenuBarMove: Equatable {
    let item: MenuBarItemIdentity
    let after: MenuBarItemIdentity?
}

enum MenuBarMovePlanner {
    /// Minimal drags turning `current` into `target` (both left→right, movable
    /// items only). Items of `target` that are gone are skipped, and items the
    /// target does not mention keep the left end, where macOS puts newcomers.
    /// The moves are meant to be performed in order.
    static func plan(current: [MenuBarItemIdentity], target: [MenuBarItemIdentity]) -> [MenuBarMove] {
        let goal = resolvedTarget(current: current, target: target)
        let rank = Dictionary(goal.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        // The longest run already in the right relative order stays put;
        // everything else needs exactly one drag.
        let settled = longestIncreasingRun(current.compactMap { rank[$0] })
        var moves: [MenuBarMove] = []
        for (index, item) in goal.enumerated() where !settled.contains(index) {
            moves.append(MenuBarMove(item: item, after: index == 0 ? nil : goal[index - 1]))
        }
        return moves
    }

    /// The order a move produces, used to tell whether a drag landed.
    static func applying(_ move: MenuBarMove, to order: [MenuBarItemIdentity]) -> [MenuBarItemIdentity] {
        var result = order.filter { $0 != move.item }
        guard result.count < order.count else { return order }
        guard let after = move.after else {
            result.insert(move.item, at: 0)
            return result
        }
        guard let anchor = result.firstIndex(of: after) else { return order }
        result.insert(move.item, at: anchor + 1)
        return result
    }

    static func isSatisfied(_ move: MenuBarMove, in order: [MenuBarItemIdentity]) -> Bool {
        guard let position = order.firstIndex(of: move.item) else { return false }
        guard let after = move.after else { return position == 0 }
        return position > 0 && order[position - 1] == after
    }

    /// Drop point for a move given fresh frames: halfway between the centers
    /// of `after` and its right neighbour, just right of `after` when it is the
    /// last one, or just left of the leftmost item. nil when a frame is missing.
    static func dropPoint(for move: MenuBarMove, frames: [MenuBarItemIdentity: CGRect],
                          order: [MenuBarItemIdentity]) -> CGPoint? {
        guard let own = frames[move.item] else { return nil }
        let others = order.filter { $0 != move.item }
        // The dragged item is held by its center, so half its width keeps it
        // clear of the neighbour it must not cross.
        let clearance = own.width / 2 + 2
        guard let after = move.after else {
            guard let first = others.first, let frame = frames[first] else { return nil }
            return CGPoint(x: frame.minX - clearance, y: own.midY)
        }
        guard let anchor = others.firstIndex(of: after), let left = frames[after] else { return nil }
        guard anchor + 1 < others.count else {
            return CGPoint(x: left.maxX + clearance, y: own.midY)
        }
        guard let right = frames[others[anchor + 1]] else { return nil }
        return CGPoint(x: (left.midX + right.midX) / 2, y: own.midY)
    }

    private static func resolvedTarget(current: [MenuBarItemIdentity],
                                       target: [MenuBarItemIdentity]) -> [MenuBarItemIdentity] {
        let present = Set(current)
        var seen = Set<MenuBarItemIdentity>()
        let wanted = target.filter { present.contains($0) && seen.insert($0).inserted }
        return current.filter { !seen.contains($0) } + wanted
    }

    /// Values of one longest strictly increasing subsequence.
    private static func longestIncreasingRun(_ values: [Int]) -> Set<Int> {
        guard !values.isEmpty else { return [] }
        var length = [Int](repeating: 1, count: values.count)
        var previous = [Int?](repeating: nil, count: values.count)
        for index in values.indices {
            for earlier in 0..<index where values[earlier] < values[index] && length[earlier] + 1 > length[index] {
                length[index] = length[earlier] + 1
                previous[index] = earlier
            }
        }
        var cursor = length.indices.max { length[$0] < length[$1] }
        var run = Set<Int>()
        while let index = cursor {
            run.insert(values[index])
            cursor = previous[index]
        }
        return run
    }
}

/// Decides when the menu bar has stopped changing after launch: the same
/// inventory on enough consecutive walks. Login items keep adding icons for a
/// while, and collapsing early would freeze a boundary they have yet to cross.
struct MenuBarQuietGate {
    static let requiredMatches = 3
    private var last: [MenuBarItemIdentity]?
    private var matches = 0

    /// Feeds one walk; true once the bar counts as quiet.
    mutating func observe(_ inventory: [MenuBarItemIdentity]) -> Bool {
        matches = inventory == last ? matches + 1 : 1
        last = inventory
        return matches >= Self.requiredMatches
    }
}

/// A hidden or never-shown item as it is remembered across the time it is
/// gone from Accessibility, so the editor can still name it.
struct MenuBarHiddenRecord: Codable, Equatable {
    let identity: MenuBarItemIdentity
    let appName: String?

    /// What a collapse hid, for the shelf and for a bar read while hidden.
    /// An item kept out for good is not among them even when the walk saw
    /// it: a bar open for a moment shows it, the shelf never does.
    static func records(for layout: MenuBarLayout, items: [MenuBarItemSnapshot],
                        neverShown: [MenuBarHiddenRecord], ownBundleID: String) -> [MenuBarHiddenRecord] {
        let byIdentity = Dictionary(items.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
        return layout.hidden.compactMap { identity in
            guard let item = byIdentity[identity],
                  MenuBarOrganizerPolicy.canHide(item, ownBundleID: ownBundleID),
                  !neverShown.contains(where: { MenuBarOrganizerPolicy.hideTogether($0.identity, identity) })
            else { return nil }
            return MenuBarHiddenRecord(identity: identity, appName: item.appName)
        }
    }

    /// Records for the given identities, in their order. An item in the
    /// inventory must be hideable; one the inventory lacks is taken over from
    /// the `known` records, and dropped when there is none.
    static func records(for identities: [MenuBarItemIdentity], items: [MenuBarItemSnapshot],
                        known: [MenuBarHiddenRecord], ownBundleID: String) -> [MenuBarHiddenRecord] {
        let byIdentity = Dictionary(items.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
        return identities.compactMap { identity in
            guard let item = byIdentity[identity] else { return known.first { $0.identity == identity } }
            guard MenuBarOrganizerPolicy.canHide(item, ownBundleID: ownBundleID) else { return nil }
            return MenuBarHiddenRecord(identity: identity, appName: item.appName)
        }
    }

    static func encode(_ records: [MenuBarHiddenRecord]) -> Data? {
        try? JSONEncoder().encode(records)
    }

    static func decode(_ data: Data?) -> [MenuBarHiddenRecord] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([MenuBarHiddenRecord].self, from: data)) ?? []
    }
}

/// The drawing behind the layout editor in Settings. Nothing moves in the bar
/// until the drawing is applied, so it is compared with the bar it started from.
enum MenuBarOrganizerEditorSupport {
    enum Tier: CaseIterable {
        /// Right of the collapser, always in the bar.
        case show
        /// Left of the collapser, in the bar only while it is expanded.
        case hide
        /// Not in the bar at all.
        case never
    }

    /// What a row says under its name without being locked.
    enum Note {
        /// macOS hides the item whenever anything is hidden, in every tier.
        case unsigned
    }

    static func note(for item: MenuBarItemSnapshot) -> Note? {
        item.hostIsAppleSigned ? nil : .unsigned
    }

    static func tier(of identity: MenuBarItemIdentity, in layout: MenuBarLayout) -> Tier? {
        if layout.visible.contains(identity) { return .show }
        if layout.hidden.contains(identity) { return .hide }
        return layout.neverShown.contains(identity) ? .never : nil
    }

    /// The layout the editor starts from. While icons are hidden the bar
    /// cannot be read, so remembered hidden items the last partition does not
    /// know (a relaunch) join the hidden side. Never-shown items are always
    /// drawn from memory. A walk of a bar that was open for a moment may have
    /// seen their apps on either side; they are hidden all the same, so every
    /// icon of such an app is drawn as never shown. A system item is kept out
    /// alone, not with the agent's other items.
    static func baseline(layout: MenuBarLayout?, lastHidden: [MenuBarHiddenRecord],
                         neverShown: [MenuBarHiddenRecord], collapsed: Bool) -> MenuBarLayout {
        var baseline = layout ?? MenuBarLayout(hidden: [], visible: [])
        if collapsed {
            let known = Set(baseline.hidden + baseline.visible)
            baseline.hidden += lastHidden.map(\.identity).filter { !known.contains($0) }
        }
        let remembered = neverShown.map(\.identity)
        let isKeptOut = { (identity: MenuBarItemIdentity) in
            remembered.contains { MenuBarOrganizerPolicy.hideTogether($0, identity) }
        }
        let seen = (baseline.hidden + baseline.visible).filter(isKeptOut)
        baseline.hidden.removeAll(where: isKeptOut)
        baseline.visible.removeAll(where: isKeptOut)
        baseline.neverShown = remembered + seen.filter { !remembered.contains($0) }
        return baseline
    }

    /// Moves an item into `tier`, in front of `target` or to the end of the
    /// tier without one. The one function behind drag and drop and the row
    /// menu. Never show works per app, so a move into or out of it takes
    /// every icon of the app along (a system item goes alone), and an item
    /// that `isLocked` never goes there. Within one list an item dragged down lands behind the row it
    /// reached, as it does when rows part under a drag.
    static func moving(_ identity: MenuBarItemIdentity, to tier: Tier, before target: MenuBarItemIdentity?,
                       in layout: MenuBarLayout, isLocked: (MenuBarItemIdentity) -> Bool) -> MenuBarLayout {
        guard identity != target, let source = Self.tier(of: identity, in: layout),
              !(tier == .never && isLocked(identity)) else { return layout }
        var moved = [identity]
        if source != tier, source == .never || tier == .never {
            moved = (layout.hidden + layout.visible + layout.neverShown).filter {
                MenuBarOrganizerPolicy.hideTogether($0, identity) && !(tier == .never && isLocked($0))
            }
        }
        let path: WritableKeyPath<MenuBarLayout, [MenuBarItemIdentity]>
        switch tier {
        case .show: path = \.visible
        case .hide: path = \.hidden
        case .never: path = \.neverShown
        }
        let list = layout[keyPath: path]
        let draggedDown = source == tier
            && (target.flatMap(list.firstIndex(of:)) ?? 0) > (list.firstIndex(of: identity) ?? 0)

        var result = layout
        result.hidden.removeAll(where: moved.contains)
        result.visible.removeAll(where: moved.contains)
        result.neverShown.removeAll(where: moved.contains)
        let anchor = target.flatMap(result[keyPath: path].firstIndex(of:))
        result[keyPath: path].insert(contentsOf: moved,
                                     at: anchor.map { draggedDown ? $0 + 1 : $0 } ?? result[keyPath: path].count)
        return result
    }
}

enum MenuBarManagerDetection {
    /// Bartender (incl. Setapp), Ice, Ice 2, Thaw, Pelmet, Hidden Bar, Dozer
    /// and MenubarHide. Prefixes, so helper and variant bundles match too.
    private static let prefixes = [
        "com.surteesstudios.bartender",
        "com.jordanbaird.ice",
        "com.dragonapp.ice",
        "com.stonerl.thaw",
        "app.fif7y.pelmet",
        "com.dwarvesv.minimalbar",
        "com.mortennn.dozer",
        "br.tec.sparrow.menubarhide"
    ]

    static func isKnownManager(bundleIdentifier: String) -> Bool {
        let lowered = bundleIdentifier.lowercased()
        return prefixes.contains { lowered == $0 || lowered.hasPrefix($0 + ".") || lowered.hasPrefix($0 + "-") }
    }
}
