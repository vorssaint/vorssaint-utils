// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One file the organizer placed, with everything needed to tell whether the
/// person has touched it since. The property names and their order are the
/// persisted JSON keys, so cases may be appended but never renamed.
struct OrganizedFileRecord: Codable, Equatable {
    let digest: String
    let destinationPath: String
    let originalName: String
    let size: Int64
    let organizedAt: Date
}

/// One reversible step of an organizer pass: a move that can be put back, or
/// a trash that can be emptied from the trash.
struct UndoTransaction: Codable {
    enum ActionKind: String, Codable { case move, trash }
    struct Action: Codable {
        let kind: ActionKind
        let currentPath: String
        let restorePath: String?
    }

    let id: UUID
    let actions: [Action]
    let recordsBefore: [OrganizedFileRecord]
    let recordsAfter: [OrganizedFileRecord]
    let createdAt: Date
}

/// The undo transaction is the most expensive correctness property in this
/// subsystem, and it is expensive because undo destroys work: restoring a
/// pass means overwriting whatever sits at the organized path today, so it is
/// only safe while every file that pass wrote is provably still that file.
/// The organizer owns the moving; the deciding does not. Keeping these rules
/// pure and here is what lets the destructive boundary be exercised by tests
/// that never touch a real Downloads folder.
enum DownloadUndoPolicy {
    static func recordMap(_ records: [OrganizedFileRecord]) -> [String: OrganizedFileRecord] {
        Dictionary(records.map { ($0.destinationPath, $0) },
                   uniquingKeysWith: { _, latest in latest })
    }

    /// The paths whose record a transaction actually changed. Only a
    /// difference counts: a record the transaction wrote and then wrote back
    /// identically involved nothing and must not block the undo.
    static func affectedRecordPaths(_ transaction: UndoTransaction) -> Set<String> {
        let before = recordMap(transaction.recordsBefore)
        let after = recordMap(transaction.recordsAfter)
        return Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
    }

    /// Whether undo may proceed. A record that changed since the transaction
    /// was written means the person moved or replaced the file themselves,
    /// and restoring would destroy that; the whole transaction is refused
    /// rather than partly applied, because a half-undone pass leaves the
    /// records describing files that no longer exist.
    static func recordsAllowUndo(_ transaction: UndoTransaction,
                                 current: [OrganizedFileRecord]) -> Bool {
        let expected = recordMap(transaction.recordsAfter)
        let current = recordMap(current)
        return affectedRecordPaths(transaction).allSatisfy { current[$0] == expected[$0] }
    }

    static func recordsAfterUndo(_ transaction: UndoTransaction,
                                 current: [OrganizedFileRecord]) -> [OrganizedFileRecord] {
        let before = recordMap(transaction.recordsBefore)
        var result = recordMap(current)
        for path in affectedRecordPaths(transaction) {
            result[path] = before[path]
        }
        return result.values.sorted { $0.organizedAt < $1.organizedAt }
    }

    /// Finds the record that makes a freshly downloaded file a duplicate.
    /// Records that share the digest but whose file is gone or no longer has
    /// those bytes are dropped and the search continues, so a stale record
    /// cannot hide the real duplicate further down the list - and equally a
    /// record that merely claims the digest is not treated as a duplicate,
    /// because acting on one would trash a file the person still has.
    static func resolveDuplicate(digest: String,
                                  records: inout [OrganizedFileRecord],
                                  isIntact: (OrganizedFileRecord) -> Bool) -> Int? {
        var index = 0
        while index < records.count {
            guard records[index].digest == digest else {
                index += 1
                continue
            }
            guard isIntact(records[index]) else {
                records.remove(at: index)
                continue
            }
            return index
        }
        return nil
    }
}