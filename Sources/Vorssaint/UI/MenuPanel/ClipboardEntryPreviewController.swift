// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import ImageIO
import QuartzCore
import SwiftUI

/// A Quick Look surface owned by the island, without a separate app window.
final class ClipboardEntryPreviewController: NSObject, NSWindowDelegate {
    private let entry: ClipboardHistoryEntry
    private let onClose: (ClipboardEntryPreviewController) -> Void
    private var window: NSPanel?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private var animationGeneration = 0
    private var isClosing = false
    private var afterClose: (() -> Void)?
    private var restingFrame = NSRect.zero
    private var editingText = false
    private var isEntering = false
    private var pendingSize: (size: CGSize, screen: NSRect)?

    var entryID: UUID { entry.id }

    init(entry: ClipboardHistoryEntry, onClose: @escaping (ClipboardEntryPreviewController) -> Void) {
        self.entry = entry
        self.onClose = onClose
    }

    func show() {
        if let window {
            if isClosing { animateIn(window, newlyCreated: false) }
            window.orderFrontRegardless()
            window.makeKey()
            return
        }
        let content = ClipboardEntryPreviewWindow(entry: entry,
            close: { [weak self] in self?.close() },
            edit: { [weak self] in
                guard let self else { return }
                let entry = self.entry
                self.close { ClipboardHistoryService.shared.editImage(entry) }
            },
            editingChanged: { [weak self] in self?.editingText = $0 },
            imageLoaded: { [weak self] in self?.resizeForImage($0) },
            textChanged: { [weak self] in self?.resizeForText($0) })
        let host = NSHostingController(rootView: content)
        host.sizingOptions = []
        let window = ClipboardPreviewPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered, defer: false)
        window.contentViewController = host
        window.title = FeatureStrings.clipboard(L10n.shared.language).previewLabel
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.animationBehavior = .none
        window.alphaValue = 0
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = false
        window.level = .floating
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle]
        window.delegate = self
        self.window = window
        NotchService.shared.attachClipboardPreview(window) { [weak self] in self?.close(animated: false) }
        if let parent = window.parent { window.level = parent.level }
        let screen = window.parent?.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let backingScale = window.parent?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let size: NSSize
        if content.isImage, let dimensions = imageDimensions() {
            size = ClipboardPreviewLayout.imageSize(dimensions, available: screen.size, backingScale: backingScale)
        } else if entry.kind == .text {
            size = ClipboardPreviewLayout.textSize(entry.text, available: screen.size)
        } else {
            size = NSSize(width: min(480, screen.width * 0.8), height: min(360, screen.height * 0.7))
        }
        let center = window.parent?.frame.midX ?? screen.midX
        restingFrame = NSRect(x: max(screen.minX + 16, min(center - size.width / 2, screen.maxX - size.width - 16)),
                              y: screen.maxY - size.height - 60, width: size.width, height: size.height)
        window.setFrame(restingFrame, display: false)
        window.contentMinSize = NSSize(width: min(size.width, 320), height: min(size.height, 180))
        window.contentView?.layoutSubtreeIfNeeded()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window, event.window === window,
                  !self.editingText,
                  event.modifierFlags.intersection([.command, .option, .shift, .control, .function]).isEmpty,
                  event.keyCode == UInt16(kVK_Space) || event.keyCode == UInt16(kVK_Escape)
            else { return event }
            if !event.isARepeat { self.close() }
            return nil
        }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self, weak window] event in
            guard let self, let window, event.window !== window,
                  !window.frame.contains(NSEvent.mouseLocation) else { return event }
            let inIsland = event.window === window.parent
            self.close()
            if !inIsland { NotchService.shared.collapse() }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self, weak window] _ in
            guard let self, let window, !window.frame.contains(NSEvent.mouseLocation) else { return }
            self.close()
            NotchService.shared.collapse()
        }
        animateIn(window, newlyCreated: true)
        window.orderFrontRegardless()
        window.makeKey()
    }

    private func imageDimensions() -> CGSize? {
        if let width = entry.imageWidth, let height = entry.imageHeight, width > 0, height > 0 {
            return CGSize(width: width, height: height)
        }
        let url: URL?
        if entry.kind == .files, entry.filePaths.count == 1 {
            url = URL(fileURLWithPath: entry.filePaths[0])
        } else if let name = entry.imageFile, (name as NSString).lastPathComponent == name {
            url = ClipboardImageStore.directory?.appendingPathComponent(name)
        } else { url = nil }
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL,
                    [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    private func resizeForImage(_ imageSize: CGSize) {
        guard let window, !isClosing else { return }
        let screen = window.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        let size = ClipboardPreviewLayout.imageSize(imageSize, available: screen.size,
                                                    backingScale: window.backingScaleFactor)
        resize(to: size, within: screen)
    }

    private func resizeForText(_ text: String) {
        guard let window, !isClosing, !editingText else { return }
        let screen = window.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        resize(to: ClipboardPreviewLayout.textSize(text, available: screen.size), within: screen)
    }

    private func resize(to size: CGSize, within screen: NSRect) {
        guard let window, restingFrame.size != size else { return }
        // A decoded image can correct metadata while the panel is arriving.
        // Apply that correction after its origin animation has settled.
        if isEntering {
            pendingSize = (size, screen)
            return
        }
        let center = restingFrame.midX
        restingFrame = NSRect(x: max(screen.minX + 16, min(center - size.width / 2, screen.maxX - size.width - 16)),
                              y: restingFrame.maxY - size.height, width: size.width, height: size.height)
        window.contentMinSize = NSSize(width: min(size.width, 320), height: min(size.height, 180))
        window.setFrame(restingFrame, display: true)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        if let window { restingFrame = window.frame }
    }

    private func animateIn(_ window: NSPanel, newlyCreated: Bool) {
        animationGeneration &+= 1
        isClosing = false
        afterClose = nil
        window.ignoresMouseEvents = false
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        isEntering = !reduceMotion
        if reduceMotion {
            window.setFrame(restingFrame, display: true)
            window.alphaValue = 1
            return
        }
        if newlyCreated { window.setFrameOrigin(NSPoint(x: restingFrame.minX, y: restingFrame.minY + 14)) }
        let generation = animationGeneration
        // Commit the starting position before animating the whole panel, including
        // its shadow. Moving only the origin leaves text and image layout stable.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window,
                  self.animationGeneration == generation, !self.isClosing else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(self.restingFrame, display: true)
                window.animator().alphaValue = 1
            } completionHandler: { [weak self, weak window] in
                guard let self, let window, self.window === window,
                      self.animationGeneration == generation, !self.isClosing else { return }
                self.isEntering = false
                if let pending = self.pendingSize {
                    self.pendingSize = nil
                    self.resize(to: pending.size, within: pending.screen)
                }
            }
        }
    }

    func close(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let window else { completion?(); return }
        if let completion { afterClose = completion }
        isEntering = false
        pendingSize = nil
        if !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            animationGeneration &+= 1
            window.close()
            return
        }
        guard !isClosing else { return }
        isClosing = true
        animationGeneration &+= 1
        let generation = animationGeneration
        window.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            let target = NSRect(x: self.restingFrame.minX, y: self.restingFrame.minY + 8,
                                width: window.frame.width, height: window.frame.height)
            window.animator().setFrame(target, display: true)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self, weak window] in
            guard let self, let window, self.window === window,
                  self.isClosing, self.animationGeneration == generation else { return }
            window.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        animationGeneration &+= 1
        isClosing = false
        isEntering = false
        pendingSize = nil
        for monitor in [keyMonitor, localClickMonitor, outsideClickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        localClickMonitor = nil
        outsideClickMonitor = nil
        if let window {
            // AppKit finishes returning the child's keyboard after willClose.
            DispatchQueue.main.async { NotchService.shared.detachClipboardPreview(window) }
        }
        window?.contentViewController = nil
        window?.delegate = nil
        window = nil
        let completion = afterClose
        afterClose = nil
        onClose(self)
        completion?()
    }
}

private final class ClipboardPreviewPanel: OverlayPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct ClipboardEntryPreviewWindow: View {
    let entry: ClipboardHistoryEntry
    let close: () -> Void
    let edit: () -> Void
    let editingChanged: (Bool) -> Void
    let imageLoaded: (CGSize) -> Void
    let textChanged: (String) -> Void
    @Environment(\.displayScale) private var displayScale
    @ObservedObject private var history = ClipboardHistoryService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var image: CGImage?
    @State private var loading = true
    @State private var isEditingText = false

    private var currentEntry: ClipboardHistoryEntry {
        history.entries.first { $0.id == entry.id } ?? entry
    }

    var isImage: Bool {
        entry.kind == .image || (entry.kind == .files && entry.filePaths.count == 1
            && ClipboardHistoryImageSupport.isImageFileName(entry.filePaths[0]))
    }

    private var text: ClipboardFeatureStrings { FeatureStrings.clipboard(l10n.language) }

    var body: some View {
        Group {
            if isImage {
                imagePreview
            } else {
                ClipboardEntryPreviewSidebar(text: text,
                                             entry: currentEntry,
                                             isEditing: $isEditingText, onClose: close)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .onChange(of: isEditingText) { _, editing in
            editingChanged(editing)
            if !editing, entry.kind == .text { textChanged(currentEntry.text) }
        }
        .onChange(of: currentEntry.text) { _, updated in
            if !isEditingText, entry.kind == .text { textChanged(updated) }
        }
        .task(id: entry.id) {
            guard isImage else { return }
            let entry = entry
            image = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    guard let directory = ClipboardImageStore.directory else { return nil as CGImage? }
                    return ClipboardHistoryImageSupport.editorImage(for: entry, directory: directory)
                        .flatMap { ScreenshotService.imageCapture(from: $0)?.image }
                }
            }.value
            guard !Task.isCancelled else { return }
            loading = false
            if let image { imageLoaded(CGSize(width: image.width, height: image.height)) }
        }
    }

    private var imagePreview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.s.menuClose)
                Label(text.previewLabel, systemImage: "photo")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button(text.edit, action: edit)
                    .disabled(image == nil || !AppFeature.screenshot.isAvailable)
                Button(text.copy) {
                    history.copy(entry) { copied in
                        if copied { close() } else { NSSound.beep() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(image == nil)
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            Divider()
            if let image {
                GeometryReader { geometry in
                    let imageSize = ClipboardPreviewLayout.imageContentSize(
                        CGSize(width: image.width, height: image.height),
                        viewport: geometry.size, backingScale: displayScale)
                    ScrollView(.vertical) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: imageSize.width, height: imageSize.height)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .scrollIndicators(.automatic)
                    .background(Color.primary.opacity(0.04))
                }
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let image {
                Divider()
                HStack {
                    Text("\(image.width) × \(image.height) px")
                    Spacer()
                    Text(FeatureStrings.screenshot(l10n.language).fitWidth)
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }
}
