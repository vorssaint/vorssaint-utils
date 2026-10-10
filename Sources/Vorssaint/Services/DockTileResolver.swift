// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Turns a Dock tile into the process it stands for.
///
/// Matching a tile's AXURL against `bundleURL` is enough for the ordinary app,
/// which owns exactly one process. It collapses apps that run as several
/// separate processes: each instance gets its own tile, yet every tile reports
/// the same bundle URL, so clicking any of them acted on whichever instance the
/// workspace happened to list first and the other instances were unreachable
/// from the Dock.
///
/// Both the Dock click tap and the Dock preview hit test resolve through here,
/// so a preview panel opened over one tile and a click on that tile always mean
/// the same process. Pairings are remembered between lookups, so a tile keeps
/// its process when it is dragged elsewhere in the Dock.
enum DockTileResolver {
    /// The instance behind the tile at `index` of `items`, the Dock's own item
    /// list the caller is already walking.
    static func application(forTileAt index: Int,
                            in items: [AXUIElement],
                            bundlePath: String) -> NSRunningApplication? {
        let instances = runningInstances(bundlePath: bundlePath)
        guard let first = instances.first, items.indices.contains(index) else { return nil }
        let tile = items[index]
        // The case virtually every click takes, and the one that runs inside the
        // click tap's Accessibility budget: a single instance needs no ordinal,
        // only one AX round trip for whether this tile shows it running.
        guard instances.count > 1 else {
            return soleInstanceIsBehind(tile, bundlePath: bundlePath, items: { items }) ? first : nil
        }
        return instance(forTile: tile,
                        amongTiles: tiles(in: items, bundlePath: bundlePath, including: tile),
                        instances: instances,
                        bundlePath: bundlePath)
    }

    /// What an element found by AX hit testing stands for.
    enum TileResolution {
        /// No tile of a running app, so the caller keeps whatever fallback it
        /// had.
        case unknown
        /// A tile that none of its app's running processes stands behind
        /// right now: one kept in the Dock after its instance quit while
        /// another runs on, or one whose instance is still launching. A
        /// fallback by name would land on another process, so the caller shows
        /// nothing.
        case unpaired
        case instance(NSRunningApplication)
    }

    /// The instance behind a tile a caller found by AX hit testing, which leaves
    /// it holding an element rather than a place in a list.
    static func resolution(forTile tile: AXUIElement) -> TileResolution {
        guard let url = readURL(tile).url else { return .unknown }
        let bundlePath = url.standardizedFileURL.path
        let instances = runningInstances(bundlePath: bundlePath)
        guard let first = instances.first else { return .unknown }
        guard instances.count > 1 else {
            return soleInstanceIsBehind(tile, bundlePath: bundlePath, items: { dockItems(holding: tile) })
                ? .instance(first) : .unpaired
        }
        // Without the list there is nothing to compare against: only a tile
        // paired before keeps its process.
        let tiles = dockItems(holding: tile).map {
            self.tiles(in: $0, bundlePath: bundlePath, including: tile)
        }
        return instance(forTile: tile, amongTiles: tiles, instances: instances, bundlePath: bundlePath)
            .map { .instance($0) } ?? .unpaired
    }

    /// The Dock's item list a hit-tested tile sits in. Read only for a bundle
    /// with several instances or a tile that reads not running, so the extra
    /// AXParent and AXChildren reads stay off the ordinary path.
    private static func dockItems(holding tile: AXUIElement) -> [AXUIElement]? {
        guard let parent = elementAttribute(tile, kAXParentAttribute as String),
              stringAttribute(parent, kAXRoleAttribute as String) == "AXList"
        else { return nil }
        return elementArray(parent, kAXChildrenAttribute as String)
    }

    /// Whether the one running instance of the bundle stands behind `tile`.
    /// `items` reads the Dock list holding it, which only a tile that reads
    /// not running needs.
    private static func soleInstanceIsBehind(_ tile: AXUIElement,
                                             bundlePath: String,
                                             items: () -> [AXUIElement]?) -> Bool {
        DockClickSupport.soleInstanceIsBehindTile(
            tileReadsRunning: readRunning(tile).isRunning,
            anotherTileReadsRunning: {
                guard let list = items() else { return false }
                return tiles(in: list, bundlePath: bundlePath, including: tile).tiles
                    .contains { !CFEqual($0, tile) }
            })
    }

    /// Every live, regular process running this exact bundle. Only regular apps
    /// get a tile, so this filter matches the tile set the ordinal counts.
    private static func runningInstances(bundlePath: String) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
                && $0.bundleURL?.standardizedFileURL.path == bundlePath
        }
    }

    /// The tiles of one bundle in Dock order, and whether every item in the
    /// list answered. A list with a tile missing pairs the rest by the wrong
    /// order, so it serves the lookup at hand but is never remembered.
    private struct TileList {
        var tiles: [AXUIElement] = []
        var complete = true
    }

    /// Reads AXURL from the Dock for every item, and AXIsApplicationRunning for
    /// the tiles of this bundle, which only apps with several instances, or a
    /// tile that reads not running, pay for. A tile kept in the Dock after its
    /// instance quit shows no running app and takes no instance, so it cannot
    /// push the running tiles out of launch order. The tile being resolved
    /// counts whatever its URL read says this time.
    private static func tiles(in items: [AXUIElement],
                              bundlePath: String,
                              including tile: AXUIElement) -> TileList {
        var list = TileList()
        for item in items {
            if !CFEqual(item, tile) {
                let read = readURL(item)
                if !read.answered { list.complete = false }
                guard read.url?.standardizedFileURL.path == bundlePath else { continue }
            }
            let running = readRunning(item)
            if !running.answered { list.complete = false }
            if running.isRunning { list.tiles.append(item) }
        }
        return list
    }

    /// A tile's element, compared the way the accessibility API compares them.
    private struct TileKey: Equatable {
        let element: AXUIElement
        static func == (lhs: TileKey, rhs: TileKey) -> Bool { CFEqual(lhs.element, rhs.element) }
    }

    /// The pairings last made for each bundle, kept so a dragged tile keeps
    /// its process. The click tap and the preview hit test both land here and
    /// need not share a thread.
    private static let pairingLock = NSLock()
    private static var pairings: [String: [DockTilePairing<TileKey>]] = [:]

    private static func instance(forTile tile: AXUIElement,
                                 amongTiles list: TileList?,
                                 instances: [NSRunningApplication],
                                 bundlePath: String) -> NSRunningApplication? {
        let described = instances.map {
            DockAppInstance(pid: $0.processIdentifier,
                            launchTime: DockClickSupport.launchTime(
                                processStartMicroseconds: KillProcessService.startTime(for: $0.processIdentifier),
                                launchDate: $0.launchDate))
        }
        let hit = TileKey(element: tile)
        let paired = pairingLock.withLock { () -> [DockTilePairing<TileKey>] in
            let previous = pairings[bundlePath] ?? []
            // Without the whole, settled tile list only a pairing this tile
            // already has holds, and nothing is stored.
            let tiles = list?.tiles.map(TileKey.init(element:)) ?? [hit]
            let complete = list?.complete ?? false
            let made = DockClickSupport.pairTiles(tiles,
                                                  instances: described,
                                                  previous: previous,
                                                  complete: complete)
            if DockClickSupport.canPairByOrder(tileCount: tiles.count,
                                               instanceCount: described.count,
                                               complete: complete) {
                pairings[bundlePath] = made
            }
            return made
        }
        guard let pid = paired.first(where: { $0.tile == hit })?.pid else { return nil }
        return instances.first { $0.processIdentifier == pid }
    }

    // MARK: - Accessibility reads

    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func elementArray(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AXUIElement]
        else { return nil }
        return array
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    /// Whether a tile shows a running app, and whether the read answered. A
    /// tile that cannot say is counted as running, which is how every tile was
    /// counted before.
    private static func readRunning(_ element: AXUIElement) -> (isRunning: Bool, answered: Bool) {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, "AXIsApplicationRunning" as CFString, &value) {
        case .success:
            return ((value as? Bool) ?? true, true)
        case .noValue, .attributeUnsupported:
            return (true, true)
        default:
            return (true, false)
        }
    }

    /// An element's AXURL, and whether the read answered at all. Separators
    /// and minimized windows have no URL, which is an answer; a timeout is not.
    private static func readURL(_ element: AXUIElement) -> (url: URL?, answered: Bool) {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) {
        case .success:
            guard let value, CFGetTypeID(value) == CFURLGetTypeID() else { return (nil, true) }
            return ((value as! CFURL) as URL, true)
        case .noValue, .attributeUnsupported:
            return (nil, true)
        default:
            return (nil, false)
        }
    }
}
