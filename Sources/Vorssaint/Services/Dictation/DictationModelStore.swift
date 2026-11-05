// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CryptoKit
import Foundation
import UniformTypeIdentifiers

final class DictationModelStore: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DictationModelStore()
    @Published private(set) var models: [DictationModel] = []
    @Published private(set) var installed: Set<String> = []
    @Published private(set) var downloading: String?
    @Published private(set) var progress = 0.0
    @Published private(set) var error: String?
    private var download: URLSessionDownloadTask?
    private var generation = UUID()
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    private let fileQueue = DispatchQueue(label: "com.vorssaint.dictation.models", qos: .utility)

    var directory: URL? { PrivateFileStore.containerURL?.appendingPathComponent("Dictation/Models", isDirectory: true) }
    var selectedID: String { UserDefaults.standard.string(forKey: DefaultsKey.dictationModel) ?? "" }
    var selected: DictationModel? { models.first { $0.id == selectedID } }
    var selectedURL: URL? {
        guard installed.contains(selectedID) else { return nil }
        return fileURL(selectedID)
    }

    override init() {
        super.init()
        let url = Bundle.main.url(forResource: "dictation-models", withExtension: "json")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/dictation-models.json")
        do {
            models = try JSONDecoder().decode(DictationModelCatalog.self, from: Data(contentsOf: url)).models.filter { $0.role == "asr" && $0.downloadFile != nil }
        } catch { self.error = "The bundled model catalog could not be read: \(error.localizedDescription)" }
        refresh()
    }

    func fileURL(_ id: String) -> URL? {
        guard id == "custom" || models.contains(where: { $0.id == id }),
              !id.contains("/"), !id.contains("..") else { return nil }
        return directory?.appendingPathComponent(id + ".model")
    }

    func refresh() {
        installed = Set((models.map(\.id) + ["custom"]).filter {
            guard let url = fileURL($0) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        })
    }

    func select(_ id: String) {
        guard !DictationService.shared.phase.isBusy, installed.contains(id) else { return }
        DictationService.shared.unloadEngine()
        UserDefaults.standard.set(id, forKey: DefaultsKey.dictationModel)
        if let model = models.first(where: { $0.id == id }) {
            if !model.capabilities.translate { UserDefaults.standard.set(false, forKey: DefaultsKey.dictationTranslate) }
            let language = UserDefaults.standard.string(forKey: DefaultsKey.dictationLanguage) ?? ""
            if !language.isEmpty, !model.languages.contains(language) {
                UserDefaults.standard.set("", forKey: DefaultsKey.dictationLanguage)
            }
        }
        objectWillChange.send()
    }

    func install(_ model: DictationModel) {
        guard AppFeature.dictation.isAvailable, downloading == nil, let url = model.downloadURL,
              let directory, PrivateFileStore.createDirectory(at: directory) else { return }
        generation = UUID()
        error = nil
        downloading = model.id
        progress = 0
        download = session.downloadTask(with: url)
        download?.resume()
    }

    func cancelDownload() {
        generation = UUID()
        download?.cancel()
        download = nil
        downloading = nil
        progress = 0
    }

    func remove(_ id: String) {
        guard !DictationService.shared.phase.isBusy, let url = fileURL(id) else { return }
        do {
            DictationService.shared.unloadEngine()
            try FileManager.default.removeItem(at: url)
            if selectedID == id { UserDefaults.standard.set("", forKey: DefaultsKey.dictationModel) }
            refresh()
        } catch { self.error = error.localizedDescription }
    }

    func importModel() {
        guard AppFeature.dictation.isAvailable, !DictationService.shared.phase.isBusy, downloading == nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gguf"), UTType(filenameExtension: "bin"), UTType(filenameExtension: "model")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url, let directory,
              PrivateFileStore.createDirectory(at: directory), let target = fileURL("custom") else { return }
        error = nil
        downloading = "custom"
        generation = UUID()
        let token = generation
        fileQueue.async {
            let staging = directory.appendingPathComponent(UUID().uuidString + ".partial")
            do {
                try FileManager.default.copyItem(at: source, to: staging)
                let handle = try FileHandle(forReadingFrom: staging)
                let header = try handle.read(upToCount: 4)
                try handle.close()
                guard header == Data("GGUF".utf8) || header == Data([0x6c, 0x6d, 0x67, 0x67]) else {
                    throw DictationError.message("Choose a GGUF or whisper.cpp GGML model file.")
                }
                DispatchQueue.main.async {
                    guard self.generation == token else { try? FileManager.default.removeItem(at: staging); return }
                    do {
                        DictationService.shared.unloadEngine()
                        if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: staging) }
                        else { try FileManager.default.moveItem(at: staging, to: target) }
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                        self.downloading = nil
                        self.refresh()
                        self.select("custom")
                    } catch { self.downloading = nil; self.error = error.localizedDescription }
                }
            } catch {
                try? FileManager.default.removeItem(at: staging)
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.downloading = nil
                    self.error = error.localizedDescription
                }
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard downloadTask == download else { return }
        progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard downloadTask == download, let id = downloading,
              let model = models.first(where: { $0.id == id }), let expected = model.downloadFile,
              let target = fileURL(id), let directory else { return }
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            error = "Model download failed. Please try again."
            downloading = nil
            return
        }
        let staging = directory.appendingPathComponent(UUID().uuidString + ".partial")
        let token = generation
        do { try FileManager.default.moveItem(at: location, to: staging) }
        catch { self.error = error.localizedDescription; downloading = nil; return }
        fileQueue.async {
            do {
                let handle = try FileHandle(forReadingFrom: staging)
                defer { try? handle.close() }
                var hash = SHA256()
                var size: Int64 = 0
                while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data); size += Int64(data.count) }
                let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
                guard size == expected.size, digest == expected.sha256 else {
                    throw DictationError.message("Model verification failed. Download it again.")
                }
                DispatchQueue.main.async {
                    guard self.generation == token else { try? FileManager.default.removeItem(at: staging); return }
                    do {
                        if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: staging) }
                        else { try FileManager.default.moveItem(at: staging, to: target) }
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                        self.downloading = nil
                        self.download = nil
                        self.refresh()
                        if self.selectedURL == nil { self.select(id) }
                    } catch { self.error = error.localizedDescription; self.downloading = nil }
                }
            } catch {
                try? FileManager.default.removeItem(at: staging)
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.downloading = nil
                    self.error = error.localizedDescription
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task == download, let error else { return }
        self.error = error.localizedDescription
        downloading = nil
        download = nil
    }
}
