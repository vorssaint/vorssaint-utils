// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Based on Textream by Fatih Kadir Akın (MIT License)

import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - External Display View

struct ExternalDisplayView: View {
    @ObservedObject var service: TeleprompterService
    @ObservedObject var recognizer: SpeechRecognizer
    let words: [String]
    let script: String
    let mirrorAxis: ExternalMirrorAxis?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            SpeechScrollView(
                words: words,
                highlightedCharCount: recognizer.recognizedCharCount,
                font: service.fontFamily.nsFont(ofSize: service.fontSize.pointSize * 1.5),
                highlightColor: service.highlightColor.color,
                cueColor: service.cueColor.color,
                cueUnreadOpacity: service.cueBrightness.alpha * 0.35,
                cueReadOpacity: service.cueBrightness.alpha,
                onWordTap: nil,
                smoothScroll: true,
                isListening: recognizer.isListening,
                paragraphBreakBeforeWordIndices: service.showParagraphDividers ? paragraphBreakWordIndices(in: script) : [],
                readingPosition: service.readingPosition,
                showLastSpokenWords: service.showLastSpokenWords
            )
            .padding(40)
            .scaleEffect(
                x: (mirrorAxis == .horizontal || mirrorAxis == .both) ? -1 : 1,
                y: (mirrorAxis == .vertical || mirrorAxis == .both) ? -1 : 1
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - External Display Controller

@MainActor
final class ExternalDisplayController {
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()

    /// Find the target external screen based on saved screen ID or first non-main screen
    func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens.filter { $0 != NSScreen.main }
        guard !screens.isEmpty else { return nil }

        let savedID = UInt32(UserDefaults.standard.integer(forKey: DefaultsKey.teleprompterExternalScreenID))
        if savedID != 0, let match = screens.first(where: { $0.displayID == savedID }) {
            return match
        }
        return screens.first
    }

    func show(
        speechRecognizer: SpeechRecognizer,
        words: [String],
        script: String,
        mode: ExternalDisplayMode,
        mirrorAxis: ExternalMirrorAxis
    ) {
        guard mode != .off else { return }
        guard let screen = targetScreen() else { return }

        dismiss()

        let axis = (mode == .mirror) ? mirrorAxis : nil
        let screenFrame = screen.frame
        let service = TeleprompterService.shared

        let content = ExternalDisplayView(
            service: service,
            recognizer: speechRecognizer,
            words: words,
            script: script,
            mirrorAxis: axis
        )

        let hostingView = NSHostingView(rootView: content)

        let newPanel = NSPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = true
        newPanel.backgroundColor = .black
        newPanel.hasShadow = false
        newPanel.sharingType = service.isRunning && service.hideFromScreenSharing ? .none : .readOnly
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.contentView = hostingView
        newPanel.setFrame(screenFrame, display: true)
        newPanel.orderFront(nil)
        self.panel = newPanel

        speechRecognizer.$shouldDismiss
            .filter { $0 }
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self?.dismiss()
                }
            }
            .store(in: &cancellables)
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        cancellables.removeAll()
    }

    func updateScreenCaptureVisibility(isHidden: Bool) {
        panel?.sharingType = isHidden ? .none : .readOnly
    }
}
