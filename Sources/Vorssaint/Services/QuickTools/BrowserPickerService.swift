// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct PickerBrowser: Identifiable {
    let id: String
    let name: String
    let url: URL
    let icon: NSImage
}

final class BrowserPickerService: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = BrowserPickerService()
    @Published private(set) var browsers: [PickerBrowser] = []
    @Published private(set) var hiddenBrowserIDs: Set<String> = []
    var visibleBrowsers: [PickerBrowser] {
        browsers.filter { !hiddenBrowserIDs.contains($0.id) }
    }
    @Published var selection = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var isOpening = false
    @Published private(set) var isSettingDefault = false
    @Published private(set) var isDefaultBrowser = false
    private var pendingURLs: [URL] = []
    private var panel: BrowserPickerPanel?
    private var keyMonitor: Any?
    private var requestID = UUID()

    private override init() {
        super.init()
        SessionActivity.shared.onChange { [weak self] active in
            DispatchQueue.main.async {
                guard let self else { return }
                if !active { self.hide() }
                else if !self.pendingURLs.isEmpty { self.show() }
            }
        }
    }

    func syncWithPreferences() {
        if !AppFeature.browserPicker.isAvailable { hide() }
    }

    func suspend() { hide() }

    func refresh() {
        let workspace = NSWorkspace.shared
        let candidates = workspace.urlsForApplications(toOpen: URL(string: "https://example.com")!)
        var seen = Set<String>()
        let installed = candidates.compactMap { url -> PickerBrowser? in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  !BrowserPickerSupport.isPicker(id),
                  FileManager.default.fileExists(atPath: url.path),
                  seen.insert(id).inserted else { return nil }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            return PickerBrowser(id: id, name: name, url: url, icon: workspace.icon(forFile: url.path))
        }.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
        let order = BrowserPickerSupport.orderedIDs(available: installed.map(\.id),
            saved: UserDefaults.standard.string(forKey: DefaultsKey.browserPickerOrder) ?? "[]")
        let byID = Dictionary(uniqueKeysWithValues: installed.map { ($0.id, $0) })
        browsers = order.compactMap { byID[$0] }
        hiddenBrowserIDs = BrowserPickerSupport.hiddenIDs(
            UserDefaults.standard.string(forKey: DefaultsKey.browserPickerHiddenBrowsers) ?? "[]")
        selection = min(selection, max(0, visibleBrowsers.count - 1))
        updateVisiblePanelFrame()
        isDefaultBrowser = ["http", "https"].allSatisfy { scheme in
            guard let url = workspace.urlForApplication(toOpen: URL(string: "\(scheme)://example.com")!) else { return false }
            return Bundle(url: url)?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
    }

    func moveBrowser(_ source: String, onto target: String) {
        setBrowserOrder(BrowserPickerSupport.reorderedIDs(browsers.map(\.id), moving: source, onto: target))
    }

    func setBrowserOrder(_ ids: [String]) {
        let current = browsers.map(\.id)
        guard ids != current, ids.count == current.count, Set(ids) == Set(current) else { return }
        let selectedID = visibleBrowsers.indices.contains(selection) ? visibleBrowsers[selection].id : nil
        let byID = Dictionary(uniqueKeysWithValues: browsers.map { ($0.id, $0) })
        browsers = ids.compactMap { byID[$0] }
        UserDefaults.standard.set(BrowserPickerSupport.encodedOrder(ids), forKey: DefaultsKey.browserPickerOrder)
        selection = visibleBrowsers.firstIndex { $0.id == selectedID } ?? 0
    }

    func setBrowserEnabled(_ browser: PickerBrowser, enabled: Bool) {
        if enabled { hiddenBrowserIDs.remove(browser.id) }
        else { hiddenBrowserIDs.insert(browser.id) }
        UserDefaults.standard.set(BrowserPickerSupport.encodedOrder(hiddenBrowserIDs.sorted()),
                                  forKey: DefaultsKey.browserPickerHiddenBrowsers)
        selection = 0
        updateVisiblePanelFrame()
    }

    func updateVisiblePanelFrame() {
        guard let panel, panel.isVisible else { return }
        position(panel)
    }

    private func position(_ panel: NSPanel) {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let placement = UserDefaults.standard.string(forKey: DefaultsKey.browserPickerPlacement) ?? "center"
        panel.setFrame(BrowserPickerSupport.windowFrame(browserCount: visibleBrowsers.count,
            visibleFrame: visibleFrame, cursor: cursor, placement: placement), display: true)
    }

    func makeDefault() {
        guard AppFeature.browserPicker.isAvailable, !isSettingDefault else { return }
        isSettingDefault = true
        errorMessage = nil
        // Preserve the original handlers on this Mac for forwarding if the feature is disabled.
        var previous = UserDefaults.standard.dictionary(forKey: DefaultsKey.browserPickerPreviousHandlers) as? [String: String] ?? [:]
        for scheme in ["http", "https"] {
            if let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\(scheme)://example.com")!),
               let id = Bundle(url: app)?.bundleIdentifier, !BrowserPickerSupport.isPicker(id) {
                previous[scheme] = id
            }
        }
        UserDefaults.standard.set(previous, forKey: DefaultsKey.browserPickerPreviousHandlers)
        Task { @MainActor in
            defer { isSettingDefault = false; refresh() }
            do {
                for scheme in ["http", "https"] {
                    try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL,
                                                                      toOpenURLsWithScheme: scheme)
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func receive(_ urls: [URL]) {
        let webURLs = BrowserPickerSupport.webURLs(urls)
        guard !webURLs.isEmpty else { return }
        guard AppFeature.browserPicker.isAvailable else {
            forwardWhenDisabled(webURLs)
            return
        }
        pendingURLs.append(contentsOf: webURLs)
        show()
    }

    private func forwardWhenDisabled(_ urls: [URL]) {
        refresh()
        let previous = UserDefaults.standard.dictionary(forKey: DefaultsKey.browserPickerPreviousHandlers) as? [String: String] ?? [:]
        for (scheme, group) in Dictionary(grouping: urls, by: { $0.scheme?.lowercased() ?? "https" }) {
            let savedApp = previous[scheme].flatMap { id -> URL? in
                guard !BrowserPickerSupport.isPicker(id) else { return nil }
                return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            }
            guard let app = savedApp ?? browsers.first?.url else {
                let alert = NSAlert()
                alert.messageText = FeatureStrings.browserPicker(L10n.shared.language).empty
                alert.runModal()
                continue
            }
            NSWorkspace.shared.open(group, withApplicationAt: app, configuration: .init()) { _, error in
                if let error { DispatchQueue.main.async { NSAlert(error: error).runModal() } }
            }
        }
    }

    func show() {
        guard AppFeature.browserPicker.isAvailable, SessionActivity.shared.isActive else { return }
        refresh()
        errorMessage = nil
        if panel?.isVisible == true { panel?.makeKeyAndOrderFront(nil); return }
        selection = 0
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.panel else { return event }
                if event.keyCode == UInt16(kVK_Escape) { self.hide(); return nil }
                guard !self.isOpening else { return nil }
                if event.keyCode == UInt16(kVK_LeftArrow) {
                    self.selection = max(0, self.selection - 1); return nil
                }
                if event.keyCode == UInt16(kVK_RightArrow) {
                    self.selection = min(max(0, self.visibleBrowsers.count - 1), self.selection + 1); return nil
                }
                if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_Space) {
                    self.choose(self.selection); return nil
                }
                if let number = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(number) {
                    self.choose(number - 1); return nil
                }
                return event
            }
        }
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> BrowserPickerPanel {
        let panel = BrowserPickerPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: BrowserPickerView(service: self))
        return panel
    }

    func windowDidResignKey(_ notification: Notification) {
        if !isOpening { hide() }
    }

    func hide() {
        panel?.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        pendingURLs = []
        requestID = UUID()
        isOpening = false
    }

    func choose(_ index: Int) {
        guard AppFeature.browserPicker.isAvailable, SessionActivity.shared.isActive, !isOpening, visibleBrowsers.indices.contains(index) else { return }
        let browser = visibleBrowsers[index]
        let urls = pendingURLs
        let token = requestID
        isOpening = true
        errorMessage = nil
        let completion: (NSRunningApplication?, Error?) -> Void = { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self, self.requestID == token else { return }
                self.isOpening = false
                if let error { self.errorMessage = error.localizedDescription; return }
                self.pendingURLs.removeFirst(min(urls.count, self.pendingURLs.count))
                if self.pendingURLs.isEmpty { self.hide() }
                else { self.panel?.makeKeyAndOrderFront(nil) }
            }
        }
        if urls.isEmpty {
            NSWorkspace.shared.openApplication(at: browser.url, configuration: .init(), completionHandler: completion)
        } else {
            NSWorkspace.shared.open(urls, withApplicationAt: browser.url, configuration: .init(), completionHandler: completion)
        }
    }
}

private final class BrowserPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
