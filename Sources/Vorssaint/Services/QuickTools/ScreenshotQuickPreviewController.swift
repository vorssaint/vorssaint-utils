// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Drives the QR button, which appears after the capture is scanned so the
/// preview never waits on detection to show.
final class ScreenshotQuickPreviewModel: ObservableObject {
    @Published var qr: BarcodeDetector.Reading?
}

/// A transient in-memory capture preview. It stays outside Command Tab and
/// performs no file write until the user explicitly chooses Save.
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
    private let action: (Action) -> Bool
    private let onClose: () -> Void
    private let model = ScreenshotQuickPreviewModel()
    private var panel: ScreenshotQuickPreviewPanel?
    private var keyMonitor: Any?
    private var dismissWork: DispatchWorkItem?
    private var autoDismissDuration: TimeInterval = 12
    private var closed = false

    init(capture: ScreenshotSelectionController.Capture,
         strings: ScreenshotFeatureStrings,
         action: @escaping (Action) -> Bool,
         onClose: @escaping () -> Void) {
        self.capture = capture
        self.strings = strings
        self.action = action
        self.onClose = onClose
    }

    func show() {
        guard panel == nil, !closed else { return }
        let defaultAction = Self.configuredDefaultAction()
        let content = ScreenshotQuickPreviewView(
            image: Self.thumbnail(for: capture.image),
            strings: strings,
            disabledActions: Self.disabledActions(for: defaultAction),
            model: model,
            perform: { [weak self] action in self?.perform(action) },
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
        let size = CGSize(width: 310, height: 210)
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

        let visibleFrame = NSScreen.screens.first { $0.frame.intersects(capture.anchorRect) }?.visibleFrame
                ?? NSScreen.withMouse.visibleFrame

        // A default action means this HUD is just a confirmation, not
        // something the person needs to act on — keep it out of the way in
        // the corner instead of popping up next to the selection.
        let frame = defaultAction == .none
            ? ScreenshotSupport.quickPreviewFrame(
                size: size,
                anchor: capture.anchorRect,
                pointer: NSEvent.mouseLocation,
                visibleFrame: visibleFrame)
            : ScreenshotSupport.quickPreviewCornerFrame(size: size, visibleFrame: visibleFrame)
        panel.setFrame(frame, display: false)
        self.panel = panel
        installKeyMonitor(for: panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        autoDismissDuration = defaultAction == .none ? 12 : 3
        scheduleAutoDismiss()
        scanForQR()
        runDefaultAction(defaultAction)
    }

    private static func configuredDefaultAction() -> ScreenshotDefaultAction {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.screenshotDefaultAction) ?? ""
        return ScreenshotDefaultAction(rawValue: raw) ?? .none
    }

    /// Buttons whose action the default action already performed, so the
    /// HUD doesn't invite doing it again.
    private static func disabledActions(for defaultAction: ScreenshotDefaultAction) -> Set<Action> {
        switch defaultAction {
            case .none, .edit: return []
            case .save: return [.save]
            case .saveAndCopy: return [.save, .copy]
            case .copy: return [.copy]
        }
    }

    /// Runs the Settings-configured default action once, immediately after
    /// the HUD appears. Unlike `perform(_:)`, this never closes the panel —
    /// it stays up as confirmation, and the person can still Edit or
    /// discard from it afterward.
    private func runDefaultAction(_ defaultAction: ScreenshotDefaultAction) {
        let mapped: Action
        switch defaultAction {
        case .none: return
        case .save: mapped = .save
        case .saveAndCopy: mapped = .saveAndCopy
        case .copy: mapped = .copy
        case .edit: mapped = .edit
        }
        _ = action(mapped)
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
        dismissWork?.cancel()
        dismissWork = nil
        guard action(requested) else {
            scheduleAutoDismiss()
            return
        }
        close()
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
            case kVK_Delete, kVK_ForwardDelete, kVK_Escape:
                self.perform(.discard)
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
    let disabledActions: Set<ScreenshotQuickPreviewController.Action>
    @ObservedObject var model: ScreenshotQuickPreviewModel
    let perform: (ScreenshotQuickPreviewController.Action) -> Void
    let showQR: () -> Void
    let hoverChanged: (Bool) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button {
                perform(.edit)
            } label: {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: 280, maxHeight: 138)
                    .frame(width: 280, height: 138)
                    .background(Color.black.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .screenshotSafeHelp(strings.editButton)
            .accessibilityLabel(strings.editButton)

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
                             disabled: disabledActions.contains(.save)) {
                    perform(.save)
                }
                actionButton(symbol: "doc.on.doc",
                             title: strings.copyButton,
                             shortcut: "⌘C",
                             disabled: disabledActions.contains(.copy)) {
                    perform(.copy)
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
        .frame(width: 310, height: 210)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .onHover(perform: hoverChanged)
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
