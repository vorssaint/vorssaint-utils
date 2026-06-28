// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

enum UpdateShowcaseInfo {
    static let releaseVersion = "3.1.4"
    static let mediaAssetName = "vorssaint-3.1.4-showcase-1.mp4"

    static var remoteMediaURL: URL {
        URL(string: "https://github.com/vorssaint/vorssaint-utils/releases/download/v\(releaseVersion)/\(mediaAssetName)")!
    }

    static var localDeveloperMediaURL: URL? {
        guard AppInfo.isDeveloperBuild else { return nil }
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.updateShowcaseMediaOverride),
           let url = mediaURL(from: raw),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let desktopDemo = URL(fileURLWithPath: "/Users/vorssaint/Desktop/demo.gif")
        return FileManager.default.fileExists(atPath: desktopDemo.path) ? desktopDemo : nil
    }

    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundleID = Bundle.main.bundleIdentifier ?? "com.vorssaint.utils"
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("UpdateShowcase", isDirectory: true)
            .appendingPathComponent(releaseVersion, isDirectory: true)
    }

    static var cachedMediaURL: URL {
        cacheDirectory.appendingPathComponent(mediaAssetName)
    }

    static func cleanupCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    private static func mediaURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.isFileURL {
            return url
        }
        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" {
            return nil
        }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
    }
}

final class UpdateShowcaseMediaLoader: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready(URL)
        case failed
    }

    @Published private(set) var state: State = .idle
    private var task: URLSessionDownloadTask?

    func load() {
        if case .ready = state { return }
        if case .loading = state { return }

        if let local = UpdateShowcaseInfo.localDeveloperMediaURL {
            state = .ready(local)
            return
        }

        let cached = UpdateShowcaseInfo.cachedMediaURL
        if FileManager.default.fileExists(atPath: cached.path) {
            state = .ready(cached)
            return
        }

        state = .loading
        let request = URLRequest(url: UpdateShowcaseInfo.remoteMediaURL,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 12)
        task = URLSession.shared.downloadTask(with: request) { [weak self] tempURL, response, error in
            guard let self else { return }
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
            guard let tempURL, error == nil, ok else {
                DispatchQueue.main.async { self.state = .failed }
                return
            }

            do {
                try FileManager.default.createDirectory(at: UpdateShowcaseInfo.cacheDirectory,
                                                        withIntermediateDirectories: true)
                let target = UpdateShowcaseInfo.cachedMediaURL
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: tempURL, to: target)
                DispatchQueue.main.async { self.state = .ready(target) }
            } catch {
                DispatchQueue.main.async { self.state = .failed }
            }
        }
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func cleanupCache() {
        UpdateShowcaseInfo.cleanupCache()
    }
}
