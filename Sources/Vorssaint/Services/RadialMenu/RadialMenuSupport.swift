// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

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
/// keyboard shortcut, mouse button and trackpad tap triggers.
struct RadialMenuProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var color: RadialMenuColor = .accent
    var shortcut: String = ""
    var mouseButton: String = RadialMenuMouseTrigger.off.rawValue
    var items: [RadialMenuItem] = []
    /// The starter set this wheel was created from, so restoring its actions
    /// brings back that one. Kept as the raw value because it is persisted;
    /// nil for a wheel whose origin is not known.
    var preset: String?
    /// A four-finger tap on the trackpad opens this wheel. Settings keeps it
    /// on one profile at most; the first one wins otherwise.
    var trackpadTap = false

    func displayName(_ text: RadialMenuFeatureStrings) -> String {
        name.isEmpty ? text.presetGeneral : name
    }

    /// The copy Duplicate adds. The shortcut, the mouse button and the
    /// trackpad tap each open one wheel, so the copy starts without them and
    /// leaves the original's.
    func duplicate(named name: String) -> RadialMenuProfile {
        var copy = self
        copy.id = UUID()
        copy.name = name
        copy.shortcut = ""
        copy.mouseButton = RadialMenuMouseTrigger.off.rawValue
        copy.trackpadTap = false
        return copy
    }
}

extension RadialMenuProfile {
    private enum CodingKeys: String, CodingKey {
        case id, name, color, shortcut, mouseButton, items, preset, trackpadTap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  name: try container.decodeIfPresent(String.self, forKey: .name) ?? "",
                  color: try container.decodeIfPresent(RadialMenuColor.self, forKey: .color) ?? .accent,
                  shortcut: try container.decodeIfPresent(String.self, forKey: .shortcut) ?? "",
                  mouseButton: try container.decodeIfPresent(String.self, forKey: .mouseButton) ?? RadialMenuMouseTrigger.off.rawValue,
                  items: try container.decodeIfPresent([FailableRadialMenuItem].self, forKey: .items)?
                      .compactMap(\.value) ?? [],
                  preset: try container.decodeIfPresent(String.self, forKey: .preset),
                  trackpadTap: try container.decodeIfPresent(Bool.self, forKey: .trackpadTap) ?? false)
    }
}

private struct FailableRadialMenuProfile: Decodable {
    let value: RadialMenuProfile?

    init(from decoder: Decoder) throws {
        value = try? RadialMenuProfile(from: decoder)
    }
}

/// A profile read for its mouse button and trackpad tap alone: the questions
/// the event taps and the Features hub ask, answered without walking the
/// items or decoding the icons they carry.
private struct RadialMenuProfileTriggers: Decodable {
    let mouseButton: String?
    let trackpadTap: Bool

    private enum CodingKeys: String, CodingKey { case mouseButton, trackpadTap }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        mouseButton = (try? container?.decodeIfPresent(String.self, forKey: .mouseButton)) ?? nil
        trackpadTap = (try? container?.decodeIfPresent(Bool.self, forKey: .trackpadTap)) ?? false
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
                           items: makeItems(),
                           preset: rawValue)
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

    /// What resting on this slice shows beside the wheel, if anything. The
    /// slice itself still runs as before; the peek only adds a way in.
    var peek: RadialMenuPeek? {
        switch kind {
        case .tool: return tool == .clipboardHistory ? .clipboardHistory : nil
        // Any file slice may be a folder; only reading it can tell, so a
        // plain file's peek finds nothing to list and never opens.
        case .file: return .folder(path: payload)
        default: return nil
        }
    }
}

/// Live content a slice can show in a panel beside the wheel while the
/// pointer rests on it.
enum RadialMenuPeek: Equatable {
    case clipboardHistory
    /// What a folder slice holds, to open, pick, copy or drag out.
    case folder(path: String)
}

/// One thing inside a folder the peek lists.
struct RadialFolderEntry: Equatable, Identifiable {
    let url: URL
    let name: String
    /// A folder the list can go into. Packages, such as apps, are files.
    let isFolder: Bool
    /// When it arrived in the folder, Finder's Date Added, or else when it
    /// last changed.
    let date: Date
    let size: Int?
    let contentType: UTType?
    let typeDescription: String?

    var id: URL { url }
}

/// Reads one folder for the peek. Only ever reads: nothing here moves,
/// renames or deletes, and hidden files stay hidden.
enum RadialFolderListing {
    enum Result: Equatable {
        case entries([RadialFolderEntry])
        /// The path is a file, a package or gone: there is no list to show.
        case notAFolder
        /// A folder the app may not read, such as Downloads before the
        /// person allowed it.
        case unreadable
    }

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .localizedNameKey, .addedToDirectoryDateKey,
        .contentModificationDateKey, .fileSizeKey, .contentTypeKey, .localizedTypeDescriptionKey,
    ]

    static func read(_ folder: URL, limit: Int, fileManager: FileManager = .default) -> Result {
        let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        guard values?.isDirectory == true, values?.isPackage != true else { return .notAFolder }
        guard let urls = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles]) else {
            return .unreadable
        }
        return .entries(Array(sorted(urls.compactMap(entry(for:))).prefix(limit)))
    }

    static func entry(for url: URL) -> RadialFolderEntry? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        let isFolder = values.isDirectory == true && values.isPackage != true
        return RadialFolderEntry(url: url,
                                 name: values.localizedName ?? url.lastPathComponent,
                                 isFolder: isFolder,
                                 date: values.addedToDirectoryDate ?? values.contentModificationDate ?? .distantPast,
                                 size: isFolder ? nil : values.fileSize,
                                 contentType: values.contentType,
                                 typeDescription: values.localizedTypeDescription)
    }

    /// Folders first, then the newest arrivals, so the download that just
    /// landed is at the top; ties read in Finder's name order.
    static func sorted(_ entries: [RadialFolderEntry]) -> [RadialFolderEntry] {
        entries.sorted { first, second in
            if first.isFolder != second.isFolder { return first.isFolder }
            if first.date != second.date { return first.date > second.date }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }
}

/// Where the folder peek is, and the files picked on the way. Picks are kept
/// across folders, like a basket, until the peek closes.
struct RadialFolderBrowser: Equatable {
    struct Step: Equatable {
        let url: URL
        let name: String
    }

    let root: Step
    /// The folders gone into below the root, outermost first.
    var trail: [Step] = []
    /// Picked files, in the order they were picked.
    private(set) var basket: [URL] = []

    static let basketLimit = 100

    init(root: URL, name: String) {
        self.root = Step(url: root, name: name)
    }

    var current: URL { (trail.last ?? root).url }
    var canGoUp: Bool { !trail.isEmpty }
    /// The header's path, from the folder on the wheel down.
    var pathNames: [String] { ([root] + trail).map(\.name) }

    mutating func enter(_ entry: RadialFolderEntry) {
        guard entry.isFolder else { return }
        trail.append(Step(url: entry.url, name: entry.name))
    }

    mutating func goUp() {
        if !trail.isEmpty { trail.removeLast() }
    }

    func isPicked(_ url: URL) -> Bool {
        basket.contains(url)
    }

    mutating func toggle(_ url: URL) {
        if let index = basket.firstIndex(of: url) {
            basket.remove(at: index)
        } else if basket.count < Self.basketLimit {
            basket.append(url)
        }
    }

    mutating func clearBasket() {
        basket.removeAll()
    }

    /// What a drag takes, as in Finder: grabbing a picked file takes every
    /// picked file, grabbing any other takes that one alone.
    func dragged(grabbing url: URL) -> [URL] {
        basket.contains(url) ? basket : [url]
    }

    /// What ⌘C copies: the picked files, or the row the pointer is on when
    /// nothing is picked.
    func copied(highlighted: URL?) -> [URL] {
        if !basket.isEmpty { return basket }
        return highlighted.map { [$0] } ?? []
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
    /// summoner. Mouse navigation and the mouse button shortcuts both ask
    /// this from inside their own tap callbacks, on every event of a
    /// side-button gesture, so it reads defaults and the stored buttons only:
    /// never the items, and never `decodeProfiles`, which decodes their
    /// custom icons. Asking never wakes the radial menu service.
    static func claimsMouseButton(_ button: Int64) -> Bool {
        claimsMouseButton(button, defaults: .standard)
    }

    static func claimsMouseButton(_ button: Int64, defaults: UserDefaults) -> Bool {
        guard defaults.bool(forKey: AppFeature.radialMenu.availabilityKey),
              defaults.bool(forKey: DefaultsKey.radialMenuEnabled) else { return false }
        return claimedMouseButtons(defaults.data(forKey: DefaultsKey.radialMenuProfiles),
                                   defaults: defaults).contains(button)
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
    /// The one artwork cap. The adapter (`Sources/NowPlayingAdapter`) drops
    /// artwork above it before encoding, and the bridge's pipe cap is
    /// `maximumAdapterReplyBytes`, sized so the base64 line (4/3 of the bytes,
    /// so 16 MB) plus the other keys fits.
    static let maximumArtworkBytes = 12 * 1_024 * 1_024
    static let maximumAdapterReplyBytes = maximumArtworkBytes / 3 * 4 + 1_024 * 1_024

    static func playbackIsActive(remoteIsPlaying: Bool?, info: [String: Any]) -> Bool {
        if let remoteIsPlaying { return remoteIsPlaying }
        return (info[playbackRateKey] as? NSNumber)?.doubleValue ?? 0 > 0
    }

    /// One reply from the Now Playing adapter (`Resources/now-playing.pl`):
    /// the MediaRemote metadata keys it forwards, plus the owning app and the
    /// remote's own playing flag, in the shape `snapshot(info:...)` reads.
    struct AdapterReply {
        let info: [String: Any]
        let pid: Int32
        let displayID: String?
        let isPlaying: Bool?
    }

    /// Parses the adapter's JSON line, the last non-blank line of the run's
    /// output: stderr shares the pipe, so a perl warning (a locale it cannot
    /// set, say) can precede it. Artwork arrives base64-encoded under
    /// `artworkBase64` and is handed on as `artworkDataKey` bytes. An `error`
    /// key, a non-object or unreadable bytes read as no reply.
    static func adapterReply(from data: Data) -> AdapterReply? {
        let blank: Set<UInt8> = [0x20, 0x09, 0x0D]
        guard let line = data.split(separator: 0x0A).last(where: { $0.contains { !blank.contains($0) } }),
              let object = try? JSONSerialization.jsonObject(with: line),
              let fields = object as? [String: Any],
              fields["error"] == nil else { return nil }
        var info: [String: Any] = [:]
        for key in [titleKey, artistKey, albumKey] {
            if let value = fields[key] as? String { info[key] = value }
        }
        for key in [playbackRateKey, "kMRMediaRemoteNowPlayingInfoDuration",
                    "kMRMediaRemoteNowPlayingInfoElapsedTime"] {
            if let value = fields[key] as? NSNumber { info[key] = value }
        }
        if fields["artworkUnchanged"] as? Bool == true { info["artworkUnchanged"] = true }
        for key in ["canSeek", "canSkipNext", "canSkipPrevious"] {
            if let value = fields[key] as? Bool { info[key] = value }
        }
        if let identifier = fields["itemIdentifier"] as? String, !identifier.isEmpty,
           identifier.utf8.count <= 512, !identifier.contains("\0") { info["itemIdentifier"] = identifier }
        if let artwork = fields["artworkBase64"] as? String,
           let bytes = Data(base64Encoded: artwork), !bytes.isEmpty {
            info[artworkDataKey] = bytes
        }
        return AdapterReply(info: info,
                            pid: (fields["pid"] as? NSNumber)?.int32Value ?? 0,
                            displayID: fields["displayID"] as? String,
                            isPlaying: fields["isPlaying"] as? Bool)
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
    /// Pointer events that can update a visible wheel's highlighted slice.
    /// AppKit reports movement with a held extra mouse button as
    /// `otherMouseDragged`, rather than as a plain mouse move.
    static let sessionMoveMask: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDragged, .otherMouseDragged,
    ]

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
    /// or claims a mouse button or the trackpad tap, and therefore needs the
    /// Accessibility permission.
    static func needsAccessibility(_ profiles: [RadialMenuProfile]) -> Bool {
        profiles.contains { profile in
            RadialMenuMouseTrigger.sanitized(profile.mouseButton) != .off
                || profile.trackpadTap
                || needsAccessibility(profile.items)
        }
    }

    /// Whether anything opens this wheel. The profile picked in Settings is
    /// only the one being edited, so a wheel without a shortcut, a mouse
    /// button or the trackpad tap never opens outside of Try it.
    static func hasTrigger(_ profile: RadialMenuProfile) -> Bool {
        GlobalShortcut(storageValue: profile.shortcut) != nil
            || RadialMenuMouseTrigger.sanitized(profile.mouseButton) != .off
            || profile.trackpadTap
    }

    /// Gives one wheel a mouse button. A button only ever opens the first
    /// wheel that has it, so claiming it here releases it from the others,
    /// the way the trackpad tap moves.
    static func assigning(mouseButton raw: String, to profileID: UUID,
                          in profiles: [RadialMenuProfile]) -> [RadialMenuProfile] {
        let button = RadialMenuMouseTrigger.sanitized(raw).buttonNumber
        return profiles.map { profile in
            var profile = profile
            if profile.id == profileID {
                profile.mouseButton = raw
            } else if let button,
                      RadialMenuMouseTrigger.sanitized(profile.mouseButton).buttonNumber == button {
                profile.mouseButton = RadialMenuMouseTrigger.off.rawValue
            }
            return profile
        }
    }

    /// The mouse buttons the wheel is bound to right now, decoded from the
    /// stored buttons alone.
    ///
    /// This is the question the event taps ask, so it must stay cheap:
    /// `decodeProfiles` answers it too, but only by paying for every item on
    /// every wheel. The legacy fallback is the same one it migrates from, so
    /// the two answers cannot drift apart for a user who has not saved a
    /// profile yet.
    static func claimedMouseButtons(_ data: Data?, defaults: UserDefaults = .standard) -> [Int64] {
        if let data, let decoded = try? JSONDecoder().decode([RadialMenuProfileTriggers].self, from: data) {
            return decoded.compactMap { RadialMenuMouseTrigger.sanitized($0.mouseButton).buttonNumber }
        }
        let legacy = RadialMenuMouseTrigger.sanitized(
            defaults.string(forKey: DefaultsKey.radialMenuMouseButton))
        return legacy.buttonNumber.map { [$0] } ?? []
    }

    /// Whether any wheel opens from a mouse button or the trackpad tap, the
    /// triggers that keep an input tap running while the menu is on. Read
    /// like `claimedMouseButtons`, from the stored triggers alone and with
    /// the same legacy fallback, so the Features hub never decodes icons.
    static func opensFromMouseOrTrackpad(_ data: Data?, defaults: UserDefaults = .standard) -> Bool {
        if let data, let decoded = try? JSONDecoder().decode([RadialMenuProfileTriggers].self, from: data) {
            return decoded.contains {
                RadialMenuMouseTrigger.sanitized($0.mouseButton) != .off || $0.trackpadTap
            }
        }
        return RadialMenuMouseTrigger.sanitized(
            defaults.string(forKey: DefaultsKey.radialMenuMouseButton)) != .off
    }

    /// Decodes profiles from JSON blob. If missing, checks for legacy
    /// items / shortcut / mouse button to migrate existing users, or creates
    /// the starter profile.
    ///
    /// Walks every item on every wheel and decodes each custom icon (up to
    /// `RadialMenuFaviconFetcher.maxStoredIconBytes` of PNG apiece), so it
    /// belongs to settings and session start, never to an event-tap callback.
    /// A callback that only needs the summoner wants `claimedMouseButtons`.
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
            items: items,
            // The single wheel that came before profiles started from the
            // general starter set, whatever it was edited into since.
            preset: RadialMenuProfilePreset.general.rawValue
        )
        return [initialProfile]
    }

    /// The combinations the wheels answer to, read the way `RadialMenuService`
    /// registers them. Before any profile is saved that is the shortcut the
    /// first wheel migrates from, and a wheel without one claims nothing.
    static func profileShortcuts(defaults: UserDefaults = .standard) -> [GlobalShortcut] {
        decodeProfiles(defaults.data(forKey: DefaultsKey.radialMenuProfiles), defaults: defaults)
            .compactMap { GlobalShortcut(storageValue: $0.shortcut) }
    }

    /// The other wheel that already opens on a combination. Two wheels on one
    /// combination would leave one of them dead, so Settings refuses the second.
    static func profile(using shortcut: GlobalShortcut, in profiles: [RadialMenuProfile],
                        excluding profileID: UUID) -> RadialMenuProfile? {
        profiles.first { $0.id != profileID && GlobalShortcut(storageValue: $0.shortcut) == shortcut }
    }

    static func encodeProfiles(_ profiles: [RadialMenuProfile]) -> Data? {
        try? JSONEncoder().encode(sanitizedProfiles(profiles))
    }

    static func sanitizedProfiles(_ profiles: [RadialMenuProfile]) -> [RadialMenuProfile] {
        var seenIDs = Set<UUID>()
        var seenButtons = Set<Int64>()
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
            // A button opens only the first wheel that has it, so a later
            // wheel saved with the same one (Duplicate used to keep it) reads
            // as off, which is what it always was.
            if let button = RadialMenuMouseTrigger.sanitized(profile.mouseButton).buttonNumber,
               !seenButtons.insert(button).inserted {
                profile.mouseButton = RadialMenuMouseTrigger.off.rawValue
            }
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

/// The peek's size and place, points, in screen coordinates (y grows
/// upward). Every row has one fixed height, so the service can tell which
/// row the pointer is on from the panel's frame alone, without asking the
/// view.
enum RadialMenuPeekLayout {
    static let width: CGFloat = 340
    static let padding: CGFloat = 8
    static let headerHeight: CGFloat = 28
    static let rowHeight: CGFloat = 40
    /// Under the rows, the whole of the entry the pointer is on, so a long
    /// text or a picture can be read before it is pasted.
    static let previewHeight: CGFloat = 116
    /// Rows on screen at once; the rest scroll by whole rows, so the layout
    /// alone still says which entry is under the pointer.
    static let visibleRows = 7
    /// Entries listed at most. The history window keeps the full history.
    static let maxEntries = 50
    /// Things listed at most in one folder, the newest first.
    static let maxFolderEntries = 200
    /// The folder list's bar of picked files, between the rows and the
    /// preview.
    static let basketHeight: CGFloat = 34
    /// The header's back arrow and the bar's clear button, measured from
    /// their own ends.
    static let backButtonWidth: CGFloat = 34
    static let clearButtonWidth: CGFloat = 30
    /// How far the pointer travels with the button down before a press on
    /// the folder list becomes a drag, the same as on the Shelf.
    static let dragThreshold: CGFloat = 4
    /// Between the wheel's rim and the panel.
    static let gap: CGFloat = 14
    static let screenMargin: CGFloat = 12
    /// How long the pointer rests on a slice before its peek opens: long
    /// enough that a flick across the wheel never opens one on the way past.
    static let dwell: TimeInterval = 0.35

    /// The folder list always takes its full height, with or without a
    /// basket, so the panel holds still while it moves between folders.
    static func height(rowCount: Int, basket: Bool = false) -> CGFloat {
        padding * 2 + headerHeight + previewHeight + (basket ? basketHeight : 0)
            + rowHeight * CGFloat(min(max(rowCount, 0), visibleRows))
    }

    static func backButtonFrame(in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + padding, y: frame.maxY - padding - headerHeight,
               width: backButtonWidth, height: headerHeight)
    }

    /// The bar under a full set of rows, as the folder list has.
    static func basketFrame(in frame: CGRect) -> CGRect {
        let rowsBottom = frame.maxY - padding - headerHeight - rowHeight * CGFloat(visibleRows)
        return CGRect(x: frame.minX + padding, y: rowsBottom - basketHeight,
                      width: frame.width - padding * 2, height: basketHeight)
    }

    static func clearButtonFrame(in frame: CGRect) -> CGRect {
        let bar = basketFrame(in: frame)
        return CGRect(x: bar.maxX - clearButtonWidth, y: bar.minY, width: clearButtonWidth, height: bar.height)
    }

    /// Beside the wheel on the side the slice points to and level with it,
    /// so the pointer leaves the slice straight toward the panel. A side that
    /// would run off the screen gives way to the other one; the panel never
    /// covers the wheel it belongs to unless the screen is too small for both.
    static func frame(wheelCenter: CGPoint, direction: (dx: CGFloat, dyUp: CGFloat),
                      rowCount: Int, basket: Bool = false, visibleFrame: CGRect) -> CGRect {
        let size = CGSize(width: width, height: height(rowCount: rowCount, basket: basket))
        let reach = RadialMenuLayout.wheelDiameter / 2 + gap
        let rightX = wheelCenter.x + reach
        let leftX = wheelCenter.x - reach - size.width
        let fitsRight = rightX + size.width <= visibleFrame.maxX - screenMargin
        let fitsLeft = leftX >= visibleFrame.minX + screenMargin
        let x: CGFloat
        if direction.dx >= 0 {
            x = fitsRight || !fitsLeft ? rightX : leftX
        } else {
            x = fitsLeft || !fitsRight ? leftX : rightX
        }
        let y = wheelCenter.y + direction.dyUp * reach - size.height / 2
        return CGRect(x: min(max(x, visibleFrame.minX + screenMargin),
                             visibleFrame.maxX - screenMargin - size.width),
                      y: min(max(y, visibleFrame.minY + screenMargin),
                             visibleFrame.maxY - screenMargin - size.height),
                      width: size.width, height: size.height)
    }

    /// The entry under a point, counted from the top of the whole list, nil
    /// over the header, the preview or outside.
    static func row(at point: CGPoint, in frame: CGRect, rowCount: Int, firstVisibleRow: Int) -> Int? {
        guard frame.contains(point) else { return nil }
        let fromTop = frame.maxY - point.y - padding - headerHeight
        guard fromTop >= 0 else { return nil }
        let onScreen = Int(fromTop / rowHeight)
        guard onScreen < visibleRows else { return nil }
        let index = firstVisibleRow + onScreen
        return index < rowCount ? index : nil
    }

    /// The arrow keys walk the rows and stop at either end; the first press
    /// enters from the side it points to.
    static func movedRow(_ current: Int?, by delta: Int, rowCount: Int) -> Int? {
        guard rowCount > 0 else { return nil }
        guard let current else { return delta > 0 ? 0 : rowCount - 1 }
        return min(max(current + delta, 0), rowCount - 1)
    }

    /// The top row after scrolling, kept so the last row never rises past the
    /// bottom of the list.
    static func scrolledFirstRow(_ first: Int, by rows: Int, rowCount: Int) -> Int {
        min(max(first + rows, 0), max(rowCount - visibleRows, 0))
    }

    /// The top row that brings `row` on screen with the least movement, so
    /// the arrow keys scroll the list as they walk past its edge.
    static func firstRow(revealing row: Int, from first: Int, rowCount: Int) -> Int {
        let wanted = row < first ? row : (row >= first + visibleRows ? row - visibleRows + 1 : first)
        return scrolledFirstRow(wanted, by: 0, rowCount: rowCount)
    }

    /// While a peek is open, a pointer past the wheel's rim is on its way to
    /// the panel, so it keeps the slice it came from instead of arming every
    /// direction it crosses. Back on the ring it points as usual again.
    static func holdsHighlight(pointerDistance: CGFloat) -> Bool {
        pointerDistance > RadialMenuLayout.wheelDiameter / 2
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
