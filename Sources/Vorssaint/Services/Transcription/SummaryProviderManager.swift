// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Runtime manager for local subscription inference providers (Claude Code,
/// Codex, Gemini CLI, Ollama, and Apple Intelligence). Discovers installed
/// CLIs, checks versions and available updates, runs safe one-click updates,
/// and invokes providers headlessly for transcript summarization.
final class SummaryProviderManager: ObservableObject, @unchecked Sendable {
    static let shared = SummaryProviderManager()

    struct ProviderState: Equatable, Identifiable, Sendable {
        let provider: SummaryInferenceProvider
        let executablePath: String?
        let installedVersion: String?
        let latestVersion: String?
        let models: [SummaryProviderSupport.ModelOption]
        let isReady: Bool
        let isUpdating: Bool
        let updateError: String?

        var id: SummaryInferenceProvider { provider }

        var hasUpdateAvailable: Bool {
            guard let installed = installedVersion, let latest = latestVersion else { return false }
            return SummaryProviderSupport.isVersion(latest, newerThan: installed)
        }

        var canUpdate: Bool {
            guard let path = executablePath else { return false }
            return SummaryProviderSupport.updateCommand(for: provider, executablePath: path) != nil
        }
    }

    @Published private(set) var states: [SummaryInferenceProvider: ProviderState] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var isCheckingUpdates = false
    @Published private(set) var lastUpdateCheckAt: Date?

    private var refreshTask: Task<Void, Never>?
    private var updateTasks: [SummaryInferenceProvider: Task<Void, Never>] = [:]

    private init() {
        var initial: [SummaryInferenceProvider: ProviderState] = [:]
        for provider in SummaryInferenceProvider.managedProviders {
            let desc = SummaryProviderSupport.descriptor(for: provider)
            initial[provider] = ProviderState(
                provider: provider,
                executablePath: nil,
                installedVersion: nil,
                latestVersion: nil,
                models: desc.defaultModels,
                isReady: provider == .appleIntelligence && Self.isAppleIntelligenceAvailable(),
                isUpdating: false,
                updateError: nil
            )
        }
        states = initial
    }

    var selectedProvider: SummaryInferenceProvider {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.audioTranscriptionSummaryProvider) ?? ""
        return SummaryInferenceProvider(rawValue: raw) ?? .auto
    }

    var selectedModel: String {
        UserDefaults.standard.string(forKey: DefaultsKey.audioTranscriptionSummaryModel) ?? ""
    }

    var updateChecksEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.audioTranscriptionSummaryProviderUpdateChecks)
    }

    func state(for provider: SummaryInferenceProvider) -> ProviderState {
        states[provider] ?? ProviderState(
            provider: provider,
            executablePath: nil,
            installedVersion: nil,
            latestVersion: nil,
            models: SummaryProviderSupport.descriptor(for: provider).defaultModels,
            isReady: false,
            isUpdating: false,
            updateError: nil
        )
    }

    func modelOptions(for provider: SummaryInferenceProvider) -> [SummaryProviderSupport.ModelOption] {
        let current = state(for: provider).models
        if !current.isEmpty { return current }
        return SummaryProviderSupport.descriptor(for: provider).defaultModels
    }

    /// Probes all local providers (CLI paths, installed versions, Ollama tags,
    /// Apple Intelligence availability) and optionally checks for CLI updates.
    func refreshProviders(checkUpdates: Bool = false) {
        refreshTask?.cancel()
        isRefreshing = true
        let shouldCheckUpdates = checkUpdates || (
            updateChecksEnabled
            && TelemetryPolicy.allowsAutomaticUpdateChecks()
            && (lastUpdateCheckAt == nil || Date().timeIntervalSince(lastUpdateCheckAt ?? .distantPast) > 3_600)
        )
        if shouldCheckUpdates {
            isCheckingUpdates = true
        }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            let probed = await Self.probeAllProviders()
            await MainActor.run {
                for (provider, next) in probed {
                    let prev = self.states[provider]
                    self.states[provider] = ProviderState(
                        provider: provider,
                        executablePath: next.executablePath,
                        installedVersion: next.installedVersion,
                        latestVersion: prev?.latestVersion,
                        models: next.models,
                        isReady: next.isReady,
                        isUpdating: prev?.isUpdating ?? false,
                        updateError: prev?.updateError
                    )
                }
                self.isRefreshing = false
            }

            guard shouldCheckUpdates, !Task.isCancelled else {
                await MainActor.run { self.isCheckingUpdates = false }
                return
            }

            let latestMap = await Self.fetchLatestVersions(for: probed)
            await MainActor.run {
                for (provider, latest) in latestMap {
                    guard let existing = self.states[provider] else { continue }
                    self.states[provider] = ProviderState(
                        provider: existing.provider,
                        executablePath: existing.executablePath,
                        installedVersion: existing.installedVersion,
                        latestVersion: latest,
                        models: existing.models,
                        isReady: existing.isReady,
                        isUpdating: existing.isUpdating,
                        updateError: existing.updateError
                    )
                }
                self.lastUpdateCheckAt = Date()
                self.isCheckingUpdates = false
            }
        }
    }

    /// Runs the detected package-manager update command for one CLI provider
    /// and re-probes its installed version afterward.
    func updateProvider(_ provider: SummaryInferenceProvider) {
        let current = state(for: provider)
        guard !current.isUpdating,
              let path = current.executablePath,
              let cmd = SummaryProviderSupport.updateCommand(for: provider, executablePath: path) else {
            return
        }
        updateTasks[provider]?.cancel()
        states[provider] = ProviderState(
            provider: current.provider,
            executablePath: current.executablePath,
            installedVersion: current.installedVersion,
            latestVersion: current.latestVersion,
            models: current.models,
            isReady: current.isReady,
            isUpdating: true,
            updateError: nil
        )

        updateTasks[provider] = Task { [weak self] in
            guard let self else { return }
            let result = await Self.runSubprocess(cmd, timeoutSeconds: 180)
            let reprobed = await Self.probeSingleProvider(provider)
            await MainActor.run {
                self.updateTasks[provider] = nil
                let existing = self.states[provider]
                let errMsg: String?
                if result.status == 0 {
                    errMsg = nil
                } else {
                    let tail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    let fallback = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    let raw = tail.isEmpty ? fallback : tail
                    errMsg = raw.isEmpty ? "Exit code \(result.status)" : String(raw.prefix(180))
                }
                self.states[provider] = ProviderState(
                    provider: provider,
                    executablePath: reprobed.executablePath,
                    installedVersion: reprobed.installedVersion,
                    latestVersion: existing?.latestVersion,
                    models: reprobed.models,
                    isReady: reprobed.isReady,
                    isUpdating: false,
                    updateError: errMsg
                )
            }
        }
    }

    // MARK: - Live Inference Execution

    enum InvocationError: LocalizedError {
        case providerUnavailable(String)
        case commandFailed(String)
        case emptyOutput

        var errorDescription: String? {
            switch self {
            case .providerUnavailable(let name):
                return "\(name) is not installed or running."
            case .commandFailed(let detail):
                return detail
            case .emptyOutput:
                return "Provider returned an empty summary."
            }
        }
    }

    /// Runs a headless local CLI subscription (`claude`, `codex`, `gemini`)
    /// with tool execution disabled and no persisted session.
    static func summarizeWithCLI(provider: SummaryInferenceProvider,
                                 executablePath: String,
                                 model: String?,
                                 transcript: String,
                                 instructions: String) async throws -> String {
        try Task.checkCancellation()
        var tempOutputURL: URL?
        if provider == .codex {
            tempOutputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("vorssaint-codex-summary-\(UUID().uuidString).txt")
        }
        defer {
            if let tempOutputURL {
                try? FileManager.default.removeItem(at: tempOutputURL)
            }
        }

        guard let spec = SummaryProviderSupport.summaryCommand(
            for: provider,
            executablePath: executablePath,
            model: model,
            transcript: transcript,
            instructions: instructions,
            codexOutputFile: tempOutputURL?.path
        ) else {
            throw InvocationError.providerUnavailable(SummaryProviderSupport.descriptor(for: provider).displayName)
        }

        let res = await runSubprocess(spec, timeoutSeconds: 120)
        try Task.checkCancellation()

        if let tempOutputURL,
           let fileText = try? String(contentsOf: tempOutputURL, encoding: .utf8) {
            let trimmed = fileText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        guard res.status == 0 else {
            let err = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let out = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = err.isEmpty ? out : err
            throw InvocationError.commandFailed(
                detail.isEmpty
                    ? "\(SummaryProviderSupport.descriptor(for: provider).displayName) exited with code \(res.status)."
                    : String(detail.prefix(240))
            )
        }

        let text = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw InvocationError.emptyOutput }
        return text
    }

    /// Runs a local Ollama `/api/generate` call against `127.0.0.1:11434`.
    static func summarizeWithOllama(model: String,
                                    transcript: String,
                                    instructions: String,
                                    baseURL: String = SummaryProviderSupport.defaultOllamaBaseURL) async throws -> String {
        try Task.checkCancellation()
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw InvocationError.providerUnavailable("Ollama")
        }
        let body: [String: Any] = [
            "model": model,
            "prompt": SummaryProviderSupport.summaryInputDocument(transcript: transcript, instructions: instructions),
            "stream": false,
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw InvocationError.commandFailed("Ollama returned HTTP \(code).")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = (obj["response"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw InvocationError.emptyOutput
        }
        return text
    }

    // MARK: - Probing Helpers

    static func probeAllProviders() async -> [SummaryInferenceProvider: ProviderState] {
        await withTaskGroup(of: (SummaryInferenceProvider, ProviderState).self) { group in
            for provider in SummaryInferenceProvider.managedProviders {
                group.addTask {
                    let state = await probeSingleProvider(provider)
                    return (provider, state)
                }
            }
            var result: [SummaryInferenceProvider: ProviderState] = [:]
            for await (provider, state) in group {
                result[provider] = state
            }
            return result
        }
    }

    static func probeSingleProvider(_ provider: SummaryInferenceProvider) async -> ProviderState {
        let desc = SummaryProviderSupport.descriptor(for: provider)
        switch provider {
        case .auto:
            return ProviderState(provider: .auto, executablePath: nil, installedVersion: nil, latestVersion: nil, models: [], isReady: true, isUpdating: false, updateError: nil)
        case .appleIntelligence:
            return ProviderState(
                provider: .appleIntelligence,
                executablePath: nil,
                installedVersion: nil,
                latestVersion: nil,
                models: [],
                isReady: isAppleIntelligenceAvailable(),
                isUpdating: false,
                updateError: nil
            )
        case .ollama:
            let path = desc.executableName.flatMap { SummaryProviderSupport.resolveExecutable(named: $0) }
            let version: String?
            if let path {
                let res = await runSubprocess(.init(executable: path, arguments: ["--version"], stdinText: nil), timeoutSeconds: 5)
                version = SummaryProviderSupport.parseSemanticVersion(from: res.stdout + "\n" + res.stderr)
            } else {
                version = nil
            }
            let models = await fetchOllamaTags()
            let list = [SummaryProviderSupport.ModelOption(id: "", label: "Default (first installed)")] + models
            return ProviderState(
                provider: .ollama,
                executablePath: path,
                installedVersion: version,
                latestVersion: nil,
                models: list,
                isReady: !models.isEmpty,
                isUpdating: false,
                updateError: nil
            )
        case .claude, .codex, .gemini:
            guard let name = desc.executableName,
                  let path = SummaryProviderSupport.resolveExecutable(named: name) else {
                return ProviderState(
                    provider: provider,
                    executablePath: nil,
                    installedVersion: nil,
                    latestVersion: nil,
                    models: desc.defaultModels,
                    isReady: false,
                    isUpdating: false,
                    updateError: nil
                )
            }
            let res = await runSubprocess(.init(executable: path, arguments: ["--version"], stdinText: nil), timeoutSeconds: 8)
            let version = SummaryProviderSupport.parseSemanticVersion(from: res.stdout + "\n" + res.stderr)
            return ProviderState(
                provider: provider,
                executablePath: path,
                installedVersion: version,
                latestVersion: nil,
                models: desc.defaultModels,
                isReady: true,
                isUpdating: false,
                updateError: nil
            )
        }
    }

    static func isAppleIntelligenceAvailable() -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }

    private static func fetchOllamaTags(baseURL: String = SummaryProviderSupport.defaultOllamaBaseURL) async -> [SummaryProviderSupport.ModelOption] {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return [] }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 2.5
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return []
        }
        return SummaryProviderSupport.parseOllamaModels(data: data)
    }

    private static func fetchLatestVersions(for states: [SummaryInferenceProvider: ProviderState]) async -> [SummaryInferenceProvider: String] {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6.0
        config.timeoutIntervalForResource = 10.0
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        return await withTaskGroup(of: (SummaryInferenceProvider, String?).self) { group in
            for (provider, state) in states where state.executablePath != nil {
                guard let url = SummaryProviderSupport.npmLatestURL(for: provider) else { continue }
                group.addTask {
                    var req = URLRequest(url: url)
                    req.setValue("Vorssaint/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
                    guard let (data, response) = try? await session.data(for: req),
                          let http = response as? HTTPURLResponse,
                          (200...299).contains(http.statusCode) else {
                        return (provider, nil)
                    }
                    return (provider, SummaryProviderSupport.parseNpmLatestVersion(data: data))
                }
            }
            var out: [SummaryInferenceProvider: String] = [:]
            for await (provider, latest) in group {
                if let latest { out[provider] = latest }
            }
            return out
        }
    }

    // MARK: - Subprocess Execution (Timeout + Cancellation + Enriched PATH)

    private struct SubprocessResult: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private static func runSubprocess(_ spec: SummaryProviderSupport.CommandSpec,
                                      timeoutSeconds: TimeInterval) async -> SubprocessResult {
        final class ProcessBox: @unchecked Sendable {
            let lock = NSLock()
            var process: Process?
            var cancelled = false
            func set(_ p: Process) {
                lock.lock()
                process = p
                let shouldTerminate = cancelled
                lock.unlock()
                if shouldTerminate, p.isRunning { p.terminate() }
            }
            func cancel() {
                lock.lock()
                cancelled = true
                let p = process
                lock.unlock()
                if let p, p.isRunning { p.terminate() }
            }
        }

        let box = ProcessBox()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: spec.executable)
                    process.arguments = spec.arguments
                    process.currentDirectoryURL = FileManager.default.temporaryDirectory

                    var env = ProcessInfo.processInfo.environment
                    let enrichedPath = SummaryProviderSupport.standardSearchDirectories().joined(separator: ":")
                    env["PATH"] = enrichedPath
                    env["NO_COLOR"] = "1"
                    env["CLICOLOR"] = "0"
                    env = TelemetryPolicy.claudeEnvironment(env)
                    env = TelemetryPolicy.codexEnvironment(env)
                    env = TelemetryPolicy.brewEnvironment(env)
                    process.environment = env

                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    process.standardOutput = outPipe
                    process.standardError = errPipe

                    var inPipe: Pipe?
                    if spec.stdinText != nil {
                        let pipe = Pipe()
                        process.standardInput = pipe
                        inPipe = pipe
                    } else {
                        process.standardInput = FileHandle.nullDevice
                    }

                    box.set(process)
                    do {
                        try process.run()
                    } catch {
                        cont.resume(returning: SubprocessResult(status: -1, stdout: "", stderr: error.localizedDescription))
                        return
                    }

                    let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                    watchdog.schedule(deadline: .now() + timeoutSeconds)
                    watchdog.setEventHandler {
                        if process.isRunning { process.terminate() }
                    }
                    watchdog.resume()

                    if let stdinText = spec.stdinText, let inPipe {
                        DispatchQueue.global(qos: .userInitiated).async {
                            if let data = stdinText.data(using: .utf8) {
                                try? inPipe.fileHandleForWriting.write(contentsOf: data)
                            }
                            try? inPipe.fileHandleForWriting.close()
                        }
                    }

                    let group = DispatchGroup()
                    final class DataBox: @unchecked Sendable { var data = Data() }
                    let outBox = DataBox()
                    let errBox = DataBox()

                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }

                    process.waitUntilExit()
                    watchdog.cancel()
                    group.wait()

                    cont.resume(returning: SubprocessResult(
                        status: process.terminationStatus,
                        stdout: String(decoding: outBox.data, as: UTF8.self),
                        stderr: String(decoding: errBox.data, as: UTF8.self)
                    ))
                }
            }
        } onCancel: {
            box.cancel()
        }
    }
}
