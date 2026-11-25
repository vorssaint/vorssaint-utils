// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// How much of the Finder selection a model may see. File contents are never
/// part of any level: the model gets names, never bytes.
enum AIBarContextLevel: String, CaseIterable {
    /// Nothing about the selection. The model sees the request alone, and
    /// commands refer to files through the names the person typed or globs.
    case none
    /// File names, extensions and whether each item is a folder. Commands are
    /// written with relative names and run inside the folder, so the model
    /// needs nothing more.
    case namesOnly
    /// Absolute paths as well.
    case fullPaths
}

/// What one selected item looks like to the model.
struct AIBarItem: Equatable {
    let url: URL
    let isDirectory: Bool
}

/// Where the model runs, which decides how much it may be told.
enum AIBarEndpoint {
    /// A model on this Mac or an address that never leaves the local network
    /// loopback. Only these are trusted with the fuller context by default.
    static func isLocal(_ baseURL: String) -> Bool {
        guard let host = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))?
            .host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
            || host.hasSuffix(".localhost")
    }

    /// `/chat/completions` below the base, tolerating a trailing slash and a
    /// base that was pasted with the path already on it.
    static func chatCompletionsURL(_ baseURL: String) -> URL? {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }
        if text.hasSuffix("/chat/completions") { text = String(text.dropLast("/chat/completions".count)) }
        guard let url = URL(string: text + "/chat/completions"),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    /// Plain http is only acceptable on this Mac; a key or a file name must
    /// not cross a network unencrypted.
    static func isTransportAcceptable(_ baseURL: String) -> Bool {
        guard let url = chatCompletionsURL(baseURL) else { return false }
        return url.scheme?.lowercased() == "https" || isLocal(baseURL)
    }
}

enum AIBarPrompt {
    /// The level a given endpoint is allowed, from the two settings.
    static func level(baseURL: String, local: AIBarContextLevel, remote: AIBarContextLevel) -> AIBarContextLevel {
        AIBarEndpoint.isLocal(baseURL) ? local : remote
    }

    /// The lines that describe the selection. Never reads a file.
    static func contextLines(items: [AIBarItem], folder: URL?, level: AIBarContextLevel,
                             limit: Int = 40) -> [String] {
        var lines: [String] = []
        guard level != .none else { return lines }
        for item in items.prefix(limit) {
            let kind = item.isDirectory ? "folder" : "file"
            switch level {
            case .none:
                continue
            case .namesOnly:
                lines.append("- \(kind): \(item.url.lastPathComponent)")
            case .fullPaths:
                lines.append("- \(kind): \(item.url.path)")
            }
        }
        if items.count > limit { lines.append("- and \(items.count - limit) more items") }
        if level == .fullPaths, let folder { lines.append("Current folder: \(folder.path)") }
        return lines
    }

    static let systemPrompt = """
    You turn a request about files on macOS into one zsh command. Reply with the command alone \
    inside a single ```sh code block and nothing else.
    Rules:
    - The command runs in the folder the user is looking at, so use relative names. Quote every \
    name that has spaces or special characters.
    - Use tools that ship with macOS (ls, mv, cp, mkdir, zip, ditto, sips, mdls, find, du, file, \
    textutil, pbcopy). Use Homebrew tools only when asked for.
    - Prefer a single, readable command. Do not use sudo.
    - Never delete anything permanently when moving to the Trash is enough: use \
    `mv -- NAME ~/.Trash/` instead of rm.
    - You cannot see inside files. If the request needs their contents, or is not about files, \
    reply with exactly: CANNOT
    """

    static func userMessage(request: String, contextLines: [String], level: AIBarContextLevel = .namesOnly) -> String {
        if level == .none {
            return "Request: \(request)\nThe selection is not shared. Use the names in the request, or globs such as *.png."
        }
        guard !contextLines.isEmpty else { return "Request: \(request)\nNothing is selected." }
        return "Selected items:\n" + contextLines.joined(separator: "\n") + "\n\nRequest: \(request)"
    }

    /// The command inside a model reply, or nil when it declined or said
    /// nothing usable. Small models wrap answers in prose, fences, prompts
    /// and quotes, so each of those is stripped.
    static func extractCommand(from reply: String) -> String? {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.uppercased() == "CANNOT" || text.uppercased().hasPrefix("CANNOT.") { return nil }

        if let open = text.range(of: "```") {
            var rest = text[open.upperBound...]
            if let newline = rest.firstIndex(of: "\n") {
                let tag = rest[..<newline].trimmingCharacters(in: .whitespaces)
                // A language tag sits on the opening line; anything else is the command.
                if tag.isEmpty || tag.range(of: "^[A-Za-z]+$", options: .regularExpression) != nil {
                    rest = rest[rest.index(after: newline)...]
                }
            }
            if let close = rest.range(of: "```") { rest = rest[..<close.lowerBound] }
            text = String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if text.hasPrefix("`"), text.hasSuffix("`"), text.count > 2 {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map { line -> String in
            var line = String(line)
            if line.hasPrefix("$ ") { line.removeFirst(2) }
            return line
        }
        // Comments the model added are not part of what runs.
        let command = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, command.uppercased() != "CANNOT", command.count <= 4000 else { return nil }
        return command
    }
}

/// What a command is about to do, read from its text before it runs. This is
/// a static look and not a simulation: it recognises the tools that change
/// things, and anything it does not recognise is treated as needing a look.
struct AIBarPrediction: Equatable {
    enum Effect: String, CaseIterable {
        case readsOnly, createsFiles, movesOrOverwrites, deletes, network, elevates, system, unknown
    }

    enum Risk: Int, Comparable {
        case low, review, dangerous
        static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }
    }

    let effects: [Effect]
    let risk: Risk
}

enum AIBarSafety {
    private static let readOnly: Set<String> = [
        "ls", "cat", "head", "tail", "wc", "file", "stat", "du", "df", "mdls", "mdfind", "find", "grep",
        "pwd", "echo", "printf", "sort", "uniq", "basename", "dirname", "realpath", "shasum", "md5",
        "sips", "tree", "sed", "open", "pbcopy", "date", "which", "xattr", "qlmanage", "bc", "awk", "cut", "tr"
    ]
    private static let creators: Set<String> = [
        "mkdir", "touch", "zip", "tar", "ditto", "ln", "textutil", "ffmpeg", "magick", "convert", "qpdf",
        "pandoc", "gs", "pdftotext", "gzip", "unzip", "cp"
    ]
    private static let movers: Set<String> = ["mv", "rename", "chmod", "chown", "chflags", "tee", "install"]
    private static let deleters: Set<String> = ["rm", "rmdir", "unlink", "srm", "trash"]
    private static let networkers: Set<String> = ["curl", "wget", "scp", "sftp", "ssh", "rsync", "nc", "ftp", "git", "brew", "pip", "pip3", "npm"]
    private static let system: Set<String> = [
        "diskutil", "dd", "mkfs", "newfs", "fdisk", "launchctl", "defaults", "kill", "killall", "pkill",
        "shutdown", "reboot", "halt", "csrutil", "spctl", "tmutil", "hdiutil", "systemsetup", "osascript"
    ]

    /// The commands of a line: the first word after every `;`, `&&`, `||`,
    /// `|`, `&`, newline or `$(`, skipping env assignments and `sudo`/`command`.
    static func commandWords(_ command: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var atStart = true
        var escaped = false
        func finish() {
            if atStart, !current.isEmpty {
                let isAssignment = current.range(of: "^[A-Za-z_][A-Za-z0-9_]*=", options: .regularExpression) != nil
                if !isAssignment {
                    words.append(current.split(separator: "/").last.map(String.init) ?? current)
                    atStart = false
                }
            }
            current = ""
        }
        let characters = Array(command)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            defer { index += 1 }
            if escaped { current.append(character); escaped = false; continue }
            if character == "\\" { escaped = true; continue }
            if let q = quote {
                if character == q { quote = nil } else { current.append(character) }
                continue
            }
            if character == "'" || character == "\"" { quote = character; continue }
            if character == "(" || character == ")" || character == "{" || character == "}" || character == "`" {
                finish(); atStart = true; continue
            }
            if character == ";" || character == "|" || character == "&" || character == "\n" {
                finish(); atStart = true; continue
            }
            if character == " " || character == "\t" { finish(); continue }
            current.append(character)
        }
        finish()
        return words
    }

    static func predict(_ command: String) -> AIBarPrediction {
        let words = commandWords(command)
        var effects = Set<AIBarPrediction.Effect>()
        var risk = AIBarPrediction.Risk.low
        func raise(_ level: AIBarPrediction.Risk) { if level > risk { risk = level } }

        let text = command
        for word in words {
            if readOnly.contains(word) { effects.insert(.readsOnly) }
            else if creators.contains(word) { effects.insert(.createsFiles) }
            else if movers.contains(word) { effects.insert(.movesOrOverwrites); raise(.review) }
            else if deleters.contains(word) { effects.insert(.deletes); raise(.review) }
            else if networkers.contains(word) { effects.insert(.network); raise(.review) }
            else if system.contains(word) { effects.insert(.system); raise(.review) }
            else if word == "sudo" { effects.insert(.elevates); raise(.dangerous) }
            else if word == "eval" || word == "source" || word == "." || word == "sh" || word == "bash" || word == "zsh" {
                effects.insert(.unknown); raise(.dangerous)
            } else { effects.insert(.unknown); raise(.review) }
        }
        if words.isEmpty { effects.insert(.unknown); raise(.review) }

        // `find ... -delete` / `-exec rm`, and `cp`/`ditto` over an existing file, are real changes.
        if text.range(of: #"\bfind\b[^|;&]*\s-(delete|exec|execdir|ok)\b"#, options: .regularExpression) != nil {
            effects.insert(.deletes); raise(.review)
        }
        if text.range(of: #"(^|[^>])>>?\s*[^\s&|]"#, options: .regularExpression) != nil,
           text.range(of: #">\s*/dev/null"#, options: .regularExpression) == nil {
            effects.insert(.movesOrOverwrites); raise(.review)
        }
        if text.range(of: #"\bcp\b(?![^|;&]*\s-[a-zA-Z]*n)"#, options: .regularExpression) != nil {
            effects.insert(.movesOrOverwrites); raise(.review)
        }
        if text.range(of: #"\bsed\b[^|;&]*\s-[a-zA-Z]*i"#, options: .regularExpression) != nil {
            effects.insert(.movesOrOverwrites); raise(.review)
        }

        // The shapes that cannot be taken back or that run unseen code.
        let dangerous: [String] = [
            #"\brm\b[^|;&]*\s-[a-zA-Z]*[rf][a-zA-Z]*\s+(/|~|\$HOME|\*|\.|\.\.)(\s|/|$)"#,
            #"\brm\b[^|;&]*\s-[a-zA-Z]*r[a-zA-Z]*f|\brm\b[^|;&]*\s-[a-zA-Z]*f[a-zA-Z]*r"#,
            #"(curl|wget)[^|;&]*\|\s*(sudo\s+)?(sh|bash|zsh)\b"#,
            #"\bdd\b[^|;&]*\bof="#,
            #"\bmkfs|\bnewfs|\bdiskutil\s+(erase|partition|apfs\s+delete|secureErase|zeroDisk)"#,
            #":\(\)\s*\{"#,
            #"\bchmod\s+(-[a-zA-Z]+\s+)*[0-7]*777\b[^|;&]*(/|~)\s*$"#,
            #">\s*/dev/(disk|rdisk)"#,
            #"\bsudo\b"#
        ]
        for pattern in dangerous where text.range(of: pattern, options: .regularExpression) != nil {
            raise(.dangerous)
            if pattern.contains("sudo") { effects.insert(.elevates) }
        }
        if effects.count > 1 { effects.remove(.readsOnly) }
        if effects.isEmpty { effects.insert(.unknown); raise(.review) }
        return AIBarPrediction(effects: AIBarPrediction.Effect.allCases.filter(effects.contains), risk: risk)
    }

    /// Presses of the Run button a command takes. Nothing runs by itself. The
    /// person reads the predicted effects and presses once; a dangerous
    /// command asks for a second, deliberate press.
    static func pressesToRun(_ prediction: AIBarPrediction) -> Int {
        prediction.risk == .dangerous ? 2 : 1
    }
}
