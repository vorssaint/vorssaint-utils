// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import Translation

/// Owns the two floating pieces of a live-translation session: a resizable,
/// mostly-click-through panel over the selected region (chips, or the
/// composited window-mode image) and a small control pill near it. Modeled
/// directly on RecorderIndicator's panel/pill split.
@available(macOS 15.0, *)
final class LiveTranslationOverlayController: NSObject {
    private var chipPanel: NSPanel?
    private var pillPanel: NSPanel?
    private var pill: LiveTranslationPillView?
    private var globalEscMonitor: Any?
    private var hoverMonitor: Any?
    private var localHoverMonitor: Any?
    private var isHoveringChip = false
    private var isNearResizeEdge = false
    private var hideOnHoverEnabled = false
    private let resizeMargin: CGFloat = 10
    private var cancellables = Set<AnyCancellable>()
    private var dragOriginalChipFrame: CGRect?
    private var dragOriginalPillFrame: CGRect?

    /// The windows the capture loop must leave out of its own screenshots.
    /// A stored snapshot, computed once right after both panels exist below
    /// - not a computed property re-reading `.windowNumber` on every access,
    /// which is only safe from the main actor (AppKit's own rule) and was
    /// forcing `LiveTranslationService.runLoop` through an `await
    /// MainActor.run` hop on every single tick just to read two ints that
    /// never actually change after panel creation. A plain stored `Set` can
    /// be read from any thread safely.
    private(set) var windowIDs: Set<CGWindowID> = []

    func show(region: RecorderSupport.Region) {
        guard chipPanel == nil,
              let screen = NSScreen.screens.first(where: { $0.displayID == region.displayID })
        else { return }

        let defaults = UserDefaults.standard
        let mode = LiveTranslationMode.sanitized(
            defaults.string(forKey: DefaultsKey.liveTranslationMode) ?? "inPlace")
        let providerRaw = defaults.string(forKey: DefaultsKey.liveTranslationProvider) ?? "apple"
        let target = LiveTranslationSupport.resolvedTargetLanguage(
            overrideRaw: defaults.string(forKey: DefaultsKey.liveTranslationTargetLanguage) ?? "",
            fallback: AppLanguage.systemDefault)
        let sourceOverride = LiveTranslationSupport.resolvedSourceLanguage(
            overrideRaw: defaults.string(forKey: DefaultsKey.liveTranslationSourceLanguage) ?? "")

        buildChipPanel(region: region, mode: mode, showsAppleSession: providerRaw != "google",
                      sourceOverride: sourceOverride, target: target)
        buildPillPanel(region: region, screen: screen, mode: mode)
        windowIDs = Set([chipPanel?.windowNumber, pillPanel?.windowNumber].compactMap { number in
            guard let number, number > 0 else { return nil }
            return CGWindowID(number)
        })
        installEscMonitor()
        hideOnHoverEnabled = defaults.bool(forKey: DefaultsKey.liveTranslationHideOnHover)
        installTrackingMonitor()
    }

    /// Split from the old single `close()` into `hide()` (immediate, safe to
    /// call any time) and `teardown()` (deallocates the SwiftUI content,
    /// only safe once `LiveTranslationService` confirms no Apple-session
    /// translate call is still in flight - see
    /// `LiveTranslationService.teardownWhenSafe`'s doc comment for why:
    /// deallocating the hosting view cancels its `.translationTask`, and
    /// doing that while `session.translate()` is still suspended inside
    /// Apple's framework crashes the whole process). Every caller that used
    /// to call `close()` now calls `hide()` immediately for the visible/
    /// interactive teardown, and routes the actual `teardown()` through
    /// `LiveTranslationService.shared.teardownWhenSafe(_:)`.
    func hide() {
        if let globalEscMonitor { NSEvent.removeMonitor(globalEscMonitor) }
        globalEscMonitor = nil
        if let hoverMonitor { NSEvent.removeMonitor(hoverMonitor) }
        hoverMonitor = nil
        if let localHoverMonitor { NSEvent.removeMonitor(localHoverMonitor) }
        localHoverMonitor = nil
        isHoveringChip = false
        isNearResizeEdge = false
        chipPanel?.orderOut(nil)
        pillPanel?.orderOut(nil)
    }

    func teardown() {
        cancellables.removeAll()
        chipPanel?.delegate = nil
        chipPanel = nil
        pillPanel = nil
        pill = nil
    }

    // MARK: - Panels

    private func buildChipPanel(region: RecorderSupport.Region, mode: LiveTranslationMode,
                                showsAppleSession: Bool, sourceOverride: AppLanguage?, target: AppLanguage) {
        let content = LiveTranslationOverlayContent(mode: mode, showsAppleSession: showsAppleSession,
                                                    sourceOverride: sourceOverride, targetLanguage: target,
                                                    service: LiveTranslationService.shared)
        let hosting = NSHostingView(rootView: content)
        let panel = NSPanel(contentRect: region.anchorRect,
                            styleMask: [.borderless, .resizable, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 2)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.minSize = CGSize(width: 80, height: 40)
        panel.delegate = self
        // Click-through by default; a global monitor flips this to false
        // only within resizeMargin of an edge, so dragging the boundary
        // still works without every interactive control needing to live on
        // this panel (they all live on the pill instead).
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.setFrame(region.anchorRect, display: false)
        panel.orderFrontRegardless()
        chipPanel = panel
    }

    private func buildPillPanel(region: RecorderSupport.Region, screen: NSScreen, mode: LiveTranslationMode) {
        let strings = FeatureStrings.liveTranslation(L10n.shared.language)
        let pill = LiveTranslationPillView(frame: CGRect(origin: .zero,
                                                          size: LiveTranslationPillView.size(for: mode)))
        pill.strings = strings
        pill.onTogglePause = { LiveTranslationService.shared.togglePause() }
        pill.onToggleMode = { [weak self] in self?.toggleMode() }
        pill.onCopyOriginal = { [weak self] in self?.copyOriginal() }
        pill.onCopyTranslated = { [weak self] in self?.copyTranslated() }
        pill.onCopyImage = { [weak self] in self?.copyImage(mode: mode) }
        pill.onSaveImage = { [weak self] in self?.saveImage(mode: mode) }
        pill.onClose = { LiveTranslationService.shared.stop() }
        pill.onDragChanged = { [weak self] delta in self?.handlePillDrag(delta: delta) }
        pill.onDragEnded = { [weak self] in self?.endPillDrag() }

        let panelFrame = LiveTranslationSupport.pillFrame(anchorRect: region.anchorRect,
                                                          pillSize: pill.frame.size,
                                                          screenVisibleFrame: screen.visibleFrame)
        let panel = NSPanel(contentRect: panelFrame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = pill
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.orderFrontRegardless()

        pillPanel = panel
        self.pill = pill

        LiveTranslationService.shared.$lines.combineLatest(LiveTranslationService.shared.$status)
            .receive(on: DispatchQueue.main)
            .sink { [weak pill] lines, status in
                pill?.update(lineCount: lines.count, status: status)
            }
            .store(in: &cancellables)
    }

    // MARK: - Pill actions

    /// Rebuilds the overlay through the service, not by calling
    /// `hide()`/`show()` on `self` directly - `show()`'s own guard requires
    /// `chipPanel == nil`, and this controller can't safely null that out
    /// itself without risking the same in-flight-translate teardown hazard
    /// `hide()`/`teardown()` exist to avoid. LiveTranslationService.
    /// rebuildOverlay() reuses the same crash-safe swap `begin()`/`stop()`
    /// use, just without restarting the translation loop or resetting
    /// published state - this is a display-mode toggle, not a new session.
    private func toggleMode() {
        let defaults = UserDefaults.standard
        let current = LiveTranslationMode.sanitized(
            defaults.string(forKey: DefaultsKey.liveTranslationMode) ?? "inPlace")
        let next: LiveTranslationMode = current == .inPlace ? .window : .inPlace
        defaults.set(next.rawValue, forKey: DefaultsKey.liveTranslationMode)
        LiveTranslationService.shared.rebuildOverlay()
    }

    private func copyOriginal() {
        let text = LiveTranslationService.shared.lines.map(\.original).joined(separator: "\n")
        guard !text.isEmpty else { NSSound.beep(); return }
        Self.copyToPasteboard(text)
        QuickToolHUD.show(icon: "doc.on.doc",
                          message: FeatureStrings.liveTranslation(L10n.shared.language).copiedOriginalHUD)
    }

    private func copyTranslated() {
        let text = LiveTranslationService.shared.lines.map(\.translated).joined(separator: "\n")
        guard !text.isEmpty else { NSSound.beep(); return }
        Self.copyToPasteboard(text)
        QuickToolHUD.show(icon: "doc.on.doc",
                          message: FeatureStrings.liveTranslation(L10n.shared.language).copiedTranslatedHUD)
    }

    private func copyImage(mode: LiveTranslationMode) {
        guard let base = LiveTranslationService.shared.lastCapturedImage else { NSSound.beep(); return }
        let composited = LiveTranslationRenderer.compositeImage(
            base: base, lines: LiveTranslationService.shared.lines, mode: mode)
        guard ScreenshotEditorController.copyImage(composited, fileNamePrefix: "Live Translation") else {
            NSSound.beep()
            return
        }
        QuickToolHUD.show(icon: "photo.on.rectangle",
                          message: FeatureStrings.liveTranslation(L10n.shared.language).copiedImageHUD)
    }

    private func saveImage(mode: LiveTranslationMode) {
        guard let base = LiveTranslationService.shared.lastCapturedImage else { NSSound.beep(); return }
        let composited = LiveTranslationRenderer.compositeImage(
            base: base, lines: LiveTranslationService.shared.lines, mode: mode)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = ScreenshotSupport.fileName(prefix: "Live Translation", date: Date())
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let data = ScreenshotRenderer.pngData(from: composited)
            else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    // MARK: - Keyboard and hover

    /// Escape is the one action that must work while some other app has
    /// focus, since that is the whole point of translating while you work
    /// elsewhere. A global monitor only observes; it never blocks the event
    /// from reaching whatever app the person is actually using.
    private func installEscMonitor() {
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            LiveTranslationService.shared.stop()
        }
    }

    /// One monitor drives two independent behaviors: fading the panel on
    /// hover (opt-in setting) and, always, flipping `ignoresMouseEvents` off
    /// within `resizeMargin` of an edge so the boundary can be dragged - a
    /// dynamic-hit-region technique for the same click-through/interactive
    /// tension. Drag-to-resize itself works fine
    /// this way (AppKit's own `.resizable` styleMask handles the drag once
    /// the panel accepts events there); showing a resize *cursor* while
    /// hovering does not - confirmed via diagnostic logging during a live
    /// resize that the panel genuinely flips `ignoresMouseEvents` and calls
    /// `NSCursor.set()` correctly and continuously the whole time, yet macOS
    /// still never displays it. That's an AppKit/WindowServer-level limit on
    /// forcing the cursor from a non-activating background panel while a
    /// different app is actually active, not fixable by adjusting this
    /// code's timing - three separate implementation attempts (single-shot
    /// `.set()`, continuous `.set()`, native cursor rects) all hit the same
    /// wall, so no cursor-forcing code lives here anymore.
    ///
    /// A global monitor only sees mouse-moved events posted to *other* apps -
    /// once the cursor is within `resizeMargin` and `ignoresMouseEvents` goes
    /// false, the very events that matter most (movement over our own panel)
    /// start being delivered locally instead and stop reaching the global
    /// monitor at all. A local monitor picks up exactly that gap, so between
    /// the two, tracking stays continuous across the whole hover journey -
    /// the same dual global+local mouseMoved pattern RadialMenuService uses
    /// for its own continuous pointer tracking elsewhere in this codebase.
    private func installTrackingMonitor() {
        hoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updateChipPanelTracking()
        }
        localHoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.updateChipPanelTracking()
            return event
        }
    }

    private func updateChipPanelTracking() {
        guard let chipPanel else { return }
        let frame = chipPanel.frame
        let point = NSEvent.mouseLocation
        let outer = frame.insetBy(dx: -resizeMargin, dy: -resizeMargin)
        let inner = frame.insetBy(dx: resizeMargin, dy: resizeMargin)
        let nearEdge = outer.contains(point) && !inner.contains(point)

        if nearEdge {
            isNearResizeEdge = true
            chipPanel.ignoresMouseEvents = false
        } else if isNearResizeEdge {
            isNearResizeEdge = false
            chipPanel.ignoresMouseEvents = true
        }

        guard hideOnHoverEnabled else { return }
        let hovering = frame.contains(point)
        guard hovering != isHoveringChip else { return }
        isHoveringChip = hovering
        // Fully invisible, not just faded: a partial fade still reads as
        // "the overlay is in the way," defeating the point of hiding it to
        // read the real content underneath.
        chipPanel.alphaValue = hovering ? 0 : 1
    }

    // MARK: - Drag to move

    /// Moves both panels together, live, by the same cumulative offset the
    /// pill reports - captured once at the start of a drag (nil again once
    /// the drag ends) rather than re-read every event, so each move is
    /// relative to where the panels actually started rather than drifting
    /// off whatever `chipPanel.frame` already was after the previous event.
    private func handlePillDrag(delta: CGSize) {
        guard let chipPanel, let pillPanel else { return }
        if dragOriginalChipFrame == nil {
            dragOriginalChipFrame = chipPanel.frame
            dragOriginalPillFrame = pillPanel.frame
        }
        guard let originalChip = dragOriginalChipFrame, let originalPill = dragOriginalPillFrame else { return }
        chipPanel.setFrameOrigin(CGPoint(x: originalChip.minX + delta.width, y: originalChip.minY + delta.height))
        pillPanel.setFrameOrigin(CGPoint(x: originalPill.minX + delta.width, y: originalPill.minY + delta.height))
    }

    /// Once the bar is dropped in its new spot, restart capture there -
    /// exactly the same "rebuild the region from the panel's own final
    /// frame" path a live resize already goes through (`restartCapture`),
    /// since the chip panel's captured pixels are tied to where it actually
    /// sits on screen, not just to how big it is.
    private func endPillDrag() {
        defer {
            dragOriginalChipFrame = nil
            dragOriginalPillFrame = nil
        }
        guard let chipPanel, dragOriginalChipFrame != nil else { return }
        restartCapture(panel: chipPanel)
    }

    /// Shared by both a live-resize's end and a pill drag's end: rebuilds
    /// the captured region from `panel`'s own current frame and restarts
    /// translation there, reusing the same restart path the initial
    /// selection already goes through rather than a second "adjust the loop
    /// in place" mechanism.
    private func restartCapture(panel: NSPanel) {
        guard let region = LiveTranslationService.shared.activeRegion,
              let screen = NSScreen.screens.first(where: { $0.displayID == region.displayID })
        else { return }
        let scale = screen.backingScaleFactor
        let viewRect = ScreenshotSupport.flippedViewRect(fromCocoa: panel.frame, screenFrame: screen.frame)
        let imageSize = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
        let pixelRect = ScreenshotSupport.imagePixelRect(fromView: viewRect, viewSize: screen.frame.size,
                                                          imageSize: imageSize)
        guard pixelRect.width >= 2, pixelRect.height >= 2 else { return }
        let newRegion = RecorderSupport.Region(displayID: region.displayID, windowID: nil,
                                               pixelRect: pixelRect, anchorRect: panel.frame, scale: scale)
        // Deferred: begin(region:) hides this panel (hide()) and stands up
        // a replacement, deferring actual teardown until safe. AppKit may
        // still be unwinding its own bookkeeping for this exact panel/event
        // while this callback runs (a live-resize delegate callback, or a
        // drag's own mouseUp), so ordering it out and nilling its delegate
        // here, synchronously, is a plausible source of the session not
        // coming back. Letting the current run loop turn finish first is the
        // standard defensive fix for "don't tear a window down from inside
        // its own callback."
        DispatchQueue.main.async {
            LiveTranslationService.shared.begin(region: newRegion)
        }
    }
}

@available(macOS 15.0, *)
extension LiveTranslationOverlayController: NSWindowDelegate {
    /// Fires once when the drag starts - clears the existing chips
    /// immediately (see `LiveTranslationService.clearLinesForResize`'s own
    /// comment for why) rather than leaving stale, pre-resize content
    /// visible for the whole drag.
    func windowWillStartLiveResize(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel, panel === chipPanel else { return }
        LiveTranslationService.shared.clearLinesForResize()
    }

    /// Fires once when the drag ends, not on every intermediate frame, so a
    /// live resize doesn't repeatedly tear down and restart the capture
    /// loop mid-drag.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel, panel === chipPanel else { return }
        restartCapture(panel: panel)
    }
}

// MARK: - Chip panel content

@available(macOS 15.0, *)
private struct LiveTranslationOverlayContent: View {
    let mode: LiveTranslationMode
    let showsAppleSession: Bool
    let sourceOverride: AppLanguage?
    let targetLanguage: AppLanguage
    @ObservedObject var service: LiveTranslationService

    var body: some View {
        ZStack {
            switch mode {
            case .inPlace:
                LiveTranslationChipsView(service: service)
            case .window:
                // Paused means "let me read the real content", so the
                // blurred backdrop goes away too, not just the chips.
                if service.status != .paused, let base = service.lastCapturedImage {
                    // Composited at the panel's own size, not squeezed into a
                    // separate small preview - this is what was illegible
                    // before: a whole region's worth of text crammed into a
                    // fixed 110pt-tall strip.
                    Image(decorative: LiveTranslationRenderer.compositeImage(
                              base: base, lines: service.lines, mode: .window),
                          scale: 1, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                }
            }
            // Always visible so the region's boundary - and its resize
            // handles, which live in the same margin - can be seen. A single
            // solid color disappears against a same-colored background (a
            // white stroke is invisible over a white page); a dark halo
            // behind a light line keeps the boundary visible over anything.
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.black.opacity(0.55), lineWidth: 4)
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.white.opacity(0.95), lineWidth: 1.5)
            // Waits for a confident per-line-detected source (or a pinned
            // override, which skips detection entirely) so the session
            // starts with a real language instead of the unreliable
            // nil-source auto-detect, and stays mounted (not rebuilt) for
            // the rest of the session - see LiveTranslationSessionHost's doc
            // comment for why rebuilding it reactively caused a crash.
            //
            // The explicit `.id(...)` is load-bearing, not decorative:
            // without it, this view's structural identity (this ZStack's
            // other children change size/count every tick as chips come and
            // go) was observed being lost across body re-evaluations even
            // though the `if` condition itself never changed - confirmed via
            // diagnostic logging showing `.onAppear` refiring on nearly every
            // tick instead of once, each time briefly leaving
            // `appleRequestContinuation` nil (surfacing as a `sessionNotReady`
            // status flicker) and abandoning the previous tick's still-live
            // `TranslationSession` without ever cancelling it - the same
            // "abandoned session keeps working daemon-side" cost this
            // session's other fixes went to real lengths to avoid elsewhere,
            // just reached by a different door. A constant literal ID is
            // enough since at most one instance of this view is ever active
            // at a time; it isn't disambiguating between siblings, it's
            // pinning this one view's identity against the reconciliation
            // that was otherwise treating it as new each time.
            if showsAppleSession, sourceOverride != nil || service.detectedSourceLanguage != nil {
                LiveTranslationSessionHost(sourceOverride: sourceOverride, targetLanguage: targetLanguage,
                                           service: service)
                    .id("liveTranslationAppleSessionHost")
            }
        }
    }
}

/// Apple's Translation framework has no standalone session initializer
/// before macOS 26 - every OS version this feature targets must obtain a
/// TranslationSession through a SwiftUI `.translationTask`. This invisible
/// view is that bridge: it lives inside the chip panel for as long as a live
/// session is, consuming `LiveTranslationService.shared.appleRequestStream`
/// and replying to each request from inside this view's own task.
///
/// This view is only inserted once (`showsAppleSession &&` a source is known
/// in the parent), and `configuration` is computed once via `@State` +
/// `.onAppear`, not reactively: an earlier version recomputed it from
/// `service.detectedSourceLanguage` on every change so it could adapt
/// mid-session, but that meant `.translationTask` would tear down and
/// rebuild its session while a translate call from a *previous* session
/// could still be in flight - TranslationSession is scoped to the task that
/// vended it, and using one after that task is no longer live crashes
/// (confirmed via a symbolicated crash report, EXC_BREAKPOINT inside
/// Translation's internals, called from this closure). One session for the
/// whole overlay lifetime, built from whatever was already detected by the
/// time this view mounts, avoids that class of bug entirely.
@available(macOS 15.0, *)
private struct LiveTranslationSessionHost: View {
    let sourceOverride: AppLanguage?
    let targetLanguage: AppLanguage
    @ObservedObject var service: LiveTranslationService
    @State private var configuration: TranslationSession.Configuration?
    @State private var requestStream: AsyncStream<AppleTranslateRequest>?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                let source = sourceOverride ?? service.detectedSourceLanguage
                configuration = TranslationSession.Configuration(
                    source: source.map { Locale.Language(identifier: $0.rawValue) },
                    target: Locale.Language(identifier: targetLanguage.rawValue))
                // Finishes whatever stream the previous session (if any) was
                // still using, so at most one .translationTask ever consumes
                // requests at a time - see appleRequestStream's doc comment.
                requestStream = service.makeAppleRequestStream()
                liveTranslationDiagLog.notice("SessionHost.onAppear fired, source=\(source?.rawValue ?? "nil", privacy: .public)")
            }
            .translationTask(configuration) { session in
                liveTranslationDiagLog.notice("SessionHost.translationTask started, requestStream is nil = \(requestStream == nil, privacy: .public)")
                guard let requestStream else { return }
                for await request in requestStream {
                    liveTranslationDiagLog.notice("SessionHost received request, \(request.texts.count, privacy: .public) texts")
                    guard !Task.isCancelled else { break }
                    // One batch call, not one `session.translate(_:)` await
                    // per text in a loop - see LiveTranslationService.
                    // batchTranslate's doc comment for why a large captured
                    // region's many separate groups made that loop blow the
                    // deadline `translateAndPublish` puts around the whole
                    // call, appearing as translation simply stopping.
                    do {
                        let results = try await LiveTranslationService.batchTranslate(
                            request.texts, using: session)
                        request.reply(.success(results))
                    } catch TranslationError.unsupportedLanguagePairing {
                        request.reply(.failure(TranslationProviderError.notInstalled))
                    } catch {
                        request.reply(.failure(error))
                    }
                }
            }
    }
}

// MARK: - The pill

@available(macOS 15.0, *)
private final class LiveTranslationPillView: NSView {
    static let buttonRowHeight: CGFloat = 34
    static let buttonCount = 7
    static let buttonSize: CGFloat = 28
    static let leadingMargin: CGFloat = 24
    static let trailingMargin: CGFloat = 10
    static let width: CGFloat = leadingMargin + CGFloat(buttonCount) * buttonSize + trailingMargin

    static func size(for mode: LiveTranslationMode) -> CGSize {
        CGSize(width: width, height: buttonRowHeight)
    }

    var strings = FeatureStrings.liveTranslation(.enUS) { didSet { applyTooltips() } }
    var onTogglePause: (() -> Void)?
    var onToggleMode: (() -> Void)?
    var onCopyOriginal: (() -> Void)?
    var onCopyTranslated: (() -> Void)?
    var onCopyImage: (() -> Void)?
    var onSaveImage: (() -> Void)?
    var onClose: (() -> Void)?
    /// Fires with the cumulative screen-point offset since the drag began -
    /// not a per-event increment - so the caller can always just set the
    /// panel's origin directly off its own frame at drag start, the same
    /// "diff against a captured starting frame" shape `restartCapture`
    /// already uses for a live-resize's final frame.
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?

    private let statusDot = CALayer()
    private var isPaused = false
    private var pauseButton: PillButton!
    private var buttons: [PillButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        statusDot.backgroundColor = NSColor.systemBlue.cgColor
        statusDot.cornerRadius = 4
        layer?.addSublayer(statusDot)

        pauseButton = addButton(symbol: "pause.fill", action: #selector(pausePressed))
        buttons = [
            pauseButton,
            addButton(symbol: "rectangle.on.rectangle", action: #selector(modePressed)),
            addButton(symbol: "doc.plaintext", action: #selector(copyOriginalPressed)),
            addButton(symbol: "character.bubble", action: #selector(copyTranslatedPressed)),
            addButton(symbol: "photo.on.rectangle", action: #selector(copyImagePressed)),
            addButton(symbol: "square.and.arrow.down", action: #selector(saveImagePressed)),
            addButton(symbol: "xmark", action: #selector(closePressed)),
        ]
        buttons[buttons.count - 1].contentTintColor = .systemRed
        layoutButtons()
        applyTooltips()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        layoutButtons()
    }

    func update(lineCount: Int, status: LiveTranslationService.Status) {
        isPaused = status == .paused
        pauseButton.image = symbolImage(isPaused ? "play.fill" : "pause.fill")
        let color: NSColor
        switch status {
        case .running: color = lineCount > 0 ? .systemGreen : .systemBlue
        case .paused: color = .systemYellow
        case .idle: color = .secondaryLabelColor
        default: color = .systemRed
        }
        statusDot.backgroundColor = color.cgColor
        toolTip = Self.statusTooltip(status, strings: strings)
    }

    private func addButton(symbol: String, action: Selector) -> PillButton {
        let button = PillButton()
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = symbolImage(symbol)
        button.contentTintColor = .white
        button.focusRingType = .none
        button.target = self
        button.action = action
        addSubview(button)
        return button
    }

    private func layoutButtons() {
        let dotSize: CGFloat = 8
        statusDot.frame = CGRect(x: 10, y: (Self.buttonRowHeight - dotSize) / 2, width: dotSize, height: dotSize)
        var x: CGFloat = Self.leadingMargin
        for button in buttons {
            button.frame = CGRect(x: x, y: (Self.buttonRowHeight - Self.buttonSize) / 2,
                                  width: Self.buttonSize, height: Self.buttonSize)
            x += Self.buttonSize
        }
    }

    private func applyTooltips() {
        guard buttons.count == 7 else { return }
        buttons[0].toolTip = isPaused ? strings.resumeTooltip : strings.pauseTooltip
        buttons[1].toolTip = strings.modeToggleTooltip
        buttons[2].toolTip = strings.copyOriginalTooltip
        buttons[3].toolTip = strings.copyTranslatedTooltip
        buttons[4].toolTip = strings.copyImageTooltip
        buttons[5].toolTip = strings.saveImageTooltip
        buttons[6].toolTip = strings.closeTooltip
    }

    private static func statusTooltip(_ status: LiveTranslationService.Status,
                                      strings: LiveTranslationFeatureStrings) -> String {
        switch status {
        case .idle, .running: return strings.statusRunning
        case .paused: return strings.statusPaused
        case .notInstalled: return strings.statusModelMissing + " - " + strings.statusModelMissingAction
        case .sessionNotReady: return strings.statusRunning
        case .missingAPIKey: return strings.statusMissingAPIKey
        case .invalidAPIKeyOrQuota: return strings.statusInvalidAPIKeyOrQuota
        case .serverError, .failed: return strings.statusFailed
        case .timedOut: return strings.statusTimedOut
        case .usageCapReached: return strings.statusUsageCapReached
        }
    }

    private func symbolImage(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let row = CGRect(x: 0, y: 0, width: bounds.width, height: Self.buttonRowHeight).insetBy(dx: 0.5, dy: 0.5)
        let path = CGPath(roundedRect: row, cornerWidth: row.height / 2, cornerHeight: row.height / 2,
                          transform: nil)
        context.addPath(path)
        context.setFillColor(CGColor(gray: 0.12, alpha: 0.94))
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
        context.setLineWidth(1)
        context.strokePath()
    }

    @objc private func pausePressed() { onTogglePause?() }
    @objc private func modePressed() { onToggleMode?() }
    @objc private func copyOriginalPressed() { onCopyOriginal?() }
    @objc private func copyTranslatedPressed() { onCopyTranslated?() }
    @objc private func copyImagePressed() { onCopyImage?() }
    @objc private func saveImagePressed() { onSaveImage?() }
    @objc private func closePressed() { onClose?() }

    // MARK: - Drag to move

    private var dragStartScreenPoint: NSPoint?

    /// Only reaches here for clicks the button subviews didn't already
    /// consume - AppKit hit-tests subviews first, so this fires solely for
    /// the bar's own empty background (the leading/trailing margins and the
    /// status-dot area around it), exactly the "drag area on the bar" this
    /// exists for, with no dedicated handle view needed.
    override func mouseDown(with event: NSEvent) {
        dragStartScreenPoint = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartScreenPoint else { return }
        let current = NSEvent.mouseLocation
        onDragChanged?(CGSize(width: current.x - start.x, height: current.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStartScreenPoint != nil else { return }
        dragStartScreenPoint = nil
        onDragEnded?()
    }
}

private final class PillButton: NSButton {
    private var hovering = false { didSet { needsDisplay = true } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self))
    }

    override func draw(_ dirtyRect: NSRect) {
        if hovering || isHighlighted {
            NSColor.white.withAlphaComponent(isHighlighted ? 0.18 : 0.10).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
        }
        super.draw(dirtyRect)
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
