// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Owns one on-demand workspace; installing the feature starts no background monitor.
final class FinderToolsService: ObservableObject {
    static let shared = FinderToolsService()

    @Published var configuration = FinderToolsConfiguration.decode(
        UserDefaults.standard.string(forKey: DefaultsKey.finderToolsConfiguration)) {
        didSet {
            UserDefaults.standard.set(configuration.encoded, forKey: DefaultsKey.finderToolsConfiguration)
            publishMenu()
        }
    }
    @Published var pendingSavedAction: FinderToolsSavedAction?
    @Published var selection: [URL] = []
    @Published var destination: URL?
    @Published var action: FinderToolsAction = .newFile {
        didSet {
            guard oldValue != action else { return }
            result = nil
            error = nil
            name = FinderToolsStrings.defaultName(action, language: L10n.shared.language)
        }
    }
    @Published var name = FinderToolsStrings.defaultName(.newFile, language: L10n.shared.language)
    @Published var treeDepth = 8
    @Published var filenameEncoding = String.Encoding.windowsCP1252.rawValue
    @Published var watermark = ""
    @Published var password = ""
    @Published var terminalTarget = FinderTerminalTarget.terminal
    @Published var terminalMode = FinderTerminalMode.window
    @Published var imageColor = Color.black
    @Published private(set) var isRunning = false
    @Published private(set) var result: FinderToolsResult?
    @Published private(set) var error: String?

    private var window: NSWindow?
    private var captureWindow: FinderCaptureWindow?
    private var sharingWindow: FinderLANShareWindow?
    private var mediaWindow: NSWindow?
    private var media: MediaService?
    private let systemActions = FinderSystemActions()
    private let queue = DispatchQueue(label: "com.vorssaint.finder-tools", qos: .userInitiated)
    private var cancellation: FinderToolsCancellation?
    private var configurationWindow: NSWindow?

    func open(request: FinderToolsRequest? = nil) {
        guard AppFeature.finderTools.isAvailable else { showFeatureSettings(); return }
        if let request, !isRunning {
            if let action = request.suggestedAction { self.action = action }
            pendingSavedAction = configuration.savedActions.first { $0.id == request.savedActionID }
            selection = request.selection
            destination = request.directory ?? request.selection.first?.deletingLastPathComponent()
            result = nil
            error = nil
        }
        if window == nil {
            let controller = NSHostingController(rootView: FinderToolsView(service: self))
            let panel = NSWindow(contentViewController: controller)
            panel.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            panel.setContentSize(NSSize(width: 650, height: 540))
            panel.minSize = NSSize(width: 540, height: 440)
            panel.isReleasedWhenClosed = false
            panel.tabbingMode = .disallowed
            panel.center()
            window = panel
        }
        window?.title = FinderToolsStrings.localized(L10n.shared.language).title
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func syncWithPreferences() {
        let saved = FinderToolsConfiguration.decode(UserDefaults.standard.string(forKey: DefaultsKey.finderToolsConfiguration))
        if saved != configuration { configuration = saved }
        publishMenu()
        if !AppFeature.finderTools.isAvailable { suspend() }
    }

    func publishMenu() {
        FinderToolsMenuSnapshot(enabled: AppFeature.finderTools.isAvailable, language: L10n.shared.language.rawValue,
            menu: configuration.menu, savedItems: configuration.savedActions.map {
                FinderToolsMenuSnapshot.SavedItem(id: $0.id, title: $0.title, group: $0.group)
            }).publish()
    }

    func openConfiguration() {
        guard AppFeature.finderTools.isAvailable else { return }
        if configurationWindow == nil {
            let host = NSHostingController(rootView: FinderToolsConfigurationView(service: self))
            let panel = NSWindow(contentViewController: host)
            panel.styleMask = [.titled, .closable, .resizable]
            panel.title = FinderToolsStrings.localized(L10n.shared.language).title
            panel.setContentSize(NSSize(width: 680, height: 600))
            panel.isReleasedWhenClosed = false
            panel.tabbingMode = .disallowed
            panel.center()
            configurationWindow = panel
        }
        configurationWindow?.makeKeyAndOrderFront(nil)
    }

    func runSavedAction(_ saved: FinderToolsSavedAction) {
        guard AppFeature.finderTools.isAvailable, !isRunning,
              configuration.savedActions.contains(saved) else { return }
        switch saved.kind {
        case .folder, .website:
            if !NSWorkspace.shared.open(saved.location) { error = CocoaError(.fileReadUnknown).localizedDescription }
        case .application:
            isRunning = true
            NSWorkspace.shared.open(selection, withApplicationAt: saved.location, configuration: .init()) { [weak self] _, failure in
                DispatchQueue.main.async {
                    self?.isRunning = false
                    if AppFeature.finderTools.isAvailable { self?.error = failure?.localizedDescription }
                }
            }
        case .icon:
            systemActions.applyIcon(saved.location, to: selection) { [weak self] outcome in
                switch outcome {
                case .success(let result): self?.result = result
                case .failure(let error): self?.error = error.localizedDescription
                }
            }
        case .template:
            selection = [saved.location]
            action = .template
            name = saved.location.lastPathComponent
        case .script:
            let token = FinderToolsCancellation()
            cancellation = token
            isRunning = true
            result = nil
            error = nil
            let inputs = selection
            let folder = destination
            queue.async { [weak self] in
                let outcome = Result { try FinderScriptOperation.run(saved.location, selection: inputs,
                    directory: folder, cancellation: token) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isRunning = false
                    self.cancellation = nil
                    guard AppFeature.finderTools.isAvailable else { return }
                    switch outcome {
                    case .success(let text): self.result = FinderToolsResult(text: text)
                    case .failure(let error): self.error = error.localizedDescription
                    }
                }
            }
        }
    }

    func openFromFinder() {
        guard AppFeature.finderTools.isAvailable else { return }
        // Do not ask for automation permission just to open a workspace. If
        // Finder access is absent, the regular file chooser remains available.
        queue.async { [weak self] in
            let selected = FinderBridge.selectionURLs(requestPermission: false)
            DispatchQueue.main.async {
                guard let self, AppFeature.finderTools.isAvailable else { return }
                self.open(request: selected.isEmpty ? nil : FinderToolsRequest(selection: selected, directory: nil))
            }
        }
    }

    func suspend() {
        cancellation?.cancel()
        window?.close()
        configurationWindow?.close()
        pendingSavedAction = nil
        sharingWindow?.close()
        sharingWindow = nil
        captureWindow?.stopAndClose()
        password = ""
        suspendMedia()
        systemActions.suspend()
        // Keep the job token until completion; reinstallation cannot start a
        // concurrent mutation while a filesystem call is still finishing.
        selection = []
        destination = nil
        result = nil
        error = nil
    }

    func suspendMedia() {
        media?.cancel()
        mediaWindow?.close()
        mediaWindow = nil
        media = nil
    }

    /// Keep an active recording alive until AVFoundation has finalized its
    /// file. The visible recorder explains why this quit was deferred.
    func prepareForTermination() -> Bool {
        guard let captureWindow, captureWindow.recorder.state.isBusy else { return true }
        captureWindow.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        captureWindow.recorder.stop()
        return false
    }

    func chooseFiles() {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, AppFeature.finderTools.isAvailable, !self.isRunning else { return }
            self.selection = panel.urls
            if self.destination == nil { self.destination = panel.urls.first?.deletingLastPathComponent() }
        }
    }

    func chooseDestination() {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = destination
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, AppFeature.finderTools.isAvailable, !self.isRunning else { return }
            self.destination = panel.url
        }
    }

    var canCancel: Bool { cancellation != nil }

    func cancel() { cancellation?.cancel() }

    func run() {
        guard AppFeature.finderTools.isAvailable, !isRunning else { return }
        result = nil
        error = nil
        if action.usesExistingTool { openExistingTool(); return }
        if action == .openTerminal {
            isRunning = true
            FinderTerminalAdapter.open(terminalTarget, mode: terminalMode, selection: selection) { [weak self] error in
                self?.isRunning = false
                if AppFeature.finderTools.isAvailable { self?.error = error?.localizedDescription }
            }
            return
        }
        if action.usesSystemUI, let window {
            isRunning = true
            result = nil
            error = nil
            systemActions.perform(action, selection: selection, destination: destination, window: window) { [weak self] outcome in
                guard let self else { return }
                self.isRunning = false
                guard AppFeature.finderTools.isAvailable else { return }
                switch outcome {
                case .success(let result): self.result = result
                case .failure(let error): self.error = error.localizedDescription
                }
            }
            return
        }
        let color = NSColor(imageColor).usingColorSpace(.sRGB) ?? .black
        var clipboardImage: Data?
        if action == .pasteImage, let image = NSImage(pasteboard: .general),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           cgImage.width <= FinderImageTools.maximumDimension, cgImage.height <= FinderImageTools.maximumDimension,
           cgImage.width * cgImage.height <= FinderImageTools.maximumPixels {
            clipboardImage = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        }
        let copiedFiles: [URL] = [.pasteFiles, .pasteAliases, .pasteZIP].contains(action)
            ? (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []) : []
        let copiedText = [.pasteText, .pasteMarkdown].contains(action) ? NSPasteboard.general.string(forType: .string) : nil
        let creation = configuration.creation ?? FinderCreationPreferences()
        let isCreation = [.newFile, .newFolder, .template, .pasteText, .pasteMarkdown, .pasteImage].contains(action)
        let operation = FinderToolsOperation(action: action, selection: selection, destination: destination,
            name: name, clipboardText: copiedText, treeDepth: treeDepth, filenameEncoding: filenameEncoding,
            watermark: watermark, red: color.redComponent, green: color.greenComponent, blue: color.blueComponent,
            password: password.isEmpty ? nil : password, clipboardImage: clipboardImage, clipboardFiles: copiedFiles,
            uniqueNames: creation.uniqueNames)
        password = ""
        let token = FinderToolsCancellation()
        cancellation = token
        result = nil
        error = nil
        isRunning = true
        queue.async { [weak self] in
            let outcome = Result {
                var result = try FinderToolsExecutor.execute(operation, cancellation: token)
                if isCreation, creation.hideExtension, operation.action != .newFolder {
                    for var url in result.outputs {
                        do {
                            var values = URLResourceValues()
                            values.hasHiddenExtension = true
                            try url.setResourceValues(values)
                        } catch { result.failures.append(.init(url: url, reason: error.localizedDescription)) }
                    }
                }
                return result
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRunning = false
                self.cancellation = nil
                guard AppFeature.finderTools.isAvailable else { return }
                switch outcome {
                case .success(var result):
                    if isCreation, result.failures.isEmpty {
                        if creation.openAfterCreation {
                            for url in result.outputs where !NSWorkspace.shared.open(url) {
                                result.failures.append(.init(url: url, reason: "The file was created, but its application could not be opened."))
                            }
                        }
                        if creation.playSound, !result.outputs.isEmpty { NSSound(named: "Glass")?.play() }
                    }
                    self.result = result
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }

    private func openExistingTool() {
        if let tool = FinderToolsSystemTool.tool(for: action) {
            guard tool.isRunnable() else { showFeatureSettings(); return }
            AppToolLauncher.run(tool)
            return
        }
        if action == .cutFiles || action == .pasteMovedFiles {
            guard AppFeature.finderCutPaste.isAvailable,
                  UserDefaults.standard.bool(forKey: DefaultsKey.finderCutPasteEnabled) else {
                showFeatureSettings()
                return
            }
            if action == .cutFiles {
                if !FinderCutPaste.shared.cutFromTools(selection) { error = "No files could be marked for moving." }
            } else if let destination {
                if !FinderCutPaste.shared.pasteFromTools(into: destination) {
                    error = "Cut files first. The clipboard may have changed or another move is in progress."
                }
            }
            return
        }
        if action == .uninstallApp {
            guard AppFeature.uninstaller.isAvailable else { showFeatureSettings(); return }
            guard selection.count == 1, AppUninstaller.shared.select(appURL: selection[0]) else {
                error = "Select one application bundle. An uninstall may already be in progress."
                return
            }
            AppToolLauncher.run(.uninstaller)
            return
        }
        if action == .recordAudio || action == .recordVideo {
            if let captureWindow, captureWindow.recorder.state.isBusy { captureWindow.showWindow(nil); return }
            captureWindow?.close()
            let controller = FinderCaptureWindow(video: action == .recordVideo)
            captureWindow = controller
            controller.showWindow(nil)
            return
        }
        guard !selection.isEmpty else { return }
        if action == .shareLAN {
            sharingWindow?.close()
            let controller = FinderLANShareWindow(selection: selection)
            sharingWindow = controller
            controller.showWindow(nil)
            return
        }
        if action == .editImage {
            guard AppFeature.screenshot.isAvailable else { showFeatureSettings(); return }
            ScreenshotService.shared.editImage(at: selection[0])
            return
        }
        guard AppFeature.mediaTools.isAvailable else { showFeatureSettings(); return }
        // A visible workspace owns its service and cannot cancel another media export.
        if let mediaWindow, mediaWindow.isVisible { mediaWindow.makeKeyAndOrderFront(nil); return }
        media?.cancel()
        let media = MediaService(replacesExistingOutputs: false)
        let tool: MediaTool = action == .convertVideo ? .videoCompressor
            : action == .extractText ? .textExtractor : .imageCompressor
        let host = NSHostingController(rootView: MediaWorkspaceView(compact: false,
            media: media, initialInputs: selection, initialTool: tool))
        let panel = NSWindow(contentViewController: host)
        panel.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        panel.title = action.title(languageCode: L10n.shared.language.rawValue)
        panel.setContentSize(NSSize(width: 900, height: 700))
        panel.isReleasedWhenClosed = false
            panel.tabbingMode = .disallowed
        panel.center()
        self.media = media
        mediaWindow = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func showFeatureSettings() {
        SettingsRouter.shared.page = .features
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }

    func copyResult() {
        guard let text = result?.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
