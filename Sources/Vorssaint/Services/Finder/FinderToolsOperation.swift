// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A snapshot of a user-confirmed operation. No UI or pasteboard objects cross the queue boundary.
struct FinderToolsOperation {
    let action: FinderToolsAction
    let selection: [URL]
    let destination: URL?
    let name: String
    let clipboardText: String?
    var treeDepth = 8
    var filenameEncoding = String.Encoding.windowsCP1252.rawValue
    var watermark = ""
    var red = 0.0
    var green = 0.0
    var blue = 0.0
    var password: String?
    var clipboardImage: Data?
    var clipboardFiles: [URL] = []
    var uniqueNames = true
}

struct FinderToolsResult {
    var outputs: [URL] = []
    var text: String?
    var failures: [FinderFileActionItemFailure] = []
}

final class FinderToolsCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var cancellationHandler: (() -> Void)?

    func cancel() {
        lock.lock()
        cancelled = true
        let handler = cancellationHandler
        lock.unlock()
        handler?()
    }

    func setHandler(_ handler: (() -> Void)?) {
        lock.lock()
        cancellationHandler = handler
        let alreadyCancelled = cancelled
        lock.unlock()
        if alreadyCancelled { handler?() }
    }

    func check() throws {
        lock.lock()
        let value = cancelled
        lock.unlock()
        if value { throw CancellationError() }
    }
}

enum FinderToolsExecutor {
    static let maximumTextBytes = 8 * 1024 * 1024

    static func execute(_ operation: FinderToolsOperation,
                        cancellation: FinderToolsCancellation) throws -> FinderToolsResult {
        try cancellation.check()
        let action = operation.action
        let creationPolicy: FinderFileActions.CollisionPolicy = operation.uniqueNames ? .makeUnique : .fail
        guard !action.needsSelection || !operation.selection.isEmpty else {
            throw FinderFileActionError.invalidRequest("Select at least one file or folder.")
        }
        guard !action.needsDestination || operation.destination != nil else {
            throw FinderFileActionError.invalidRequest("Choose a destination folder.")
        }
        if action.needsName {
            guard !operation.name.isEmpty, operation.name != ".", operation.name != "..",
                  !operation.name.contains("/"), !operation.name.contains("\\"),
                  !operation.name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw FinderFileActionError.invalidName(operation.name)
            }
        }
        if action == .pasteFiles || action == .pasteAliases || action == .pasteZIP {
            guard !operation.clipboardFiles.isEmpty else {
                throw FinderFileActionError.invalidRequest("The clipboard contains no files.")
            }
            return try execute(FinderToolsOperation(action: action == .pasteFiles ? .copyTo : action == .pasteZIP ? .zip : .alias,
                selection: operation.clipboardFiles, destination: operation.destination, name: operation.name,
                clipboardText: nil), cancellation: cancellation)
        }
        if action == .pasteImage {
            guard let data = operation.clipboardImage, !data.isEmpty, let destination = operation.destination else {
                throw FinderFileActionError.invalidRequest("The clipboard contains no readable image.")
            }
            let outputName = operation.name.lowercased().hasSuffix(".png") ? operation.name : operation.name + ".png"
            return FinderToolsResult(outputs: [try FinderFileActions.createFile(in: destination, named: outputName,
                contents: data, collisionPolicy: creationPolicy)])
        }
        if action.isDocumentOutput || action == .readQR {
            do { return try FinderDocumentExecutor.execute(operation, cancellation: cancellation) }
            catch FinderFileActionError.partialFailure(_, let completed, let failures) {
                return FinderToolsResult(outputs: completed, failures: failures)
            }
        }
        guard !action.usesExistingTool && !action.usesSystemUI else {
            throw FinderFileActionError.invalidRequest("Open this action in its workspace.")
        }
        switch action {
        case .searchFolder:
            let matches = try FinderSearchTools.search(in: operation.selection, query: operation.name, cancellation: cancellation)
            return FinderToolsResult(outputs: matches, text: matches.map(\.path).joined(separator: "\n"))
        case .batchRename, .repairNames:
            let changes = action == .repairNames
                ? try FinderSearchTools.repairedNames(operation.selection, encoding: .init(rawValue: operation.filenameEncoding))
                : FinderBatchTools.renameChanges(operation.selection, pattern: operation.name)
            let plan = try FinderFileActions.planRenames(changes)
            do { return FinderToolsResult(outputs: try FinderBatchTools.rename(plan, cancellation: cancellation)) }
            catch FinderFileActionError.partialFailure(_, let completed, let failures) {
                return FinderToolsResult(outputs: completed, failures: failures)
            }
        case .duplicates:
            let groups = try FinderBatchTools.duplicates(in: operation.selection, cancellation: cancellation)
            return FinderToolsResult(text: groups.map { $0.map(\.path).joined(separator: "\n") }.joined(separator: "\n\n"))
        case .newFile, .pasteText, .pasteMarkdown:
            var data = FinderNewFileTemplates.contents(for: operation.name)
            if action != .newFile {
                guard let text = operation.clipboardText, !text.isEmpty,
                      text.utf8.count <= maximumTextBytes else {
                    throw FinderFileActionError.invalidRequest("The clipboard must contain nonempty text smaller than 8 MB.")
                }
                data = Data(text.utf8)
            }
            let output = try FinderFileActions.createFile(in: operation.destination!, named: operation.name,
                                                          contents: data, collisionPolicy: creationPolicy)
            return FinderToolsResult(outputs: [output])
        case .newFolder:
            return FinderToolsResult(outputs: [try FinderFileActions.createFolder(
                in: operation.destination!, named: operation.name, collisionPolicy: creationPolicy)])
        case .template:
            guard operation.selection.count == 1 else {
                throw FinderFileActionError.invalidRequest("Choose one template file or package.")
            }
            return FinderToolsResult(outputs: [try FinderFileActions.copyItem(at: operation.selection[0],
                to: operation.destination!.appendingPathComponent(operation.name))])
        case .group:
            return FinderToolsResult(outputs: [try FinderFileActions.group(operation.selection,
                in: operation.destination!, named: operation.name)])
        default: break
        }

        var result = FinderToolsResult()
        var lines: [String] = []
        var textBytes = 0
        selectionLoop: for item in operation.selection {
            do {
                try cancellation.check()
                let text: String?
                switch action {
                case .copySummary:
                    let values = try item.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey])
                    text = [item.path, "\(values.fileSize ?? 0) bytes",
                            values.contentModificationDate.map { ISO8601DateFormatter().string(from: $0) } ?? ""].joined(separator: "\n")
                case .zip:
                    let archive = NotchArchiveOperation()
                    cancellation.setHandler { archive.cancel() }
                    defer { cancellation.setHandler(nil) }
                    let destination = operation.destination!.appendingPathComponent(item.lastPathComponent + ".zip")
                    try archive.archive(item, to: destination)
                    result.outputs.append(destination)
                    text = nil
                case .trash:
                    var trashed: NSURL?
                    try FileManager.default.trashItem(at: item, resultingItemURL: &trashed)
                    if let trashed { result.outputs.append(trashed as URL) }
                    text = nil
                case .permanentDelete:
                    // The UI requires a separate destructive confirmation.
                    guard item.standardizedFileURL.path != "/" else { throw CocoaError(.fileWriteNoPermission) }
                    try FileManager.default.removeItem(at: item)
                    result.outputs.append(item)
                    text = nil
                case .hideExtension, .showExtension:
                    var values = URLResourceValues()
                    values.hasHiddenExtension = action == .hideExtension
                    var url = item
                    try url.setResourceValues(values)
                    result.outputs.append(item)
                    text = nil
                case .copyPath: text = FinderFileActions.path(of: item)
                case .copyName: text = item.lastPathComponent
                case .copyStem: text = item.deletingPathExtension().lastPathComponent
                case .copyMarkdown: text = FinderFileActions.markdownLink(to: item)
                case .copyContents: text = try readText(item)
                case .size:
                    text = "\(item.lastPathComponent): \(try FinderFileActions.size(of: item, checkCancellation: cancellation.check)) bytes"
                case .sha256:
                    text = "\(try FinderFileActions.sha256(of: item, checkCancellation: cancellation.check))  \(item.lastPathComponent)"
                case .fileTree, .directoryTree:
                    let tree = try FinderFileActions.fileTree(at: item, maximumDepth: operation.treeDepth, checkCancellation: cancellation.check)
                    text = tree.entries.filter { action != .directoryTree || $0.kind == .directory }
                        .map { String(repeating: "  ", count: $0.depth) + $0.name }
                        .joined(separator: "\n") + (tree.truncated ? "\n…" : "")
                case .copyTo, .moveTo, .alias, .aliasDesktop:
                    let name = item.lastPathComponent + ([.alias, .aliasDesktop].contains(action) ? " alias" : "")
                    let folder = action == .aliasDesktop
                        ? try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                        : operation.destination!
                    let destination = folder.appendingPathComponent(name)
                    let output: URL
                    if action == .copyTo { output = try FinderFileActions.copyItem(at: item, to: destination) }
                    else if action == .moveTo { output = try FinderFileActions.moveItem(at: item, to: destination) }
                    else { output = try FinderFileActions.createAlias(to: item, at: destination) }
                    result.outputs.append(output)
                    text = nil
                case .hide, .unhide:
                    try FinderFileActions.setHidden(action == .hide, at: item)
                    result.outputs.append(item)
                    text = nil
                case .lock, .unlock:
                    try FinderFileActions.setLocked(action == .lock, at: item)
                    result.outputs.append(item)
                    text = nil
                case .flatten:
                    result.outputs += try FinderFileActions.flattenContents(of: item)
                    text = nil
                default:
                    preconditionFailure("Creation operations are handled before the selection loop")
                }
                if let text {
                    textBytes += text.utf8.count + 1
                    guard textBytes <= maximumTextBytes else {
                        throw FinderFileActionError.invalidRequest("The combined text exceeds 8 MB. Select fewer items.")
                    }
                    lines.append(text)
                }
            } catch is CancellationError {
                result.failures.append(.init(url: item, reason: CancellationError().localizedDescription))
                break selectionLoop
            } catch FinderFileActionError.partialFailure(_, let completed, let failures) {
                result.outputs += completed
                result.failures += failures
            } catch {
                result.failures.append(.init(url: item, reason: error.localizedDescription))
            }
        }
        if !lines.isEmpty { result.text = lines.joined(separator: "\n") }
        return result
    }

    private static func readText(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= maximumTextBytes else {
            throw FinderFileActionError.unsupported(url, "Choose a regular UTF-8 text file smaller than 8 MB")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumTextBytes + 1) ?? Data()
        guard data.count <= maximumTextBytes, let text = String(data: data, encoding: .utf8) else {
            throw FinderFileActionError.unsupported(url, "The file is too large or is not UTF-8 text")
        }
        return text
    }
}
