// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// One action on the wheel. `payload` carries the target: an app or file path,
/// a link, tool, media or window-layout identifier, or a shortcut storage
/// value. Submenus keep their actions in `children`.
struct RadialMenuItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case app, file, url, shortcut, tool, windowLayout, media, submenu
    }

    var id = UUID()
    var kind = Kind.app
    var name = ""
    var symbolName = ""
    var payload = ""
    var children: [RadialMenuItem] = []

    var tool: RadialMenuTool? {
        kind == .tool ? RadialMenuTool(rawValue: payload) : nil
    }

    var mediaKey: RadialMenuMediaKey? {
        kind == .media ? RadialMenuMediaKey(rawValue: payload) : nil
    }

    var windowLayoutAction: WindowLayoutAction? {
        kind == .windowLayout ? WindowLayoutAction(rawValue: payload) : nil
    }

    /// The symbol drawn when the user picked none. App and file items prefer
    /// their real file icons in the UI; these are the fallbacks.
    var defaultSymbolName: String {
        switch kind {
        case .app: return "app"
        case .file: return "folder"
        case .url: return "link"
        case .shortcut: return "command"
        case .tool: return tool?.symbolName ?? "wrench.and.screwdriver"
        case .windowLayout: return windowLayoutAction?.symbolName ?? AppFeature.windowLayout.symbolName
        case .media:
            switch mediaKey {
            case .previousTrack: return "backward.fill"
            case .nextTrack: return "forward.fill"
            default: return "playpause.fill"
            }
        case .submenu: return "ellipsis.circle"
        }
    }

    var effectiveSymbolName: String {
        symbolName.isEmpty ? defaultSymbolName : symbolName
    }
}

// The custom decoder lives in an extension so the memberwise initializer
// stays synthesized. It tolerates blobs written by newer versions: absent
// fields fall back to their defaults, and an unknown kind fails just this
// item, which the lossy array decode below then drops instead of losing the
// whole menu.
extension RadialMenuItem {
    private enum CodingKeys: String, CodingKey {
        case id, kind, name, symbolName, payload, children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  kind: try container.decode(Kind.self, forKey: .kind),
                  name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
                  symbolName: try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "",
                  payload: try container.decodeIfPresent(String.self, forKey: .payload) ?? "",
                  children: try container.decodeIfPresent([FailableRadialMenuItem].self, forKey: .children)?
                      .compactMap(\.value) ?? [])
    }
}

private struct FailableRadialMenuItem: Decodable {
    let value: RadialMenuItem?

    init(from decoder: Decoder) throws {
        value = try? RadialMenuItem(from: decoder)
    }
}

/// Vorssaint tools a slice can trigger. Raw values persist inside the items
/// blob; never rename them.
enum RadialMenuTool: String, Codable, CaseIterable, Identifiable {
    case screenshot, colorPicker, screenOCR, micMute, clipboardHistory, quickLauncher, cameraPreview,
         scratchpad, shelf, cleaningMode, keepAwake

    var id: String { rawValue }

    var feature: AppFeature {
        switch self {
        case .screenshot: return .screenshot
        case .colorPicker: return .colorPicker
        case .screenOCR: return .screenOCR
        case .micMute: return .micMute
        case .clipboardHistory: return .clipboardHistory
        case .quickLauncher: return .quickLauncher
        case .cameraPreview: return .cameraPreview
        case .scratchpad: return .scratchpad
        case .shelf: return .shelf
        case .cleaningMode: return .cleaningMode
        case .keepAwake: return .keepAwake
        }
    }

    var symbolName: String { feature.symbolName }

    /// Hub availability and a feature's own master switch are separate. A
    /// saved Shelf slice stays dormant while Shelf is explicitly disabled and
    /// returns automatically when the user enables it again.
    func isRunnable(isFeatureAvailable: (AppFeature) -> Bool = { $0.isAvailable },
                    boolFor: (String) -> Bool = { UserDefaults.standard.bool(forKey: $0) }) -> Bool {
        guard isFeatureAvailable(feature) else { return false }
        return self != .shelf || boolFor(DefaultsKey.shelfEnabled)
    }
}

/// The optional second summoner: a spare side mouse button. Raw values are
/// persisted; button numbers follow the HID convention the side buttons
/// report (3 back, 4 forward).
enum RadialMenuMouseTrigger: String, CaseIterable, Identifiable {
    case off, back, forward

    var id: String { rawValue }

    var buttonNumber: Int64? {
        switch self {
        case .off: return nil
        case .back: return 3
        case .forward: return 4
        }
    }

    static func sanitized(_ raw: String?) -> RadialMenuMouseTrigger {
        RadialMenuMouseTrigger(rawValue: raw ?? "") ?? .off
    }
}

/// How the summoning shortcut or side button owns a radial-menu session.
/// Raw values are persisted; never rename them.
enum RadialMenuActivationMode: String, CaseIterable, Identifiable {
    /// The existing adaptive gesture: release over a slice to run it, or
    /// release near the center to leave the wheel open for clicking.
    case pressOrHold
    /// A press opens a sticky wheel. Releasing the summoner has no effect.
    case press
    /// The wheel exists only while the summoner is down. Release runs the
    /// highlighted slice, or simply dismisses when nothing is highlighted.
    case hold

    var id: String { rawValue }

    static func sanitized(_ raw: String?) -> RadialMenuActivationMode {
        RadialMenuActivationMode(rawValue: raw ?? "") ?? .pressOrHold
    }

    func startsHeld(requestedHold: Bool, hasHeldButton: Bool,
                    shortcutHasModifiers: Bool) -> Bool {
        guard self != .press else { return false }
        return hasHeldButton || (requestedHold && shortcutHasModifiers)
    }

    func releaseAction(hasSelection: Bool) -> RadialMenuReleaseAction {
        if hasSelection { return .select }
        return self == .hold ? .dismiss : .stayOpen
    }
}

enum RadialMenuReleaseAction: Equatable {
    case stayOpen, dismiss, select
}

extension RadialMenuSupport {
    /// Whether the radial menu currently owns this side button as its
    /// summoner. Mouse navigation asks this from its own tap and lets a
    /// claimed button through; pure defaults reads, so asking never wakes
    /// the radial menu service.
    static func claimsMouseButton(_ button: Int64) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppFeature.radialMenu.availabilityKey),
              defaults.bool(forKey: DefaultsKey.radialMenuEnabled) else { return false }
        return RadialMenuMouseTrigger.sanitized(
            defaults.string(forKey: DefaultsKey.radialMenuMouseButton)).buttonNumber == button
    }
}

/// Media keys a slice can press, mapped to the aux-button codes the physical
/// keys post (NX_KEYTYPE_PLAY / FAST / REWIND).
enum RadialMenuMediaKey: String, Codable, CaseIterable, Identifiable {
    case playPause, previousTrack, nextTrack

    var id: String { rawValue }

    var auxKeyType: Int32 {
        switch self {
        case .playPause: return 16
        case .previousTrack: return 20
        case .nextTrack: return 19
        }
    }
}

enum RadialMenuSupport {
    static let maxItemsPerWheel = 12
    /// Root plus one submenu level. Deeper nesting turns the wheel into a maze.
    static let maxDepth = 2

    /// Whether the target can actually run for this kind. The editor blocks
    /// saving what fails here, and `sanitized` drops it, so the two can never
    /// disagree about what belongs on a wheel.
    static func isValidPayload(_ item: RadialMenuItem) -> Bool {
        switch item.kind {
        case .app, .file: return !item.payload.isEmpty
        case .url: return normalizedURL(item.payload) != nil
        case .shortcut: return GlobalShortcut(storageValue: item.payload) != nil
        case .tool: return item.tool != nil
        case .windowLayout: return item.windowLayoutAction != nil
        case .media: return item.mediaKey != nil
        case .submenu: return true
        }
    }

    /// Drops what cannot run (unknown tools or media keys, unparseable
    /// shortcuts, empty targets, submenus past the depth cap) and clamps
    /// counts, so the wheel never renders a dead slice.
    static func sanitized(_ items: [RadialMenuItem], depth: Int = 0) -> [RadialMenuItem] {
        guard depth < maxDepth else { return [] }
        var seen = Set<UUID>()
        var result: [RadialMenuItem] = []
        for var item in items {
            guard result.count < maxItemsPerWheel, seen.insert(item.id).inserted else { continue }
            item.name = String(item.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            item.payload = item.payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidPayload(item) else { continue }
            if item.kind == .url, let normalized = normalizedURL(item.payload) {
                item.payload = normalized
            }
            if item.kind == .submenu {
                guard depth + 1 < maxDepth else { continue }
                item.children = sanitized(item.children, depth: depth + 1)
            } else {
                item.children = []
            }
            result.append(item)
        }
        return result
    }

    /// A missing blob means a fresh install and yields the starter wheel; a
    /// present blob, even an empty list, is the user's own menu.
    static func decode(_ data: Data?) -> [RadialMenuItem] {
        guard let data else { return starterItems }
        let decoded = (try? JSONDecoder().decode([FailableRadialMenuItem].self, from: data)) ?? []
        return sanitized(decoded.compactMap(\.value))
    }

    static func encode(_ items: [RadialMenuItem]) -> Data? {
        try? JSONEncoder().encode(sanitized(items))
    }

    /// Accepts "example.com/page" style input by assuming https, keeps
    /// explicit schemes (mailto:, app links) as typed, and rejects anything
    /// that cannot become a loadable URL.
    static func normalizedURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if hasExplicitScheme(trimmed) {
            guard let url = URL(string: trimmed) else { return nil }
            if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return url.host != nil ? trimmed : nil
            }
            return trimmed
        }
        let candidate = "https://" + trimmed
        guard let url = URL(string: candidate), url.host != nil else { return nil }
        return candidate
    }

    /// A leading URL scheme, minding that "example.com:8080" is a host and
    /// port while "tel:5551234" is a scheme: digits after the colon only
    /// mean a port when the part before it looks like a host.
    private static func hasExplicitScheme(_ value: String) -> Bool {
        if value.contains("://") { return true }
        guard value.first?.isLetter == true,
              let colon = value.firstIndex(of: ":"),
              value[..<colon].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
        else { return false }
        let after = value.index(after: colon)
        guard after < value.endIndex else { return false }
        guard value[after].isNumber else { return true }
        let prefix = value[..<colon]
        return !prefix.contains(".") && prefix.lowercased() != "localhost"
    }

    /// The wheel a fresh install starts with: media around the top, tools and
    /// the Downloads folder below. Names stay empty so every language derives
    /// its own labels. A single evaluation keeps the seed ids stable for the
    /// whole session, so equality against a decoded seed behaves.
    static let starterItems: [RadialMenuItem] = [
        RadialMenuItem(kind: .media, payload: RadialMenuMediaKey.playPause.rawValue),
        RadialMenuItem(kind: .media, payload: RadialMenuMediaKey.nextTrack.rawValue),
        RadialMenuItem(kind: .tool, payload: RadialMenuTool.screenshot.rawValue),
        RadialMenuItem(kind: .file, payload: "~/Downloads"),
        RadialMenuItem(kind: .tool, payload: RadialMenuTool.colorPicker.rawValue),
        RadialMenuItem(kind: .media, payload: RadialMenuMediaKey.previousTrack.rawValue),
    ]

    /// True when any item, at any level, controls keyboard input or windows
    /// and therefore needs the Accessibility permission.
    static func needsAccessibility(_ items: [RadialMenuItem]) -> Bool {
        items.contains { item in
            switch item.kind {
            case .shortcut, .windowLayout, .media: return true
            case .submenu: return needsAccessibility(item.children)
            default: return false
            }
        }
    }

    static func usesWindowLayout(_ items: [RadialMenuItem]) -> Bool {
        items.contains { item in
            item.kind == .windowLayout
                || (item.kind == .submenu && usesWindowLayout(item.children))
        }
    }
}

/// Shared wheel dimensions, points. The service positions the panel and maps
/// pointer distances with these; the view draws with them. The panel is a
/// good margin wider than the wheel so its soft shadow fades out naturally
/// instead of being clipped into a visible square.
enum RadialMenuLayout {
    static let panelSize: CGFloat = 400
    static let wheelDiameter: CGFloat = 300
    static let ringRadius: CGFloat = 112
    static let chipSize: CGFloat = 52
    static let hubDiameter: CGFloat = 76
    static let deadZoneRadius: CGFloat = 40
    /// The pointer must travel this far from where the wheel opened before
    /// slices start highlighting, so a center-of-screen wheel never fires on
    /// whatever direction the pointer already happened to sit in.
    static let moveActivationDistance: CGFloat = 8
}

/// Pure slice math shared by the wheel view and the pointer tracking. Slice 0
/// sits at 12 o'clock and indices grow clockwise; angles are measured
/// clockwise from the top in radians.
enum RadialMenuGeometry {
    /// Angle of the vector (dx, dyUp) where dyUp grows toward the top of the
    /// screen, in [0, 2 * pi).
    static func angle(dx: CGFloat, dyUp: CGFloat) -> CGFloat {
        let raw = atan2(dx, dyUp)
        return raw < 0 ? raw + 2 * .pi : raw
    }

    static func index(forAngle angle: CGFloat, itemCount: Int) -> Int? {
        guard itemCount > 0 else { return nil }
        let step = 2 * .pi / CGFloat(itemCount)
        let shifted = (angle + step / 2).truncatingRemainder(dividingBy: 2 * .pi)
        let index = Int(shifted / step)
        return min(max(index, 0), itemCount - 1)
    }

    /// The slice under the pointer, nil inside the dead zone around the hub.
    static func highlightedIndex(dx: CGFloat, dyUp: CGFloat,
                                 deadZoneRadius: CGFloat, itemCount: Int) -> Int? {
        guard itemCount > 0 else { return nil }
        let distance = (dx * dx + dyUp * dyUp).squareRoot()
        guard distance >= deadZoneRadius else { return nil }
        return index(forAngle: angle(dx: dx, dyUp: dyUp), itemCount: itemCount)
    }

    /// Unit-circle position of a slice center, dyUp toward the screen top.
    static func unitPosition(index: Int, itemCount: Int) -> (dx: CGFloat, dyUp: CGFloat) {
        guard itemCount > 0 else { return (0, 1) }
        let theta = 2 * .pi * CGFloat(index) / CGFloat(itemCount)
        return (sin(theta), cos(theta))
    }
}
