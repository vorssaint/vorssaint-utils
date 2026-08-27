// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ArchiveFailure: Error, Equatable {
    case noInput
    case duplicateSourceName(String)
    case commandFailed(String)
    case cannotPrepare
    case cannotPublish
    case cancelled
}

enum ArchiveOperationState: Equatable {
    case idle
    case running
    case completed(URL)
    case failed(ArchiveFailure)
    case cancelled
}

enum ArchiveSupport {
    static func archiveBaseName(for sources: [URL]) -> String {
        guard sources.count == 1, let source = sources.first else { return "Archive" }
        let values = try? source.resourceValues(forKeys: [.isDirectoryKey])
        let raw = values?.isDirectory == true
            ? source.lastPathComponent
            : source.deletingPathExtension().lastPathComponent
        return FileOutputSupport.sanitizedBaseName(raw, fileExtension: "zip")
    }

    static func duplicateTopLevelName(in sources: [URL]) -> String? {
        var seen = Set<String>()
        for source in sources {
            let name = source.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased()
            if !seen.insert(name).inserted { return source.lastPathComponent }
        }
        return nil
    }

    static func createArguments(sources: [URL], stagedOutput: URL,
                                excludesDSStore: Bool) -> [String] {
        var arguments = ["-a", "-cf", stagedOutput.path]
        if excludesDSStore { arguments += ["--exclude", ".DS_Store"] }
        for source in sources {
            arguments += ["-C", source.deletingLastPathComponent().path,
                          "./" + source.lastPathComponent]
        }
        return arguments
    }

    static func boundedFailureMessage(_ data: Data) -> String {
        let text = String(data: data.suffix(2_000), encoding: .utf8) ?? ""
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "The system archive tool failed." : clean
    }
}
