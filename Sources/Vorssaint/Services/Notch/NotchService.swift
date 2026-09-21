// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import IOKit.ps
import SwiftUI

struct NotchNotice: Equatable {
    let event: NotchEvent
    let title: String
    let detail: String
    let symbol: String
    var level: Double? = nil
    var notification: NotchNotificationContent? = nil
    var notificationID: UUID? = nil

    var preferredWingWidth: CGFloat {
        if notification != nil { return 190 }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let leading = ((level == nil ? title : detail) as NSString).size(withAttributes: [.font: font]).width
        let trailing = level == nil ? (detail as NSString).size(withAttributes: [.font: font]).width : 0
        // Reserve the icon, spacing and both insets before limiting long names.
        return min(240, max(112, ceil(max(leading + 18 + 8, trailing)) + 32))
    }

    var accessibilityText: String {
        notification?.accessibilityText ?? [title, detail].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    func previewContentHeight(width: CGFloat) -> CGFloat {
        guard let notification else { return 0 }
        return NotchNotificationPreviewLayout.contentHeight(for: notification, width: width)
    }
}

/// Owns presentation only. Clipboard, files, captures, audio and metrics keep
/// their original owners, gates and privacy rules.
final class NotchService: ObservableObject {
    static let shared = NotchService()

    @Published private(set) var geometry = NotchGeometry(
        screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 0, cameraWidth: 0)
    @Published private(set) var expanded = false
    @Published private(set) var peeking = false
    @Published private(set) var dragPlaceholder = false
    @Published private(set) var choosingFileDropDestination = false
    @Published private(set) var targetsMediaDrop = false
    @Published private(set) var selectedMetric: MetricDetailKind?
    @Published private(set) var captureControls: ScreenCaptureSelectionOptions?
    @Published private(set) var captureControlsCollapsed = false
    @Published private(set) var captureSelectionInProgress = false
    @Published var pinned = false
    @Published private(set) var selected: NotchModule = .controls
    @Published private(set) var showingAppPanel = false
    @Published private(set) var showingSections = false
    @Published private(set) var sectionQuery = ""
    @Published var highlightedSection: NotchModule?
    @Published private(set) var modules: [NotchModule] = []
    @Published private(set) var notice: NotchNotice?
    @Published private(set) var noticeExpanded = false
    @Published private(set) var captureContent: AnyView?
    /// Bumped when Command-W asks the Scratchpad page to close its selected
    /// pad, so the confirmation stays in the page as it does in the floating pad.
    @Published private(set) var scratchpadCloseSerial = 0
    @Published private var captureContentHeight: CGFloat?
    @Published private(set) var power = PowerReading()
    @Published private var musicDetailVisible = false

    private var windowHost: NotchWindowHost?
    private var panel: NotchPanel? { windowHost?.panel }
    private var captureControlsCancel: (() -> Void)?
    private var captureControlsSubscription: AnyCancellable?
    private var captureControlsWork: DispatchWorkItem?
    private var heldDrag = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var subscriptions = Set<AnyCancellable>()
    private var eventMonitors: [Any] = []
    private var screenEdgeClickMonitors: [Any] = []
    private var screenEdgePressArea: CGRect?
    private var captureControlsMonitors: [Any] = []
    private var hiddenHoverMonitors: [Any] = []
    private var hoverWork: DispatchWorkItem?
    private var noticeWork: DispatchWorkItem?
    private var powerSource: CFRunLoopSource?
    private var powerSampler: PowerSampler?
    private var captureID: UUID?
    private var captureFallback: (() -> Void)?
    private var captureClose: (() -> Void)?
    private var captureHover: ((Bool) -> Void)?
    private var inside = false
    private var hoverState = NotchHoverState()
    private var openedByHover = false
    private var trackingMenu = false
    private var fileInteractionActive = false
    private var keepsWorkingSurface: Bool {
        pinned || trackingMenu || NSApp.modalWindow != nil || panel?.attachedSheet != nil
            || (expanded && !showingSections && selected == .calendar && Permissions.shared.keepsCalendarPrompt)
            || (expanded && !showingSections && selected == .files && fileInteractionActive)
            || CameraPreviewService.shared.keepsNotchPermissionPrompt
            || (expanded && !showingSections && selected == .captures && captureContent != nil)
            || (expanded && !showingSections && selected == .tools && (QuickLauncherService.shared.activeUtility != nil || QuickLauncherService.shared.isEditing))
    }
    private var running = false
    private var session = NotchSessionState()
    private var suspended: Bool { !session.canPresent }
    private var hiddenInFullscreen = false
    private var settingsSignature = ""
    private var gesture = NotchGestureSupport()
    private var volumeBaseline: Double?
    private var muteBaseline: Bool?
    private var volumeDeviceUID: String?
    private var notchNeedsMonitor = false
    private var menuSpaceTimer: Timer?
    private var menuSpaceReading = false
    private var menuSpaceGeneration = 0
    private var menuBarMeasurements = NotchMenuBarMeasurements()
    private var screenRefreshWork: DispatchWorkItem?
    private let menuSpaceQueue = DispatchQueue(label: "com.vorssaint.notch-menu-space", qos: .utility)

    private init() {}

    private var hiddenUntilHover: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.notchHideUntilHover)
            && UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover)
            && !expanded && !peeking && !dragPlaceholder && captureControls == nil
    }

    var idleContent: NotchIdleContent {
        NotchSupport.visibleIdleContent(isPlaying: NotchMusicService.shared.playback?.isPlaying == true)
    }

    var hasTimerActivity: Bool {
        NotchTimerSupport.isEnabled() && NotchTimerService.shared.session.hasSession
    }

    var hasDownloadActivity: Bool {
        NotchSupport.routes(.download)
            && NotchDownloadService.shared.items.contains { $0.active && !$0.completed }
    }

    var hasMusicActivity: Bool {
        NotchSupport.showsMusicActivity(isPlaying: NotchMusicService.shared.playback?.isPlaying == true)
    }

    var compactActivity: NotchCompactActivity? {
        NotchSupport.compactActivity(timer: hasTimerActivity, downloads: hasDownloadActivity, music: hasMusicActivity)
    }

    private var compactActivityIsVisible: Bool {
        !expanded && !peeking && !dragPlaceholder && notice == nil && captureControls == nil
            && compactActivity != nil
    }

    private var compactMusicIsVisible: Bool { compactActivityIsVisible && compactActivity == .music }

    var compactActivityGeometry: NotchGeometry {
        switch compactActivity {
        case .music: return geometry.compactMusicGeometry
        case .timer: return geometry.compactTimerGeometry(showsDownloads: hasDownloadActivity)
        default: return geometry
        }
    }

    var expandedSize: CGSize {
        if showingSections {
            return geometry.sectionPickerSize(count: filteredSections.count)
        }
        let controls = NotchSupport.controls()
        let sliders = controls.filter { $0 == .volume || $0 == .brightness }.count
        let shortcuts = controls.filter { $0 != .volume && $0 != .brightness && $0 != .music }.count
        let musicExtras = NotchLyricsSupport.isEnabled() || NotchQueueSupport.isEnabled()
        let launcher = QuickLauncherService.shared
        return geometry.expandedSize(module: showingAppPanel ? .tools : selected,
                                     detail: selectedMetric != nil, panel: showingAppPanel, shortcutCount: shortcuts,
                                     sliderCount: sliders, controlsHaveMusic: controls.contains(.music), musicHasContent: NotchMusicService.shared.playback != nil,
                                     musicHasControlsRow: AppFeature.mixer.isAvailable || musicExtras,
                                     musicExtraHeight: musicExtras && musicDetailVisible ? geometry.musicExtrasHeight : 0,
                                     fileMediaHeight: !choosingFileDropDestination && AppFeature.mediaTools.isAvailable
                                        && NotchFileToolsService.shared.mediaPresented ? NotchFileToolsService.shared.mediaContentHeight : nil,
                                     systemCards: NotchSupport.systemCardCount(hasBattery: PowerSampler.hasInternalBattery,
                                                                               fans: SystemMonitor.shared.snapshot.fanSpeeds.count),
                                     toolCount: launcher.isEditing || launcher.activeUtility != nil ? nil : launcher.visibleItems.count,
                                     capturePreviewHeight: captureContent == nil ? nil : captureContentHeight,
                                     timerHasSession: NotchTimerService.shared.session.hasSession,
                                     timerMode: NotchTimerService.shared.session.hasSession
                                        ? NotchTimerService.shared.session.mode : NotchTimerSupport.savedMode())
    }
    var contentSize: CGSize { geometry.contentSize(for: expandedSize) }
    var surfaceSize: CGSize {
        if let captureControls {
            if captureControlsCollapsed {
                return CGSize(width: geometry.cameraWidth + 56, height: geometry.menuBarHeight)
            }
            return CGSize(width: geometry.expanded.width,
                          height: geometry.safeContentTop + 28 + 12 + NotchLayout.shortcutHeight + 16
                            + (captureControls.selectedTool.capturesAudio ? 40 : 0))
        }
        if expanded { return expandedSize }
        if dragPlaceholder { return CGSize(width: geometry.peek.width, height: geometry.safeContentTop + 66) }
        if let notice {
            guard noticeExpanded else { return geometry.noticeSize(wingWidth: notice.preferredWingWidth) }
            return geometry.notificationPreviewSize(
                contentHeight: notice.previewContentHeight(width: geometry.notificationPreviewContentWidth))
        }
        if peeking { return geometry.peek }
        if compactActivity != nil { return compactActivityGeometry.compactActivitySize }
        return geometry.restingSize(showsContent: idleContent != .none)
    }

    var presentationWindow: NSPanel? { panel }
    var acceptsSystemFeedback: Bool {
        running && !suspended && !hiddenInFullscreen && panel != nil
    }
    var showsSystemFeedback: Bool {
        acceptsSystemFeedback && !hiddenUntilHover
    }

    var protectedWindowIDs: Set<CGWindowID> {
        guard !NotchSupport.showsInCaptures(),
              let panel, panel.isVisible, panel.windowNumber > 0 else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    var captureVisibleWindowIDs: Set<CGWindowID> {
        guard NotchSupport.showsInCaptures(), let panel, panel.isVisible,
              panel.windowNumber > 0 else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    /// While a capture is choosing an area on screen, the notch is part of the
    /// capture interface, so its window is kept out of the pixels no matter
    /// what the everyday "show in captures" preference says. This lets people
    /// grab whatever sits behind the notch cleanly.
    var captureChromeWindowIDs: Set<CGWindowID> {
        guard running, let panel, panel.isVisible, panel.windowNumber > 0 else { return [] }
        return [CGWindowID(panel.windowNumber)]
    }

    func syncWithPreferences() {
        guard NotchSupport.isEnabled() else { stop(); return }
        if !running {
            running = true
            installObservers()
        }
        if !NotchTimerSupport.isEnabled() { NotchTimerService.shared.stop() }
        // Requested file work can continue while locked, but disabling its
        // feature must still cancel it before presentation resumes.
        NotchFileToolsService.shared.syncWithPreferences()
        if !NotchFileToolsService.shared.offersMediaDrop { endFileDrop() }
        guard !suspended else {
            if session.canRunTimer { NotchTimerService.shared.syncWithPreferences() }
            else { NotchTimerService.shared.suspend() }
            return
        }
        refreshModules()
        NotchDownloadService.shared.syncWithPreferences()
        NotchCalendarService.shared.syncWithPreferences()
        NotchNotificationService.shared.syncWithPreferences()
        NotchAudioLevelService.shared.syncWithPreferences()
        updateScreen()
        syncGestures()
        NotchTimerService.shared.syncWithPreferences()
        NotchAccessoryService.shared.syncWithPreferences()
        let signature = NotchEvent.allCases.map { String(NotchSupport.routes($0)) }.joined()
            + NotchSupport.idleContent().rawValue + String(NotchSupport.watchesMusicActivity())
            + modules.map(\.rawValue).joined()
            + String(AppFeature.fanControl.isAvailable)
            + String(NotchSupport.routesShelf()) + String(NotchSupport.revealsShelfDrag())
            + String(NotchSupport.routesCaptureControls())
        if signature != settingsSignature {
            settingsSignature = signature
            bindEvents()
            if AppFeature.shelf.isAvailable { ShelfService.shared.syncWithPreferences() }
        }
        if !NotchSupport.routes(.capture), captureContent != nil {
            let fallback = captureFallback
            clearCapture()
            fallback?()
        }
        if captureControls != nil, !NotchSupport.routesCaptureControls() { cancelCaptureControls() }
        syncNoticeWithPreferences()
        syncVisibleConsumers()
        refreshPresentation(animated: false)
        if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
    }

    private func refreshModules() {
        let updated = NotchSupport.modules()
        if modules != updated { modules = updated }
        let selection = modules.contains(selected) ? selected : modules.first ?? .controls
        if selected != selection { selected = selection }
        if let selectedMetric, !metricIsAvailable(selectedMetric) { self.selectedMetric = nil }
    }

    private func metricIsAvailable(_ metric: MetricDetailKind) -> Bool {
        MenuBarMetric.allCases.contains { $0.detailKind == metric && $0.feature.isAvailable }
    }

    func stop(restoreCapture: Bool = true) {
        NotchLyricsService.shared.stop()
        NotchFileToolsService.shared.stop()
        guard running else { return }
        running = false
        NotchTimerService.shared.stop()
        NotchAccessoryService.shared.stop()
        let cancelCapture = captureControlsCancel
        endCaptureControls()
        cancelCapture?()
        let fallback = restoreCapture ? captureFallback : captureClose
        clearCapture()
        tearDownPresentation()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        session = NotchSessionState()
        if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
        if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }
        if AppFeature.shelf.isAvailable { ShelfService.shared.syncWithPreferences() }
        fallback?()
    }

    private func tearDownPresentation() {
        screenRefreshWork?.cancel(); screenRefreshWork = nil
        captureControlsWork?.cancel(); captureControlsWork = nil
        musicDetailVisible = false
        panel?.handleScroll = nil
        gesture = NotchGestureSupport()
        stopMenuSpaceMonitoring()
        geometry.compactSideRoom = nil
        hoverWork?.cancel(); hoverWork = nil
        noticeWork?.cancel(); noticeWork = nil
        subscriptions.removeAll()
        stopPower()
        NotchMusicService.shared.stop()
        NotchAudioLevelService.shared.stop()
        CameraPreviewService.shared.hideEmbedded()
        NotchAccessoryService.shared.suspend()
        NotchDownloadService.shared.stop()
        NotchCalendarService.shared.stop()
        NotchNotificationService.shared.stop()
        settingsSignature = ""
        expanded = false
        peeking = false
        dragPlaceholder = false
        endFileDrop()
        fileInteractionActive = false
        heldDrag = false
        selectedMetric = nil
        pinned = false
        notice = nil
        noticeExpanded = false
        showingAppPanel = false
        showingSections = false
        sectionQuery = ""
        highlightedSection = nil
        inside = false
        hoverState = NotchHoverState()
        openedByHover = false
        removeEventMonitors()
        removeScreenEdgeClickMonitors()
        removeCaptureControlsClickThrough()
        removeHiddenHoverMonitors()
        releaseMonitor()
        windowHost?.close()
        windowHost = nil
        hiddenInFullscreen = false
    }

    /// Opening without a page shows what the closed island is already
    /// presenting. Only at rest does the reopening preference decide.
    var reopeningModule: NotchModule {
        if !expanded {
            let activity = notice?.notificationID != nil ? NotchModule.notifications : compactActivity?.module
            if let activity, modules.contains(activity) { return activity }
            if UserDefaults.standard.bool(forKey: DefaultsKey.notchReturnHome) {
                let home = NotchModule(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.notchHomeModule) ?? "") ?? .controls
                return modules.contains(home) ? home : modules.first ?? .controls
            }
        }
        return selected
    }

    func open(_ module: NotchModule? = nil, pinned: Bool = false, takeFocus: Bool = true,
              appPanel: Bool = false, metric: MetricDetailKind? = nil, feedback: Bool = true, sections: Bool = false) {
        guard NotchSupport.isEnabled(), !suspended else { return }
        if !running || self.panel == nil { syncWithPreferences() }
        else { refreshModules() }
        guard !hiddenInFullscreen, let panel else { return }
        let destination = module.flatMap { modules.contains($0) ? $0 : nil } ?? reopeningModule
        let metric = metric.flatMap { metricIsAvailable($0) ? $0 : nil }
        let changesPresentation = !expanded || selected != destination
            || showingAppPanel != appPanel || selectedMetric != metric || showingSections != sections
        if changesPresentation, destination == .tools, !appPanel, !sections, metric == nil {
            QuickLauncherService.shared.prepareForPresentation()
        }
        (NSApp.delegate as? AppDelegate)?.closePopover(preservingNotch: true)
        if !expanded, modules.contains(.clipboard) { ClipboardHistoryService.shared.rememberPasteTarget() }
        panel.acceptsKeyFocus = true
        hoverState.open()
        hoverWork?.cancel()
        mutatePresentation(transitionContent: changesPresentation ? (expanded ? .replace : .reveal) : .none) {
            showingAppPanel = appPanel
            showingSections = sections
            if selected != destination { selected = destination }
            if pinned { self.pinned = true }
            selectedMetric = metric
            peeking = false
            openedByHover = !takeFocus
            expanded = true
            // The open island covers a mirrored banner, and the inbox keeps
            // the message; a held one must not reappear after collapsing.
            if notice?.notificationID != nil { noticeWork?.cancel(); noticeWork = nil; notice = nil; noticeExpanded = false }
        }
        inside = windowHost?.containsHover(NSEvent.mouseLocation) == true
        installEventMonitors()
        syncVisibleConsumers()
        if takeFocus { panel.makeKey() }
        if feedback, changesPresentation { provideHapticFeedback() }
    }

    func collapse() {
        guard captureControls == nil, !heldDrag else { return }
        hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
        pinned = false
        hoverWork?.cancel(); hoverWork = nil
        if noticeExpanded { noticeWork?.cancel(); noticeWork = nil }
        mutatePresentation(transitionContent: expanded || peeking || noticeExpanded ? .dismiss : .none) {
            if noticeExpanded { notice = nil; noticeExpanded = false }
            expanded = false
            openedByHover = false
            peeking = false
            selectedMetric = nil
            showingAppPanel = false
            showingSections = false
            sectionQuery = ""
            highlightedSection = nil
        }
        panel?.acceptsKeyFocus = false
        panel?.resignKey()
        removeEventMonitors()
        syncVisibleConsumers()
    }

    func toggle() { expanded ? collapse() : open() }

    func setMusicDetailsVisible(_ visible: Bool) {
        guard visible != musicDetailVisible else { return }
        mutatePresentation { musicDetailVisible = visible }
    }

    @discardableResult
    func showClipboard(toggle: Bool = false) -> Bool {
        guard acceptsSystemFeedback, NotchSupport.routesClipboardWindow() else { return false }
        if toggle, expanded, selected == .clipboard, !showingAppPanel, !showingSections { collapse() }
        else { open(.clipboard) }
        return true
    }

    func hover(_ entered: Bool) {
        guard running, !suspended, !hiddenInFullscreen else { return }
        let point = NSEvent.mouseLocation
        let wasInside = inside
        inside = hiddenUntilHover ? geometry.contains(point, in: geometry.collapsed)
            : windowHost?.containsHover(point) == true
        hoverState.update(pointerInside: inside)
        captureHover?(entered)
        if captureControls != nil {
            updateCaptureControlsHover(wasInside: wasInside)
            return
        }
        guard !pinned, !heldDrag, !keepsWorkingSurface else {
            hoverWork?.cancel(); hoverWork = nil
            // A dialog or menu keeps the island, not a banner the pointer left.
            if !inside { releaseNotification() }
            return
        }
        // Overlapping tracking areas can report the same presence repeatedly.
        // Keep the first deadline until the pointer actually crosses the boundary.
        if inside == wasInside, let hoverWork, !hoverWork.isCancelled { return }
        hoverWork?.cancel(); hoverWork = nil
        if inside {
            if holdsNotification, let id = notice?.notificationID { holdNotification(id); return }
            guard !hoverState.suppressed, (notice == nil || hiddenUntilHover), !expanded, !peeking, !dragPlaceholder,
                  UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover) else { return }
            if compactActivity != nil, compactActivityGeometry.compactActivityWingWidth > 0,
               !UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverExpands) { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hoverWork = nil
                guard self.running, !self.suspended, self.inside, !self.hoverState.suppressed,
                      !self.expanded, !self.peeking, !self.pinned, !self.heldDrag, !self.keepsWorkingSurface,
                      self.captureControls == nil, (self.notice == nil || self.hiddenUntilHover), !self.dragPlaceholder,
                      UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover),
                      self.geometry.contains(NSEvent.mouseLocation, in: self.hiddenUntilHover ? self.geometry.collapsed : self.surfaceSize) else { return }
                if UserDefaults.standard.bool(forKey: DefaultsKey.notchHoverExpands) {
                    self.open(takeFocus: false)
                } else {
                    self.mutatePresentation(transitionContent: .reveal) { self.peeking = true }
                    self.provideHapticFeedback()
                }
            }
            hoverWork = work
            let delay = NotchSupport.sanitizedHoverDelay(UserDefaults.standard.double(forKey: DefaultsKey.notchHoverDelay))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else if holdsNotification
                    || NotchSupport.closesOnPointerExit(expanded: expanded, peeking: peeking, openedByHover: openedByHover) {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hoverWork = nil
                guard self.running, !self.suspended, !self.inside,
                      self.windowHost?.containsHover(NSEvent.mouseLocation) != true else { return }
                self.releaseNotification()
                guard !self.pinned, !self.heldDrag, !self.keepsWorkingSurface, self.captureControls == nil,
                      !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation),
                      NotchSupport.closesOnPointerExit(expanded: self.expanded, peeking: self.peeking, openedByHover: self.openedByHover) else { return }
                self.collapse()
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (expanded || noticeExpanded ? NotchQuickAccessLayout.hoverExitDelay : 0.12), execute: work)
        }
    }

    /// A mirrored banner the pointer can hold: on screen and not covered.
    /// Hidden mode keeps its notices out of reach, as the surface is not shown.
    private var holdsNotification: Bool {
        notice?.notificationID != nil && noticeCanPresent && !hiddenUntilHover
    }

    /// A mirrored banner waits under the pointer, as the native one does, and
    /// a deliberate hover opens its whole message in place.
    private func holdNotification(_ id: UUID) {
        noticeWork?.cancel(); noticeWork = nil
        guard !noticeExpanded, !hoverState.suppressed,
              UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverWork = nil
            guard self.running, !self.suspended, self.inside, !self.hoverState.suppressed, !self.pinned, !self.heldDrag,
                  !self.keepsWorkingSurface, self.holdsNotification, self.notice?.notificationID == id, !self.noticeExpanded,
                  UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover),
                  self.geometry.contains(NSEvent.mouseLocation, in: self.surfaceSize) else { return }
            self.mutatePresentation(transitionContent: .reveal) { self.peeking = false; self.noticeExpanded = true }
            self.provideHapticFeedback()
        }
        hoverWork = work
        let delay = NotchSupport.sanitizedHoverDelay(UserDefaults.standard.double(forKey: DefaultsKey.notchHoverDelay))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Leaving closes an opened preview; a banner that was only held gets its
    /// full time again, so a quick pass over it never cuts it short.
    private func releaseNotification() {
        guard let notice, notice.notificationID != nil else { return }
        if noticeExpanded { dismissNotice() }
        else if noticeWork == nil { scheduleNoticeDismissal(after: notice.event.duration) }
    }

    private func syncNoticeWithPreferences() {
        guard let notice else { return }
        if !NotchSupport.routes(notice.event) || (notice.notificationID != nil && hiddenUntilHover) {
            dismissNotice()
        }
    }

    private func scheduleNoticeDismissal(after duration: TimeInterval) {
        noticeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismissNotice() }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    var filteredSections: [NotchModule] {
        NotchSupport.filteredModules(modules, query: sectionQuery) { module in
            let language = L10n.shared.language
            let music = module == .music ? FeatureStrings.notch(language).music : ""
            return [module.title(language), module.rawValue, music].joined(separator: " ")
        }
    }

    func searchSections(_ query: String) {
        guard sectionQuery != query else { return }
        mutatePresentation {
            sectionQuery = query
            highlightedSection = filteredSections.first
        }
    }

    func toggleSections() {
        guard captureControls == nil, !heldDrag else { return }
        if showingSections {
            open(appPanel: showingAppPanel, metric: selectedMetric)
        } else {
            sectionQuery = ""
            highlightedSection = selected
            open(appPanel: showingAppPanel, metric: selectedMetric, sections: true)
        }
    }

    private func handleSectionKey(_ event: NSEvent) -> Bool {
        guard showingSections,
              (panel?.firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.keyCode == 48, modifiers.isEmpty || modifiers == .shift {
            highlightedSection = NotchSupport.adjacentModule(to: highlightedSection, modules: filteredSections,
                                                             backwards: modifiers == .shift)
            return true
        }
        guard modifiers.isEmpty else { return false }
        if event.keyCode == 36 || event.keyCode == 76 {
            if let target = highlightedSection, filteredSections.contains(target) { select(target) }
            return true
        }
        let direction: QuickToolsSupport.GridDirection
        switch event.keyCode {
        case 123 where sectionQuery.isEmpty: direction = .left
        case 124 where sectionQuery.isEmpty: direction = .right
        case 125: direction = .down
        case 126: direction = .up
        default: return false
        }
        let sections = filteredSections
        guard !sections.isEmpty else { return true }
        // While typing, the side arrows keep editing the query and the
        // vertical pair steps through the matches in order.
        guard sectionQuery.isEmpty else {
            highlightedSection = NotchSupport.adjacentModule(to: highlightedSection, modules: sections,
                                                             backwards: direction == .up)
            return true
        }
        let index = highlightedSection.flatMap { sections.firstIndex(of: $0) } ?? 0
        highlightedSection = sections[QuickToolsSupport.gridIndex(after: index, count: sections.count,
                                                                   flow: .columns(rows: geometry.sectionRows(count: sections.count)),
                                                                   direction: direction)]
        return true
    }

    /// The floating pad's tab shortcuts work on its page too. With one pad
    /// left, Command-W closes the island the way it hides the pad.
    private func handleScratchpadKey(_ event: NSEvent) -> Bool {
        guard selected == .scratchpad, !showingAppPanel, !showingSections, selectedMetric == nil else { return false }
        let pad = ScratchpadService.shared
        let commandOnly = event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command
        guard let action = ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                                                               commandOnly: commandOnly,
                                                               canCreatePad: pad.canCreatePad,
                                                               canClosePad: pad.canClosePad) else {
            // At the tab limit Command-T still belongs to the pad, not the text.
            return commandOnly && event.charactersIgnoringModifiers?.lowercased() == "t"
        }
        switch action {
        case .createPad: pad.createPad(defaultName: FeatureStrings.scratchpad(L10n.shared.language).pageTitle)
        case .closeSelectedPad: scratchpadCloseSerial += 1
        case .hidePad: collapse()
        }
        return true
    }

    func activateQuickAction(_ action: NotchQuickAction) {
        guard NotchSupport.isEnabled(), action.isAvailable() else { return }
        switch action {
        case .explore: toggleSections()
        case .settings: openSettings()
        case .pin: pinned.toggle()
        case .module(let module): select(module)
        case .control(let item):
            switch item {
            case .keepAwake: KeepAwakeManager.shared.toggle()
            case .microphone: MicMuteService.shared.toggle()
            case .screenshot: perform { ScreenshotService.shared.capture() }
            case .recording: perform { ScreenRecorderService.shared.toggle() }
            case .speedTest: showMetric(.network)
            case .panel: openAppPanel()
            case .mixer: select(.mixer)
            case .music: select(.music)
            case .timer: select(.timer)
            case .calendar: select(.calendar)
            case .commandBar: perform { CommandBarService.shared.show() }
            case .scratchpad: openScratchpad()
            case .volume, .brightness: select(.controls)
            }
        }
    }

    func select(_ module: NotchModule) {
        guard modules.contains(module) else { return }
        open(module)
    }

    /// The pad lives in the island when its page is on; otherwise the
    /// shortcut opens the floating pad as it always did.
    func openScratchpad() {
        if modules.contains(.scratchpad) { open(.scratchpad) }
        else { perform { ScratchpadService.shared.show() } }
    }

    func openAppPanel(toggle: Bool = false) {
        if toggle, expanded, showingAppPanel, !showingSections { collapse(); return }
        MenuPanelFocus.shared.showNormalPanel()
        open(.controls, appPanel: true)
    }

    func openQuickPanel(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesQuickPanel(), acceptsSystemFeedback else { return false }
        if toggle, expanded, selected == .tools, !showingSections { collapse() }
        else { open(.tools) }
        return true
    }

    func openShelf(toggle: Bool = false) -> Bool {
        guard NotchSupport.routesShelf(), acceptsSystemFeedback else { return false }
        if toggle, expanded, selected == .files, !showingSections { collapse() }
        else { open(.files) }
        return true
    }

    func showMetric(_ metric: MetricDetailKind, toggle: Bool = false) {
        guard metricIsAvailable(metric) else { return }
        if toggle, expanded, selectedMetric == metric, !showingSections { collapse(); return }
        open(.system, metric: metric)
    }

    func goBack() {
        let changesPresentation = selectedMetric != nil || showingAppPanel
        mutatePresentation(transitionContent: changesPresentation ? .replace : .none) { selectedMetric = nil; showingAppPanel = false }
        syncVisibleConsumers()
        if changesPresentation { provideHapticFeedback() }
    }

    func provideHapticFeedback() {
        guard acceptsSystemFeedback, panel?.isVisible == true, NotchSupport.usesHapticFeedback() else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    func fileDragChanged(_ active: Bool, internalDrag: Bool = false) {
        guard running, !suspended, internalDrag || NotchSupport.routesShelf() else { return }
        heldDrag = active && internalDrag
        if active, !internalDrag, NotchSupport.revealsShelfDrag(), !expanded {
            mutatePresentation { dragPlaceholder = true; peeking = false }
        } else if !active {
            mutatePresentation { dragPlaceholder = false }
            inside = windowHost?.containsHover(NSEvent.mouseLocation) == true
            if !inside, !pinned { hover(false) }
        }
    }

    func presentCaptureControls(_ options: ScreenCaptureSelectionOptions, cancel: @escaping () -> Void) {
        guard acceptsSystemFeedback else { cancel(); return }
        pinned = false
        captureControlsCancel = cancel
        captureControls = options
        captureControlsCollapsed = false
        captureSelectionInProgress = false
        hoverState.open()
        options.onSelectionProgressChange = { [weak self, weak options] active in
            guard let self, let options, self.captureControls === options else { return }
            self.setCaptureSelectionInProgress(active)
        }
        captureControlsSubscription = options.$selectedTool.dropFirst()
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.objectWillChange.send()
                self?.refreshPresentation()
                self?.updateCaptureControlsClickThrough()
                self?.scheduleCaptureControlsCollapse()
            }
        expanded = false
        showingSections = false
        peeking = false
        notice = nil
        noticeExpanded = false
        hoverWork?.cancel()
        removeEventMonitors()
        panel?.acceptsKeyFocus = true
        panel?.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        refreshPresentation()
        panel?.orderFrontRegardless()
        panel?.makeKey()
        installCaptureControlsClickThrough()
        syncVisibleConsumers()
    }

    func collapseCaptureControls() {
        guard captureControls != nil else { return }
        captureControlsWork?.cancel(); captureControlsWork = nil
        hoverWork?.cancel(); hoverWork = nil
        hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
        captureControls?.hasFocusedControl = false
        captureControlsCollapsed = true
        refreshPresentation(animated: !captureSelectionInProgress)
        updateCaptureControlsClickThrough()
    }

    func expandCaptureControls() {
        guard captureControls != nil, !captureSelectionInProgress else { return }
        hoverWork?.cancel(); hoverWork = nil
        hoverState.open()
        captureControlsCollapsed = false
        refreshPresentation()
        panel?.makeKey()
        updateCaptureControlsClickThrough()
    }

    private func setCaptureSelectionInProgress(_ active: Bool) {
        guard captureControls != nil else { return }
        captureSelectionInProgress = active
        if active { collapseCaptureControls() }
        else {
            refreshPresentation()
            updateCaptureControlsClickThrough()
        }
    }

    func scheduleCaptureControlsCollapse() {
        captureControlsWork?.cancel(); captureControlsWork = nil
        guard let options = captureControls, !captureControlsCollapsed, !captureSelectionInProgress,
              !options.hasFocusedControl, !inside else { return }
        let work = DispatchWorkItem { [weak self, weak options] in
            guard let self, let options, self.captureControls === options else { return }
            self.captureControlsWork = nil
            guard !self.captureControlsCollapsed, !self.captureSelectionInProgress,
                  !options.hasFocusedControl, !self.trackingMenu,
                  self.panel?.attachedSheet == nil,
                  self.windowHost?.containsHover(NSEvent.mouseLocation) != true else { return }
            self.collapseCaptureControls()
        }
        captureControlsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func updateCaptureControlsHover(wasInside: Bool) {
        guard let options = captureControls, !captureSelectionInProgress else { return }
        if !captureControlsCollapsed {
            if inside {
                captureControlsWork?.cancel(); captureControlsWork = nil
            } else if wasInside || captureControlsWork == nil {
                scheduleCaptureControlsCollapse()
            }
            return
        }
        if inside == wasInside, let hoverWork, !hoverWork.isCancelled { return }
        hoverWork?.cancel(); hoverWork = nil
        guard inside, !hoverState.suppressed else { return }
        let work = DispatchWorkItem { [weak self, weak options] in
            guard let self, let options, self.captureControls === options else { return }
            self.hoverWork = nil
            guard self.captureControlsCollapsed, !self.captureSelectionInProgress,
                  !self.hoverState.suppressed,
                  self.windowHost?.containsHover(NSEvent.mouseLocation) == true else { return }
            self.expandCaptureControls()
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// The capture-controls window covers the top center of the screen, over
    /// the selection surface. Only its visible controls should catch the
    /// mouse; everywhere else the click falls through to the selection beneath,
    /// so a region under the notch can still be dragged or a window clicked.
    private func updateCaptureControlsClickThrough() {
        guard let panel, captureControls != nil else { return }
        let point = NSEvent.mouseLocation
        // A collapsing animation still reserves the old window frame. Only
        // the compact target should own clicks while that space is released.
        let overControls = !captureSelectionInProgress && windowHost?.contains(point) == true
            && (!captureControlsCollapsed || windowHost?.containsHover(point) == true)
        if panel.ignoresMouseEvents != !overControls { panel.ignoresMouseEvents = !overControls }
        // While the panel catches the mouse it is the window under the pointer
        // across its whole frame, transparent parts included, so it must be the
        // one reporting the move that leaves the controls; otherwise the next
        // click there would be swallowed. Away from the controls the selection
        // surface reports every move itself, and the panel stays quiet.
        if panel.acceptsMouseMovedEvents != overControls { panel.acceptsMouseMovedEvents = overControls }
        hover(overControls)
    }

    private func installCaptureControlsClickThrough() {
        guard captureControlsMonitors.isEmpty else { return }
        // The selection surface below is this app's own window and already
        // tracks the pointer, so a local monitor sees every move that could
        // reach a control. A global monitor would add a second, system-wide
        // stream of every move at the mouse's full rate, and asking the key
        // panel for moved events on top of that starved the selector: with
        // both installed it received fewer events and trailed the pointer.
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged,
                                            .rightMouseDragged, .otherMouseDragged]
        if let token = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            self?.updateCaptureControlsClickThrough(); return event
        }) { captureControlsMonitors.append(token) }
        updateCaptureControlsClickThrough()
    }

    private func removeCaptureControlsClickThrough() {
        captureControlsMonitors.forEach(NSEvent.removeMonitor)
        captureControlsMonitors.removeAll()
        panel?.ignoresMouseEvents = false
        panel?.acceptsMouseMovedEvents = false
    }

    func endCaptureControls() {
        guard captureControls != nil else { return }
        captureControlsWork?.cancel(); captureControlsWork = nil
        hoverWork?.cancel(); hoverWork = nil
        captureControls?.onSelectionProgressChange = nil
        geometry.compactSideRoom = nil
        captureControls = nil
        captureControlsCollapsed = false
        captureSelectionInProgress = false
        captureControlsSubscription = nil
        captureControlsCancel = nil
        removeCaptureControlsClickThrough()
        panel?.level = NotchPanel.normalLevel
        panel?.acceptsKeyFocus = false
        panel?.resignKey()
        refreshPresentation()
        syncVisibleConsumers()
    }

    func cancelCaptureControls() { captureControlsCancel?() }

    func openSettings() {
        collapse()
        SettingsRouter.shared.request(FeatureSettingsDestination(.notch))
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }

    func perform(_ action: @escaping () -> Void) {
        collapse()
        if let windowHost { windowHost.whenSettled(action) }
        else { DispatchQueue.main.async(execute: action) }
    }

    var canAcceptFileDrop: Bool {
        acceptsSystemFeedback && captureControls == nil && modules.contains(.files)
            && AppFeature.shelf.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled)
    }

    func beginFileDrop(_ pasteboard: NSPasteboard) {
        guard canAcceptFileDrop else { return }
        choosingFileDropDestination = NotchFileToolsService.shared.mediaDropContent(for: pasteboard) != nil
        targetsMediaDrop = false
        open(.files, takeFocus: false)
    }

    @discardableResult
    func updateFileDrop(at point: CGPoint) -> Bool {
        let targeted = choosingFileDropDestination
            && NotchFileToolsSupport.mediaDropArea(in: geometry, size: surfaceSize).contains(point)
        if targetsMediaDrop != targeted { targetsMediaDrop = targeted }
        return !targeted || NotchFileToolsService.shared.canAcceptMediaDrop
    }

    func endFileDrop() {
        let changed = choosingFileDropDestination
        if changed { choosingFileDropDestination = false }
        if targetsMediaDrop { targetsMediaDrop = false }
        if changed, acceptsSystemFeedback { refreshPresentation() }
    }

    func keepFileInteractionOpen(_ active: Bool) {
        fileInteractionActive = active
        hover(false)
    }

    func accept(_ pasteboard: NSPasteboard) -> Bool {
        defer { endFileDrop() }
        guard canAcceptFileDrop else { return false }
        let optimize = choosingFileDropDestination && targetsMediaDrop
        let accepted = optimize
            ? NotchFileToolsService.shared.openMediaDrop(pasteboard)
            : ShelfService.shared.acceptDrop(pasteboard: pasteboard)
        if accepted {
            heldDrag = false
            dragPlaceholder = false
            if !optimize { NotchFileToolsService.shared.hideMedia() }
            open(.files)
        }
        return accepted
    }

    @discardableResult
    func show(_ incoming: NotchNotice) -> Bool {
        guard showsSystemFeedback, NotchSupport.routes(incoming.event),
              NotchSupport.shouldReplace(notice?.event, with: incoming.event, held: noticeExpanded) else { return false }
        noticeWork?.cancel(); noticeWork = nil
        let keepsPreview = noticeExpanded && incoming.notificationID != nil
            && windowHost?.containsHover(NSEvent.mouseLocation) == true
        // Slider and key bursts only replace the displayed value. They never
        // restart a window resize or enqueue another layout animation.
        let transition: NotchContentTransition = !noticeCanPresent ? .none
            : notice == nil ? .reveal : notice?.event != incoming.event || noticeExpanded ? .replace : .none
        mutatePresentation(transitionContent: transition) {
            notice = incoming
            noticeExpanded = keepsPreview
        }
        // A banner arriving under the pointer is held at once, whether the
        // pointer was already inside or an opening was pending.
        if let id = incoming.notificationID, holdsNotification, windowHost?.containsHover(NSEvent.mouseLocation) == true {
            hoverWork?.cancel(); hoverWork = nil
            inside = true
            holdNotification(id)
        } else {
            scheduleNoticeDismissal(after: incoming.event.duration)
        }
        return true
    }

    func activateNotice(_ selectedNotice: NotchNotice) {
        guard notice == selectedNotice else { return }
        if let id = selectedNotice.notificationID {
            guard NotchNotificationService.shared.openingID == nil else { return }
            // The pointer stays where the banner was; like a click on the
            // island itself, this must not turn into a hover opening.
            settleNotificationHover()
            NotchNotificationService.shared.open(id) { [weak self] result in
                guard let self else { return }
                if self.notice?.notificationID == id { self.dismissNotice() }
                if result == .unavailable || result == .uncertain { self.open(.notifications) }
            }
            return
        }
        open(selectedNotice.event == .download ? .downloads : selectedNotice.event == .timer ? .timer
             : selectedNotice.event == .accessory ? .system : selectedNotice.event == .systemNotification ? .notifications
             : selectedNotice.event == .clipboard ? .clipboard : .controls)
    }

    func showBrightness(_ level: Double) -> Bool {
        let text = FeatureStrings.notch(L10n.shared.language)
        return show(NotchNotice(event: .brightness, title: text.brightness,
                                detail: "\(BrightnessSupport.wholePercent(level))%",
                                symbol: "sun.max.fill", level: level))
    }

    @discardableResult
    func showKeyboardLight(_ level: Double) -> Bool {
        guard level.isFinite, (0...1).contains(level) else { return false }
        return show(NotchNotice(event: .keyboardLight,
                                title: FeatureStrings.brightness(L10n.shared.language).keyboardLight,
                                detail: "\(BrightnessSupport.wholePercent(level))%",
                                symbol: "keyboard", level: level))
    }

    /// The close button of a held preview also takes the message out of the
    /// inbox, like the close button of the inbox row.
    func dismissNotification(_ selectedNotice: NotchNotice) {
        guard notice == selectedNotice, let id = selectedNotice.notificationID else { return }
        settleNotificationHover()
        NotchNotificationService.shared.dismiss(id)
        dismissNotice()
    }

    private func settleNotificationHover() {
        hoverWork?.cancel(); hoverWork = nil
        hoverState.close(pointerInside: windowHost?.containsHover(NSEvent.mouseLocation) == true)
    }

    private func dismissNotice() {
        noticeWork?.cancel(); noticeWork = nil
        let transition: NotchContentTransition = notice != nil && noticeCanPresent ? .dismiss : .none
        mutatePresentation(transitionContent: transition) { notice = nil; noticeExpanded = false }
    }

    private var noticeCanPresent: Bool {
        !expanded && !dragPlaceholder && captureControls == nil
    }

    func presentCapture(id: UUID, content: AnyView, height: CGFloat, fallback: @escaping () -> Void,
                        close: @escaping () -> Void, hover: @escaping (Bool) -> Void) -> Bool {
        guard acceptsSystemFeedback, NotchSupport.routes(.capture) else { return false }
        let keepOpen = expanded && pinned
        captureID = id
        captureContentHeight = height
        captureContent = content
        captureFallback = fallback
        captureClose = close
        captureHover = hover
        open(.captures, pinned: keepOpen,
             takeFocus: UserDefaults.standard.bool(forKey: DefaultsKey.screenshotPreviewTakesFocus), feedback: false)
        captureHover?(inside)
        return true
    }

    func updateCaptureHeight(id: UUID, height: CGFloat) {
        guard captureID == id, captureContent != nil, height.isFinite, height > 0,
              captureContentHeight != height else { return }
        captureContentHeight = height
        refreshPresentation()
    }

    func isCaptureVisible(id: UUID) -> Bool {
        acceptsSystemFeedback && expanded && selected == .captures
            && !showingAppPanel && !showingSections && selectedMetric == nil
            && captureControls == nil && captureID == id && captureContent != nil
    }

    func removeCapture(id: UUID) {
        guard captureID == id else { return }
        clearCapture()
        if expanded, selected == .captures, !showingSections {
            if pinned { refreshPresentation() }
            else { collapse() }
        }
    }

    private func clearCapture() {
        captureID = nil
        captureContent = nil
        captureContentHeight = nil
        captureFallback = nil
        captureClose = nil
        captureHover = nil
    }

    private func mutatePresentation(transitionContent: NotchContentTransition = .none, _ change: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
        refreshPresentation(transitionContent: transitionContent)
    }

    func refreshPresentation(animated: Bool = true, transitionContent: NotchContentTransition = .none) {
        if hiddenInFullscreen {
            windowHost?.hide(animated: false)
            removeHiddenHoverMonitors()
            removeScreenEdgeClickMonitors()
            return
        }
        syncHiddenHoverMonitoring()
        if hiddenUntilHover || (captureControls != nil && captureSelectionInProgress) {
            if hiddenUntilHover { windowHost?.hide(animated: animated) }
            else { panel?.orderOut(nil) }
            removeScreenEdgeClickMonitors()
            return
        }
        let open = expanded || peeking || notice != nil || dragPlaceholder || captureControls != nil
        guard open || geometry.isNotched || geometry.compactSideRoom != nil else {
            panel?.orderOut(nil)
            removeScreenEdgeClickMonitors()
            return
        }
        let access = NotchQuickAccessConfiguration.current()
        let size = surfaceSize
        // Preferences can change computed dimensions without publishing a
        // service property. Update SwiftUI's layout along with the native host.
        if let windowHost, windowHost.targetSize != size { objectWillChange.send() }
        windowHost?.present(size: size, geometry: geometry, animated: animated,
                            transitionContent: transitionContent,
                            quickAccess: expanded && captureControls == nil && !access.buttons.isEmpty ? access : nil,
                            revealFromHidden: captureControls == nil
                                && UserDefaults.standard.bool(forKey: DefaultsKey.notchHideUntilHover)
                                && UserDefaults.standard.bool(forKey: DefaultsKey.notchOpenOnHover))
        let activationRect: CGRect
        if captureControls != nil {
            activationRect = captureControlsCollapsed ? CGRect(origin: .zero, size: size) : .zero
        } else if notice != nil || dragPlaceholder {
            activationRect = .zero
        } else {
            activationRect = (compactActivityIsVisible ? compactActivityGeometry : geometry)
                .activationArea(in: size, hasHeader: expanded || peeking, compactActivity: compactActivityIsVisible)
        }
        let text = FeatureStrings.notch(L10n.shared.language)
        windowHost?.setActivationArea(activationRect, title: expanded ? text.collapse : text.open,
            willPress: { [weak self] in
                self?.hoverWork?.cancel()
                self?.hoverState.close(pointerInside: true)
            }, activate: { [weak self] in
                guard let self else { return }
                if self.captureControls != nil { self.expandCaptureControls() }
                else { self.toggle() }
            })
        if panel?.isVisible != true { panel?.orderFrontRegardless() }
        syncScreenEdgeClicks()
    }

    private func syncHiddenHoverMonitoring() {
        guard running, !suspended, hiddenUntilHover, windowHost != nil else {
            removeHiddenHoverMonitors()
            return
        }
        guard hiddenHoverMonitors.isEmpty else { return }
        // The window is ordered out, so native tracking areas cannot see entry.
        // Observe movement without intercepting the menu bar or polling at rest.
        if let token = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            self?.hover(true)
        }) { hiddenHoverMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            self?.hover(true)
            return event
        }) { hiddenHoverMonitors.append(token) }
    }

    private func removeHiddenHoverMonitors() {
        hiddenHoverMonitors.forEach(NSEvent.removeMonitor)
        hiddenHoverMonitors.removeAll()
    }

    private var screenEdgeClickArea: CGRect? {
        guard running, !suspended, !expanded, captureControls == nil, notice == nil,
              !dragPlaceholder, !heldDrag, let panel, panel.isVisible, !panel.ignoresMouseEvents else { return nil }
        let geometry = compactActivityIsVisible ? compactActivityGeometry : self.geometry
        let area = geometry.activationArea(in: surfaceSize, hasHeader: peeking, compactActivity: compactActivityIsVisible)
        guard !area.isEmpty else { return nil }
        let frame = geometry.frame(for: surfaceSize)
        return CGRect(x: frame.minX + area.minX, y: frame.maxY - area.maxY, width: area.width, height: area.height)
    }

    private func syncScreenEdgeClicks() {
        guard screenEdgeClickArea != nil else { removeScreenEdgeClickMonitors(); return }
        guard screenEdgeClickMonitors.isEmpty else { return }
        // The menu bar owns the first screen row even above its window level.
        // Observe only mouse clicks, with no event tap or Accessibility requirement.
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handleScreenEdgeEvent(event)
        }) { screenEdgeClickMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handleScreenEdgeEvent(event)
            return event
        }) { screenEdgeClickMonitors.append(token) }
    }

    private func handleScreenEdgeEvent(_ event: NSEvent) {
        guard event.type == .leftMouseDown || screenEdgePressArea != nil else { return }
        guard let location = event.cgEvent?.location, let primary = NSScreen.withMenuBar else {
            screenEdgePressArea = nil
            return
        }
        handleScreenEdgeClick(event.type, at: CGPoint(x: location.x, y: primary.frame.maxY - location.y),
                              isNotchWindow: event.window === panel)
    }

    private func handleScreenEdgeClick(_ type: NSEvent.EventType, at point: CGPoint, isNotchWindow: Bool) {
        guard let area = screenEdgeClickArea else { screenEdgePressArea = nil; return }
        let local = CGPoint(x: point.x - area.minX, y: area.maxY - point.y)
        switch type {
        case .leftMouseDown:
            screenEdgePressArea = nil
            guard !isNotchWindow, !keepsWorkingSurface,
                  CGRect(x: 0, y: 0, width: area.width, height: 1).contains(local),
                  windowHost?.contains(point) == true else { return }
            screenEdgePressArea = area
            hoverWork?.cancel(); hoverWork = nil
            hoverState.close(pointerInside: true)
        case .leftMouseUp:
            let pressedArea = screenEdgePressArea
            screenEdgePressArea = nil
            guard pressedArea == area, CGRect(origin: .zero, size: area.size).contains(local),
                  windowHost?.contains(point) == true else { return }
            open()
        case .leftMouseDragged:
            screenEdgePressArea = nil
        default:
            break
        }
    }

    private func removeScreenEdgeClickMonitors() {
        screenEdgeClickMonitors.forEach(NSEvent.removeMonitor)
        screenEdgeClickMonitors.removeAll()
        screenEdgePressArea = nil
    }

    private func stopMenuSpaceMonitoring() {
        menuSpaceTimer?.invalidate()
        menuSpaceTimer = nil
        menuSpaceGeneration += 1
    }

    private func syncMenuSpaceMonitoring() {
        guard !hiddenInFullscreen else { stopMenuSpaceMonitoring(); return }
        if running, !suspended, NotchSupport.coversMenus() {
            // Nothing to measure: the island keeps the room an empty bar
            // would leave it, over whatever menus and status items are there.
            stopMenuSpaceMonitoring()
            applyMenuSpace(NotchMenuBarLayout.sideRoom(screen: geometry.screen, cameraWidth: geometry.cameraWidth,
                                                       barHeight: geometry.menuBarHeight, occupied: []))
            return
        }
        guard AXIsProcessTrusted() else {
            stopMenuSpaceMonitoring()
            if geometry.compactSideRoom != nil {
                geometry.compactSideRoom = nil
                refreshPresentation(animated: false)
            }
            return
        }
        let wanted = running && !suspended && !hiddenUntilHover && !expanded && captureControls == nil
            && (idleContent != .none || compactActivity != nil || !geometry.isNotched)
        guard wanted else { stopMenuSpaceMonitoring(); return }
        guard menuSpaceTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.readMenuSpace() }
        timer.tolerance = 0.2
        menuSpaceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        readMenuSpace()
    }

    private func invalidateMenuSpace() {
        menuSpaceGeneration += 1
        // Keep the last measured layout until its replacement arrives, so a
        // switch does not blink; the read that follows withdraws the cutout
        // once the new menu bar reaches the camera.
        readMenuSpace()
    }

    private func screenParametersDidChange() {
        guard running, !suspended else { return }
        screenRefreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.screenRefreshWork = nil
            guard self.running, !self.suspended else { return }
            self.invalidateMenuSpace()
            self.syncWithPreferences()
        }
        screenRefreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func readMenuSpace() {
        // The displayed menus belong to the menu bar's owner, which is not the
        // frontmost application while an accessory app such as a launcher has
        // focus; that app's own menu geometry was never laid out.
        guard menuSpaceTimer != nil, !menuSpaceReading,
              let app = NSWorkspace.shared.menuBarOwningApplication else { return }
        menuSpaceReading = true
        let generation = menuSpaceGeneration
        let geometry = geometry
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? geometry.screen.maxY
        let window = panel?.windowNumber ?? -1
        let pid = app.processIdentifier
        menuSpaceQueue.async { [weak self] in
            let room = NotchMenuBarSpace.measure(pid: pid, geometry: geometry,
                                                primaryTop: primaryTop, ownWindow: window)
            DispatchQueue.main.async {
                guard let self else { return }
                self.menuSpaceReading = false
                guard self.menuSpaceTimer != nil else { return }
                guard self.menuSpaceGeneration == generation,
                      NSWorkspace.shared.menuBarOwningApplication?.processIdentifier == pid else {
                    self.readMenuSpace(); return
                }
                self.applyMenuSpace(room)
            }
        }
    }

    private func applyMenuSpace(_ room: CGFloat?) {
        guard geometry.compactSideRoom != room else { return }
        let previousSize = surfaceSize
        let grows = (room ?? 0) > (geometry.compactSideRoom ?? 0)
        geometry.compactSideRoom = room
        // Losing a safe center must also hide an unchanged bare cutout.
        if previousSize != surfaceSize || panel?.isVisible != true || room == nil {
            refreshPresentation(animated: grows)
        }
    }

    private func updateScreen() {
        let screens = NSScreen.screens
        menuBarMeasurements.retainDisplays(screens.map(\.notchDisplayID))
        let builtIn = screens.map { CGDisplayIsBuiltin($0.notchDisplayID) != 0 }
        let index = NotchSupport.screenIndex(
            preference: NotchDisplay(rawValue: UserDefaults.standard.string(
                forKey: DefaultsKey.notchDisplay) ?? "") ?? .automatic,
            builtIn: builtIn, notched: screens.map { $0.safeAreaInsets.top > 0 },
            main: screens.firstIndex(where: { $0 === NSScreen.withMenuBar }) ?? 0)
        guard let index else { tearDownPresentation(); return }
        let screen = screens[index]
        let cameraWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            cameraWidth = max(0, right.minX - left.maxX)
        } else { cameraWidth = 0 }
        var next = NotchGeometry(screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
                                 cameraWidth: cameraWidth,
                                 layout: NotchSize(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.notchSize) ?? "") ?? .compact,
                                 menuBarHeight: menuBarMeasurements.height(
                                    displayID: screen.notchDisplayID, frame: screen.frame,
                                    visibleTop: screen.visibleFrame.maxY, scale: screen.backingScaleFactor,
                                    statusBarThickness: NSStatusBar.system.thickness),
                                 customWidth: UserDefaults.standard.double(forKey: DefaultsKey.notchCustomWidth),
                                 customHeight: UserDefaults.standard.double(forKey: DefaultsKey.notchCustomHeight))
        if next.hasSameMenuBar(as: geometry) { next.compactSideRoom = geometry.compactSideRoom }
        next.quickAccessBottomInset = NotchQuickAccessConfiguration.current().hasBottom ? NotchQuickAccessLayout.gutter : 0
        if next != geometry { menuSpaceGeneration += 1; geometry = next }
        if windowHost == nil {
            windowHost = NotchWindowHost(content: AnyView(NotchView(service: self)), geometry: geometry, size: surfaceSize,
                                        quickAccess: { AnyView(NotchQuickAccessView(service: self, motion: $0)) })
            windowHost?.setHoverHandler { [weak self] in self?.hover($0) }
            panel?.title = FeatureStrings.notch(L10n.shared.language).title
        }
        if modules.contains(.files), AppFeature.shelf.isAvailable {
            windowHost?.setFileDropActions(NotchFileDropActions(
                canAccept: { [weak self] pasteboard in
                    self?.canAcceptFileDrop == true && !ShelfService.shared.isInternalDragActive
                        && ShelfService.shared.canAcceptPasteboard(pasteboard)
                },
                enter: { [weak self] in self?.beginFileDrop($0) },
                accept: { [weak self] in self?.accept($0) == true },
                exit: { [weak self] in
                    guard let self else { return }
                    self.endFileDrop()
                    self.hover(self.windowHost?.contains(NSEvent.mouseLocation) == true)
                },
                update: { [weak self] in self?.updateFileDrop(at: $0) == true }))
        } else { windowHost?.setFileDropActions(nil) }
        panel?.sharingType = NotchSupport.showsInCaptures() ? .readOnly : .none
        updateFullscreenVisibility(displayID: screen.notchDisplayID)
    }

    private func updateFullscreenVisibility(displayID: CGDirectDisplayID) {
        let hidden = UserDefaults.standard.bool(forKey: DefaultsKey.notchHideInFullscreen)
            && SpaceWindowBridge.topology()?.isFullscreen(on: displayID, separateSpaces: NSScreen.screensHaveSeparateSpaces) == true
        guard hidden != hiddenInFullscreen else { return }
        hiddenInFullscreen = hidden
        if hidden {
            hoverWork?.cancel(); hoverWork = nil
            heldDrag = false
            dragPlaceholder = false
            cancelCaptureControls()
            noticeWork?.cancel(); noticeWork = nil
            notice = nil
            noticeExpanded = false
            collapse()
        }
    }

    private func fullscreenEnvironmentDidChange() {
        guard running, !suspended else { return }
        updateScreen()
        syncVisibleConsumers()
        refreshPresentation(animated: false)
    }

    private func installObservers() {
        observe(.default, NSMenu.didBeginTrackingNotification) { [weak self] in self?.trackingMenu = true; self?.hoverWork?.cancel() }
        observe(.default, NSMenu.didEndTrackingNotification) { [weak self] in
            guard let self else { return }
            self.trackingMenu = false
            self.hover(self.windowHost?.contains(NSEvent.mouseLocation) == true)
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.screenParametersDidChange()
        }
        observe(.default, UserDefaults.didChangeNotification) { [weak self] in
            // AppStorage can notify during a view update; defer any window work.
            DispatchQueue.main.async { self?.syncWithPreferences() }
        }
        observe(.default, .menuPanelWillShow) { [weak self] in self?.collapse() }
        session.onConsole = SessionActivity.shared.isActive
        session.locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            self?.fullscreenEnvironmentDidChange()
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] in self?.applicationDidActivate() }
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] in
            self?.updateSession { $0.sleeping = true }
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            self?.updateSession { $0.sleeping = false }
        }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.updateSession { $0.displaysSleeping = true }
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.updateSession { $0.displaysSleeping = false }
        }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { [weak self] in
            self?.updateSession { $0.onConsole = false }
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.updateSession { $0.onConsole = true }
        }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.updateSession { $0.locked = true }
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.updateSession { $0.locked = false }
        }
    }

    private func applicationDidActivate() {
        guard !suspended else { return }
        fullscreenEnvironmentDidChange()
        invalidateMenuSpace()
        let identifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard identifier != Bundle.main.bundleIdentifier, identifier != AssistiveKeyboard.bundleID else { return }
        panel?.resignKey()
        if expanded, modules.contains(.clipboard) { ClipboardHistoryService.shared.rememberPasteTarget() }
        if expanded, !pinned, !keepsWorkingSurface, captureControls == nil { collapse() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }

    private func updateSession(_ change: (inout NotchSessionState) -> Void) {
        guard running else { return }
        let couldPresent = session.canPresent
        let timerCouldRun = session.canRunTimer
        change(&session)
        if couldPresent != session.canPresent {
            if session.canPresent {
                syncWithPreferences()
            } else {
                let cancel = captureControlsCancel
                endCaptureControls()
                cancel?()
                captureClose?()
                clearCapture()
                tearDownPresentation()
                if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }
            }
        }
        // A dark display does not stop an alarm while the same user and Mac
        // remain awake. Privacy changes still apply when presentation is
        // already suspended by the display.
        guard timerCouldRun != session.canRunTimer, !session.canPresent else { return }
        if session.canRunTimer { NotchTimerService.shared.syncWithPreferences() }
        else { NotchTimerService.shared.suspend() }
    }

    private func installEventMonitors() {
        guard eventMonitors.isEmpty else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let token = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            guard let self, !self.keepsWorkingSurface,
                  (NSApp.delegate as? AppDelegate)?.isOverStatusItem(NSEvent.mouseLocation) != true,
                  !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) else { return }
            self.collapse()
        }) { eventMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown), handler: { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.window === self.panel, self.captureControls == nil {
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "k" {
                    self.toggleSections()
                    return nil
                }
                if modifiers == [.command, .option],
                   let module = NotchSupport.moduleShortcut(event.charactersIgnoringModifiers ?? "", modules: self.modules) {
                    self.select(module)
                    return nil
                }
                if event.keyCode == 48, modifiers == .control || modifiers == [.control, .shift],
                   let module = NotchSupport.adjacentModule(to: self.selected, modules: self.modules,
                                                           backwards: modifiers.contains(.shift)) {
                    self.select(module)
                    return nil
                }
                if event.keyCode == 53, self.showingSections {
                    self.toggleSections()
                    return nil
                }
                if self.handleSectionKey(event) { return nil }
                if self.handleScratchpadKey(event) { return nil }
            }
            if event.type == .keyDown, event.window === self.panel, self.selected == .tools, !self.showingAppPanel, !self.showingSections {
                let launcher = QuickLauncherService.shared
                // The rail fills columns; the editing grid keeps its rows.
                let flow: QuickToolsSupport.GridFlow = launcher.isEditing
                    ? .rows(columns: NotchSupport.toolColumns)
                    : .columns(rows: self.geometry.toolRows(count: launcher.visibleItems.count))
                return launcher.handlePanelKey(event, flow: flow)
            }
            if event.type == .keyDown, event.window === self.panel, event.keyCode == 53 {
                // A level being typed in the mixer cancels on Escape by
                // itself; the island collapses on the next one.
                if let editor = self.panel?.firstResponder as? NSTextView, editor.isFieldEditor,
                   (editor.delegate as AnyObject?) is MixerPercentNativeTextField { return event }
                self.collapse()
                return nil
            }
            if clicks.contains(NSEvent.EventTypeMask(rawValue: 1 << event.type.rawValue)),
               event.window !== self.panel, !self.keepsWorkingSurface,
               (NSApp.delegate as? AppDelegate)?.isOverStatusItem(NSEvent.mouseLocation) != true,
               !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) { self.collapse() }
            return event
        }) { eventMonitors.append(token) }
    }

    private func syncGestures() {
        guard NotchGestureSupport.isEnabled() else {
            panel?.handleScroll = nil
            gesture = NotchGestureSupport()
            return
        }
        panel?.handleScroll = { [weak self] event in self?.handleGesture(event) ?? false }
    }

    private func handleGesture(_ event: NSEvent) -> Bool {
        guard running, !suspended, NotchGestureSupport.isEnabled(), let panel,
              !trackingMenu, captureControls == nil, !heldDrag,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            gesture = NotchGestureSupport()
            return false
        }
        let screenPoint = panel.convertPoint(toScreen: event.locationInWindow)
        guard windowHost?.contains(screenPoint) == true else { gesture = NotchGestureSupport(); return false }
        let fromTop = panel.frame.maxY - screenPoint.y
        let inHeader = NotchSupport.gestureIsOverHeader(expanded: expanded, peeking: peeking,
                                                       fromTop: fromTop, safeTop: geometry.safeContentTop)
        let interaction = NotchGestureSupport.nativeInteraction(at: panel.contentView?.hitTest(event.locationInWindow))
        let musicSurface = modules.contains(.music)
            && (compactMusicIsVisible || (expanded && selected == .music && !showingAppPanel && !showingSections))
        let vertical = !interaction.control && (!expanded || inHeader)
        let horizontal = !interaction.control && !interaction.scroll && !inHeader && musicSurface
        let x = NotchGestureSupport.movement(Double(event.scrollingDeltaX), precise: event.hasPreciseScrollingDeltas,
                                             inverted: event.isDirectionInvertedFromDevice)
        let y = NotchGestureSupport.movement(Double(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas,
                                             inverted: event.isDirectionInvertedFromDevice)
        guard let action = gesture.handle(x: x, y: y, timestamp: event.timestamp,
                                          began: event.phase.contains(.began),
                                          ended: !event.phase.intersection([.ended, .cancelled]).isEmpty,
                                          momentum: !event.momentumPhase.isEmpty,
                                          precise: event.hasPreciseScrollingDeltas,
                                          hasPhase: !event.phase.isEmpty,
                                          allowVertical: vertical, allowHorizontal: horizontal, expanded: expanded) else { return false }
        switch action {
        case .open: open()
        case .close: collapse()
        case .nextTrack, .previousTrack:
            guard musicSurface else { gesture = NotchGestureSupport(); return false }
            NotchMusicService.shared.send(action == .nextTrack ? .next : .previous)
        }
        return true
    }

    private func removeEventMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    func showUpdate() {
        guard running, !suspended, expanded, case .available = UpdateService.shared.state else { return }
        collapse()
        appDelegate()?.showUpdatePreview()
    }

    private func bindEvents() {
        subscriptions.removeAll()
        if modules.contains(.timer) {
            NotchTimerService.shared.$session.removeDuplicates().receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.music) {
            NotchMusicService.shared.$playback.map { ($0 != nil, $0?.isPlaying == true) }
                .removeDuplicates { $0 == $1 }.receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.syncMenuSpaceMonitoring()
                    self?.objectWillChange.send()
                    self?.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.tools) {
            // The tools page is a rail sized by its tiles; editing or a
            // hosted utility turns it into a page.
            let launcher = QuickLauncherService.shared
            launcher.$isEditing.map { _ in () }
                .merge(with: launcher.$activeUtility.map { _ in () }, launcher.$hiddenItemsRaw.map { _ in () })
                .dropFirst(3).receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    guard let self, self.expanded, self.selected == .tools, !self.showingAppPanel, !self.showingSections else { return }
                    self.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if modules.contains(.system), AppFeature.fanControl.isAvailable {
            // The fan card only exists once the page's first sample lands; the
            // strip that was sized without it reserves its row again.
            SystemMonitor.shared.$snapshot.map { $0.fanSpeeds.isEmpty }.removeDuplicates().dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self, self.expanded, self.selected == .system, self.selectedMetric == nil,
                          !self.showingAppPanel, !self.showingSections else { return }
                    self.refreshPresentation()
                }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.download) {
            NotchDownloadService.shared.$items.receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.syncMenuSpaceMonitoring()
                self?.objectWillChange.send()
                self?.refreshPresentation()
            }.store(in: &subscriptions)
            NotchDownloadService.shared.onArrival = { [weak self] item in
                self?.show(NotchNotice(event: .download,
                    title: FeatureStrings.notchFiles(L10n.shared.language).completed,
                    detail: item.name, symbol: "arrow.down.circle.fill"))
            }
        }
        stopPower()
        if NotchSupport.routes(.volume) {
            bindVolumeEvents()
        }
        if NotchSupport.routes(.systemNotification) {
            NotchNotificationService.shared.received.sink { [weak self] item in
                guard let self else { return }
                let shown = self.show(NotchNotice(event: .systemNotification, title: item.content.title,
                                                 detail: item.content.body, symbol: "bell.fill", notification: item.content, notificationID: item.id))
                if shown, !self.expanded, self.captureControls == nil, !self.dragPlaceholder {
                    NotchNotificationService.shared.closeNative(item.id)
                }
            }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.clipboard) {
            let history = ClipboardHistoryService.shared
            history.capturedEntry.receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                let text = FeatureStrings.clipboard(L10n.shared.language)
                self.show(NotchNotice(event: .clipboard, title: text.copied,
                                      detail: text.title, symbol: "doc.on.clipboard"))
            }.store(in: &subscriptions)
        }
        if NotchSupport.routes(.battery) || idleContent == .battery { startPower() }
    }

    func showCurrentVolume() {
        let mixer = AppVolumeMixer.shared
        guard let volume = mixer.systemOutputVolume else { return }
        showVolume(volume, muted: mixer.systemOutputMuted)
    }

    private func bindVolumeEvents() {
        let mixer = AppVolumeMixer.shared
        volumeDeviceUID = mixer.currentOutputDeviceUID
        volumeBaseline = mixer.systemOutputVolume
        muteBaseline = mixer.systemOutputMuted
        mixer.$systemOutputVolume.combineLatest(mixer.$systemOutputMuted, mixer.$currentOutputDeviceUID)
            .handleEvents(receiveOutput: { [weak self] _, _, deviceUID in
                guard let self, deviceUID != self.volumeDeviceUID else { return }
                self.volumeDeviceUID = deviceUID
                self.volumeBaseline = nil
                self.muteBaseline = nil
            })
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak mixer] _ in
                guard let mixer else { return }
                // Published fields arrive separately and before assignment. Read
                // the settled device and controls together on the main queue.
                self?.volumeChanged(mixer.systemOutputVolume, muted: mixer.systemOutputMuted)
            }
            .store(in: &subscriptions)
    }

    private func volumeChanged(_ volume: Double?, muted: Bool?) {
        defer { volumeBaseline = volume; muteBaseline = muted }
        guard volumeDeviceUID != nil, let volume, volumeBaseline != nil,
              volume != volumeBaseline || (muteBaseline != nil && muted != muteBaseline) else { return }
        showVolume(volume, muted: muted)
    }

    private func showVolume(_ volume: Double, muted: Bool?) {
        // The open panel already shows the adjustment. Do not retain a notice
        // behind it that would appear only after the pointer leaves.
        guard volume.isFinite, !expanded else { return }
        let value = muted == true ? 0 : min(1, max(0, volume))
        show(NotchNotice(event: .volume, title: FeatureStrings.notch(L10n.shared.language).volume,
                         detail: "\(Int((value * 100).rounded()))%",
                         symbol: value == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", level: value))
    }

    private func startPower() {
        guard PowerSampler.hasInternalBattery else { return }
        powerSampler = PowerSampler(smc: nil)
        power = powerSampler?.sample() ?? PowerReading()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let owner = Unmanaged<NotchService>.fromOpaque(context).takeUnretainedValue()
            owner.powerChanged()
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }

    private func stopPower() {
        if let source = powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        powerSource = nil
        powerSampler = nil
    }

    private func powerChanged() {
        guard running, !suspended, let sampler = powerSampler else { return }
        let before = power
        let next = sampler.sample()
        power = next
        let low = (next.chargePercent ?? 100) <= 20 && (before.chargePercent ?? 0) > 20
        guard before.externalConnected != next.externalConnected || low
                || (before.isCharging && !next.isCharging && next.chargePercent == 100) else { return }
        let text = FeatureStrings.notch(L10n.shared.language)
        let title = low ? text.lowBattery : next.externalConnected
            ? (next.isCharging ? text.charging : next.chargePercent == 100
                ? text.charged : L10n.shared.s.powerPluggedIn) : text.onBattery
        show(NotchNotice(event: .battery, title: title,
                         detail: next.chargePercent.map { "\($0)%" } ?? "",
                         symbol: next.externalConnected ? "battery.100percent.bolt" : "battery.25percent"))
    }

    private func syncVisibleConsumers() {
        syncMenuSpaceMonitoring()
        guard running, !suspended else { releaseMonitor(); return }
        if hiddenInFullscreen {
            CameraPreviewService.shared.hideEmbedded()
            NotchMusicService.shared.stop()
            releaseMonitor()
            return
        }
        if !NotchCameraSupport.canPresent(expanded: expanded && !showingSections, selected: selected,
            appPanel: showingAppPanel, captureControls: captureControls != nil) {
            CameraPreviewService.shared.hideEmbedded()
        }
        let musicWanted = modules.contains(.music) && ((expanded && (selected == .music || (selected == .controls && NotchSupport.controls().contains(.music)))
            && !showingAppPanel && !showingSections)
            || (!hiddenUntilHover && NotchSupport.watchesMusicActivity()))
        if musicWanted { NotchMusicService.shared.start() } else { NotchMusicService.shared.stop() }
        let needs = expanded && selected == .system && selectedMetric == nil && modules.contains(.system) && !showingAppPanel && !showingSections
        var detailNeeds = expanded && !showingSections ? selectedMetric?.monitorNeeds ?? .none : .none
        if needs, AppFeature.monitorDisk.isAvailable { detailNeeds.disk = true }
        if needs, AppFeature.fanControl.isAvailable { detailNeeds.fanSpeed = true }
        SystemMonitor.shared.setNotchDetailNeeds(detailNeeds)
        if needs != notchNeedsMonitor {
            notchNeedsMonitor = needs
            SystemMonitor.shared.setNotchVisible(needs)
        }
    }

    private func releaseMonitor() {
        SystemMonitor.shared.setNotchDetailNeeds(.none)
        guard notchNeedsMonitor else { return }
        notchNeedsMonitor = false
        SystemMonitor.shared.setNotchVisible(false)
    }
}

extension NSScreen {
    var notchDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
