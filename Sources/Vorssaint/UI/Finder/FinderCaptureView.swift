// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct FinderCaptureView: View {
    @ObservedObject var recorder: FinderCaptureRecorder
    let video: Bool
    @ObservedObject private var l10n = L10n.shared
    @State private var microphone = true
    @State private var startedAt = Date()
    private var text: RecorderFeatureStrings { FeatureStrings.recorder(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text((video ? FinderToolsAction.recordVideo : .recordAudio).title(languageCode: l10n.language.rawValue)).font(.title2.bold())
            if video { Toggle(text.microphoneToggle, isOn: $microphone).disabled(recorder.state.isBusy) }
            if let session = recorder.previewSession { FinderCapturePreview(session: session).frame(minHeight: 240) }
            switch recorder.state {
            case .preparing, .finishing: ProgressView()
            case .recording: Label { Text(startedAt, style: .timer).monospacedDigit() } icon: { Image(systemName: "record.circle.fill").foregroundStyle(.red) }
            case .saved(let url):
                Text(url.path).textSelection(.enabled)
                Button(FinderToolsAction.reveal.title(languageCode: l10n.language.rawValue)) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            case .failed(let reason): Text(reason).foregroundStyle(.red).textSelection(.enabled)
            case .idle: EmptyView()
            }
            Spacer()
            HStack {
                Spacer()
                if recorder.state.isBusy {
                    Button(text.stopButton) { recorder.stop() }.disabled(recorder.state == .finishing)
                } else {
                    Button(text.startButton) { chooseOutput() }.buttonStyle(.borderedProminent)
                }
            }
        }.padding(22).frame(minWidth: 480, minHeight: video ? 380 : 200)
            .onChange(of: recorder.state) { _, state in if state == .recording { startedAt = Date() } }
    }

    private func chooseOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [video ? .quickTimeMovie : .mpeg4Audio]
        panel.nameFieldStringValue = FinderToolsStrings.defaultName(.extractAudio, language: l10n.language) + (video ? ".mov" : ".m4a")
        panel.begin { response in
            guard response == .OK, let url = panel.url, AppFeature.finderTools.isAvailable else { return }
            recorder.start(video: video, microphone: microphone, destination: url)
        }
    }
}

private struct FinderCapturePreview: NSViewRepresentable {
    let session: AVCaptureSession
    final class Preview: NSView {
        let preview = AVCaptureVideoPreviewLayer()
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            preview.videoGravity = .resizeAspect
            layer?.addSublayer(preview)
        }
        required init?(coder: NSCoder) { nil }
        override func layout() { super.layout(); preview.frame = bounds }
    }
    func makeNSView(context: Context) -> Preview { Preview() }
    func updateNSView(_ view: Preview, context: Context) { view.preview.session = session }
}

final class FinderCaptureWindow: NSWindowController, NSWindowDelegate {
    let recorder = FinderCaptureRecorder()
    private var forceClose = false
    init(video: Bool) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: FinderCaptureView(recorder: recorder, video: video)))
        window.styleMask = [.titled, .closable, .resizable]
        window.title = (video ? FinderToolsAction.recordVideo : .recordAudio).title(languageCode: L10n.shared.language.rawValue)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !forceClose, recorder.state.isBusy else { return true }
        recorder.stop()
        return false
    }
    func stopAndClose() {
        forceClose = true
        recorder.stop()
        close()
    }
}
