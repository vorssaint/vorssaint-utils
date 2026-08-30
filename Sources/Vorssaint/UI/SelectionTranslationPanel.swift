// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import Combine

private extension Notification.Name {
    static let selectionTranslationFocusSource = Notification.Name("Vorssaint.SelectionTranslation.focusSource")
}

@MainActor
final class SelectionTranslationPanelController: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = SelectionTranslationPanelController()

    private var panel: NSPanel?
    private var host: NSHostingView<SelectionTranslationPanelView>?
    private var pinHost: NSHostingController<SelectionTranslationTitlebarPinButton>?
    private var pinAccessory: NSTitlebarAccessoryViewController?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isPositioning = false
    @Published private(set) var isPinned = false
    private var hasUserResized = false

    private override init() { super.init() }

    func present(anchor: NSPoint = NSEvent.mouseLocation, focusSourceEditor: Bool = false) {
        if panel == nil { createPanel() }
        guard let panel else { return }
        if !hasUserResized {
            let size = NSSize(width: SelectionTranslationPanelSizing.defaultWidth, height: 610)
            let visible = NSScreen.screens.first(where: { $0.frame.contains(anchor) })?.visibleFrame
                ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let boundedHeight = min(size.height, visible.height * 0.78)
            let boundedSize = NSSize(width: size.width, height: boundedHeight)
            let origin = safeOrigin(anchor: anchor, size: boundedSize, visible: visible)
            isPositioning = true
            panel.setFrame(NSRect(origin: origin, size: boundedSize), display: true)
            isPositioning = false
        }
        panel.orderFrontRegardless()
        if focusSourceEditor {
            panel.makeKeyAndOrderFront(nil)
        }
        updateOutsideClickMonitors()
    }

    func focusSourceEditor() {
        guard let panel else { return }
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .selectionTranslationFocusSource, object: nil)
    }

    func togglePin() {
        isPinned.toggle()
        panel?.hidesOnDeactivate = false
        updateOutsideClickMonitors()
    }

    func hide() {
        panel?.orderOut(nil)
        removeOutsideClickMonitors()
        hasUserResized = false
        isPinned = false
    }

    func close() {
        SelectionTranslationService.shared.dismiss()
    }

    private func createPanel() {
        let content = SelectionTranslationPanelView()
        let host = NSHostingView(rootView: content)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0,
                                                width: SelectionTranslationPanelSizing.defaultWidth,
                                                height: 610),
                            styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = FeatureStrings.selectionTranslation(L10n.shared.language).title
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = host
        panel.minSize = NSSize(width: SelectionTranslationPanelSizing.minimumWidth, height: 360)
        panel.maxSize = NSSize(width: SelectionTranslationPanelSizing.maximumWidth, height: 900)
        self.host = host
        self.panel = panel

        let pinHost = NSHostingController(rootView: SelectionTranslationTitlebarPinButton())
        pinHost.view.translatesAutoresizingMaskIntoConstraints = false
        pinHost.view.widthAnchor.constraint(equalToConstant: 34).isActive = true
        pinHost.view.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let pinAccessory = NSTitlebarAccessoryViewController()
        pinAccessory.layoutAttribute = .right
        pinAccessory.view = pinHost.view
        panel.addTitlebarAccessoryViewController(pinAccessory)
        self.pinHost = pinHost
        self.pinAccessory = pinAccessory
    }

    private func safeOrigin(anchor: NSPoint, size: NSSize, visible: NSRect) -> NSPoint {
        var x = anchor.x + 16
        var y = anchor.y - size.height - 12
        if x + size.width > visible.maxX { x = anchor.x - size.width - 16 }
        if x < visible.minX { x = visible.minX + 12 }
        if y < visible.minY { y = anchor.y + 18 }
        if y + size.height > visible.maxY { y = visible.maxY - size.height - 12 }
        return NSPoint(x: x, y: max(visible.minY + 12, y))
    }

    private func updateOutsideClickMonitors() {
        removeOutsideClickMonitors()
        guard !isPinned else { return }
        let shouldDismiss: (NSEvent) -> Void = { [weak self] _ in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            let active = SelectionTranslationService.shared.phase
            let busy: Bool
            switch active {
            case .reading, .translating, .streaming: busy = true
            default: busy = false
            }
            guard !busy, !panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.close()
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            shouldDismiss(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            shouldDismiss(event)
            return event
        }
    }

    private func removeOutsideClickMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    func windowDidResize(_ notification: Notification) {
        if !isPositioning { hasUserResized = true }
    }

    func adjustToContentIfNeeded() {
        guard !hasUserResized, let panel, panel.isVisible, let host else { return }
        let visible = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        guard let visible else { return }
        let measured = host.fittingSize
        let height = min(max(360, measured.height + 8), visible.height * 0.78)
        guard height > panel.frame.height + 8 else { return }
        isPositioning = true
        panel.setFrame(NSRect(x: panel.frame.minX, y: panel.frame.maxY - height,
                              width: panel.frame.width, height: height), display: true)
        isPositioning = false
    }

    func windowWillClose(_ notification: Notification) {
        SelectionTranslationService.shared.dismiss()
    }
}

struct SelectionTranslationPanelView: View {
    @ObservedObject private var service = SelectionTranslationService.shared
    @ObservedObject private var panelController = SelectionTranslationPanelController.shared
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var sourceFocused: Bool
    private var text: SelectionTranslationFeatureStrings { FeatureStrings.selectionTranslation(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            sourceCard
            languageBar
            resultCard
            footer
        }
        .padding(16)
        .frame(minWidth: SelectionTranslationPanelSizing.minimumWidth,
               idealWidth: SelectionTranslationPanelSizing.defaultWidth,
               maxWidth: SelectionTranslationPanelSizing.maximumWidth,
               minHeight: 360, idealHeight: 610, maxHeight: 900)
        .background(HUDBackdrop(cornerRadius: 14, contrast: .high))
        .onChange(of: service.translatedText) { _, _ in panelController.adjustToContentIfNeeded() }
        .onChange(of: service.phase) { _, _ in panelController.adjustToContentIfNeeded() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            BrandMark(width: 20, tint: .accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Vorssaint").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(text.title).font(.headline)
            }
            Spacer()
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(text.sourceText).font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    copy(service.draft.source)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.plain)
                .disabled(service.draft.source.isEmpty)
            }
            TextEditor(text: Binding(get: { service.draft.source }, set: { service.updateSource($0) }))
                .font(.body)
                .focused($sourceFocused)
                .disabled(service.phase == .reading)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 94, maxHeight: 190)
                .overlay(alignment: .topLeading) {
                    if service.draft.source.isEmpty && service.phase != .reading {
                        Text(text.sourcePlaceholder).foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }
        }
        .panelCard()
        .accessibilityIdentifier("selection-translation-source-editor")
        .onReceive(NotificationCenter.default.publisher(for: .selectionTranslationFocusSource)) { _ in
            sourceFocused = true
        }
    }

    private var languageBar: some View {
        HStack(spacing: 8) {
            languagePickers
                .layoutPriority(1)
            Spacer(minLength: 4)
            actionButton
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("selection-translation-language-bar")
    }

    private var languagePickers: some View {
        HStack(spacing: 8) {
            Picker(text.sourceLanguage, selection: Binding(get: { service.draft.languages.source },
                                                           set: { source in
                                                               service.updateLanguageSelection(.init(source: source,
                                                                                                     target: service.draft.languages.target))
                                                           })) {
                ForEach(SelectionTranslationLanguage.sourceOptions) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            Button {
                service.swapLanguages()
            } label: { Image(systemName: "arrow.left.arrow.right") }
            .buttonStyle(.borderless)
            .help(text.swapLanguages)
            Picker(text.targetLanguage, selection: Binding(get: { service.draft.languages.target },
                                                           set: { target in
                                                               service.updateLanguageSelection(.init(source: service.draft.languages.source,
                                                                                                     target: target))
                                                           })) {
                ForEach(SelectionTranslationLanguage.targetOptions) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch service.phase {
        case .reading:
            ProgressView().controlSize(.small)
            Text(text.translating).font(.caption).foregroundStyle(.secondary)
        case .translating, .streaming:
            Button(text.interrupt) { service.interrupt() }.buttonStyle(.borderedProminent)
        case .failed:
            Button(failureActionTitle) { service.openFailureAction() }.buttonStyle(.borderedProminent)
        default:
            Button(text.translate) { service.submitDraft() }
                .buttonStyle(.borderedProminent)
                .disabled(service.draft.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(text.translationText).font(.subheadline.weight(.semibold))
                Spacer()
                if !service.providerName.isEmpty {
                    Text(service.providerName).font(.caption).foregroundStyle(.secondary)
                }
                Button { copy(service.translatedText) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain)
                    .disabled(service.translatedText.isEmpty)
            }
            ScrollView {
                Text(resultText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.vertical, 3)
            }
            .frame(minHeight: 130, maxHeight: 390)
        }
        .panelCard()
        .accessibilityIdentifier("selection-translation-result-card")
    }

    private var resultText: String {
        if !service.translatedText.isEmpty { return service.translatedText }
        switch service.phase {
        case .reading: return text.translating
        case .translating, .streaming: return text.translating
        case .failed(let message): return message
        case .interrupted: return text.cancelled
        case .ready: return service.draft.source.isEmpty ? text.noSelection : text.sourcePlaceholder
        default: return ""
        }
    }

    private var failureActionTitle: String {
        switch service.failureAction {
        case .openAccessibilitySettings: return text.openAccessibilitySettings
        case .openSettings: return text.openTranslationSettings
        case .retry, nil: return text.retry
        }
    }

    @ViewBuilder
    private var footer: some View {
        if service.timing.isRunning {
            TimelineView(.periodic(from: .now, by: 0.2)) { context in
                footerContent(at: context.date)
            }
        } else {
            footerContent(at: Date())
        }
    }

    private func footerContent(at date: Date) -> some View {
        HStack(spacing: 10) {
            if let startedAt = service.timing.startedAt {
                let elapsed = service.timing.isRunning
                    ? max(0, date.timeIntervalSince(startedAt))
                    : service.timing.elapsed
                metric(String(format: text.elapsedFormat, elapsed))
            }
            let usage = service.usage
            if usage.totalTokens > 0 {
                metric(String(format: text.tokensFormat, usage.inputTokens, usage.outputTokens, usage.totalTokens))
                if usage.isEstimated { metric(text.estimatedSuffix, emphasized: true) }
            }
            Spacer()
            if service.phase == .completed || service.phase == .interrupted || isFailed {
                Button(text.retry) { service.retry() }.buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func metric(_ value: String, emphasized: Bool = false) -> some View {
        Text(value)
            .font(.caption.weight(emphasized ? .semibold : .medium).monospacedDigit())
            .foregroundStyle(emphasized ? .primary : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, emphasized ? 5 : 0)
            .padding(.vertical, emphasized ? 2 : 0)
            .background {
                if emphasized {
                    Capsule().fill(Color.accentColor.opacity(0.18))
                }
            }
    }

    private var isFailed: Bool {
        if case .failed = service.phase { return true }
        return false
    }

    private func copy(_ value: String) {
        guard !value.isEmpty else { return }
        GeneralPasteboardAccess.shared.async {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    }
}

private struct SelectionTranslationTitlebarPinButton: View {
    @ObservedObject private var panelController = SelectionTranslationPanelController.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        let text = FeatureStrings.selectionTranslation(l10n.language)
        Button {
            panelController.togglePin()
        } label: {
            Image(systemName: panelController.isPinned ? "pin.fill" : "pin")
                .imageScale(.medium)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(panelController.isPinned ? text.unpin : text.pin)
        .accessibilityLabel(panelController.isPinned ? text.unpin : text.pin)
    }
}
