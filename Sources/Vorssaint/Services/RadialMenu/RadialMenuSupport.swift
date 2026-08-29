// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// Accent colors available for radial menu profiles.
enum RadialMenuColor: String, Codable, CaseIterable, Identifiable {
    case accent, blue, purple, pink, red, orange, yellow, green, mint, cyan, indigo, graphite

    var id: String { rawValue }

    func color(for scheme: ColorScheme) -> Color {
        switch self {
        case .accent: return .accentColor
        case .blue: return scheme == .light ? Color(red: 0.00, green: 0.48, blue: 1.00) : .blue
        case .purple: return scheme == .light ? Color(red: 0.58, green: 0.20, blue: 0.85) : .purple
        case .pink: return scheme == .light ? Color(red: 0.88, green: 0.16, blue: 0.45) : .pink
        case .red: return scheme == .light ? Color(red: 0.85, green: 0.18, blue: 0.18) : .red
        case .orange: return scheme == .light ? Color(red: 0.95, green: 0.45, blue: 0.00) : .orange
        case .yellow: return scheme == .light ? Color(red: 0.85, green: 0.65, blue: 0.00) : .yellow
        case .green: return scheme == .light ? Color(red: 0.18, green: 0.65, blue: 0.25) : .green
        case .mint: return scheme == .light ? Color(red: 0.00, green: 0.68, blue: 0.60) : .mint
        case .cyan: return scheme == .light ? Color(red: 0.15, green: 0.65, blue: 0.85) : .cyan
        case .indigo: return scheme == .light ? Color(red: 0.35, green: 0.35, blue: 0.85) : .indigo
        case .graphite: return scheme == .light ? Color(white: 0.40) : Color(white: 0.65)
        }
    }

    var baseColor: Color {
        switch self {
        case .accent: return .accentColor
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .cyan: return .cyan
        case .indigo: return .indigo
        case .graphite: return .gray
        }
    }

    func title(_ strings: RadialMenuFeatureStrings) -> String {
        switch self {
        case .accent: return strings.colorAccent
        case .blue: return strings.colorBlue
        case .purple: return strings.colorPurple
        case .pink: return strings.colorPink
        case .red: return strings.colorRed
        case .orange: return strings.colorOrange
        case .yellow: return strings.colorYellow
        case .green: return strings.colorGreen
        case .mint: return strings.colorMint
        case .cyan: return strings.colorCyan
        case .indigo: return strings.colorIndigo
        case .graphite: return strings.colorGraphite
        }
    }
}

/// A complete configuration of the radial menu wheel: its items, color theme,
/// keyboard shortcut, and mouse button trigger.
struct RadialMenuProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var color: RadialMenuColor = .accent
    var shortcut: String = ""
    var mouseButton: String = RadialMenuMouseTrigger.off.rawValue
    var items: [RadialMenuItem] = []

    func displayName(_ text: RadialMenuFeatureStrings) -> String {
        name.isEmpty ? text.presetGeneral : name
    }
}

extension RadialMenuProfile {
    private enum CodingKeys: String, CodingKey {
        case id, name, color, shortcut, mouseButton, items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
                  color: try container.decodeIfPresent(RadialMenuColor.self, forKey: .color) ?? .accent,
                  shortcut: try container.decodeIfPresent(String.self, forKey: .shortcut) ?? "",
                  mouseButton: try container.decodeIfPresent(String.self, forKey: .mouseButton) ?? RadialMenuMouseTrigger.off.rawValue,
                  items: try container.decodeIfPresent([FailableRadialMenuItem].self, forKey: .items)?
                      .compactMap(\.value) ?? [])
    }
}

private struct FailableRadialMenuProfile: Decodable {
    let value: RadialMenuProfile?

    init(from decoder: Decoder) throws {
        value = try? RadialMenuProfile(from: decoder)
    }
}

/// Curated starter presets when creating new profiles.
enum RadialMenuProfilePreset: String, CaseIterable, Identifiable {
    case general, media, tools, windowLayout, quickToggles, blank

    var id: String { rawValue }

    func title(_ strings: RadialMenuFeatureStrings) -> String {
        switch self {
        case .general: return strings.presetGeneral
        case .media: return strings.presetMedia
        case .tools: return strings.presetTools
        case .windowLayout: return strings.presetWindowLayout
        case .quickToggles: return strings.presetQuickToggles
        case .blank: return strings.presetBlank
        }
    }

    var defaultColor: RadialMenuColor {
        switch self {
        case .general: return .accent
        case .media: return .purple
        case .tools: return .cyan
        case .windowLayout: return .orange
        case .quickToggles: return .mint
        case .blank: return .graphite
        }
    }

    func makeItems() -> [RadialMenuItem] {
        switch self {
        case .general:
            return RadialMenuSupport.starterItems
        case .media:
            return [
                RadialMenuItem(kind: .media, payload: RadialMenuMediaKey.playPause.rawValue),
                RadialMenuItem(kind: .media, payload: RadialMenuMediaKey.nextTrack.rawValue),
                RadialMenuItem(kind: .media, payload: RadialMenuMediaKey.nowPlaying.rawValue),
                RadialMenuItem(kind: .media, payload: RadialMenuMediaKey.previousTrack.rawValue),
            ]
        case .tools:
            return [
                RadialMenuItem(kind: .tool, payload: RadialMenuTool.screenshot.rawValue),
                RadialMenuItem(kind: .tool, payload: RadialMenuTool.colorPicker.rawValue),
                RadialMenuItem(kind: .tool, payload: RadialMenuTool.screenOCR.rawValue),
                RadialMenuItem(kind: .tool, payload: RadialMenuTool.screenRecorder.rawValue),
                RadialMenuItem(kind: .tool, payload: RadialMenuTool.micMute.rawValue),
                RadialMenuItem(kind: .tool, payload: RadialMenuTool.scratchpad.rawValue),
            ]
        case .windowLayout:
            return [
                RadialMenuItem(kind: .windowLayout, payload: WindowLayoutAction.maximize.rawValue),
                RadialMenuItem(kind: .windowLayout, payload: WindowLayoutAction.rightHalf.rawValue),
                RadialMenuItem(kind: .windowLayout, payload: WindowLayoutAction.bottomHalf.rawValue),
                RadialMenuItem(kind: .windowLayout, payload: WindowLayoutAction.leftHalf.rawValue),
                RadialMenuItem(kind: .windowLayout, payload: WindowLayoutAction.topHalf.rawValue),
            ]
        case .quickToggles:
            return [
                RadialMenuItem(kind: .quickToggle, payload: RadialMenuQuickToggle.darkMode.rawValue),
                RadialMenuItem(kind: .quickToggle, payload: RadialMenuQuickToggle.desktopIcons.rawValue),
                RadialMenuItem(kind: .quickToggle, payload: RadialMenuQuickToggle.hiddenFiles.rawValue),
                RadialMenuItem(kind: .quickToggle, payload: RadialMenuQuickToggle.lockScreen.rawValue),
                RadialMenuItem(kind: .quickToggle, payload: RadialMenuQuickToggle.emptyTrash.rawValue),
            ]
        case .blank:
            return []
        }
    }

    func createProfile(name: String? = nil,
                       color: RadialMenuColor? = nil,
                       shortcut: String = "",
                       mouseButton: String = RadialMenuMouseTrigger.off.rawValue) -> RadialMenuProfile {
        RadialMenuProfile(id: UUID(),
                           name: name ?? "",
                           color: color ?? defaultColor,
                           shortcut: shortcut,
                           mouseButton: mouseButton,
                           items: makeItems())
    }
}

/// One action on the wheel. `payload` carries the target: an app or file path,
/// a link, tool, media or window-layout identifier, or a shortcut storage
/// value. Submenus keep their actions in `children`.
struct RadialMenuItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case app, file, url, shortcut, tool, quickToggle, windowLayout, media, submenu
    }

    var id = UUID()
    var kind = Kind.app
    var name = ""
    var symbolName = ""
    var payload = ""
    var customIconData: Data? = nil
    var children: [RadialMenuItem] = []

    var tool: RadialMenuTool? {
        kind == .tool ? RadialMenuTool(rawValue: payload) : nil
    }

    var mediaKey: RadialMenuMediaKey? {
        kind == .media ? RadialMenuMediaKey(rawValue: payload) : nil
    }

    var quickToggle: RadialMenuQuickToggle? {
        kind == .quickToggle ? RadialMenuQuickToggle(rawValue: payload) : nil
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
        case .quickToggle: return quickToggle?.symbolName ?? "togglepower"
        case .windowLayout: return windowLayoutAction?.symbolName ?? AppFeature.windowLayout.symbolName
        case .media:
            switch mediaKey {
            case .previousTrack: return "backward.fill"
            case .nextTrack: return "forward.fill"
            case .nowPlaying: return "music.note"
            default: return "playpause.fill"
            }
        case .submenu: return "ellipsis.circle"
        }
    }

    var effectiveSymbolName: String {
        symbolName.isEmpty ? defaultSymbolName : symbolName
    }
}

/// Quick toggle actions a slice can trigger. Raw values persist inside the
/// items blob; never rename them.
enum RadialMenuQuickToggle: String, Codable, CaseIterable, Identifiable {
    case darkMode, emptyTrash, ejectDisks, hiddenFiles, desktopIcons,
         lockScreen, displayOff, screenSaver

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .darkMode: return "moon.fill"
        case .emptyTrash: return "trash"
        case .ejectDisks: return "eject.fill"
        case .hiddenFiles: return "eye"
        case .desktopIcons: return "desktopcomputer"
        case .lockScreen: return "lock.fill"
        case .displayOff: return "display"
        case .screenSaver: return "sparkles.tv"
        }
    }
}

// The custom decoder lives in an extension so the memberwise initializer
// stays synthesized. It tolerates blobs written by newer versions: absent
// fields fall back to their defaults, and an unknown kind fails just this
// item, which the lossy array decode below then drops instead of losing the
// whole menu.
extension RadialMenuItem {
    private enum CodingKeys: String, CodingKey {
        case id, kind, name, symbolName, payload, customIconData, children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  kind: try container.decode(Kind.self, forKey: .kind),
                  name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
                  symbolName: try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "",
                  payload: try container.decodeIfPresent(String.self, forKey: .payload) ?? "",
                  customIconData: try container.decodeIfPresent(Data.self, forKey: .customIconData),
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
    case screenshot, screenRecorder, colorPicker, screenOCR, micMute, clipboardHistory, quickLauncher,
         cameraPreview, scratchpad, shelf, cleaner, uninstaller, appUpdates, cleaningMode, keepAwake

    var id: String { rawValue }

    var feature: AppFeature {
        switch self {
        case .screenshot: return .screenshot
        case .screenRecorder: return .screenRecorder
        case .colorPicker: return .colorPicker
        case .screenOCR: return .screenOCR
        case .micMute: return .micMute
        case .clipboardHistory: return .clipboardHistory
        case .quickLauncher: return .quickLauncher
        case .cameraPreview: return .cameraPreview
        case .scratchpad: return .scratchpad
        case .shelf: return .shelf
        case .cleaner: return .cleaner
        case .uninstaller: return .uninstaller
        case .appUpdates: return .appUpdates
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

/// The optional second summoner: any extra mouse button. The original raw
/// values stay stable for existing settings; newer buttons use their
/// CoreGraphics number, which follows USB order from 3 through 31.
enum RadialMenuMouseTrigger: Equatable, Identifiable {
    case off
    case button(Int64)

    static let back = button(MouseButtonShortcutSupport.backButtonNumber)
    static let forward = button(MouseButtonShortcutSupport.forwardButtonNumber)

    var id: String { rawValue }

    var rawValue: String {
        switch self {
        case .off: return "off"
        case .button(let number):
            if number == MouseButtonShortcutSupport.backButtonNumber { return "back" }
            if number == MouseButtonShortcutSupport.forwardButtonNumber { return "forward" }
            return "button:\(number)"
        }
    }

    var buttonNumber: Int64? {
        guard case .button(let number) = self else { return nil }
        return number
    }

    static func sanitized(_ raw: String?) -> RadialMenuMouseTrigger {
        switch raw {
        case "back": return .back
        case "forward": return .forward
        case let value?:
            guard value.hasPrefix("button:"),
                  let number = Int64(value.dropFirst("button:".count)),
                  MouseButtonShortcutSupport.buttonRange.contains(number) else { return .off }
            return .button(number)
        default: return .off
        }
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
    /// The Super Key is a virtual modifier: it decorates the summoning key but
    /// never appears in the system's current physical-modifier state.
    static func shortcutIsStillHeld(modifiersHeld: Bool, superKeyHeld: Bool) -> Bool {
        modifiersHeld || superKeyHeld
    }

    /// Whether the radial menu currently owns this extra button as its
    /// summoner. Mouse navigation asks this from its own tap and lets a
    /// claimed button through; pure defaults reads, so asking never wakes
    /// the radial menu service.
    static func claimsMouseButton(_ button: Int64) -> Bool {
        claimsMouseButton(button, defaults: .standard)
    }

    static func claimsMouseButton(_ button: Int64, defaults: UserDefaults) -> Bool {
        guard defaults.bool(forKey: AppFeature.radialMenu.availabilityKey),
              defaults.bool(forKey: DefaultsKey.radialMenuEnabled) else { return false }
        let profiles = decodeProfiles(defaults.data(forKey: DefaultsKey.radialMenuProfiles), defaults: defaults)
        return profiles.contains {
            RadialMenuMouseTrigger.sanitized($0.mouseButton).buttonNumber == button
        }
    }
}

/// Media keys a slice can press, mapped to the aux-button codes the physical
/// keys post (NX_KEYTYPE_PLAY / FAST / REWIND).
enum RadialMenuMediaKey: String, Codable, CaseIterable, Identifiable {
    case playPause, previousTrack, nextTrack, nowPlaying

    var id: String { rawValue }

    /// Now Playing opens Vorssaint's metadata card rather than posting a key.
    var auxKeyType: Int32? {
        switch self {
        case .playPause: return 16
        case .previousTrack: return 20
        case .nextTrack: return 19
        case .nowPlaying: return nil
        }
    }
}

struct RadialNowPlayingSnapshot: Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let appBundleIdentifier: String?
    let appPID: Int32?

    var radialLabel: String? {
        let parts = [title, artist].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

enum RadialNowPlayingState: Equatable {
    case loading
    case nothingPlaying
    case playing(RadialNowPlayingSnapshot)
}

enum RadialNowPlayingSupport {
    static let titleKey = "kMRMediaRemoteNowPlayingInfoTitle"
    static let artistKey = "kMRMediaRemoteNowPlayingInfoArtist"
    static let albumKey = "kMRMediaRemoteNowPlayingInfoAlbum"
    static let artworkDataKey = "kMRMediaRemoteNowPlayingInfoArtworkData"
    static let playbackRateKey = "kMRMediaRemoteNowPlayingInfoPlaybackRate"

    private static let forbiddenScalars = CharacterSet.controlCharacters.union(.newlines)
    private static let maximumArtworkBytes = 12 * 1_024 * 1_024

    static func playbackIsActive(remoteIsPlaying: Bool?, info: [String: Any]) -> Bool {
        if let remoteIsPlaying { return remoteIsPlaying }
        return (info[playbackRateKey] as? NSNumber)?.doubleValue ?? 0 > 0
    }

    static func snapshot(info: [String: Any],
                         isPlaying: Bool,
                         appBundleIdentifier: String?,
                         appPID: Int32) -> RadialNowPlayingSnapshot? {
        guard isPlaying else { return nil }
        let title = sanitizedText(info[titleKey])
        let artist = sanitizedText(info[artistKey])
        let album = sanitizedText(info[albumKey])
        let bundleIdentifier = sanitizedBundleIdentifier(appBundleIdentifier)
        let pid = appPID > 0 ? appPID : nil
        let artworkData = sanitizedArtworkData(info[artworkDataKey])
        guard title != nil || bundleIdentifier != nil || pid != nil else { return nil }
        return RadialNowPlayingSnapshot(title: title,
                                        artist: artist,
                                        album: album,
                                        artworkData: artworkData,
                                        appBundleIdentifier: bundleIdentifier,
                                        appPID: pid)
    }

    private static func sanitizedText(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let clean = String(String.UnicodeScalarView(
            trimmed.unicodeScalars.filter { !forbiddenScalars.contains($0) }))
        return clean.isEmpty ? nil : String(clean.prefix(300))
    }

    private static func sanitizedBundleIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 255,
              !trimmed.unicodeScalars.contains(where: { forbiddenScalars.contains($0) })
        else { return nil }
        return trimmed
    }

    private static func sanitizedArtworkData(_ value: Any?) -> Data? {
        guard let data = value as? Data, !data.isEmpty, data.count <= maximumArtworkBytes else {
            return nil
        }
        return data
    }
}

enum RadialMenuSupport {
    static let maxItemsPerWheel = 12
    /// Root plus one submenu level. Deeper nesting turns the wheel into a maze.
    static let maxDepth = 2

    /// Curated built-in symbols for the editor. The picker filters this list
    /// at runtime so older supported macOS releases only show symbols they own.
    static let symbolNames = [
        "star.fill", "heart.fill", "bolt.fill", "flame.fill", "sparkles",
        "folder.fill", "doc.fill", "tray.full.fill", "terminal.fill", "globe",
        "envelope.fill", "message.fill", "music.note", "headphones", "camera.fill",
        "photo.fill", "video.fill", "gamecontroller.fill", "calendar", "clock.fill",
        "house.fill", "cart.fill", "hammer.fill", "paintbrush.fill", "book.fill",
        "keyboard", "magnifyingglass", "airplane",
        "checkmark.circle.fill", "xmark.circle.fill", "plus.circle.fill", "minus.circle.fill",
        "exclamationmark.triangle.fill", "questionmark.circle.fill", "info.circle.fill",
        "lock.fill", "lock.open.fill", "key.fill", "person.fill", "person.2.fill",
        "bell.fill", "flag.fill", "bookmark.fill", "tag.fill",
        "paperclip", "link", "scissors", "doc.on.clipboard",
        "square.and.arrow.up", "square.and.arrow.down", "trash.fill", "archivebox.fill",
        "externaldrive.fill", "internaldrive.fill", "display", "desktopcomputer",
        "laptopcomputer", "iphone", "ipad", "applewatch",
        "wifi", "network", "antenna.radiowaves.left.and.right",
        "speaker.wave.2.fill", "mic.fill", "waveform",
        "play.fill", "pause.fill", "stop.fill", "backward.fill", "forward.fill",
        "shuffle", "repeat",
        "sun.max.fill", "moon.fill", "lightbulb.fill", "battery.100", "power",
        "eye.fill", "eye.slash.fill", "location.fill", "map.fill",
        "paperplane.fill", "bubble.left.fill", "phone.fill",
        "gearshape.fill", "slider.horizontal.3", "switch.2", "command",
        "printer.fill", "textformat", "number",
    ]

    /// Whether the target can actually run for this kind. The editor blocks
    /// saving what fails here, and `sanitized` drops it, so the two can never
    /// disagree about what belongs on a wheel.
    static func isValidPayload(_ item: RadialMenuItem) -> Bool {
        switch item.kind {
        case .app, .file: return !item.payload.isEmpty
        case .url: return normalizedURL(item.payload) != nil
        case .shortcut: return GlobalShortcut(storageValue: item.payload) != nil
        case .tool: return item.tool != nil
        case .quickToggle: return item.quickToggle != nil
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
            if let customData = item.customIconData {
                if customData.count > RadialMenuFaviconFetcher.maxStoredIconBytes || NSImage(data: customData) == nil {
                    item.customIconData = nil
                }
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
            case .shortcut, .windowLayout: return true
            case .media: return item.mediaKey?.auxKeyType != nil
            case .submenu: return needsAccessibility(item.children)
            default: return false
            }
        }
    }

    /// True when any profile, at any level, controls keyboard input or windows,
    /// or claims a mouse button, and therefore needs the Accessibility permission.
    static func needsAccessibility(_ profiles: [RadialMenuProfile]) -> Bool {
        profiles.contains { profile in
            RadialMenuMouseTrigger.sanitized(profile.mouseButton) != .off
                || needsAccessibility(profile.items)
        }
    }

    /// Decodes profiles from JSON blob. If missing, checks for legacy
    /// items / shortcut / mouse button to migrate existing users, or creates
    /// the starter profile.
    static func decodeProfiles(_ data: Data?, defaults: UserDefaults = .standard) -> [RadialMenuProfile] {
        if let data, let decoded = try? JSONDecoder().decode([FailableRadialMenuProfile].self, from: data) {
            let sanitized = sanitizedProfiles(decoded.compactMap(\.value))
            if !sanitized.isEmpty { return sanitized }
        }
        // Legacy items migration
        let legacyItemsData = defaults.data(forKey: DefaultsKey.radialMenuItems)
        let legacyShortcut = defaults.string(forKey: DefaultsKey.radialMenuShortcut)
            ?? GlobalShortcut.radialMenuDefault.storageValue
        let legacyMouseButton = defaults.string(forKey: DefaultsKey.radialMenuMouseButton)
            ?? RadialMenuMouseTrigger.off.rawValue

        let items = decode(legacyItemsData)
        let initialProfile = RadialMenuProfile(
            id: UUID(),
            name: "",
            color: .accent,
            shortcut: legacyShortcut,
            mouseButton: legacyMouseButton,
            items: items
        )
        return [initialProfile]
    }

    static func encodeProfiles(_ profiles: [RadialMenuProfile]) -> Data? {
        try? JSONEncoder().encode(sanitizedProfiles(profiles))
    }

    static func sanitizedProfiles(_ profiles: [RadialMenuProfile]) -> [RadialMenuProfile] {
        var seenIDs = Set<UUID>()
        var result: [RadialMenuProfile] = []
        for var profile in profiles {
            guard seenIDs.insert(profile.id).inserted else { continue }
            profile.name = String(profile.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
            profile.items = sanitized(profile.items)
            profile.shortcut = profile.shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
            if !profile.shortcut.isEmpty && GlobalShortcut(storageValue: profile.shortcut) == nil {
                profile.shortcut = ""
            }
            profile.mouseButton = RadialMenuMouseTrigger.sanitized(profile.mouseButton).rawValue
            result.append(profile)
        }
        if result.isEmpty {
            result.append(RadialMenuProfilePreset.general.createProfile(shortcut: GlobalShortcut.radialMenuDefault.storageValue))
        }
        return result
    }

    static func containsNowPlaying(_ items: [RadialMenuItem]) -> Bool {
        items.contains { item in
            item.mediaKey == .nowPlaying
                || (item.kind == .submenu && containsNowPlaying(item.children))
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

/// On-demand fetcher for website favicons, executed exclusively when explicitly
/// requested by the user in the Settings editor.
enum RadialMenuFaviconFetcher {
    /// Max allowable icon data storage: 64KB
    static let maxStoredIconBytes = 65536
    /// A favicon should be tiny. Stop the transfer itself at this bound so a
    /// hostile response cannot be buffered into unbounded memory first.
    static let maxDownloadBytes = 2 * 1_024 * 1_024
    static let maxSourceDimension = 4_096
    static let maxSourcePixels = 16_777_216

    /// Fetches the favicon for a URL string on-demand.
    /// Runs on a background task, calls completion on main queue.
    static func fetchFavicon(for rawURL: String, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let url = faviconURL(for: rawURL) else {
            DispatchQueue.main.async {
                completion(.failure(FaviconError.invalidURL))
            }
            return
        }
        FaviconDownload(url: url, byteLimit: maxDownloadBytes) { result in
            DispatchQueue.main.async {
                guard case let .success(data) = result,
                      sourceDimensionsAreSafe(data),
                      let image = NSImage(data: data),
                      image.size.width > 0, image.size.height > 0,
                      let pngData = scaledPNGData(from: image)
                else {
                    completion(.failure(FaviconError.notFound))
                    return
                }
                completion(.success(pngData))
            }
        }.start()
    }

    static func faviconURL(for rawURL: String) -> URL? {
        guard let normalized = RadialMenuSupport.normalizedURL(rawURL),
              let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.user = nil
        components.password = nil
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func sourceDimensionsAreSafe(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0,
              width <= maxSourceDimension, height <= maxSourceDimension,
              width <= maxSourcePixels / height
        else { return false }
        return true
    }

    static func scaledPNGData(from image: NSImage, targetSize: CGFloat = 64) -> Data? {
        let size = NSSize(width: targetSize, height: targetSize)
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        newImage.unlockFocus()

        guard let tiffData = newImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return png.count <= maxStoredIconBytes ? png : nil
    }

    enum FaviconError: Error {
        case invalidURL
        case notFound
    }

    private struct Origin: Equatable {
        let scheme: String
        let host: String
        let port: Int

        init?(_ url: URL) {
            guard let scheme = url.scheme?.lowercased(),
                  let host = url.host?.lowercased() else { return nil }
            self.scheme = scheme
            self.host = host
            port = url.port ?? (scheme == "https" ? 443 : 80)
        }
    }

    private final class FaviconDownload: NSObject, URLSessionDataDelegate {
        private let url: URL
        private let byteLimit: Int
        private let completion: (Result<Data, Error>) -> Void
        private let origin: Origin
        private var session: URLSession?
        private var data = Data()
        private var finished = false

        init(url: URL, byteLimit: Int, completion: @escaping (Result<Data, Error>) -> Void) {
            self.url = url
            self.byteLimit = byteLimit
            self.completion = completion
            origin = Origin(url)!
        }

        func start() {
            var request = URLRequest(url: url,
                                     cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: 5)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 5
            let session = URLSession(configuration: configuration,
                                     delegate: self,
                                     delegateQueue: nil)
            self.session = session
            session.dataTask(with: request).resume()
        }

        func urlSession(_ session: URLSession,
                        dataTask: URLSessionDataTask,
                        didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  response.expectedContentLength <= 0
                    || response.expectedContentLength <= Int64(byteLimit)
            else {
                completionHandler(.cancel)
                finish(.failure(FaviconError.notFound))
                return
            }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession,
                        dataTask: URLSessionDataTask,
                        didReceive chunk: Data) {
            guard data.count + chunk.count <= byteLimit else {
                dataTask.cancel()
                finish(.failure(FaviconError.notFound))
                return
            }
            data.append(chunk)
        }

        func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                        willPerformHTTPRedirection newResponse: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            guard let redirectURL = request.url,
                  Origin(redirectURL) == origin else {
                completionHandler(nil)
                return
            }
            completionHandler(request)
        }

        func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                        didCompleteWithError error: Error?) {
            if let error {
                finish(.failure(error))
            } else {
                finish(.success(data))
            }
        }

        private func finish(_ result: Result<Data, Error>) {
            guard !finished else { return }
            finished = true
            session?.finishTasksAndInvalidate()
            session = nil
            completion(result)
        }
    }
}
