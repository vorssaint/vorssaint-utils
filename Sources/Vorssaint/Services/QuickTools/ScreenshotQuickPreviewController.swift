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
        case pin
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
    private let presentationID = UUID()
    private var shownInNotch = false
    private var didRunDefaultAction = false
    private var pointerInside = false

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

    func show(inNotch: Bool = true) {
        guard panel == nil, !shownInNotch, !closed else { return }
        let wantsNotch = inNotch && NotchSupport.routes(.capture)
            && NotchService.shared.acceptsSystemFeedback
        let content = ScreenshotQuickPreviewView(
            image: Self.thumbnail(for: capture.image),
            strings: strings,
            model: model,
            perform: { [weak self] action in self?.perform(action) },
            dragItem: { [weak self] in
                guard let self else { return NSItemProvider() }
                return ScreenshotService.dragItemProvider(image: self.capture.image,
                                                          scale: self.capture.scale,
                                                          strings: self.strings)
                    ?? NSItemProvider()
            },
            share: { [weak self] duration in self?.performShare(duration) },
            copySharedLink: { [weak self] in self?.copySharedLink() },
            deleteSharedLink: { [weak self] in self?.deleteSharedLink() },
            showQR: { [weak self] in self?.showQRResult() },
            hoverChanged: { [weak self] inside in self?.hoverChanged(inside) },
            embedded: wantsNotch)
        if wantsNotch, NotchService.shared.presentCapture(
            id: presentationID, content: AnyView(content), actions: AnyView(content.toolbar), height: Self.size(showingLink: model.sharedRecord != nil).height,
            fallback: { [weak self] in
                guard let self else { return }
                self.shownInNotch = false
                self.pointerInside = false
                if let keyMonitor = self.keyMonitor { NSEvent.removeMonitor(keyMonitor) }
                self.keyMonitor = nil
                self.show(inNotch: false)
            },
            close: { [weak self] in self?.close() },
            hover: { [weak self] inside in self?.hoverChanged(inside) }) {
            shownInNotch = true
            if let window = NotchService.shared.presentationWindow { installKeyMonitor(for: window) }
            finishShowing()
            return
        }
        let host = NSHostingController(rootView: content)
        let size = Self.size(showingLink: model.sharedRecord != nil)
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
        // On by default: leaving the keyboard behind after a capture is what
        // #1463 reported, since Command-C and Command-S did nothing until a
        // click. Taking it costs the caret in the app being typed into
        // (#1089), so More options can hand that trade back to a click.
        if UserDefaults.standard.bool(forKey: DefaultsKey.screenshotPreviewTakesFocus) {
            panel.makeKey()
        }
        // A performed action turns the preview into a short confirmation; a
        // failed one keeps the full stay so the person can still act by hand.
        finishShowing()
    }

    private func finishShowing() {
        if !didRunDefaultAction {
            didRunDefaultAction = true
            autoDismissDuration = runDefaultAction(defaultAction) ? 3 : 12
            scanForQR()
        }
        scheduleAutoDismiss()
    }

    private func hoverChanged(_ inside: Bool) {
        pointerInside = inside
        dismissWork?.cancel()
        dismissWork = nil
        if !inside { scheduleAutoDismiss() }
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
        if shownInNotch {
            shownInNotch = false
            NotchService.shared.removeCapture(id: presentationID)
        }
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
        if shownInNotch {
            NotchService.shared.updateCaptureHeight(id: presentationID, height: Self.size(showingLink: showingLink).height)
            return
        }
        panel?.setFrame(previewFrame(for: Self.size(showingLink: showingLink)),
                        display: true,
                        animate: true)
    }

    private func scheduleAutoDismiss() {
        guard !closed, !pointerInside, !model.sharing, !model.deletingShare else { return }
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissDuration, execute: work)
    }

    private func installKeyMonitor(for panel: NSPanel) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, !self.closed, let panel, panel.isVisible, event.window === panel,
                  !self.shownInNotch || NotchService.shared.isCaptureVisible(id: self.presentationID),
                  panel.attachedSheet == nil, !(panel.firstResponder is NSText),
                  !ShortcutCapture.isCapturing else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let key = Int(event.keyCode)
            if flags.intersection([.command, .option, .shift, .control]) == .command {
                let text = event.charactersIgnoringModifiers?.folding(
                    options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                let letter = text?.count == 1 ? text?.first : nil
                let isLatinLetter = letter.map { $0.isASCII && $0.isLetter } ?? false
                if isLatinLetter ? letter == "w" : key == kVK_ANSI_W {
                    self.close()
                    return nil
                }
            }
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

    /// The preview shows up unasked for, so presenting it leaves the keyboard
    /// where it was unless the person opted in, and a click is what hands it
    /// over. Its shortcuts read a local monitor, and that monitor is delivered
    /// nothing until this panel is key. The hand-off sits in `sendEvent`
    /// rather than `mouseDown` because the hosted SwiftUI content answers a
    /// press on a button itself, and a window's `mouseDown` never runs for the
    /// clicks a view has taken.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }
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
    var embedded = false
    var actionsOnly = false
    var toolbar: Self {
        var view = self
        view.actionsOnly = true
        return view
    }
    @AppStorage(DefaultsKey.screenshotSharingEnabled) private var sharingEnabled = true

    var body: some View {
        if actionsOnly { actionBar }
        else { preview }
    }

    private var actionBar: some View {
        HStack(spacing: embedded ? 2 : 5) {
            Button {
                perform(.discard)
            } label: {
                Image(systemName: "trash")
                    .frame(width: embedded ? 28 : 22, height: embedded ? 28 : 18)
            }
            .modifier(ScreenshotPreviewActionStyle(embedded: embedded))
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
            if !embedded { Spacer(minLength: 4) }
            if embedded {
                Button {
                    perform(.pin)
                } label: {
                    Image(systemName: "pin").frame(width: 28, height: 28)
                }
                .modifier(ScreenshotPreviewActionStyle(embedded: true))
                .controlSize(.small)
                .screenshotSafeHelp(strings.pinButton)
                .accessibilityLabel(strings.pinButton)
            }
            Button { perform(.edit) } label: {
                if embedded { Image(systemName: "pencil").frame(width: 28, height: 28) }
                else { Text(strings.editButton) }
            }
            .accessibilityLabel(strings.editButton)
            .modifier(ScreenshotPreviewActionStyle(embedded: embedded, prominent: true))
            .controlSize(.small)
            .screenshotSafeHelp("\(strings.editButton)  (⏎)")
        }
    }

    private var thumbnailPinButton: some View {
        Button {
            perform(.pin)
        } label: {
            Image(systemName: "pin")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .screenshotSafeHelp(strings.pinButton)
        .accessibilityLabel(strings.pinButton)
    }

    private var preview: some View {
        VStack(spacing: 10) {
            Button {
                perform(.edit)
            } label: {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 320, maxHeight: 138)
                    .frame(width: embedded ? nil : 320, height: 138)
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
            .overlay(alignment: .topTrailing) {
                // The floating action row already fills its fixed width in
                // longer languages, so the pin rides on the thumbnail there
                // instead of squeezing Save, Copy and Edit.
                if !embedded { thumbnailPinButton }
            }

            if let record = model.sharedRecord {
                sharedLinkRow(record)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !embedded { actionBar }
        }
        .padding(10)
        .frame(width: embedded ? nil : ScreenshotQuickPreviewController.size(showingLink: false).width,
               height: embedded ? nil : ScreenshotQuickPreviewController.size(
                   showingLink: model.sharedRecord != nil).height)
        .background {
            if !embedded {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial)
            }
        }
        .overlay {
            if !embedded {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
        .onHover(perform: previewHoverChanged)
    }

    private func previewHoverChanged(_ inside: Bool) {
        // The island tracks the image and header together. Leaving just the
        // image must not restart dismissal while its actions are still hovered.
        guard !embedded else { return }
        hoverChanged(inside)
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
        .frame(width: embedded ? nil : 320, height: 48)
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
                .frame(width: embedded ? 28 : 22, height: embedded ? 28 : 18)
        }
        .modifier(ScreenshotPreviewActionStyle(embedded: embedded))
        .controlSize(.small)
        .tint(.accentColor)
        .screenshotSafeHelp(L10n.shared.s.qrResultTitle)
        .accessibilityLabel(L10n.shared.s.qrResultTitle)
    }

    @ViewBuilder private var shareMenu: some View {
        if embedded {
            shareMenuContent.menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(width: 28, height: 28)
        } else {
            shareMenuContent.menuStyle(.button).buttonStyle(.bordered).controlSize(.small)
        }
    }

    private var shareMenuContent: some View {
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
            .frame(width: embedded ? 28 : 22, height: embedded ? 28 : 18)
        }
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
            Group {
                if embedded { Image(systemName: symbol).frame(width: 28, height: 28) }
                else { Label(title, systemImage: symbol) }
            }
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .modifier(ScreenshotPreviewActionStyle(embedded: embedded))
        .controlSize(.small)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .screenshotSafeHelp("\(title)  (\(shortcut))")
        .accessibilityLabel(title)
    }
}

/// The island header has its own surface; native button bezels waste the space
/// needed by its title at the minimum width. Keep 28-point targets in that host.
private struct ScreenshotPreviewActionStyle: ViewModifier {
    let embedded: Bool
    var prominent = false

    @ViewBuilder func body(content: Content) -> some View {
        if embedded {
            content.buttonStyle(NotchButtonStyle(cornerRadius: 8))
                .background(prominent ? Color.white.opacity(0.14) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
