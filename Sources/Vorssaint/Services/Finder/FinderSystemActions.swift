// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Quartz
import UniformTypeIdentifiers

/// Main-thread macOS presentation. File mutations remain in the queued executor.
final class FinderSystemActions: NSObject, QLPreviewPanelDataSource {
    private var previewURLs: [URL] = []
    private var sharingPicker: NSSharingServicePicker?

    func suspend() {
        if QLPreviewPanel.sharedPreviewPanelExists(), !previewURLs.isEmpty { QLPreviewPanel.shared()?.orderOut(nil) }
        previewURLs = []
        sharingPicker = nil
    }

    func perform(_ action: FinderToolsAction, selection: [URL], destination: URL?, window: NSWindow,
                 completion: @escaping (Result<FinderToolsResult?, Error>) -> Void) {
        guard let first = selection.first else { completion(.failure(CocoaError(.fileNoSuchFile))); return }
        do {
            switch action {
            case .setIcon:
                let chooser = NSOpenPanel()
                chooser.allowedContentTypes = [.image]
                chooser.beginSheetModal(for: window) { response in
                    guard response == .OK, let imageURL = chooser.url, AppFeature.finderTools.isAvailable else {
                        completion(.success(nil)); return
                    }
                    self.applyIcon(imageURL, to: selection, completion: completion)
                }
                return
            case .resetIcon:
                applyIcon(nil, to: selection, completion: completion)
                return
            case .defaultApplication, .openWith:
                if action == .defaultApplication && selection.count != 1 {
                    throw FinderFileActionError.invalidRequest("Select one file to change the default application for its type.")
                }
                let chooser = NSOpenPanel()
                chooser.allowedContentTypes = [.applicationBundle]
                chooser.beginSheetModal(for: window) { response in
                    guard response == .OK, let app = chooser.url, AppFeature.finderTools.isAvailable else {
                        completion(.success(nil)); return
                    }
                    let finish: (Error?) -> Void = { error in
                        DispatchQueue.main.async {
                            if let error { completion(.failure(error)) }
                            else { completion(.success(nil)) }
                        }
                    }
                    if action == .defaultApplication {
                        Task {
                            do {
                                try await NSWorkspace.shared.setDefaultApplication(at: app, toOpenContentTypeOfFileAt: first)
                                finish(nil)
                            } catch { finish(error) }
                        }
                    } else {
                        NSWorkspace.shared.open(selection, withApplicationAt: app, configuration: .init()) { _, error in finish(error) }
                    }
                }
                return
            case .quickLook:
                previewURLs = selection
                let panel = QLPreviewPanel.shared()
                panel?.dataSource = self
                panel?.reloadData()
                panel?.makeKeyAndOrderFront(nil)
            case .reveal:
                NSWorkspace.shared.activateFileViewerSelecting(selection)
            case .packageContents:
                let values = try first.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                guard values.isDirectory == true, values.isPackage == true else { throw CocoaError(.fileReadUnsupportedScheme) }
                let contents = try FileManager.default.contentsOfDirectory(at: first, includingPropertiesForKeys: nil)
                guard let item = contents.first else { throw CocoaError(.fileReadUnknown) }
                NSWorkspace.shared.activateFileViewerSelecting([item])
            case .share:
                guard let view = window.contentView else { throw CocoaError(.featureUnsupported) }
                let picker = NSSharingServicePicker(items: selection)
                sharingPicker = picker
                picker.show(relativeTo: CGRect(x: view.bounds.midX, y: 15, width: 1, height: 1), of: view, preferredEdge: .minY)
            case .wallpaper:
                guard selection.count == 1 else { throw CocoaError(.fileReadUnsupportedScheme) }
                for screen in NSScreen.screens {
                    try NSWorkspace.shared.setDesktopImageURL(first, for: screen, options: [:])
                }
            case .eject:
                for item in selection { try NSWorkspace.shared.unmountAndEjectDevice(at: item) }
            case .openTerminal:
                let isDirectory = try first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                let folder = isDirectory ? first : first.deletingLastPathComponent()
                let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: .init()) { _, error in
                    DispatchQueue.main.async {
                        if let error { completion(.failure(error)) }
                        else { completion(.success(nil)) }
                    }
                }
                return
            case .extractIcon:
                guard let destination else { throw CocoaError(.fileWriteInvalidFileName) }
                let icon = NSWorkspace.shared.icon(forFile: first.path)
                var rect = CGRect(x: 0, y: 0, width: 512, height: 512)
                guard let image = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { throw CocoaError(.fileReadUnknown) }
                let output = try FinderImageTools.savePNG(image, in: destination,
                    named: first.lastPathComponent + "-icon", cancellation: FinderToolsCancellation())
                completion(.success(FinderToolsResult(outputs: [output])))
                return
            case .info:
                DispatchQueue.global(qos: .userInitiated).async {
                    let allowed = AppleScriptRunner.consentToAutomate(bundleID: "com.apple.finder")
                    let targets = selection.map { "open information window of (POSIX file \(AppleScriptRunner.literal($0.path)) as alias)" }
                        .joined(separator: "\n")
                    let result = allowed ? AppleScriptRunner.run("with timeout of 15 seconds\ntell application \"Finder\"\n\(targets)\nend tell\nend timeout") : (ok: false, output: "")
                    DispatchQueue.main.async {
                        completion(result.ok ? .success(nil) : .failure(CocoaError(.fileReadNoPermission)))
                    }
                }
                return
            default: throw CocoaError(.featureUnsupported)
            }
            // Opening a system panel is not a claim that a share or preview was completed.
            completion(.success(nil))
        } catch { completion(.failure(error)) }
    }

    func applyIcon(_ imageURL: URL?, to selection: [URL], completion: @escaping (Result<FinderToolsResult?, Error>) -> Void) {
        do {
            let image = try imageURL.map { NSImage(cgImage: try FinderImageTools.load($0), size: NSSize(width: 512, height: 512)) }
            var result = FinderToolsResult()
            for item in selection {
                do {
                    guard try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                          NSWorkspace.shared.setIcon(image, forFile: item.path, options: []) else {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    result.outputs.append(item)
                } catch { result.failures.append(.init(url: item, reason: error.localizedDescription)) }
            }
            completion(.success(result))
        } catch { completion(.failure(error)) }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard previewURLs.indices.contains(index) else { return nil }
        return previewURLs[index] as NSURL
    }
}
