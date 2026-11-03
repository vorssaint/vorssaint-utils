// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure rules for the duplicate finder. The promise they protect: at least
/// one copy of every file always stays, and a copy is only removed if it
/// still looks exactly as it did when the scan read it.
enum DuplicateFileSupport {
    /// Size thresholds offered in the picker, smallest first.
    static let minimumSizes: [Int64] = [1_000_000, 10_000_000, 100_000_000]
    /// How much of a file the cheap first comparison reads.
    static let partialReadBytes = 64 * 1024
    /// The list stops at this many groups so a huge result stays readable.
    static let maxGroups = 100

    /// Whether ticking one more copy would leave the group with no copy left
    /// unticked. `tickedCount` counts copies already ticked, not including
    /// the one being asked about.
    static func mayTick(tickedCount: Int, groupCount: Int) -> Bool {
        tickedCount + 1 < groupCount
    }

    /// The copy that stays by default: the oldest by modification date, and
    /// among equals the first in the list. A copy without a date is only
    /// chosen when every copy lacks one.
    static func defaultKeepIndex(modified: [Date?]) -> Int {
        var best = 0
        for index in modified.indices.dropFirst() {
            switch (modified[best], modified[index]) {
            case let (current?, candidate?): if candidate < current { best = index }
            case (nil, _?): best = index
            default: break
            }
        }
        return best
    }

    // MARK: - Where a copy lives

    /// Why removing a copy could hurt more than it frees.
    enum Risk: Equatable {
        /// Inside a cloud folder: deleting it also deletes it on other devices.
        case synced
        /// Inside a code project's dependency folders.
        case project
        /// Inside a virtual machine folder.
        case virtualMachine
    }

    /// Where a copy sits and what it is tied to, read from its path alone.
    struct Placement: Equatable {
        /// The first folder under home, or the project or machine it belongs to.
        let tiedTo: String
        /// Loose in a place files pile up (Downloads, Desktop), so a likely extra.
        let isTemporary: Bool
        /// A folder people file things into on purpose.
        let isOrganized: Bool
        let risk: Risk?
    }

    /// Cloud folders, matched by name or by name plus a suffix such as
    /// "Dropbox (Personal)" or "OneDrive - Company".
    private static let syncedFolderRoots = ["Dropbox", "OneDrive", "Google Drive", "Box", "MEGA",
                                            "Creative Cloud Files", "pCloud", "iCloud Drive"]
    private static let vmImageExtensions: Set<String> = ["vdi", "vmdk", "qcow2", "hdd", "vhd", "vhdx"]
    private static let projectFolders: Set<String> = [
        "node_modules", "Pods", "site-packages", "DerivedData", "Carthage",
        "venv", "vendor", "miniconda3", "anaconda3",
    ]
    private static let machineFolders: Set<String> = [
        "Virtual Machines", "Parallels", "VirtualBox VMs", "VMware Fusion",
    ]
    private static let machineSuffixes = [".pvm", ".vmwarevm", ".utm"]
    private static let organizedFolders: Set<String> = ["Documents", "Pictures", "Movies", "Music"]

    static func placement(of url: URL, home: URL) -> Placement {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        guard path.hasPrefix(homePath + "/") else {
            return Placement(tiedTo: "", isTemporary: false, isOrganized: false, risk: nil)
        }
        let parts = path.dropFirst(homePath.count + 1).split(separator: "/").map(String.init)
        let top = parts.first ?? ""
        // Everything after the first part is the folder chain above the file.
        let folders = parts.dropLast()

        var risk: Risk?
        var tiedTo = top
        if let index = folders.firstIndex(where: { projectFolders.contains($0) }) {
            risk = .project
            tiedTo = index > folders.startIndex ? folders[folders.index(before: index)] : top
        } else if let machine = folders.first(where: { name in
            machineFolders.contains(name) || machineSuffixes.contains { name.lowercased().hasSuffix($0) }
        }) {
            risk = .virtualMachine
            tiedTo = machine
        } else if syncedFolderRoots.contains(where: { top == $0 || top.hasPrefix($0 + " ") }) {
            risk = .synced
        } else if vmImageExtensions.contains(url.pathExtension.lowercased()) {
            risk = .virtualMachine
            tiedTo = folders.last ?? top
        }
        return Placement(tiedTo: tiedTo, isTemporary: top == "Downloads" || top == "Desktop",
                         isOrganized: organizedFolders.contains(top), risk: risk)
    }

    /// Whether a file name looks like something made by duplicating another:
    /// "report copy.pdf", "report copy 2.pdf" or "report (1).pdf".
    static func looksLikeCopy(_ fileName: String) -> Bool {
        let stem = (fileName as NSString).deletingPathExtension.lowercased()
        return stem.hasSuffix(" copy") || stem.contains(" copy ")
            || stem.range(of: #" \(\d+\)$"#, options: .regularExpression) != nil
    }

    /// How much a copy deserves to be the one that stays. Higher is better.
    static func keepScore(url: URL, home: URL) -> Int {
        let place = placement(of: url, home: home)
        var score = 0
        if place.isTemporary { score -= 30 }
        if place.isOrganized { score += 15 }
        if place.risk != nil { score += 25 }
        if looksLikeCopy(url.lastPathComponent) { score -= 40 }
        // Deeper paths lose a point per level, a small tie-breaker.
        score -= url.standardizedFileURL.pathComponents.count
        return score
    }

    struct Copy: Equatable {
        let url: URL
        let modified: Date?
    }

    /// The copy most likely to be the one you need: the best score, then the
    /// oldest, then the first.
    static func bestIndex(of copies: [Copy], home: URL) -> Int {
        var best = 0
        for index in copies.indices.dropFirst() {
            let candidate = keepScore(url: copies[index].url, home: home)
            let current = keepScore(url: copies[best].url, home: home)
            if candidate > current { best = index; continue }
            guard candidate == current else { continue }
            switch (copies[best].modified, copies[index].modified) {
            case let (a?, b?): if b < a { best = index }
            case (nil, _?): best = index
            default: break
            }
        }
        return best
    }

    static func newestIndex(of copies: [Copy]) -> Int {
        var newest = 0
        for index in copies.indices.dropFirst() {
            switch (copies[newest].modified, copies[index].modified) {
            case let (a?, b?): if b > a { newest = index }
            case (nil, _?): newest = index
            default: break
            }
        }
        return newest
    }

    // MARK: - Smart selection

    enum SelectMode: Equatable {
        case keepBest
        case keepNewest
        case keepOldest
        /// Tick only the copies loose in Downloads or Desktop, when a copy
        /// elsewhere stays.
        case temporaryOnly
        /// Keep this one copy (by position) and tick the others.
        case keep(Int)
    }

    /// Which copies of one set to tick. Copies with a risk are never ticked
    /// for the person, and the result never covers every copy.
    static func indicesToTick(_ mode: SelectMode, copies: [Copy], home: URL) -> Set<Int> {
        guard copies.count > 1 else { return [] }
        let isSafe = { (index: Int) in placement(of: copies[index].url, home: home).risk == nil }
        var ticked: Set<Int>
        switch mode {
        case .keepBest, .keepNewest, .keepOldest, .keep:
            let keep: Int
            switch mode {
            case .keepNewest: keep = newestIndex(of: copies)
            case .keepOldest: keep = defaultKeepIndex(modified: copies.map(\.modified))
            case let .keep(index): keep = copies.indices.contains(index) ? index : 0
            default: keep = bestIndex(of: copies, home: home)
            }
            ticked = Set(copies.indices.filter { $0 != keep && isSafe($0) })
        case .temporaryOnly:
            let temporary = copies.indices.filter { placement(of: copies[$0].url, home: home).isTemporary && isSafe($0) }
            ticked = temporary.count < copies.count ? Set(temporary) : []
        }
        return ticked.count < copies.count ? ticked : []
    }

    /// Whether a copy still matches what the scan saw, so a file edited after
    /// the scan is never removed on the strength of an old comparison.
    static func unchanged(scannedSize: Int64, scannedModified: Date?,
                          currentSize: Int64?, currentModified: Date?) -> Bool {
        currentSize == scannedSize && currentModified == scannedModified
    }

    /// Largest reclaimable space first, trimmed to the cap. Reclaimable space
    /// is the size times every copy but one.
    static func ranked<T>(_ groups: [T], size: (T) -> Int64, copies: (T) -> Int) -> [T] {
        Array(groups.sorted {
            size($0) * Int64(max(0, copies($0) - 1)) > size($1) * Int64(max(0, copies($1) - 1))
        }.prefix(maxGroups))
    }
}
