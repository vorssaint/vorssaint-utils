// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Emre Aribulan
import AppKit
import Combine
import UniformTypeIdentifiers

final class IslandLauncherService: ObservableObject {
    static let shared = IslandLauncherService()
    @Published private(set) var entries: [IslandLauncherEntry]
    @Published private(set) var isChoosing = false
    private var strings: NotchShortcutStrings { .localized(L10n.shared.language) }
    private var chooser: NSOpenPanel?
    private var preferencesObserver: AnyCancellable?

    struct Candidate: Identifiable {
        let url: URL
        let name: String
        let bottle: String
        var id: String { url.path }
        var title: String { bottle.isEmpty ? name : "\(name) — \(bottle)" }
    }

    private init() {
        entries = Self.storedEntries()
        preferencesObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let updated = Self.storedEntries()
                guard updated != self.entries else { return }
                for entry in self.entries where !updated.contains(entry) {
                    WebsiteShortcutIconService.shared.remove(entry.id)
                }
                self.entries = updated
                NotchService.shared.syncWithPreferences()
            }
    }

    private static func storedEntries() -> [IslandLauncherEntry] {
        IslandLauncherSupport.decode(UserDefaults.standard.data(forKey: DefaultsKey.notchLauncherEntries) ?? Data())
    }

    func resolvedURL(_ entry: IslandLauncherEntry) -> URL? {
        guard entry.website == nil else { return nil }
        var stale = false
        let bookmarked = try? URL(
            resolvingBookmarkData: entry.bookmark, options: [.withoutUI, .withoutMounting],
            relativeTo: nil, bookmarkDataIsStale: &stale)
        let url = (bookmarked ?? URL(fileURLWithPath: entry.path)).standardizedFileURL
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
            (try? url.resourceValues(forKeys: [.isApplicationKey]).isApplication) == true
        else { return nil }
        return url
    }

    func contains(_ url: URL) -> Bool {
        entries.contains {
            $0.website == nil
                && (($0.path == url.standardizedFileURL.path)
                    || resolvedURL($0)?.resolvingSymlinksInPath() == url.resolvingSymlinksInPath())
        }
    }

    func crossOverApps() -> [Candidate] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Applications/CrossOver", isDirectory: true)
        guard
            let files = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var results: [Candidate] = []
        while let url = files.nextObject() as? URL {
            if url.pathExtension.lowercased() == "app" {
                files.skipDescendants()
                guard let bundle = Bundle(url: url),
                    let bottle = bundle.object(forInfoDictionaryKey: "CXHelperAppBottleName") as? String
                else { continue }
                results.append(Candidate(url: url, name: url.deletingPathExtension().lastPathComponent, bottle: bottle))
                if results.count == 200 { break }
            }
        }
        return results.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func add(_ url: URL) {
        guard entries.count < IslandLauncherSupport.maximumItems else {
            showError(strings.capacity)
            return
        }
        let url = url.standardizedFileURL
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
            (try? url.resourceValues(forKeys: [.isApplicationKey]).isApplication) == true
        else {
            showError(strings.invalidApp)
            return
        }
        guard !contains(url) else { return }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let entry = IslandLauncherEntry(
                name: url.deletingPathExtension().lastPathComponent, path: url.path, bookmark: bookmark)
            if append(entry) { autoPlace(entry.id) }
        } catch { showError(strings.saveFailed + " " + error.localizedDescription) }
    }

    @discardableResult func addWebsite(_ input: String, name: String) -> Bool {
        guard let url = IslandLauncherSupport.websiteURL(input) else {
            showError(strings.invalidURL)
            return false
        }
        guard entries.count < IslandLauncherSupport.maximumItems else {
            showError(strings.capacity)
            return false
        }
        guard !entries.contains(where: { $0.websiteURL == url }) else {
            showError(strings.duplicateWebsite)
            return false
        }
        let entry = IslandLauncherEntry(name: name, path: "", website: url.absoluteString)
        guard append(entry) else { return false }
        autoPlace(entry.id)
        WebsiteShortcutIconService.shared.load(entry)
        return true
    }

    private func autoPlace(_ id: UUID) {
        let layout = NotchQuickAccessConfiguration.stored()
        if let side = [NotchQuickAccessSide.right, .left, .bottom].first(where: { layout.hasRoom(on: $0) }) {
            place(id, on: side)
        } else {
            showError(strings.slotsFull)
        }
    }

    func remove(_ id: UUID) {
        WebsiteShortcutIconService.shared.remove(id)
        place(id, on: nil)
        entries.removeAll { $0.id == id }
        save()
    }

    func side(for id: UUID) -> NotchQuickAccessSide? {
        NotchQuickAccessConfiguration.stored().buttons.first { $0.action == .application(id) }?.side
    }

    func place(_ id: UUID, on side: NotchQuickAccessSide?) {
        guard entries.contains(where: { $0.id == id }),
            let layout = NotchQuickAccessConfiguration.stored().placingApplication(id, on: side)
        else {
            showError(strings.slotsFull)
            return
        }
        UserDefaults.standard.set(layout.encoded, forKey: DefaultsKey.notchQuickAccessLayout)
        NotchService.shared.syncWithPreferences()
        objectWillChange.send()
    }

    func move(_ id: UUID, by offset: Int) {
        guard let from = entries.firstIndex(where: { $0.id == id }), entries.indices.contains(from + offset) else {
            return
        }
        entries.swapAt(from, from + offset)
        save()
        var layout = NotchQuickAccessConfiguration.stored()
        let positions = layout.buttons.indices.filter {
            if case .application = layout.buttons[$0].action { return true }
            return false
        }
        let order = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.id, $0.offset) })
        let buttons = positions.map { layout.buttons[$0] }.sorted { a, b in
            guard case .application(let first) = a.action, case .application(let second) = b.action else {
                return false
            }
            return (order[first] ?? Int.max) < (order[second] ?? Int.max)
        }
        for (position, button) in zip(positions, buttons) { layout.buttons[position] = button }
        UserDefaults.standard.set(layout.encoded, forKey: DefaultsKey.notchQuickAccessLayout)
        NotchService.shared.syncWithPreferences()
    }

    func chooseApp() {
        guard chooser == nil else { return }
        let panel = NSOpenPanel()
        panel.title = strings.addApp
        panel.message = strings.invalidApp
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Applications", isDirectory: true)
        panel.prompt = strings.add
        chooser = panel
        isChoosing = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self, weak panel] response in
            guard let self, let panel else { return }
            self.chooser = nil
            self.isChoosing = false
            if response == .OK, let url = panel.url { self.add(url) }
        }
    }

    func launch(_ entry: IslandLauncherEntry) {
        if entry.website != nil {
            guard let url = entry.websiteURL, NSWorkspace.shared.open(url) else {
                showError(strings.websiteFailed)
                return
            }
            return
        }
        guard let url = resolvedURL(entry) else {
            showError(strings.appMissing)
            return
        }
        // CrossOver launchers encode their own bottle and command in the .app wrapper.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.showError(self.strings.appFailed + " " + error.localizedDescription)
            }
        }
    }

    private func append(_ entry: IslandLauncherEntry) -> Bool {
        let updated = IslandLauncherSupport.sanitized(entries + [entry])
        guard updated.count == entries.count + 1 else {
            showError(strings.storageFull)
            return false
        }
        entries = updated
        save()
        return true
    }

    private func save() {
        entries = IslandLauncherSupport.sanitized(entries)
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.notchLauncherEntries)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = strings.title
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
