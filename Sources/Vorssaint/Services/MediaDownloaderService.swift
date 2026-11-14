// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class MediaDownloaderService: ObservableObject {
    static let shared = MediaDownloaderService()

    @Published private(set) var dependencies = MediaDownloaderSupport.Dependencies.locate()
    @Published var inputURLText = ""
    @Published private(set) var metadata: MediaDownloaderSupport.Metadata?
    @Published private(set) var progress: MediaDownloaderSupport.Progress?
    @Published private(set) var isInspecting = false
    @Published private(set) var isDownloading = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastFileURL: URL?
    @Published private(set) var history: [MediaDownloaderSupport.HistoryEntry] = []
    @Published private(set) var destinationFolder: URL
    @Published private(set) var batchDestinationFolder: URL
    @Published private(set) var batchItems: [MediaDownloaderSupport.BatchItem] = []
    @Published private(set) var batchCompletedCount = 0
    @Published private(set) var batchFailedCount = 0
    @Published private(set) var isBatchRunning = false
    @Published private(set) var isImportingBatchFile = false
    @Published private(set) var batchOutputFolder: URL?

    private var activeProcess: Process?
    private var operationID = UUID()
    private var cancelRequested = false
    private var batchTemporaryFolder: URL?
    private var activeOpenPanel: NSOpenPanel?

    private init() {
        destinationFolder = UserDefaults.standard.string(forKey: DefaultsKey.mediaDownloaderDestination)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        batchDestinationFolder = UserDefaults.standard.string(forKey: DefaultsKey.mediaDownloaderBatchDestination)
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Movies", isDirectory: true)
        loadHistory()
    }

    var activeDownloadTitle: String? {
        if isBatchRunning { return "Batch download · \(min(batchCompletedCount + 1, batchItems.count))/\(batchItems.count)" }
        guard isDownloading else { return nil }
        return metadata?.title
    }
    var activeDownloadFraction: Double? {
        guard isBatchRunning, !batchItems.isEmpty else { return isDownloading ? progress?.fraction : nil }
        return (Double(batchCompletedCount) + (progress?.fraction ?? 0)) / Double(batchItems.count)
    }

    func refreshDependencies() {
        dependencies = MediaDownloaderSupport.Dependencies.locate()
    }

    func prepareForURLChange() {
        guard !isDownloading, !isBatchRunning else { return }
        if isInspecting { activeProcess?.terminate() }
        operationID = UUID()
        activeProcess = nil
        isInspecting = false
        metadata = nil
        errorMessage = nil
        statusMessage = nil
    }

    func inspect(_ rawURL: String) {
        guard !isDownloading, !isBatchRunning else { return }
        if isInspecting { activeProcess?.terminate() }
        refreshDependencies()
        guard let executable = dependencies.ytDLP else {
            errorMessage = MediaDownloaderError.dependenciesMissing.localizedDescription
            return
        }
        guard let url = MediaDownloaderSupport.normalizedURL(rawURL) else {
            errorMessage = MediaDownloaderError.invalidURL.localizedDescription
            return
        }

        operationID = UUID()
        let requestID = operationID
        cancelRequested = false
        metadata = nil
        progress = nil
        errorMessage = nil
        statusMessage = "Checking link…"
        isInspecting = true
        run(executable: executable,
            arguments: MediaDownloaderSupport.metadataArguments(url: url),
            progressHandler: { _ in }) { [weak self] status, output, errorOutput in
                guard let self, self.operationID == requestID else { return }
                self.activeProcess = nil
                self.isInspecting = false
                self.statusMessage = nil
                guard status == 0 else {
                    self.errorMessage = Self.visibleError(errorOutput)
                    return
                }
                do {
                    self.metadata = try MediaDownloaderSupport.Metadata.decode(
                        output,
                        platform: MediaDownloaderPlatform.identify(url)
                    )
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
    }

    func downloadVideo(from rawURL: String, maximumHeight: Int?) {
        guard let ffmpeg = dependencies.ffmpeg else {
            errorMessage = MediaDownloaderError.dependenciesMissing.localizedDescription
            return
        }
        guard let url = MediaDownloaderSupport.normalizedURL(rawURL) else {
            errorMessage = MediaDownloaderError.invalidURL.localizedDescription
            return
        }
        startDownload(url: url,
                      arguments: MediaDownloaderSupport.videoArguments(
                        url: url, folder: destinationFolder, quality: maximumHeight, ffmpeg: ffmpeg),
                      kind: .video,
                      quality: maximumHeight.map { "MP4 · Up to \($0)p" } ?? "MP4 · Best available")
    }

    func downloadAudio(from rawURL: String, format: String) {
        guard let ffmpeg = dependencies.ffmpeg else {
            errorMessage = MediaDownloaderError.dependenciesMissing.localizedDescription
            return
        }
        guard let url = MediaDownloaderSupport.normalizedURL(rawURL) else {
            errorMessage = MediaDownloaderError.invalidURL.localizedDescription
            return
        }
        startDownload(url: url,
                      arguments: MediaDownloaderSupport.audioArguments(
                        url: url, folder: destinationFolder, format: format, ffmpeg: ffmpeg),
                      kind: .audio,
                      quality: format == "original" ? "Original audio" : format.uppercased())
    }

    func importBatchFile() {
        guard !isDownloading, !isInspecting, !isBatchRunning, !isImportingBatchFile else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.item]
        panel.title = "Choose Links File"
        panel.message = "Choose a file containing video links (CSV, TSV, TXT, or JSON)."
        presentOpenPanel(panel) { [weak self, weak panel] response in
            guard response == .OK, let fileURL = panel?.url else { return }
            guard let self else { return }
            self.isImportingBatchFile = true
            self.errorMessage = nil
            self.statusMessage = "Reading links file…"
            let hasSecurityScope = fileURL.startAccessingSecurityScopedResource()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { if hasSecurityScope { fileURL.stopAccessingSecurityScopedResource() } }
                let importedItems: [MediaDownloaderSupport.BatchItem]?
                do {
                    let data = try Data(contentsOf: fileURL)
                    importedItems = MediaDownloaderSupport.batchItems(in: String(decoding: data, as: UTF8.self))
                } catch {
                    importedItems = nil
                }
                DispatchQueue.main.async {
                    self.isImportingBatchFile = false
                    guard let importedItems else {
                        self.statusMessage = nil
                        self.errorMessage = "Could not read that file."
                        return
                    }
                    guard !importedItems.isEmpty else {
                        self.statusMessage = nil
                        self.errorMessage = "No video links were found in that file."
                        return
                    }
                    self.batchItems = importedItems
                    self.batchCompletedCount = 0
                    self.batchFailedCount = 0
                    self.errorMessage = nil
                    self.statusMessage = "Loaded \(importedItems.count) download links."
                }
            }
        }
    }

    func clearBatchLinks() {
        guard !isBatchRunning else { return }
        batchItems = []
        batchCompletedCount = 0
        batchFailedCount = 0
        statusMessage = nil
        errorMessage = nil
    }

    func startBatchDownloads(maximumHeight: Int?) {
        guard !batchItems.isEmpty, !isDownloading, !isInspecting, !isBatchRunning else { return }
        refreshDependencies()
        guard let ffmpeg = dependencies.ffmpeg, dependencies.ytDLP != nil else {
            errorMessage = MediaDownloaderError.dependenciesMissing.localizedDescription
            return
        }
        guard AppFeature.mediaDownloader.isAvailable else { return }

        do {
            batchOutputFolder = try createBatchOutputFolder()
        } catch {
            errorMessage = "Could not create a folder for this batch."
            return
        }

        batchCompletedCount = 0
        batchFailedCount = 0
        isBatchRunning = true
        metadata = nil
        errorMessage = nil
        if AppFeature.notch.isAvailable && AppFeature.mediaDownloader.isAvailable {
            NotchService.shared.openActivity(.mediaDownloader)
        }
        startNextBatchItem(maximumHeight: maximumHeight, ffmpeg: ffmpeg)
    }

    func cancel() {
        guard isInspecting || isDownloading else { return }
        isBatchRunning = false
        cancelRequested = true
        operationID = UUID()
        activeProcess?.terminate()
        activeProcess = nil
        isInspecting = false
        isDownloading = false
        progress = nil
        if let folder = batchTemporaryFolder {
            try? FileManager.default.removeItem(at: folder)
            batchTemporaryFolder = nil
        }
        statusMessage = "Cancelled"
        NotchService.shared.refreshPresentation(animated: false)
    }

    func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = destinationFolder
        panel.title = "Choose Download Folder"
        panel.message = "Choose where downloaded media is saved."
        presentOpenPanel(panel) { [weak self, weak panel] response in
            guard response == .OK, let url = panel?.url else { return }
            Task { @MainActor in
                self?.destinationFolder = url
                UserDefaults.standard.set(url.path, forKey: DefaultsKey.mediaDownloaderDestination)
            }
        }
    }

    func chooseBatchDestinationFolder() {
        guard !isBatchRunning else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.fileExists(atPath: batchDestinationFolder.path)
            ? batchDestinationFolder
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies", isDirectory: true)
        panel.title = "Choose Batch Location"
        panel.message = "Choose where batch download folders are created."
        presentOpenPanel(panel) { [weak self, weak panel] response in
            guard response == .OK, let url = panel?.url else { return }
            Task { @MainActor in
                self?.batchDestinationFolder = url
                UserDefaults.standard.set(url.path, forKey: DefaultsKey.mediaDownloaderBatchDestination)
            }
        }
    }

    private func presentOpenPanel(_ panel: NSOpenPanel,
                                  completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let activeOpenPanel {
            NSApp.activate(ignoringOtherApps: true)
            activeOpenPanel.makeKeyAndOrderFront(nil)
            return
        }

        let island = NotchService.shared.presentationWindow
        let presentedFromNotch = island != nil
            && (NSApp.currentEvent?.window === island || NSApp.keyWindow === island)
        if presentedFromNotch, let island {
            panel.level = NSWindow.Level(rawValue: island.level.rawValue + 1)
            panel.hidesOnDeactivate = false
        } else {
            PanelInteractionState.shared.isPresentingPopoverModal = true
        }

        activeOpenPanel = panel
        panel.begin { [weak self] response in
            guard let self else { return }
            self.activeOpenPanel = nil
            if !presentedFromNotch {
                PanelInteractionState.shared.isPresentingPopoverModal = false
            } else if let island {
                DispatchQueue.main.async {
                    if NotchService.shared.expanded { island.makeKey() }
                }
            }
            completion(response)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func open(_ entry: MediaDownloaderSupport.HistoryEntry) {
        guard FileManager.default.fileExists(atPath: entry.filePath) else {
            errorMessage = "That file is no longer in its saved location."
            return
        }
        NSWorkspace.shared.open(entry.fileURL)
    }

    func reveal(_ entry: MediaDownloaderSupport.HistoryEntry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.fileURL])
    }

    func clearHistory() {
        history = []
        persistHistory()
    }

    func revealBatchFolder() {
        guard let batchOutputFolder,
              FileManager.default.fileExists(atPath: batchOutputFolder.path) else { return }
        NSWorkspace.shared.open(batchOutputFolder)
    }

    func syncWithPreferences() {
        if !AppFeature.mediaDownloader.isAvailable { cancel() }
    }

    private func startDownload(url: URL,
                               arguments: [String],
                               kind: MediaDownloaderSupport.HistoryEntry.Kind,
                               quality: String,
                               isBatchItem: Bool = false,
                               outputResolver: ((Data) -> URL?)? = nil,
                               outputProcessor: ((URL) -> URL?)? = nil,
                               completion: @escaping (Bool) -> Void = { _ in }) {
        guard !isDownloading, !isInspecting, (!isBatchRunning || isBatchItem) else { return }
        refreshDependencies()
        guard let executable = dependencies.ytDLP, dependencies.ffmpeg != nil else {
            errorMessage = MediaDownloaderError.dependenciesMissing.localizedDescription
            return
        }
        guard AppFeature.mediaDownloader.isAvailable else { return }

        operationID = UUID()
        let requestID = operationID
        cancelRequested = false
        errorMessage = nil
        statusMessage = "Starting download…"
        progress = nil
        isDownloading = true
        if !isBatchRunning && AppFeature.notch.isAvailable && AppFeature.mediaDownloader.isAvailable {
            NotchService.shared.openActivity(.mediaDownloader)
        }
        run(executable: executable,
            arguments: arguments,
            progressHandler: { [weak self] value in
                guard let self, self.operationID == requestID else { return }
                self.progress = value
                self.statusMessage = value.fraction.map {
                    let percent = $0.formatted(.percent.precision(.fractionLength(0)))
                    return self.isBatchRunning
                        ? "Item \(self.batchCompletedCount + 1) of \(self.batchItems.count) · \(percent)"
                        : "Downloading · \(percent)"
                } ?? "Downloading…"
            }) { [weak self] status, output, errorOutput in
                guard let self, self.operationID == requestID else { return }
                self.activeProcess = nil
                self.isDownloading = false
                self.progress = nil
                if self.cancelRequested {
                    self.cancelRequested = false
                    self.statusMessage = "Cancelled"
                    NotchService.shared.refreshPresentation(animated: false)
                    return
                }
                guard status == 0 else {
                    self.statusMessage = nil
                    self.errorMessage = Self.visibleError(errorOutput)
                    NotchService.shared.refreshPresentation(animated: false)
                    completion(false)
                    return
                }
                guard let downloadedURL = outputResolver?(output) ?? Self.outputFile(in: output),
                      FileManager.default.fileExists(atPath: downloadedURL.path) else {
                    self.statusMessage = nil
                    self.errorMessage = MediaDownloaderError.outputFileMissing.localizedDescription
                    NotchService.shared.refreshPresentation(animated: false)
                    completion(false)
                    return
                }
                let fileURL: URL
                if let outputProcessor {
                    guard let processedURL = outputProcessor(downloadedURL),
                          FileManager.default.fileExists(atPath: processedURL.path) else {
                        self.statusMessage = nil
                        self.errorMessage = "The selected output format could not be created."
                        NotchService.shared.refreshPresentation(animated: false)
                        completion(false)
                        return
                    }
                    fileURL = processedURL
                } else {
                    fileURL = downloadedURL
                }
                self.lastFileURL = fileURL
                self.statusMessage = "Saved to \(fileURL.lastPathComponent)"
                let entry = MediaDownloaderSupport.HistoryEntry(
                    title: self.metadata?.title ?? fileURL.deletingPathExtension().lastPathComponent,
                    url: url.absoluteString,
                    platform: MediaDownloaderPlatform.identify(url),
                    filePath: fileURL.path,
                    kind: kind,
                    quality: quality
                )
                self.history.insert(entry, at: 0)
                self.history = Array(self.history.prefix(100))
                self.persistHistory()
                NotchService.shared.refreshPresentation(animated: false)
                completion(true)
            }
    }

    private func startNextBatchItem(maximumHeight: Int?, ffmpeg: URL) {
        guard isBatchRunning else { return }
        guard batchCompletedCount < batchItems.count else {
            isBatchRunning = false
            statusMessage = "Batch complete · \(batchCompletedCount - batchFailedCount) of \(batchItems.count) downloaded."
            errorMessage = batchFailedCount > 0
                ? "\(batchFailedCount) of \(batchItems.count) items could not be downloaded."
                : nil
            NotchService.shared.refreshPresentation(animated: false)
            return
        }

        let item = batchItems[batchCompletedCount]
        let url = item.url
        let outputFolder = batchOutputFolder ?? destinationFolder
        let arguments: [String]
        let historyKind: MediaDownloaderSupport.HistoryEntry.Kind
        let quality: String
        switch item.format {
        case .mp4, .mkv, .mov, .webm, .avi, .flv, .gif:
            arguments = MediaDownloaderSupport.videoArguments(
                url: url, folder: outputFolder, quality: maximumHeight, ffmpeg: ffmpeg,
                outputFormat: item.format.rawValue)
            historyKind = .video
            quality = item.format == .mp4
                ? (maximumHeight.map { "MP4 · Up to \($0)p" } ?? "MP4 · Best available")
                : item.format.historyQuality
        case .mp3, .m4a, .wav, .opus, .flac, .aac, .alac, .vorbis, .original:
            arguments = MediaDownloaderSupport.audioArguments(
                url: url, folder: outputFolder, format: item.format.rawValue, ffmpeg: ffmpeg)
            historyKind = .audio
            quality = item.format.historyQuality
        case .heic, .heif, .jpg, .png, .webp:
            let temporaryFolder = FileManager.default.temporaryDirectory
                .appendingPathComponent("vorssaint-heic-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
            } catch {
                batchFailedCount += 1
                batchCompletedCount += 1
                startNextBatchItem(maximumHeight: maximumHeight, ffmpeg: ffmpeg)
                return
            }
            batchTemporaryFolder = temporaryFolder
            let host = (url.host ?? "media").replacingOccurrences(of: ".", with: "-")
            let destination = outputFolder.appendingPathComponent(
                "\(host)-\(UUID().uuidString.prefix(8)).\(item.format.rawValue)")
            let isHEIF = item.format == .heic || item.format == .heif
            let thumbnailFormat = isHEIF ? "png" : item.format.rawValue
            startDownload(url: url,
                          arguments: MediaDownloaderSupport.thumbnailArguments(
                            url: url, folder: temporaryFolder, ffmpeg: ffmpeg,
                            outputFormat: thumbnailFormat),
                          kind: .image,
                          quality: item.format.historyQuality,
                          isBatchItem: true,
                          outputResolver: { _ in
                              try? FileManager.default.contentsOfDirectory(at: temporaryFolder,
                                                                           includingPropertiesForKeys: nil)
                                  .first { $0.pathExtension.lowercased() == thumbnailFormat }
                          },
                          outputProcessor: { source in
                              if isHEIF {
                                  return Self.convertImage(source, destination: destination,
                                                           contentType: UTType.heic.identifier)
                              }
                              do {
                                  try FileManager.default.copyItem(at: source, to: destination)
                                  return destination
                              } catch {
                                  return nil
                              }
                          }, completion: { [weak self] succeeded in
                guard let self, self.isBatchRunning else { return }
                try? FileManager.default.removeItem(at: temporaryFolder)
                self.batchTemporaryFolder = nil
                if !succeeded { self.batchFailedCount += 1 }
                self.batchCompletedCount += 1
                self.startNextBatchItem(maximumHeight: maximumHeight, ffmpeg: ffmpeg)
            })
            return
        }
        startDownload(url: url,
                      arguments: arguments,
                      kind: historyKind,
                      quality: quality,
                      isBatchItem: true,
                      completion: { [weak self] succeeded in
            guard let self, self.isBatchRunning else { return }
            if !succeeded { self.batchFailedCount += 1 }
            self.batchCompletedCount += 1
            self.startNextBatchItem(maximumHeight: maximumHeight, ffmpeg: ffmpeg)
        })
    }

    private func run(executable: URL,
                     arguments: [String],
                     progressHandler: @escaping (MediaDownloaderSupport.Progress) -> Void,
                     completion: @escaping (Int32, Data, String) -> Void) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "HOME": NSHomeDirectory()]
        activeProcess = process

        let group = DispatchGroup()
        let lock = NSLock()
        var output = Data()
        var errorOutput = Data()
        group.enter()
        group.enter()
        process.terminationHandler = { process in
            group.notify(queue: .main) {
                lock.lock()
                let capturedOutput = output
                let capturedErrors = errorOutput
                lock.unlock()
                completion(process.terminationStatus,
                           capturedOutput,
                           String(decoding: capturedErrors, as: UTF8.self))
            }
        }

        do {
            try process.run()
        } catch {
            activeProcess = nil
            group.leave()
            group.leave()
            completion(-1, Data(), error.localizedDescription)
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            lock.lock()
            output = data
            lock.unlock()
            group.leave()
        }
        DispatchQueue.global(qos: .utility).async {
            let handle = errorPipe.fileHandleForReading
            var pending = Data()
            while true {
                let chunk = handle.availableData
                guard !chunk.isEmpty else { break }
                lock.lock()
                errorOutput.append(chunk)
                lock.unlock()
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 10) {
                    let line = String(decoding: pending[..<newline], as: UTF8.self)
                    pending.removeSubrange(...newline)
                    if let progress = MediaDownloaderSupport.Progress.parseProgressLine(line) {
                        DispatchQueue.main.async { progressHandler(progress) }
                    }
                }
            }
            group.leave()
        }
    }

    private func loadHistory() {
        guard let url = MediaDownloaderSupport.historyURL(),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([MediaDownloaderSupport.HistoryEntry].self, from: data)
        else { return }
        history = entries.filter { FileManager.default.fileExists(atPath: $0.filePath) }
    }

    private func persistHistory() {
        guard let container = PrivateFileStore.containerURL,
              PrivateFileStore.createDirectory(at: container),
              let url = MediaDownloaderSupport.historyURL(),
              let data = try? JSONEncoder().encode(history)
        else { return }
        _ = PrivateFileStore.write(data, to: url)
    }

    private func createBatchOutputFolder() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let baseName = "Batch Downloads - \(formatter.string(from: Date()))"
        let batchRoot = batchDestinationFolder
        var name = baseName
        var suffix = 2
        var folder = batchRoot.appendingPathComponent(name, isDirectory: true)
        while FileManager.default.fileExists(atPath: folder.path) {
            name = "\(baseName) (\(suffix))"
            suffix += 1
            folder = batchRoot.appendingPathComponent(name, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func outputFile(in data: Data) -> URL? {
        let prefix = "VORSSAINT_FILE:"
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).reversed() {
            guard line.hasPrefix(prefix) else { continue }
            let encodedPath = String(line.dropFirst(prefix.count))
            if let path = try? JSONDecoder().decode(String.self, from: Data(encodedPath.utf8)) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private static func convertImage(_ sourceURL: URL, destination destinationURL: URL,
                                     contentType: String) -> URL? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL, contentType as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: destinationURL)
            return nil
        }
        return destinationURL
    }

    private static func visibleError(_ output: String) -> String {
        if output.localizedCaseInsensitiveContains("Unable to extract flashvars") {
            return "Platform not available."
        }
        let lines = output.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.hasPrefix("VORSSAINT_PROGRESS:") && !$0.hasPrefix("WARNING:") }
        return lines.last ?? "The media download failed. Check the URL and try again."
    }
}
