// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

final class SelectionTranslationPanelController {
    static let shared = SelectionTranslationPanelController()
    private var panel: NSPanel?
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .selectionTranslationPresentPanel, object: nil, queue: .main) { [weak self] _ in self?.present() }
    }

    func present() {
        if panel == nil {
            let host = NSHostingView(rootView: SelectionTranslationPanelView())
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 500), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            p.title = FeatureStrings.selectionTranslation(L10n.shared.language).title
            p.isFloatingPanel = true; p.level = .floating; p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.titleVisibility = .hidden; p.titlebarAppearsTransparent = true
            p.contentView = host; panel = p
        }
        guard let panel else { return }
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2, y: screen.visibleFrame.midY - panel.frame.height / 2)) }
        panel.orderFrontRegardless()
    }
    func close() { panel?.orderOut(nil) }
}

struct SelectionTranslationPanelView: View {
    @ObservedObject private var service = SelectionTranslationService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: SelectionTranslationFeatureStrings { FeatureStrings.selectionTranslation(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(text.title).font(.headline); Spacer(); Button(text.close) { SelectionTranslationPanelController.shared.close() }.buttonStyle(.plain) }
            GroupBox(text.sourceLanguage) { Text(service.sourceText.isEmpty ? text.translating : service.sourceText).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(6) }
            GroupBox(text.targetLanguage) { ScrollView { Text(service.translatedText.isEmpty ? phaseText : service.translatedText).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(6) }.frame(minHeight: 140) }
            HStack {
                if case .failed = service.phase { Button(text.retry) { service.retry() } }
                if service.phase == .translating || service.phase == .streaming { Button("Stop") { service.cancel() } }
                Spacer()
                Button(text.copy) { copy() }.disabled(service.translatedText.isEmpty)
            }
        }
        .padding(18)
        .background(.regularMaterial)
        .frame(minWidth: 500, minHeight: 430)
    }
    private var phaseText: String {
        if case let .failed(message) = service.phase { return message }
        return text.translating
    }
    private func copy() {
        let value = service.translatedText
        GeneralPasteboardAccess.shared.async {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
        }
    }
}
