// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Summary inference provider preference, modeled after multi-provider local
/// CLI orchestration: uses existing local CLI subscriptions (Claude Code,
/// Codex, Gemini CLI) or local Ollama before falling back to Apple
/// Intelligence and local extractive summarization.
enum SummaryInferenceProvider: String, CaseIterable, Identifiable, Sendable {
    case auto
    case claude
    case codex
    case gemini
    case ollama
    case appleIntelligence

    var id: String { rawValue }

    /// Concrete providers that appear in the provider management list.
    static let managedProviders: [SummaryInferenceProvider] = [
        .claude, .codex, .gemini, .ollama, .appleIntelligence,
    ]
}

/// How an installed CLI provider can be updated in place.
enum SummaryProviderInstallMethod: String, Equatable, Sendable {
    case claudeNative
    case homebrew
    case bun
    case npm
    case unknown
}

/// Pure, Foundation-only provider discovery, semver comparison, CLI argument
/// construction, and update-command planning for summary inference providers.
enum SummaryProviderSupport {
    struct ModelOption: Equatable, Identifiable, Sendable {
        let id: String
        let label: String
    }

    struct ProviderDescriptor: Equatable, Sendable {
        let provider: SummaryInferenceProvider
        let displayName: String
        let executableName: String?
        let npmPackage: String?
        let brewFormula: String?
        let defaultModels: [ModelOption]
    }

    struct CommandSpec: Equatable, Sendable {
        let executable: String
        let arguments: [String]
        let stdinText: String?
    }

    static let defaultOllamaBaseURL = "http://127.0.0.1:11434"

    static func descriptor(for provider: SummaryInferenceProvider) -> ProviderDescriptor {
        switch provider {
        case .auto:
            return ProviderDescriptor(
                provider: .auto,
                displayName: "Auto",
                executableName: nil,
                npmPackage: nil,
                brewFormula: nil,
                defaultModels: []
            )
        case .claude:
            return ProviderDescriptor(
                provider: .claude,
                displayName: "Claude Code",
                executableName: "claude",
                npmPackage: "@anthropic-ai/claude-code",
                brewFormula: "claude-code",
                defaultModels: [
                    ModelOption(id: "", label: "Default (CLI setting)"),
                    ModelOption(id: "sonnet", label: "Claude Sonnet"),
                    ModelOption(id: "haiku", label: "Claude Haiku"),
                    ModelOption(id: "opus", label: "Claude Opus"),
                ]
            )
        case .codex:
            return ProviderDescriptor(
                provider: .codex,
                displayName: "Codex",
                executableName: "codex",
                npmPackage: "@openai/codex",
                brewFormula: "codex",
                defaultModels: [
                    ModelOption(id: "", label: "Default (CLI setting)"),
                    ModelOption(id: "gpt-5.4-mini", label: "GPT-5.4 Mini"),
                    ModelOption(id: "gpt-5.4", label: "GPT-5.4"),
                    ModelOption(id: "o4-mini", label: "o4-mini"),
                ]
            )
        case .gemini:
            return ProviderDescriptor(
                provider: .gemini,
                displayName: "Gemini CLI",
                executableName: "gemini",
                npmPackage: "@google/gemini-cli",
                brewFormula: "gemini-cli",
                defaultModels: [
                    ModelOption(id: "", label: "Default (CLI setting)"),
                    ModelOption(id: "gemini-2.5-flash", label: "Gemini 2.5 Flash"),
                    ModelOption(id: "gemini-2.5-pro", label: "Gemini 2.5 Pro"),
                ]
            )
        case .ollama:
            return ProviderDescriptor(
                provider: .ollama,
                displayName: "Ollama",
                executableName: "ollama",
                npmPackage: nil,
                brewFormula: "ollama",
                defaultModels: [
                    ModelOption(id: "", label: "Default (first installed)"),
                ]
            )
        case .appleIntelligence:
            return ProviderDescriptor(
                provider: .appleIntelligence,
                displayName: "Apple Intelligence",
                executableName: nil,
                npmPackage: nil,
                brewFormula: nil,
                defaultModels: []
            )
        }
    }

    /// Standard macOS search directories so GUI launches (which do not inherit
    /// interactive shell profiles) still locate local CLI subscriptions.
    static func standardSearchDirectories(homeDirectory: String = NSHomeDirectory(),
                                          environmentPath: String? = ProcessInfo.processInfo.environment["PATH"]) -> [String] {
        var dirs: [String] = [
            "\(homeDirectory)/.local/bin",
            "\(homeDirectory)/.bun/bin",
            "\(homeDirectory)/.volta/bin",
            "\(homeDirectory)/.npm-global/bin",
            "\(homeDirectory)/.cargo/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        if let envPath = environmentPath, !envPath.isEmpty {
            for entry in envPath.split(separator: ":").map(String.init) where !entry.isEmpty {
                dirs.append(entry)
            }
        }
        var seen = Set<String>()
        return dirs.filter { seen.insert($0).inserted }
    }

    /// Locates an executable by name across `searchDirectories` (including
    /// versioned `~/.nvm/versions/node/*/bin` paths).
    static func resolveExecutable(named name: String,
                                  homeDirectory: String = NSHomeDirectory(),
                                  environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
                                  isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        for dir in standardSearchDirectories(homeDirectory: homeDirectory, environmentPath: environmentPath) {
            let candidate = "\(dir)/\(name)"
            if isExecutable(candidate) {
                return candidate
            }
        }
        let nvmRoot = "\(homeDirectory)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmRoot) {
            for version in versions.sorted().reversed() {
                let candidate = "\(nvmRoot)/\(version)/bin/\(name)"
                if isExecutable(candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    /// Extracts the first semantic version (`major.minor.patch`) from CLI
    /// `--version` output such as `"2.1.332 (Claude Code)"` or `"codex-cli 0.172.0"`.
    static func parseSemanticVersion(from text: String) -> String? {
        let pattern = #"\b(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    /// Returns true when `latest` is strictly newer than `current` using
    /// numeric dot-separated comparison (ignoring prerelease suffixes).
    static func isVersion(_ latest: String, newerThan current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            let core = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
            return core.split(separator: ".").compactMap { Int($0) }
        }
        let a = parts(latest)
        let b = parts(current)
        guard !a.isEmpty, !b.isEmpty else { return false }
        let count = max(a.count, b.count)
        for idx in 0..<count {
            let lhs = idx < a.count ? a[idx] : 0
            let rhs = idx < b.count ? b[idx] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    /// Infers how a CLI was installed from its executable path so updates run
    /// through the matching package manager without breaking installations.
    static func detectInstallMethod(provider: SummaryInferenceProvider,
                                    executablePath: String) -> SummaryProviderInstallMethod {
        let lower = executablePath.lowercased()
        if provider == .claude, lower.contains("/.local/bin/") {
            return .claudeNative
        }
        if lower.contains("/opt/homebrew/") || lower.contains("/cellar/") || lower.contains("/homebrew/") {
            return .homebrew
        }
        if lower.contains("/.bun/") {
            return .bun
        }
        if lower.contains("/node_modules/") || lower.contains("/.nvm/") || lower.contains("/.volta/") || lower.contains("/npm") || lower.hasPrefix("/usr/local/bin/") {
            return .npm
        }
        return provider == .claude ? .claudeNative : .unknown
    }

    /// Builds a non-interactive update command for `provider` using the
    /// detected package manager.
    static func updateCommand(for provider: SummaryInferenceProvider,
                              executablePath: String,
                              resolveTool: (String) -> String? = { resolveExecutable(named: $0) }) -> CommandSpec? {
        let info = descriptor(for: provider)
        let method = detectInstallMethod(provider: provider, executablePath: executablePath)
        switch method {
        case .claudeNative:
            return CommandSpec(executable: executablePath, arguments: ["update"], stdinText: nil)
        case .homebrew:
            guard let formula = info.brewFormula, let brew = resolveTool("brew") else { return nil }
            return CommandSpec(executable: brew, arguments: ["upgrade", formula], stdinText: nil)
        case .bun:
            guard let pkg = info.npmPackage, let bun = resolveTool("bun") else { return nil }
            return CommandSpec(executable: bun, arguments: ["add", "-g", "\(pkg)@latest"], stdinText: nil)
        case .npm:
            guard let pkg = info.npmPackage, let npm = resolveTool("npm") else { return nil }
            return CommandSpec(executable: npm, arguments: ["install", "-g", "\(pkg)@latest"], stdinText: nil)
        case .unknown:
            if let pkg = info.npmPackage, let npm = resolveTool("npm") {
                return CommandSpec(executable: npm, arguments: ["install", "-g", "\(pkg)@latest"], stdinText: nil)
            }
            if let formula = info.brewFormula, let brew = resolveTool("brew") {
                return CommandSpec(executable: brew, arguments: ["upgrade", formula], stdinText: nil)
            }
            return nil
        }
    }

    /// Builds the unified user prompt sent to any local subscription CLI or
    /// Ollama model, keeping instructions clear and returning only the summary.
    static func summaryInputDocument(transcript: String, instructions: String) -> String {
        let resolved = AudioTranscriptionSupport.resolvedSummaryPrompt(instructions)
        return """
        Follow these instructions carefully and return only the summary in clean Markdown (no preamble or meta commentary). Match the primary language of the transcript unless the instructions ask for another language.

        Instructions:
        \(resolved)

        Transcript:
        \(transcript)
        """
    }

    /// Builds a headless, tool-disabled, ephemeral invocation for a local CLI
    /// subscription so it summarizes text cleanly without touching local files
    /// or saving chat sessions.
    static func summaryCommand(for provider: SummaryInferenceProvider,
                               executablePath: String,
                               model: String?,
                               transcript: String,
                               instructions: String,
                               codexOutputFile: String? = nil) -> CommandSpec? {
        let payload = summaryInputDocument(transcript: transcript, instructions: instructions)
        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch provider {
        case .claude:
            var args = [
                "-p",
                "--no-session-persistence",
                "--tools", "",
                "--output-format", "text",
            ]
            if !trimmedModel.isEmpty {
                args += ["--model", trimmedModel]
            }
            return CommandSpec(executable: executablePath, arguments: args, stdinText: payload)
        case .codex:
            var args = [
                "exec",
                "--ephemeral",
                "--skip-git-repo-check",
                "--sandbox", "read-only",
            ]
            if !trimmedModel.isEmpty {
                args += ["-m", trimmedModel]
            }
            if let codexOutputFile, !codexOutputFile.isEmpty {
                args += ["-o", codexOutputFile]
            }
            args.append("-")
            return CommandSpec(executable: executablePath, arguments: args, stdinText: payload)
        case .gemini:
            var args = [
                "-p",
                "Summarize the transcript provided on stdin following the embedded instructions. Return only the summary.",
            ]
            if !trimmedModel.isEmpty {
                args += ["-m", trimmedModel]
            }
            return CommandSpec(executable: executablePath, arguments: args, stdinText: payload)
        case .auto, .ollama, .appleIntelligence:
            return nil
        }
    }

    /// Ordered provider cascade used when `.auto` is selected.
    static func autoResolutionOrder(availableCLIProviders: Set<SummaryInferenceProvider>,
                                    ollamaReady: Bool) -> [SummaryInferenceProvider] {
        var order: [SummaryInferenceProvider] = []
        for cli in [SummaryInferenceProvider.claude, .codex, .gemini] where availableCLIProviders.contains(cli) {
            order.append(cli)
        }
        if ollamaReady {
            order.append(.ollama)
        }
        order.append(.appleIntelligence)
        return order
    }

    /// Parses Ollama `/api/tags` JSON into sorted `ModelOption` entries.
    static func parseOllamaModels(data: Data) -> [ModelOption] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [[String: Any]] else {
            return []
        }
        var names: [String] = []
        for entry in models {
            if let name = entry["name"] as? String, !name.isEmpty {
                names.append(name)
            }
        }
        return names.sorted().map { ModelOption(id: $0, label: $0) }
    }

    /// Parses npm registry `/latest` JSON (`{"version": "x.y.z"}`).
    static func parseNpmLatestVersion(data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = obj["version"] as? String else {
            return nil
        }
        return parseSemanticVersion(from: version)
    }

    /// Returns the npm registry URL for checking latest CLI version (nil for
    /// providers without an npm package).
    static func npmLatestURL(for provider: SummaryInferenceProvider) -> URL? {
        guard let pkg = descriptor(for: provider).npmPackage else { return nil }
        return URL(string: "https://registry.npmjs.org/\(pkg)/latest")
    }
}
