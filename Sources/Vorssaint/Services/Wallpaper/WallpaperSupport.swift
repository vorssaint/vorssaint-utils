// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Lets a folder scan publish only while its gallery is open and it is the
/// latest scan. The scan reads this from a worker queue while the UI changes
/// visibility on the main thread.
final class WallpaperGalleryLifecycle {
    private let lock = NSLock()
    private var viewers = Set<UUID>()
    private var generation = UUID()

    var isVisible: Bool { lock.withLock { !viewers.isEmpty } }

    func begin(_ viewer: UUID) { lock.withLock { _ = viewers.insert(viewer) } }

    /// A closing panel cancels work only when no other gallery is still open.
    @discardableResult
    func end(_ viewer: UUID) -> Bool {
        lock.withLock {
            guard viewers.remove(viewer) != nil, viewers.isEmpty else { return false }
            generation = UUID()
            return true
        }
    }

    func endAll() {
        lock.withLock {
            viewers.removeAll()
            generation = UUID()
        }
    }

    @discardableResult
    func invalidate() -> UUID {
        lock.withLock {
            generation = UUID()
            return generation
        }
    }

    func accepts(_ token: UUID) -> Bool {
        lock.withLock { !viewers.isEmpty && generation == token }
    }
}

/// Catalog / filter / store-patch helpers. No AppKit (test harness).
enum WallpaperSupport {
    enum Source: String, Equatable {
        case apple
        case own
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all
        case own
        case apple

        var id: String { rawValue }
    }

    struct Entry: Equatable, Identifiable {
        let id: String
        let imageURL: URL
        let previewURL: URL
        let title: String
        let source: Source
    }

    static let appleDesktopPicturesPath = "/System/Library/Desktop Pictures"
    static let appleDesktopPicturesURL = URL(fileURLWithPath: appleDesktopPicturesPath,
                                             isDirectory: true)

    static let imageExtensions: Set<String> = [
        "heic", "jpg", "jpeg", "png", "tif", "tiff", "gif", "bmp", "webp",
    ]

    static func isStillImageURL(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    static func title(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    // top-level stills + .madesktop → thumbnail HEIC
    static func enumerateAppleEntries(
        at root: URL = appleDesktopPicturesURL,
        fileManager: FileManager = .default
    ) -> [Entry] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else {
            return []
        }
        var entries: [Entry] = []
        var seen = Set<String>()
        for name in names where !name.hasPrefix(".") {
            let url = root.appendingPathComponent(name)
            guard let resolved = resolveAppleStill(at: url, root: root, fileManager: fileManager)
            else { continue }
            let key = resolved.imageURL.standardizedFileURL.path
            guard seen.insert(key).inserted else { continue }
            entries.append(resolved)
        }
        return entries.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    static func resolveAppleStill(at url: URL,
                                  root: URL = appleDesktopPicturesURL,
                                  fileManager: FileManager = .default) -> Entry? {
        if isStillImageURL(url), fileManager.fileExists(atPath: url.path) {
            return Entry(id: url.standardizedFileURL.path,
                         imageURL: url,
                         previewURL: url,
                         title: title(for: url),
                         source: .apple)
        }
        guard url.pathExtension.lowercased() == "madesktop" else { return nil }
        let stem = url.deletingPathExtension().lastPathComponent
        let wallpaperAsset = root
            .appendingPathComponent(".wallpapers", isDirectory: true)
            .appendingPathComponent(stem, isDirectory: true)
            .appendingPathComponent("\(stem).heic")
        let thumbnail = root
            .appendingPathComponent(".thumbnails", isDirectory: true)
            .appendingPathComponent("\(stem).heic")
        let plistThumbnail = madesktopThumbnailPath(at: url).map { URL(fileURLWithPath: $0) }

        let imageURL: URL?
        // full-size still only; .thumbnails / thumbnailPath are preview-sized
        if fileManager.fileExists(atPath: wallpaperAsset.path) {
            imageURL = wallpaperAsset
        } else {
            imageURL = nil
        }
        guard let imageURL else { return nil }
        let previewURL: URL
        if let plistThumbnail, fileManager.fileExists(atPath: plistThumbnail.path) {
            previewURL = plistThumbnail
        } else if fileManager.fileExists(atPath: thumbnail.path) {
            previewURL = thumbnail
        } else {
            previewURL = imageURL
        }
        return Entry(id: url.standardizedFileURL.path,
                     imageURL: imageURL,
                     previewURL: previewURL,
                     title: stem,
                     source: .apple)
    }

    static func madesktopThumbnailPath(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data,
                                                                      options: [],
                                                                      format: nil)
                as? [String: Any],
              let path = plist["thumbnailPath"] as? String,
              !path.isEmpty
        else { return nil }
        return path
    }

    static func images(inFolder folder: URL,
                       fileManager: FileManager = .default,
                       shouldContinue: () -> Bool = { true }) -> [URL] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard shouldContinue() else { return [] }
            let values = try? url.resourceValues(forKeys: keys)
            // don't walk into .app / Photos Library / other bundles
            if values?.isSymbolicLink == true || values?.isPackage == true {
                enumerator.skipDescendants()
                continue
            }
            guard isStillImageURL(url), values?.isRegularFile == true else { continue }
            urls.append(url)
        }
        return urls.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent)
                == .orderedAscending
        }
    }

    static func ownEntries(from urls: [URL]) -> [Entry] {
        var entries: [Entry] = []
        var seen = Set<String>()
        for url in urls {
            let key = url.standardizedFileURL.path
            guard seen.insert(key).inserted else { continue }
            entries.append(Entry(id: key,
                                 imageURL: url,
                                 previewURL: url,
                                 title: title(for: url),
                                 source: .own))
        }
        return entries
    }

    static func merge(apple: [Entry], own: [Entry]) -> [Entry] {
        var seen = Set(apple.map(\.id))
        var merged = apple
        for entry in own where seen.insert(entry.id).inserted {
            merged.append(entry)
        }
        return merged.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    static func filtered(_ entries: [Entry], by filter: Filter) -> [Entry] {
        switch filter {
        case .all: return entries
        case .own: return entries.filter { $0.source == .own }
        case .apple: return entries.filter { $0.source == .apple }
        }
    }

    static let pageSize = 24

    static func pageCount(itemCount: Int, pageSize: Int = pageSize) -> Int {
        guard pageSize > 0, itemCount > 0 else { return itemCount == 0 ? 0 : 1 }
        return (itemCount + pageSize - 1) / pageSize
    }

    // 1-based, clamped
    static func clampedPage(_ page: Int, itemCount: Int, pageSize: Int = pageSize) -> Int {
        let pages = pageCount(itemCount: itemCount, pageSize: pageSize)
        guard pages > 0 else { return 1 }
        return min(max(page, 1), pages)
    }

    static func pageSlice<T>(_ items: [T], page: Int, pageSize: Int = pageSize) -> [T] {
        let safe = clampedPage(page, itemCount: items.count, pageSize: pageSize)
        guard !items.isEmpty, pageSize > 0 else { return [] }
        let start = (safe - 1) * pageSize
        guard start < items.count else { return [] }
        let end = min(start + pageSize, items.count)
        return Array(items[start..<end])
    }

    static func targetScreenIDs(allDisplays: Bool,
                                screenIDs: [UInt32],
                                pointerScreenID: UInt32?) -> [UInt32] {
        if allDisplays { return screenIDs }
        if let pointerScreenID, screenIDs.contains(pointerScreenID) {
            return [pointerScreenID]
        }
        return screenIDs.first.map { [$0] } ?? []
    }

    static let systemWallpaperSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
    )

    // MARK: - WallpaperAgent store

    // Choice.Configuration bplist
    static func imageFileConfigurationData(for imageURL: URL) -> Data? {
        let payload: [String: Any] = [
            "type": "imageFile",
            "url": ["relative": imageURL.absoluteString],
        ]
        return try? PropertyListSerialization.data(fromPropertyList: payload,
                                                   format: .binary,
                                                   options: 0)
    }

    // Fill Screen = Crop in EncodedOptionValues
    static func fillScreenOptionValuesData() -> Data? {
        let payload: [String: Any] = [
            "values": [
                "placement": [
                    "picker": ["_0": ["id": "Crop"]],
                ],
            ],
        ]
        return try? PropertyListSerialization.data(fromPropertyList: payload,
                                                   format: .binary,
                                                   options: 0)
    }

    // stamp the still into every wallpaper slot (AllSpaces / Displays / Spaces).
    // unknown layouts return false so AppKit current-space apply stays the fallback.
    @discardableResult
    static func patchStoreRoot(_ root: inout [String: Any],
                               imageURL: URL,
                               now: Date = Date()) -> Bool {
        guard let configuration = imageFileConfigurationData(for: imageURL),
              let options = fillScreenOptionValuesData()
        else { return false }

        // Sonoma+ store always has this container; inventing it rewrites unsupported shapes
        guard var allSpaces = root["AllSpacesAndDisplays"] as? [String: Any] else { return false }

        let slot: [String: Any] = [
            "Content": [
                "Choices": [[
                    "Provider": "com.apple.wallpaper.choice.image",
                    "Files": [] as [Any],
                    "Configuration": configuration,
                ]],
                "Shuffle": "$null",
                "EncodedOptionValues": options,
            ] as [String: Any],
            "LastSet": now,
            "LastUse": now,
        ]

        guard patchWallpaperSlot(&allSpaces, slot: slot) else { return false }
        root["AllSpacesAndDisplays"] = allSpaces

        if let displaysValue = root["Displays"] {
            guard var displays = displaysValue as? [String: Any] else { return false }
            for key in displays.keys {
                guard var entry = displays[key] as? [String: Any] else { return false }
                guard patchWallpaperSlot(&entry, slot: slot) else { return false }
                displays[key] = entry
            }
            root["Displays"] = displays
        }

        if let spacesValue = root["Spaces"] {
            guard var spaces = spacesValue as? [String: Any] else { return false }
            for spaceKey in spaces.keys {
                guard var space = spaces[spaceKey] as? [String: Any] else { return false }
                if let defaultValue = space["Default"] {
                    guard var defaultEntry = defaultValue as? [String: Any] else { return false }
                    guard patchWallpaperSlot(&defaultEntry, slot: slot) else { return false }
                    space["Default"] = defaultEntry
                }
                if let spaceDisplaysValue = space["Displays"] {
                    guard var spaceDisplays = spaceDisplaysValue as? [String: Any] else { return false }
                    for displayKey in spaceDisplays.keys {
                        guard var entry = spaceDisplays[displayKey] as? [String: Any] else {
                            return false
                        }
                        guard patchWallpaperSlot(&entry, slot: slot) else { return false }
                        spaceDisplays[displayKey] = entry
                    }
                    space["Displays"] = spaceDisplays
                }
                spaces[spaceKey] = space
            }
            root["Spaces"] = spaces
        }

        if let systemDefaultValue = root["SystemDefault"] {
            guard var systemDefault = systemDefaultValue as? [String: Any] else { return false }
            guard patchWallpaperSlot(&systemDefault, slot: slot) else { return false }
            root["SystemDefault"] = systemDefault
        }

        return true
    }

    // System Settings stills (Sonoma+) write Type=linked + Linked on
    // AllSpacesAndDisplays and SystemDefault, with Content.Choices Provider
    // com.apple.wallpaper.choice.image and an imageFile Configuration blob.
    // Captured from a store that only System Settings wrote (no Vorssaint bak).
    // Index.plist has no screen saver keys; that choice lives outside this store,
    // so replacing Linked does not rewrite a screen saver slot here.
    // Desktop is the older individual/idle slot. Key off Type so a leftover
    // Linked key on an individual container cannot steal the Desktop slot.
    @discardableResult
    static func patchWallpaperSlot(_ container: inout [String: Any],
                                   slot: [String: Any]) -> Bool {
        let type = container["Type"] as? String

        if type == "linked" {
            guard container["Linked"] == nil || container["Linked"] is [String: Any] else {
                return false
            }
            container["Linked"] = slot
            container.removeValue(forKey: "Desktop")
            return true
        }

        if type == "individual" || container["Desktop"] is [String: Any] {
            container["Desktop"] = slot
            return true
        }

        // idle (and similar) without a slot yet — Desktop path, refuse if Linked is present
        if type != nil {
            if container["Linked"] is [String: Any] { return false }
            container["Desktop"] = slot
            return true
        }

        return false
    }
}
