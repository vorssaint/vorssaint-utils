// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Emre Aribulan

import Foundation

@main
struct WebsiteIconTests {
    @MainActor static func main() async throws {
        let base = "http://127.0.0.1:" + CommandLine.arguments[1]
        let icon = await WebsiteIconFetcher.icon(for: URL(string: base + "/private?token=should-not-be-requested")!)
        precondition(
            icon?.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) == true,
            "declared icon redirects decode and normalize to PNG after an invalid image")
        precondition(WebsiteIconFetcher.needsLightBackground(icon!), "a dark coloured icon gets light backing")
        let white = await WebsiteIconRequest.fetch(URL(string: base + "/white.png")!, limit: 1024)
        precondition(
            white.map { !WebsiteIconFetcher.needsLightBackground($0.data) } == true, "white icons get dark backing")
        let large = await WebsiteIconRequest.fetch(URL(string: base + "/large")!, limit: 1024)
        precondition(large == nil, "oversized Content-Length rejected")
        let streamed = await WebsiteIconRequest.fetch(URL(string: base + "/streamed")!, limit: 1024)
        precondition(streamed == nil, "streaming bytes bounded even without Content-Length")
        let missing = await WebsiteIconRequest.fetch(URL(string: base + "/missing")!, limit: 1024)
        precondition(missing == nil, "HTTP errors rejected")
        let loop = await WebsiteIconRequest.fetch(URL(string: base + "/loop")!, limit: 1024)
        precondition(loop == nil, "redirect loops bounded")
        precondition(
            WebsiteIconFetcher.rasterIcon(Data("<html>error</html>".utf8)) == nil, "HTML is not accepted as an icon")
        let before = Date()
        let pending = Task { await WebsiteIconRequest.fetch(URL(string: base + "/slow")!, limit: 1024) }
        try await Task.sleep(for: .milliseconds(100))
        pending.cancel()
        let cancelled = await pending.value
        precondition(
            cancelled == nil && Date().timeIntervalSince(before) < 2,
            "cancelling a fetch stops the network request promptly")
        let preCancelled = Task { await WebsiteIconRequest.fetch(URL(string: base + "/slow")!, limit: 1024) }
        preCancelled.cancel()
        let early = await preCancelled.value
        precondition(early == nil, "cancellation before request startup also completes")
        let denied = await WebsiteIconRequest.fetch(URL(string: base + "/auth")!, limit: 1024)
        precondition(denied == nil, "authentication challenges fail without asking for credentials")
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let service = WebsiteShortcutIconService(directory: cache)
        let entry = IslandLauncherEntry(name: "Fixture", path: "", website: base)
        service.load(entry)
        while service.loading.contains(entry.id) { try await Task.sleep(for: .milliseconds(20)) }
        precondition(service.icons[entry.id] != nil && !service.failed.contains(entry.id), "fetched icon appears")
        _ = await WebsiteIconRequest.fetch(URL(string: base + "/disable-icons")!, limit: 1024)
        service.load(entry, refresh: true)
        while service.loading.contains(entry.id) { try await Task.sleep(for: .milliseconds(20)) }
        precondition(
            service.icons[entry.id] != nil && service.failed.contains(entry.id),
            "a failed refresh preserves the last working icon")
        _ = await WebsiteIconRequest.fetch(URL(string: base + "/enable-icons")!, limit: 1024)
        let restored = WebsiteShortcutIconService(directory: cache)
        restored.load(entry)
        precondition(
            restored.icons[entry.id] != nil && restored.loading.isEmpty, "saved icon restores without another request")
        service.remove(entry.id)
        precondition(
            service.icons[entry.id] == nil
                && !FileManager.default.fileExists(
                    atPath: cache.appendingPathComponent(entry.id.uuidString + ".png").path),
            "removing a shortcut removes its memory and disk icons")
        let removed = IslandLauncherEntry(name: "Removed", path: "", website: base)
        service.load(removed)
        service.remove(removed.id)
        try await Task.sleep(for: .milliseconds(200))
        precondition(
            service.icons[removed.id] == nil && !service.loading.contains(removed.id),
            "cancelled loads cannot restore a removed icon")
        print("PASS: 16 website icon fetch, cancellation, cache and contrast checks")
    }
}
