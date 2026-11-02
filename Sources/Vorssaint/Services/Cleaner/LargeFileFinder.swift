// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Finds big files in the home folder and moves the ones you tick to the
/// Trash. Nothing starts selected: these are your own files, not leftovers.
final class LargeFileFinder: ObservableObject {
    static let shared = LargeFileFinder()

    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case removing
        case done(freed: Int64, failed: Int)
    }

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let size: Int64
        let lastOpened: Date?
        var include = false

        var name: String { url.lastPathComponent }

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.id == rhs.id && lhs.include == rhs.include
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published var items: [Item] = []
    private var cancellation: CleanerSupport.ScanCancellation?

    private init() {}

    var selectedSize: Int64 { items.filter(\.include).reduce(0) { $0 + $1.size } }

    func setInclude(_ include: Bool, for id: UUID) {
        guard phase == .results, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].include = include
    }

    func selectAll(_ include: Bool) {
        guard phase == .results else { return }
        for index in items.indices { items[index].include = include }
    }

    func reset() {
        guard phase != .removing else { return }
        cancellation?.cancel()
        cancellation = nil
        items = []
        phase = .idle
    }

    func scan(minimumSize: Int64, olderThanDays: Int) {
        guard phase != .scanning, phase != .removing else { return }
        let cancel = CleanerSupport.ScanCancellation()
        cancellation = cancel
        items = []
        phase = .scanning
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.walk(home: home, minimumSize: minimumSize,
                                  olderThanDays: olderThanDays, cancel: cancel)
            DispatchQueue.main.async {
                // A reset or a newer scan replaced this one: drop its result.
                guard self.cancellation === cancel, !cancel.isCancelled else { return }
                self.items = found
                self.cancellation = nil
                self.phase = .results
            }
        }
    }

    func trashSelected() {
        guard phase == .results else { return }
        let chosen = items.filter(\.include)
        guard !chosen.isEmpty else { return }
        phase = .removing
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async {
            var freed: Int64 = 0
            var failed = 0
            for item in chosen {
                guard LargeFileSupport.mayRemove(item.url, home: home),
                      Self.isPlainFile(item.url) else { failed += 1; continue }
                do {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                    freed += item.size
                } catch {
                    failed += 1
                }
            }
            DispatchQueue.main.async {
                self.items = []
                self.phase = .done(freed: freed, failed: failed)
            }
        }
    }

    // MARK: - Walk

    private static func isPlainFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true
    }

    private static func walk(home: URL, minimumSize: Int64, olderThanDays: Int,
                             cancel: CleanerSupport.ScanCancellation) -> [Item] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                      .contentAccessDateKey]
        guard let walker = FileManager.default.enumerator(
            at: home, includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants, .skipsHiddenFiles], errorHandler: { _, _ in true }) else { return [] }
        var found: [Item] = []
        let now = Date()
        for case let url as URL in walker {
            if cancel.isCancelled { return [] }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { walker.skipDescendants(); continue }
            if values.isDirectory == true {
                if LargeFileSupport.shouldSkipDirectory(url, home: home) { walker.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            guard LargeFileSupport.qualifies(size: size, lastOpened: values.contentAccessDate,
                                             minimumSize: minimumSize, olderThanDays: olderThanDays,
                                             now: now) else { continue }
            found.append(Item(url: url, size: size, lastOpened: values.contentAccessDate))
        }
        return LargeFileSupport.ranked(found) { $0.size }
    }
}
