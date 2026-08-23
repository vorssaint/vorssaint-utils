// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Drives the QR button, which appears after the capture is scanned so the
/// preview never waits on detection to show, and the buttons grayed out
/// because the after-capture action already did their work.
final class ScreenshotQuickPreviewModel: ObservableObject {
    @Published var qr: BarcodeDetector.Reading?
    @Published var disabledActions: Set<ScreenshotQuickPreviewController.Action> = []
    @Published var sharing = false
    @Published var sharedRecord: ScreenshotShareRecord?
    @Published var deletingShare = false
}

/// A transient in-memory capture preview. It stays outside Command Tab and
/// performs no file write until the user explicitly chooses Save or Copy.
final class ScreenshotQuickPreviewController {
    enum Action {
        case edit
        case copy
        case save
        case saveAndCopy
        case discard
    }

    private let capture: ScreenshotSelectionController.Capture
    private let strings: ScreenshotFeatureStrings
    private let defaultAction: ScreenshotDefaultAction
    /// Runs one action and reports which sub-actions actually happened —
    /// save-and-copy can succeed by halves, and only the done halves gray
    /// their buttons out. Empty means the action failed entirely.
    private let action: (Action) -> Set<Action>
    private let share: (ScreenshotShareDuration,
                        @escaping (ScreenshotShareRecord?) -> Void) -> Void
    private let onClose: () -> Void
    private let model = ScreenshotQuickPreviewModel()
    private var panel: ScreenshotQuickPreviewPanel?
    private var keyMonitor: Any?
    private var dismissWork: DispatchWorkItem?
    private var autoDismissDuration: TimeInterval = 12
    private var closed = false

    var protectedWindowIDs: Set<CGWindowID> {
        guard let panel, panel.isVisible, panel.windowNumber > 0 else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    init(capture: ScreenshotSelectionController.Capture,
         strings: ScreenshotFeatureStrings,
         defaultAction: ScreenshotDefaultAction,
         action: @escaping (Action) -> Set<Action>,
         share: @escaping (ScreenshotShareDuration,
                           @escaping (ScreenshotShareRecord?) -> Void) -> Void,
         onClose: @escaping () -> Void) {
        self.capture = capture
        self.strings = strings
        self.defaultAction = defaultAction
        self.action = action
        self.share = share
        self.onClose = onClose
    }

    func show() {
        guard panel == nil, !closed else { return }
        let content = ScreenshotQuickPreviewView(
            image: Self.thumbnail(for: capture.image),
            strings: strings,
            model: model,
            perform: { [weak self] action in self?.perform(action) },
            dragItem: { [weak self] in
                guard let self else { return NSItemProvider() }
                return ScreenshotService.dragItemProvider(image: self.capture.image,
                                                          strings: self.strings)
                    ?? NSItemProvider()
            },
            share: { [weak self] duration in self?.performShare(duration) },
            copySharedLink: { [weak self] in self?.copySharedLink() },
            deleteSharedLink: { [weak self] in self?.deleteSharedLink() },
            showQR: { [weak self] in self?.showQRResult() },
            hoverChanged: { [weak self] inside in
                if inside {
                    self?.dismissWork?.cancel()
                    self?.dismissWork = nil
                } else {
                    self?.scheduleAutoDismiss()
                }
            })
        let host = NSHostingController(rootView: content)
        let size = Self.size(showingLink: false)
        let panel = ScreenshotQuickPreviewPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.contentViewController = host
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .transient, .ignoresCycle]

        let frame = previewFrame(for: size)
        panel.setFrame(frame, display: false)
        self.panel = panel
        installKeyMonitor(for: panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        // A performed action turns the preview into a short confirmation; a
        // failed one keeps the full stay so the person can still act by hand.
        autoDismissDuration = runDefaultAction(defaultAction) ? 3 : 12
        scheduleAutoDismiss()
        scanForQR()
    }

    /// Runs the Settings-configured action once, right after the preview
    /// appears, and reports whether anything happened. Only the halves that
    /// actually succeeded gray their buttons out, so a failed copy leaves
    /// Copy available. Unlike `perform(_:)` this never closes the panel: it
    /// stays up as confirmation, and the person can still edit or discard
    /// from it. Edit never reaches here, the service routes it straight
    /// into the editor without a preview.
    private func runDefaultAction(_ defaultAction: ScreenshotDefaultAction) -> Bool {
        let mapped: Action
        switch defaultAction {
        case .none, .edit: return false
        case .save: mapped = .save
        case .saveAndCopy: mapped = .saveAndCopy
        case .copy: mapped = .copy
        }
        let performed = action(mapped)
        guard !performed.isEmpty else { return false }
        model.disabledActions = performed.intersection([.save, .copy])
        return true
    }

    /// Scans the full resolution capture off the main thread and reveals the
    /// QR button if a code is found. Silent when there is none, so a plain
    /// screenshot preview is untouched.
    private func scanForQR() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let image = self?.capture.image, let reading = BarcodeDetector.read(image) else { return }
            DispatchQueue.main.async {
                guard let self, !self.closed else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    self.model.qr = reading
                }
            }
        }
    }

    /// Hands the code to the shared result panel, which spells out the
    /// content before anything is copied. The preview steps aside.
    private func showQRResult() {
        guard let reading = model.qr else { return }
        close()
        QRResultController.shared.show(reading: reading)
    }

    private static func thumbnail(for image: CGImage) -> CGImage {
        let maximumDimension: CGFloat = 1_200
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maximumDimension else { return image }
        let factor = maximumDimension / longest
        let width = max(1, Int((CGFloat(image.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(image.height) * factor).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    func close() {
        guard !closed else { return }
        closed = true
        dismissWork?.cancel()
        dismissWork = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        onClose()
    }

    private func perform(_ requested: Action) {
        guard !closed else { return }
        // Keyboard shortcuts honor the grayed-out buttons: what the
        // after-capture action already did is not done twice.
        guard !model.disabledActions.contains(requested) else { return }
        dismissWork?.cancel()
        dismissWork = nil
        guard !action(requested).isEmpty else {
            scheduleAutoDismiss()
            return
        }
        close()
    }

    private func performShare(_ duration: ScreenshotShareDuration) {
        guard !closed, !model.sharing else { return }
        dismissWork?.cancel()
        dismissWork = nil
        model.sharing = true
        share(duration) { [weak self] record in
            guard let self, !self.closed else {
                if let record {
                    Task { @MainActor in
                        try? await ScreenshotShareService.shared.delete(record)
                    }
                }
                return
            }
            self.model.sharing = false
            guard let record else {
                self.scheduleAutoDismiss()
                return
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                self.model.sharedRecord = record
            }
            self.autoDismissDuration = 30
            self.resizePanel(showingLink: true)
            self.scheduleAutoDismiss()
        }
    }

    private func copySharedLink() {
        guard let record = model.sharedRecord else { return }
        dismissWork?.cancel()
        dismissWork = nil
        Task { @MainActor [weak self] in
            guard let self, !self.closed else { return }
            if ScreenshotShareService.shared.copy(record.url) {
                QuickToolHUD.show(icon: "link", message: self.strings.sharedHUD)
            } else {
                NSSound.beep()
            }
            self.scheduleAutoDismiss()
        }
    }

    private func deleteSharedLink() {
        guard let record = model.sharedRecord, !model.deletingShare else { return }
        dismissWork?.cancel()
        dismissWork = nil
        model.deletingShare = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await ScreenshotShareService.shared.delete(record)
                guard !self.closed else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    self.model.sharedRecord = nil
                    self.model.deletingShare = false
                }
                QuickToolHUD.show(icon: "link", message: self.strings.linkDeletedHUD)
                self.autoDismissDuration = 12
                self.resizePanel(showingLink: false)
            } catch {
                guard !self.closed else { return }
                self.model.deletingShare = false
                QuickToolHUD.show(icon: "link", message: self.strings.deleteFailedHUD)
                NSSound.beep()
            }
            self.scheduleAutoDismiss()
        }
    }

    fileprivate static func size(showingLink: Bool) -> CGSize {
        CGSize(width: 350, height: showingLink ? 268 : 210)
    }

    private func previewFrame(for size: CGSize) -> CGRect {
        let pointer = NSEvent.mouseLocation
        let screens = NSScreen.screens.map { (frame: $0.frame, visibleFrame: $0.visibleFrame) }
        let visibleFrame = ScreenshotSupport.quickPreviewVisibleFrame(
            anchor: capture.anchorRect,
            pointer: pointer,
            screens: screens,
            fallback: NSScreen.pointerVisibleFrame)
        let storedPosition = UserDefaults.standard.string(
            forKey: DefaultsKey.screenshotPreviewPosition) ?? ""
        let position = ScreenshotSupport.QuickPreviewPosition(rawValue: storedPosition)
            ?? .automatic
        // With an after-capture action the preview is just a confirmation,
        // so it sits quietly in the corner and leaves sooner, instead of
        // popping up next to the selection and waiting.
        let effectivePosition: ScreenshotSupport.QuickPreviewPosition =
            position == .automatic && defaultAction != .none
                ? .bottomRight
                : position
        return ScreenshotSupport.quickPreviewFrame(
            size: size,
            anchor: capture.anchorRect,
            pointer: pointer,
            visibleFrame: visibleFrame,
            position: effectivePosition)
    }

    private func resizePanel(showingLink: Bool) {
        panel?.setFrame(previewFrame(for: Self.size(showingLink: showingLink)),
                        display: true,
                        animate: true)
    }

    private func scheduleAutoDismiss() {
        guard !closed else { return }
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissDuration, execute: work)
    }

    private func installKeyMonitor(for panel: NSPanel) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = Int(event.keyCode)
            if flags.contains(.command) {
                switch key {
                case kVK_ANSI_C:
                    self.perform(.copy)
                    return nil
                case kVK_ANSI_S:
                    self.perform(.save)
                    return nil
                case kVK_Delete, kVK_ForwardDelete:
                    self.perform(.discard)
                    return nil
                default:
                    return event
                }
            }
            guard flags.isDisjoint(with: [.command, .control, .option]) else { return event }
            switch key {
            case kVK_Return, kVK_ANSI_KeypadEnter, kVK_ANSI_E:
                self.perform(.edit)
                return nil
            case kVK_Delete, kVK_ForwardDelete:
                self.perform(.discard)
                return nil
            case kVK_Escape:
                // Escape only dismisses. Before the after-capture actions it
                // was equivalent to discard; now a discard can delete a file
                // the HUD just announced as saved, and "make this popup go
                // away" must never do that. Deleting stays on Trash and ⌫.
                self.close()
                return nil
            default:
                return event
            }
        }
    }
}

private final class ScreenshotQuickPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct ScreenshotQuickPreviewView: View {
    let image: CGImage
    let strings: ScreenshotFeatureStrings
    @ObservedObject var model: ScreenshotQuickPreviewModel
    let perform: (ScreenshotQuickPreviewController.Action) -> Void
    let dragItem: () -> NSItemProvider
    let share: (ScreenshotShareDuration) -> Void
    let copySharedLink: () -> Void
    let deleteSharedLink: () -> Void
    let showQR: () -> Void
    let hoverChanged: (Bool) -> Void
    @AppStorage(DefaultsKey.screenshotSharingEnabled) private var sharingEnabled = true

    var body: some View {
        VStack(spacing: 10) {
            Button {
                perform(.edit)
            } label: {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 138)
                    .frame(width: 320, height: 138)
                    .background(Color.black.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .onDrag(dragItem)
            .screenshotSafeHelp(strings.editButton)
            .accessibilityLabel(strings.editButton)

            if let record = model.sharedRecord {
                sharedLinkRow(record)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(spacing: 5) {
                Button {
                    perform(.discard)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 22, height: 18)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .screenshotSafeHelp("\(strings.discardConfirm)  (⌫)")
                .accessibilityLabel(strings.discardConfirm)
                if model.qr != nil {
                    qrControl
                        .transition(.scale.combined(with: .opacity))
                }
                actionButton(symbol: "square.and.arrow.down",
                             title: strings.saveButton,
                             shortcut: "⌘S",
                             disabled: model.disabledActions.contains(.save)) {
                    perform(.save)
                }
                actionButton(symbol: "doc.on.doc",
                             title: strings.copyButton,
                             shortcut: "⌘C",
                             disabled: model.disabledActions.contains(.copy)) {
                    perform(.copy)
                }
                if sharingEnabled, model.sharedRecord == nil {
                    shareMenu
                }
                Spacer(minLength: 4)
                Button(strings.editButton) {
                    perform(.edit)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .screenshotSafeHelp("⏎")
            }
        }
        .padding(10)
        .frame(width: ScreenshotQuickPreviewController.size(showingLink: false).width,
               height: ScreenshotQuickPreviewController.size(
                   showingLink: model.sharedRecord != nil).height)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .onHover(perform: hoverChanged)
    }

    private func sharedLinkRow(_ record: ScreenshotShareRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.url.absoluteString)
                    .font(.system(size: 11, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 3) {
                    Text(strings.expiresLabel)
                    Text(record.expiresAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            Button(action: copySharedLink) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(model.deletingShare)
            .screenshotSafeHelp(strings.copyLink)
            .accessibilityLabel(strings.copyLink)
            Button(role: .destructive, action: deleteSharedLink) {
                Group {
                    if model.deletingShare {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "trash")
                    }
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(model.deletingShare)
            .screenshotSafeHelp(strings.deleteLink)
            .accessibilityLabel(strings.deleteLink)
        }
        .padding(.horizontal, 9)
        .frame(width: 320, height: 48)
        .background(Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        )
    }

    /// A code was found: open the result panel that spells out its content.
    private var qrControl: some View {
        Button(action: showQR) {
            Image(systemName: "qrcode")
                .frame(width: 22, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.accentColor)
        .screenshotSafeHelp(L10n.shared.s.qrResultTitle)
        .accessibilityLabel(L10n.shared.s.qrResultTitle)
    }

    private var shareMenu: some View {
        Menu {
            ForEach(ScreenshotShareDuration.allCases) { duration in
                Button(duration.title(strings)) { share(duration) }
            }
        } label: {
            Group {
                if model.sharing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "link")
                }
            }
            .frame(width: 22, height: 18)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(model.sharing)
        .screenshotSafeHelp(model.sharing ? strings.sharingHUD : strings.shareButton)
        .accessibilityLabel(strings.shareButton)
    }

    private func actionButton(symbol: String,
                              title: String,
                              shortcut: String,
                              disabled: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .screenshotSafeHelp("\(title)  (\(shortcut))")
        .accessibilityLabel(title)
    }
}
