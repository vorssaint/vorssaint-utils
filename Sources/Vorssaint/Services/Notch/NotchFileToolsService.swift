// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Darwin

struct NotchMediaSession: Identifiable {
    let id = UUID()
    let inputs: [URL]
    let tool: MediaTool
}

final class NotchFileToolsService: ObservableObject {
    static let shared = NotchFileToolsService()
    let media = MediaService(replacesExistingOutputs: false)
    @Published private(set) var mediaSession: NotchMediaSession?
    @Published private(set) var mediaPresented = false
    @Published private(set) var mediaContentHeight: CGFloat?
    private(set) var mediaSelection = MediaWorkspaceSelection()
    private var mediaResults: AnyCancellable?
    @Published private(set) var isRunning = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var outputURLs: [URL] = []
    @Published private(set) var failure: String?
    @Published private(set) var wasCancelled = false
    private var operation: NotchArchiveOperation?
    private let queue = DispatchQueue(label: "com.vorssaint.notch.archive", qos: .userInitiated)
    private var generation = UUID()

    private init() {}
    deinit { operation?.cancel(immediately: true) }

    var offersMediaDrop: Bool {
        NotchSupport.isEnabled() && NotchSupport.modules().contains(.files)
            && AppFeature.mediaTools.isAvailable && AppFeature.shelf.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled)
    }

    var canAcceptMediaDrop: Bool {
        if case .running = media.state { return false }
        return offersMediaDrop && !isRunning
    }

    func mediaDropContent(for pasteboard: NSPasteboard) -> (tool: MediaTool, inputs: [URL])? {
        guard offersMediaDrop,
              !pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil) else { return nil }
        let inputs = ShelfService.shared.fileURLs(from: pasteboard)
        // Mixed payloads stay in the shelf, where every companion is preserved.
        guard inputs.count >= (pasteboard.pasteboardItems?.count ?? 0) else { return nil }
        guard let tool = NotchFileToolsSupport.optimizationTool(for: inputs) else { return nil }
        return (tool, inputs)
    }

    func openMediaDrop(_ pasteboard: NSPasteboard) -> Bool {
        guard canAcceptMediaDrop, let content = mediaDropContent(for: pasteboard) else { return false }
        return openMedia(content.tool, inputs: content.inputs)
    }

    func updateMediaHeight(id: UUID, height: CGFloat) {
        guard mediaSession?.id == id, height.isFinite, height > 0 else { return }
        let measured = ceil(height)
        if mediaContentHeight != measured { mediaContentHeight = measured }
    }

    func showMedia() {
        guard offersMediaDrop, mediaSession != nil else { return }
        mediaPresented = true
    }

    func hideMedia() {
        mediaPresented = false
    }

    func syncWithPreferences() {
        guard NotchSupport.isEnabled(), NotchSupport.modules().contains(.files),
              AppFeature.mediaTools.isAvailable, AppFeature.shelf.isAvailable else {
            stop()
            return
        }
    }

    /// A real stop, including application termination, must not depend on the
    /// saved switches. Killing the owned child now also works when there will
    /// be no future run-loop turn to deliver a delayed cancellation fallback.
    func stop() {
        if isRunning { wasCancelled = true }
        generation = UUID()
        operation?.cancel(immediately: true)
        operation = nil
        isRunning = false
        mediaResults = nil
        media.cancel(immediately: true)
        mediaSelection.durationLoading.cancel()
        mediaSelection = MediaWorkspaceSelection()
        mediaSession = nil
        mediaPresented = false
        mediaContentHeight = nil
    }

    @discardableResult
    func openMedia(_ tool: MediaTool, inputs: [URL]) -> Bool {
        guard NotchSupport.isEnabled(), NotchSupport.modules().contains(.files),
              AppFeature.mediaTools.isAvailable, AppFeature.shelf.isAvailable,
              NotchFileToolsSupport.accepts(inputs, for: tool) else { return false }
        closeMedia()
        mediaSession = NotchMediaSession(inputs: inputs, tool: tool)
        mediaPresented = true
        mediaResults = media.$state.dropFirst().sink { state in
            guard case let .completed(result) = state, AppFeature.shelf.isAvailable else { return }
            _ = ShelfService.shared.addFiles(result.outputURLs)
        }
        return true
    }

    func closeMedia() {
        mediaResults = nil
        media.reset()
        mediaSelection.durationLoading.cancel()
        mediaSelection = MediaWorkspaceSelection()
        mediaSession = nil
        mediaPresented = false
        mediaContentHeight = nil
    }

    func cancel() {
        guard isRunning else { return }
        wasCancelled = true
        operation?.cancel()
    }

    func archive(_ inputs: [URL], destination: URL, directory: Bool) {
        guard !isRunning, AppFeature.notch.isAvailable, AppFeature.shelf.isAvailable,
              AppFeature.mediaTools.isAvailable, NotchSupport.isEnabled(),
              NotchSupport.modules().contains(.files) else { return }
        guard destination.isFileURL, !inputs.isEmpty, inputs.allSatisfy(\.isFileURL) else {
            failure = CocoaError(.fileWriteInvalidFileName).localizedDescription
            return
        }
        let job = NotchArchiveOperation()
        operation = job
        let id = UUID()
        generation = id
        completed = 0
        total = inputs.count
        outputURLs = []
        failure = nil
        wasCancelled = false
        isRunning = true
        queue.async { [weak self] in
            var failure: String?
            let safeDestination = NotchFileToolsSupport.destinationIsOutsideInputs(destination, inputs: inputs)
            if !safeDestination { failure = CocoaError(.fileWriteInvalidFileName).localizedDescription }
            for input in inputs where safeDestination {
                let output = directory
                    ? MediaSupport.uniqueOutputURL(in: destination, baseName: input.lastPathComponent, fileExtension: "zip")
                    : destination
                do {
                    try job.archive(input, to: output)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == id else { return }
                        self.completed += 1
                        self.outputURLs.append(output)
                        if AppFeature.shelf.isAvailable { _ = ShelfService.shared.addFiles([output]) }
                    }
                } catch is CancellationError { break }
                catch { failure = error.localizedDescription; break }
            }
            let finalFailure = failure
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == id else { return }
                self.failure = finalFailure
                self.operation = nil
                self.isRunning = false
            }
        }
    }
}
