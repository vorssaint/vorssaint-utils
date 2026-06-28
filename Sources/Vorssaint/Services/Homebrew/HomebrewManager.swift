// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

final class HomebrewManager: ObservableObject {
    static let shared = HomebrewManager()

    @Published private(set) var brewPath: String?
    @Published private(set) var installed: [HomebrewPackage] = []
    @Published private(set) var searchResults: [HomebrewPackage] = []
    @Published private(set) var selectedPackage: HomebrewPackage?
    @Published private(set) var isLoadingInstalled = false
    @Published private(set) var isLoadingOutdated = false
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingPopularity = false
    @Published private(set) var isLoadingDetails = false
    @Published private(set) var operation: HomebrewOperation?
    @Published private(set) var operationStatus: HomebrewOperationStatus?
    @Published private(set) var log = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var terminalFallbackCommand: String?
    @Published private(set) var didOpenInstaller = false
    @Published private(set) var isShellConfigured = true
    @Published private(set) var shellConfigProfilePath: String?
    @Published private(set) var didOpenShellConfig = false
    @Published private(set) var outdatedPackagesByID: [String: HomebrewPackageUpdate] = [:]

    private let workQueue = DispatchQueue(label: "com.vorssaint.homebrew", qos: .userInitiated)
    private var searchGeneration = 0
    private var detailsGeneration = 0
    private var outdatedGeneration = 0
    private var currentSearchKind: HomebrewPackageKind?
    private var popularityCache: [HomebrewPackageKind: PopularityCacheEntry] = [:]
    private var popularityLoads: Set<HomebrewPackageKind> = []
    private var activeProcess: Process?
    private var cancelRequested = false
    private var completedOperationCleanup: DispatchWorkItem?
    private lazy var analyticsSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 8
        return URLSession(configuration: configuration)
    }()

    var isBusy: Bool {
        isLoadingInstalled || isSearching || isLoadingDetails || operation != nil
    }

    var outdatedCount: Int {
        outdatedPackagesByID.count
    }

    private init() {
        brewPath = detectBrewPath()
    }

    func refreshInstalled() {
        guard let brewPath = detectBrewPath() else {
            self.brewPath = nil
            installed = []
            searchResults = []
            selectedPackage = nil
            outdatedGeneration += 1
            outdatedPackagesByID = [:]
            isLoadingOutdated = false
            errorMessage = nil
            isShellConfigured = true
            shellConfigProfilePath = nil
            didOpenShellConfig = false
            return
        }
        self.brewPath = brewPath
        updateShellConfigStatus(brewPath: brewPath)
        isLoadingInstalled = true
        errorMessage = nil
        let command = HomebrewCommandBuilder.installed(brewPath: brewPath)
        run(command) { [weak self] status, output in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingInstalled = false
                guard status == 0 else {
                    self.errorMessage = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.outdatedGeneration += 1
                    self.outdatedPackagesByID = [:]
                    self.isLoadingOutdated = false
                    return
                }
                do {
                    self.installed = try HomebrewParser.parseInfoCommandOutput(output).map(self.packageEnriched)
                    self.didOpenInstaller = false
                    if let selected = self.selectedPackage {
                        self.selectedPackage = self.packageEnriched(self.installed.first { $0.id == selected.id } ?? selected)
                    }
                    self.refreshOutdated(brewPath: brewPath)
                } catch {
                    self.errorMessage = error.localizedDescription
                    self.outdatedGeneration += 1
                    self.outdatedPackagesByID = [:]
                    self.isLoadingOutdated = false
                }
            }
        }
    }

    func search(query: String, kind: HomebrewPackageKind) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        guard let brewPath = brewPath ?? detectBrewPath() else {
            self.brewPath = nil
            searchResults = []
            return
        }
        self.brewPath = brewPath
        searchGeneration += 1
        let generation = searchGeneration
        currentSearchKind = kind
        isSearching = true
        errorMessage = nil
        let command = HomebrewCommandBuilder.search(brewPath: brewPath, kind: kind, query: trimmed)
        run(command) { [weak self] status, output in
            DispatchQueue.main.async {
                guard let self, generation == self.searchGeneration else { return }
                self.isSearching = false
                if status == 0 {
                    let packages = HomebrewParser.parseSearchOutput(output,
                                                                    kind: kind,
                                                                    installed: self.installed)
                    self.searchResults = self.packagesEnriched(packages, kind: kind)
                    if !packages.isEmpty {
                        self.loadPopularityIfNeeded(kind: kind)
                    }
                } else if output.localizedCaseInsensitiveContains("No formulae or casks found") {
                    self.searchResults = []
                } else {
                    self.searchResults = []
                    self.errorMessage = output.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }

    func select(_ package: HomebrewPackage) {
        selectedPackage = package
        guard let brewPath = brewPath ?? detectBrewPath() else { return }
        detailsGeneration += 1
        let generation = detailsGeneration
        isLoadingDetails = true
        errorMessage = nil
        let command = HomebrewCommandBuilder.details(brewPath: brewPath, package: package)
        run(command) { [weak self] status, output in
            DispatchQueue.main.async {
                guard let self, generation == self.detailsGeneration else { return }
                self.isLoadingDetails = false
                guard status == 0 else {
                    self.errorMessage = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    return
                }
                do {
                    if let detail = try HomebrewParser.parseInfoCommandOutput(output).first {
                        self.selectedPackage = self.packageEnriched(detail)
                    }
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func clearSelection() {
        detailsGeneration += 1
        selectedPackage = nil
        isLoadingDetails = false
    }

    func install(_ package: HomebrewPackage) {
        perform(.install, package: package)
    }

    func uninstall(_ package: HomebrewPackage) {
        perform(.uninstall, package: package)
    }

    func upgrade(_ package: HomebrewPackage) {
        perform(.upgrade, package: package)
    }

    func upgradeAll() {
        perform(.upgradeAll, package: nil)
    }

    func updateHomebrew() {
        perform(.updateHomebrew, package: nil)
    }

    func cancelOperation() {
        guard operation != nil else { return }
        cancelRequested = true
        activeProcess?.terminate()
        appendLog("\nCancelled.\n")
    }

    func clearLog() {
        completedOperationCleanup?.cancel()
        completedOperationCleanup = nil
        log = ""
        terminalFallbackCommand = nil
        if operation == nil {
            operationStatus = nil
        }
    }

    func openTerminalFallback() {
        guard let command = terminalFallbackCommand else { return }
        openTerminal(command: command)
    }

    func openHomebrewInstaller() {
        errorMessage = nil
        if openTerminal(command: HomebrewCommandBuilder.installerCommand) {
            didOpenInstaller = true
        }
    }

    func openShellConfiguration() {
        guard let brewPath = brewPath ?? detectBrewPath() else { return }
        self.brewPath = brewPath
        errorMessage = nil
        let command = HomebrewCommandBuilder.shellConfigCommand(brewPath: brewPath)
        if openTerminal(command: command) {
            didOpenShellConfig = true
        }
    }

    func refreshShellConfigurationStatus() {
        guard let brewPath = brewPath ?? detectBrewPath() else {
            isShellConfigured = true
            shellConfigProfilePath = nil
            didOpenShellConfig = false
            return
        }
        updateShellConfigStatus(brewPath: brewPath)
    }

    @discardableResult
    private func openTerminal(command: String) -> Bool {
        let source = """
        tell application "Terminal"
            activate
            do script \(appleScriptString(command))
        end tell
        """
        // In-process Apple Events (see AppleScriptRunner): the Terminal Automation
        // consent is attributed to this app and re-requested if it was lost,
        // instead of a fragile osascript subprocess. Same permission as before.
        let result = AppleScriptRunner.run(source)
        if !result.ok {
            errorMessage = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return false
        }
        return true
    }

    private func perform(_ action: HomebrewOperation.Action, package: HomebrewPackage?) {
        guard operation == nil else { return }
        guard let brewPath = brewPath ?? detectBrewPath() else { return }
        let command: HomebrewCommand
        switch action {
        case .install:
            guard let package,
                  HomebrewCommandBuilder.isValidToken(package.name) else { return }
            command = HomebrewCommandBuilder.install(brewPath: brewPath, package: package)
        case .uninstall:
            guard let package,
                  HomebrewCommandBuilder.isValidToken(package.name) else { return }
            command = HomebrewCommandBuilder.uninstall(brewPath: brewPath, package: package)
        case .upgrade:
            guard let package,
                  HomebrewCommandBuilder.isValidToken(package.name) else { return }
            command = HomebrewCommandBuilder.upgrade(brewPath: brewPath, package: package)
        case .upgradeAll:
            command = HomebrewCommandBuilder.upgradeAll(brewPath: brewPath)
        case .updateHomebrew:
            command = HomebrewCommandBuilder.update(brewPath: brewPath)
        }
        operation = HomebrewOperation(action: action, package: package)
        operationStatus = HomebrewOperationStatus(action: action,
                                                  package: package,
                                                  phase: initialPhase(for: action),
                                                  result: .running,
                                                  progressFraction: nil,
                                                  startedAt: Date(),
                                                  finishedAt: nil,
                                                  lastActivity: nil)
        terminalFallbackCommand = nil
        errorMessage = nil
        cancelRequested = false
        completedOperationCleanup?.cancel()
        completedOperationCleanup = nil
        log = ""
        runStreaming(command,
                     onOutput: { [weak self] chunk in
                         self?.appendLog(chunk)
                         self?.updateOperationStatus(from: chunk, action: action)
                     }) { [weak self] status, output in
            DispatchQueue.main.async {
                guard let self else { return }
                self.activeProcess = nil
                self.operation = nil
                if status == 0 {
                    self.markOperationComplete(result: .succeeded,
                                               phase: .refreshing,
                                               activity: nil)
                    self.refreshInstalled()
                    if let package {
                        self.select(package)
                    }
                } else if self.cancelRequested {
                    self.markOperationComplete(result: .cancelled,
                                               phase: self.operationStatus?.phase ?? .finalizing,
                                               activity: nil)
                } else if HomebrewCommandBuilder.needsTerminalFallback(output: output) {
                    self.terminalFallbackCommand = HomebrewCommandBuilder.shellCommand(command)
                    self.markOperationComplete(result: .needsTerminal,
                                               phase: self.operationStatus?.phase ?? .finalizing,
                                               activity: HomebrewProgressParser.visibleError(from: output))
                } else {
                    let message = HomebrewProgressParser.visibleError(from: output)
                    self.errorMessage = message.isEmpty ? output.trimmingCharacters(in: .whitespacesAndNewlines) : message
                    self.markOperationComplete(result: .failed,
                                               phase: self.operationStatus?.phase ?? .finalizing,
                                               activity: self.errorMessage)
                }
                self.cancelRequested = false
            }
        }
    }

    private func updateOperationStatus(from chunk: String, action: HomebrewOperation.Action) {
        guard var status = operationStatus, status.isActive else { return }
        if let phase = HomebrewProgressParser.phase(in: chunk, action: action) {
            status.phase = phase
        }
        if let progress = HomebrewProgressParser.progressFraction(in: chunk) {
            status.progressFraction = progress
        }
        if let activity = HomebrewProgressParser.activity(in: chunk) {
            status.lastActivity = activity
        }
        operationStatus = status
    }

    private func initialPhase(for action: HomebrewOperation.Action) -> HomebrewOperationPhase {
        switch action {
        case .install, .upgrade, .upgradeAll, .updateHomebrew:
            return .preparing
        case .uninstall:
            return .uninstalling
        }
    }

    private func updateShellConfigStatus(brewPath: String) {
        let expectedLine = HomebrewCommandBuilder.shellEnvLine(brewPath: brewPath)
        let primaryPath = HomebrewCommandBuilder.shellProfilePath()
        let paths = HomebrewCommandBuilder.shellProfilePathsToCheck()
        shellConfigProfilePath = primaryPath
        isShellConfigured = paths.contains { path in
            guard let contents = try? String(contentsOfFile: path) else { return false }
            return contents.contains(expectedLine)
        }
        if isShellConfigured {
            didOpenShellConfig = false
        }
    }

    private func markOperationComplete(result: HomebrewOperationResult,
                                       phase: HomebrewOperationPhase,
                                       activity: String?) {
        guard var status = operationStatus else { return }
        status.result = result
        status.phase = phase
        status.finishedAt = Date()
        if result == .succeeded {
            status.progressFraction = 1
        }
        if let activity, !activity.isEmpty {
            status.lastActivity = activity
        }
        operationStatus = status
        scheduleCompletedOperationCleanup(result: result,
                                          targetID: status.targetID,
                                          finishedAt: status.finishedAt)
    }

    private func loadPopularityIfNeeded(kind: HomebrewPackageKind) {
        if popularityCache[kind]?.isFresh == true {
            applyPopularityToCurrentSearch(kind: kind)
            return
        }
        guard !popularityLoads.contains(kind) else { return }
        popularityLoads.insert(kind)
        isLoadingPopularity = true
        let url = HomebrewAnalytics.url(kind: kind)
        analyticsSession.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.popularityLoads.remove(kind)
                self.isLoadingPopularity = !self.popularityLoads.isEmpty
                guard let data,
                      let values = try? HomebrewAnalytics.parse(data, kind: kind) else { return }
                self.popularityCache[kind] = PopularityCacheEntry(values: values, fetchedAt: Date())
                self.applyPopularityToCurrentSearch(kind: kind)
            }
        }.resume()
    }

    private func applyPopularityToCurrentSearch(kind: HomebrewPackageKind) {
        guard currentSearchKind == kind else { return }
        searchResults = packagesEnriched(searchResults, kind: kind)
        if let selectedPackage, selectedPackage.kind == kind {
            self.selectedPackage = packageEnriched(selectedPackage)
        }
    }

    private func packagesApplyingPopularity(_ packages: [HomebrewPackage],
                                            kind: HomebrewPackageKind) -> [HomebrewPackage] {
        guard let cache = popularityCache[kind], cache.isFresh else {
            return packages
        }
        return HomebrewAnalytics.enrichAndSort(packages, popularity: cache.values)
    }

    private func packageApplyingPopularity(_ package: HomebrewPackage) -> HomebrewPackage {
        guard let popularity = popularityCache[package.kind]?.values[package.name] else {
            return package
        }
        var copy = package
        copy.popularity = popularity
        return copy
    }

    private func refreshOutdated(brewPath: String) {
        outdatedGeneration += 1
        let generation = outdatedGeneration
        isLoadingOutdated = true
        let command = HomebrewCommandBuilder.outdated(brewPath: brewPath)
        run(command) { [weak self] status, output in
            DispatchQueue.main.async {
                guard let self, generation == self.outdatedGeneration else { return }
                self.isLoadingOutdated = false
                guard status == 0,
                      let updates = try? HomebrewParser.parseOutdatedCommandOutput(output) else {
                    self.outdatedPackagesByID = [:]
                    self.applyOutdatedToCurrentPackages()
                    return
                }
                self.outdatedPackagesByID = updates
                self.applyOutdatedToCurrentPackages()
            }
        }
    }

    private func applyOutdatedToCurrentPackages() {
        installed = installed.map(packageApplyingOutdated)
        searchResults = searchResults.map(packageApplyingOutdated)
        if let selectedPackage {
            self.selectedPackage = packageApplyingOutdated(selectedPackage)
        }
    }

    private func packagesEnriched(_ packages: [HomebrewPackage],
                                  kind: HomebrewPackageKind) -> [HomebrewPackage] {
        packagesApplyingPopularity(packages, kind: kind).map(packageApplyingOutdated)
    }

    private func packageEnriched(_ package: HomebrewPackage) -> HomebrewPackage {
        packageApplyingOutdated(packageApplyingPopularity(package))
    }

    private func packageApplyingOutdated(_ package: HomebrewPackage) -> HomebrewPackage {
        var copy = package
        copy.update = outdatedPackagesByID[package.id]
        return copy
    }

    private func scheduleCompletedOperationCleanup(result: HomebrewOperationResult,
                                                   targetID: String,
                                                   finishedAt: Date?) {
        completedOperationCleanup?.cancel()
        guard result != .running,
              let finishedAt else { return }
        let delay: TimeInterval
        let clearsWholeStatus: Bool
        switch result {
        case .succeeded:
            delay = 8
            clearsWholeStatus = true
        case .cancelled:
            delay = 6
            clearsWholeStatus = true
        case .failed, .needsTerminal:
            delay = 20
            clearsWholeStatus = false
        case .running:
            return
        }

        let item = DispatchWorkItem { [weak self] in
            guard let self,
                  self.operation == nil,
                  self.operationStatus?.targetID == targetID,
                  self.operationStatus?.finishedAt == finishedAt else { return }
            self.log = ""
            if clearsWholeStatus {
                self.terminalFallbackCommand = nil
                self.operationStatus = nil
            }
            self.completedOperationCleanup = nil
        }
        completedOperationCleanup = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func detectBrewPath() -> String? {
        HomebrewCommandBuilder.candidatePaths.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private func run(_ command: HomebrewCommand,
                     completion: @escaping (_ status: Int32, _ output: String) -> Void) {
        workQueue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                completion(-1, error.localizedDescription)
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            completion(process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func runStreaming(_ command: HomebrewCommand,
                              onOutput: @escaping (String) -> Void,
                              completion: @escaping (_ status: Int32, _ output: String) -> Void) {
        workQueue.async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            var output = Data()
            let lock = NSLock()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                lock.lock()
                output.append(data)
                lock.unlock()
                if let chunk = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async { onOutput(chunk) }
                }
            }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                completion(-1, error.localizedDescription)
                return
            }
            DispatchQueue.main.async { self?.activeProcess = process }
            process.waitUntilExit()
            pipe.fileHandleForReading.readabilityHandler = nil
            let remainder = pipe.fileHandleForReading.readDataToEndOfFile()
            if !remainder.isEmpty {
                lock.lock()
                output.append(remainder)
                lock.unlock()
            }
            lock.lock()
            let finalOutput = String(data: output, encoding: .utf8) ?? ""
            lock.unlock()
            completion(process.terminationStatus, finalOutput)
        }
    }

    private func appendLog(_ text: String) {
        log.append(text)
    }

    private func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private struct PopularityCacheEntry {
    let values: [String: HomebrewPopularity]
    let fetchedAt: Date

    var isFresh: Bool {
        Date().timeIntervalSince(fetchedAt) < 24 * 60 * 60
    }
}
