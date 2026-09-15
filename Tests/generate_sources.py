#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Compile selected production methods against test doubles, without an app.

Bodies are read verbatim on every build, never copied into a maintained fixture.
The narrow declaration/indentation contract fails closed if a method moves or
changes shape; the Swift compiler then checks the generated source normally.
"""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build/generated-tests"


def declaration(path, prefix):
    lines = (ROOT / path).read_text().splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line.startswith(prefix)]
    if len(starts) != 1:
        raise ValueError(f"Expected one declaration {prefix!r} in {path}")
    start = starts[0]
    indent = prefix[:len(prefix) - len(prefix.lstrip())]
    end = next(i for i in range(start + 1, len(lines)) if lines[i].rstrip() == indent + "}")
    body = "".join(lines[start:end + 1])
    return f'#sourceLocation(file: {json.dumps(path)}, line: {start + 1})\n{body}\n#sourceLocation()\n'


def write(name, text):
    path = OUTPUT / name
    if not path.exists() or path.read_text() != text:
        path.write_text(text)


def availability_declaration(path, prefix):
    return declaration(path, prefix).replace(".feature.isAvailable", ".feature.isAvailable(in: ReviewDefaults.current)")


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    mixer = "Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift"
    write("MixerOutputAdjustment.swift", "import CoreAudio\nimport Foundation\n"
          + "extension MixerOutputAdjustmentContract {\nfinal class Mixer {\n"
          + declaration(mixer, "    private struct OutputAdjustment {")
          + "var systemOutputVolume: Double?\nvar systemOutputMuted: Bool?\n"
          + "var outputControlListenerDevice: AudioObjectID?\n"
          + "var outputControlListenerAddresses: [AudioObjectPropertyAddress] = []\n"
          + "var outputControlRefreshGeneration = 0\n"
          + "private var pendingOutputAdjustment: OutputAdjustment?\nprivate var outputWriteInFlight: OutputAdjustment?\n"
          + "let outputControlLock = NSLock()\nvar outputControlLifetime = UUID()\nlet halQueue = Queue()\n"
          + "var controlRefreshes: [AudioObjectID] = []\nvar listenerRefreshes = 0\n"
          + "static let outputControlListenerCallback: AudioObjectPropertyListenerProc = { _, _, _, _ in noErr }\n"
          + "var listenerClient: UnsafeMutableRawPointer? { nil }\n"
          + "static func defaultOutputDeviceID() -> AudioObjectID { Hardware.device }\n"
          + "static func setOutputVolume(_ value: Float, for device: AudioObjectID) -> Bool {\n"
          + "Hardware.writes.append(.init(device: device, volume: value, muted: nil))\n"
          + "let after = Hardware.afterVolumeWrite; Hardware.afterVolumeWrite = nil; after?()\nreturn Hardware.succeeds\n}\n"
          + "static func setOutputMuted(_ value: Bool, for device: AudioObjectID) -> Bool {\n"
          + "Hardware.writes.append(.init(device: device, volume: nil, muted: value)); return Hardware.succeeds\n}\n"
          + "func scheduleListenerRefresh() { listenerRefreshes += 1 }\n"
          + "func scheduleOutputControlRefresh(for device: AudioObjectID) { controlRefreshes.append(device) }\n"
          + "func selectOutput(_ device: AudioObjectID?, volume: Double?, muted: Bool?) {\n"
          + "removeOutputControlListeners(); outputControlListenerDevice = device; applyOutputControls(volume: volume, muted: muted)\n}\n"
          + "func readSnapshot(volume: Double?, muted: Bool?) { applyOutputControls(volume: volume, muted: muted) }\n"
          + "".join(declaration(mixer, prefix) for prefix in [
              "    func requestOutputAdjustment(", "    private func removeOutputControlListeners(",
              "    private func isCurrentOutputAdjustment(", "    private var hasCurrentOutputAdjustment:",
              "    private func applyOutputControls(", "    private func drainOutputAdjustment("])
          + "}\n}\n")
    cleaner = "Sources/Vorssaint/Services/Cleaner/JunkCleaner.swift"
    write("CleanerEligibilityBodies.swift", "import Foundation\nextension CleanerEligibilityTests {\n"
          + "".join(declaration(cleaner, "    private static func " + name)
                    .replace("private static func", "static func", 1)
                    for name in ["appendLeftovers(", "scanCaches(", "scanLogs(",
                                 "directorySize(", "fileSize(", "sorted("])
          + declaration(cleaner, "    private static func leftoverOwner(")
          + declaration(cleaner, "    private static func containerOwner(")
          + declaration(cleaner, "    private static func mayRemove(")
          + "static func owner(_ url: URL, metadata: Bool = false) -> String? {\n"
          + "leftoverOwner(entry: url.lastPathComponent, url: url, usesContainerMetadata: metadata)\n}\n"
          + "static func canRemove(_ item: Item, installed: Set<String> = []) -> Bool {\n"
          + "mayRemove(item, installed: installed)\n}\n}\n")

    updates = "Sources/Vorssaint/Services/AppUpdates/AppUpdatesService.swift"
    loader = "Sources/Vorssaint/Services/AppUpdates/AppUpdateFeedLoader.swift"
    # Only the network configuration, clock and declaration visibility change.
    # The loader, batch loop, catalog matching and fallback resolution stay verbatim.
    write("AppUpdates.swift", "import Foundation\nimport Darwin\nextension AppUpdatesContract {\n"
          + declaration(loader, "final class AppUpdateFeedLoader:")
          + "final class Service {\nlet workQueue = DispatchQueue(label: \"app-updates.contract\")\n"
          + "let clock = Clock()\nstatic let ownPackageTokens: Set<String> = [\"vorssaint\", \"vorssaint@beta\", \"vorssaint-beta\"]\n"
          + "static let onlineCatalogCacheLifetime: TimeInterval = 60 * 60\n"
          + "var onlineCatalogCache: (loadedAt: Foundation.Date, entries: [AppUpdatesSupport.CatalogEntry])?\n"
          + "lazy var catalogSession = URLSession(configuration: URLSessionConfiguration.ephemeral)\n"
          + declaration(updates, "    private struct SourceResult {").replace("private struct", "struct", 1)
          + declaration(updates, "    private func publisherFindings(").replace("private func", "func", 1).replace("Date()", "self.clock.now()")
          + declaration(updates, "    private func onlineCatalogFindings(").replace("private func", "func", 1).replace("Date()", "self.clock.now()")
          + declaration(updates, "    private func onlineResult(").replace("private func", "func", 1)
          + "}\n}\n")
    playback_adapter = "Sources/NowPlayingAdapter/NowPlayingSelection.swift"
    write("NotchPlaybackRouting.swift", "import Foundation\nimport ObjectiveC\nextension NotchPlaybackRoutingContract {\n"
          + declaration(playback_adapter, "    private struct Identity:").replace("private struct", "struct", 1)
          + declaration(playback_adapter, "    static var target:")
          + declaration(playback_adapter, "    static func publish(").replace("    static func", "    @discardableResult\n    static func", 1)
          + declaration(playback_adapter, "    static func validatedTarget(")
          + declaration(playback_adapter, "    static func readInfo(")
          + declaration(playback_adapter, "    static func supportedCommands(")
          + declaration(playback_adapter, "    static func send(")
          + declaration(playback_adapter, "    private static func makeTarget(").replace("private static", "static", 1)
          + declaration("Sources/NowPlayingAdapter/NowPlayingAdapter.swift", "private func sendPlaybackCommand(")
            .replace("private func", "static func", 1) + "}\n")
    write("NotchActivationButton.swift", "import AppKit\n"
          + declaration("Sources/Vorssaint/Services/Notch/NotchWindowHost.swift", "final class NotchActivationButton:"))
    shelf = "Sources/Vorssaint/Services/Shelf/ShelfService.swift"
    write("ShelfDragCompletion.swift", "import Foundation\n\nextension ShelfDragCompletionContract {\n"
          + "final class Service {\nvar activeInternalDragIDs: [UUID] = []\n"
          + "weak var internalDragWindow: NSWindow?\nvar internalDragWasMerged = false\n"
          + "var panel: NSWindow?\nvar dockedPanel: NSWindow?\n"
          + "var isPinned = false\nvar isVisible = false\nvar dockedVisible = false\n"
          + "var removed: [UUID] = []\nvar floatingClosures = 0\nvar dockedClosures = 0\n"
          + "func endInteraction() {}\nfunc removeItems(_ ids: [UUID]) { removed += ids }\n"
          + "func hide() { floatingClosures += 1; isVisible = false }\n"
          + "func collapseDocked() { dockedClosures += 1; dockedVisible = false }\n"
          + declaration(shelf, "    func beginInternalDrag(")
          + declaration(shelf, "    func finishInternalDrag(")
          + declaration(shelf, "    func completeInternalDrag(")
          + "}\n}\n")
    notch = "Sources/Vorssaint/Services/Notch/NotchService.swift"
    canvas = "Sources/Vorssaint/Services/Notch/NotchWindowHost.swift"
    write("NotchHover.swift", "import Foundation\nextension NotchHoverTests {\nfinal class Service: State {\n"
          + declaration(notch, "    func hover(") + "}\n}\n")
    music_visibility = "".join(declaration(notch, prefix).replace("    private ", "    ", 1) for prefix in [
        "    var idleContent:", "    var hasMusicActivity:", "    var compactActivity:",
        "    var compactActivityGeometry:", "    var surfaceSize:", "    func collapse(",
        "    private func syncVisibleConsumers(", "    private func releaseMonitor("])
    for call in ["NotchSupport.controls", "NotchSupport.watchesMusicActivity", "NotchSupport.idleContent"]:
        music_visibility = music_visibility.replace(call + "()", call + "(in: ReviewDefaults.current)")
    music_visibility = music_visibility.replace("playback?.isPlaying == true)",
                                                "playback?.isPlaying == true, in: ReviewDefaults.current)")
    music_visibility = music_visibility.replace("captureControls: captureControls != nil)",
                                                "captureControls: captureControls != nil, in: ReviewDefaults.current)")
    music_visibility = music_visibility.replace("AppFeature.monitorDisk.isAvailable",
                                                "AppFeature.monitorDisk.isAvailable(in: ReviewDefaults.current)")
    write("NotchMusicVisibility.swift", "import Foundation\nextension NotchMusicVisibilityTests {\n"
          + "final class Service: State {\n" + music_visibility + "}\n}\n")
    write("NotchScreenEdgeClicks.swift", "import AppKit\nextension NotchScreenEdgeClickTests {\nfinal class Service: State {\n"
          + "func open() { openings += 1; expanded = true; syncScreenEdgeClicks() }\n"
          + "".join(declaration(notch, prefix).replace("    private ", "    ", 1) for prefix in [
              "    private var screenEdgeClickArea:", "    private func syncScreenEdgeClicks(",
              "    private func handleScreenEdgeEvent(", "    private func handleScreenEdgeClick(",
              "    private func removeScreenEdgeClickMonitors("])
          + "}\n}\n")
    write("NotchScreenRefresh.swift", "import Foundation\n\nextension NotchScreenRefreshContract {\nfinal class Service: State {\n"
          + declaration(notch, "    private func screenParametersDidChange()").replace("private func", "func", 1)
          + declaration(notch, "    private func invalidateMenuSpace(").replace("private func", "func", 1)
          + declaration(notch, "    private func stopMenuSpaceMonitoring()")
          + declaration(notch, "    private func syncMenuSpaceMonitoring()").replace("private func", "func", 1)
              .replace("AXIsProcessTrusted()", "accessibilityGranted")
          + "}\n}\n")
    write("NotchPresentationRefresh.swift", "import Foundation\nimport Combine\n"
          + "extension NotchPresentationRefreshContract {\nfinal class Service: State {\n"
          + declaration(notch, "    func refreshPresentation(")
          + declaration(notch, "    private func applyMenuSpace(").replace("private func", "func", 1)
          + declaration(notch, "    func updateCaptureHeight(")
          + declaration(notch, "    func removeCapture(")
          + declaration(notch, "    private func clearCapture(")
          + "}\n}\n")
    metric_view = "Sources/Vorssaint/UI/MenuPanel/MetricDetailView.swift"
    renderer = "Sources/Vorssaint/App/MenuBarRenderer.swift"
    metric_cases = "\n".join(line for line in declaration(metric_view, "enum MetricDetailKind:").splitlines()
                             if line.startswith("    case "))
    menu_metric_cases = "\n".join(line for line in declaration(renderer, "enum MenuBarMetric:").splitlines()
                                  if line.startswith("    case "))
    write("NotchDestinations.swift", "import Foundation\n\nextension NotchDestinationContract {\n"
          + "enum MetricDetailKind: String {\n" + metric_cases + "\n}\n"
          + "enum MenuBarMetric: String, CaseIterable {\n" + menu_metric_cases + "\n"
          + declaration(renderer, "    var feature: AppFeature")
          + declaration(metric_view, "    var detailKind:") + "}\n"
          + "final class Service: State {\n"
          + "func syncWithPreferences() { presentationSyncs += 1; refreshModules(); syncVisibleConsumers(); NotchTimerService.shared.syncWithPreferences() }\n"
          + availability_declaration(notch, "    private func metricIsAvailable(")
          + declaration(notch, "    private func refreshModules(")
              .replace("NotchSupport.modules()", "NotchSupport.modules(in: ReviewDefaults.current)")
          + declaration(notch, "    func open(_ module:")
              .replace("NotchSupport.isEnabled()", "NotchSupport.isEnabled(in: ReviewDefaults.current)")
          + declaration(notch, "    private func updateSession(").replace("private func", "func", 1)
              .replace("AppFeature.mixer.isAvailable", "AppFeature.mixer.isAvailable(in: ReviewDefaults.current)")
          + "}\n}\n")
    write("ShelfDropRouting.swift", "import AppKit\n\nextension ShelfDropRoutingContract {\n"
          + declaration(canvas, "struct NotchFileDropActions {")
          + "final class ShelfService: ShelfState {\nstatic var shared = ShelfService()\n"
          + declaration(shelf, "    func acceptDrop(pasteboard:")
          + declaration(shelf, "    func accept(draggingInfo:")
          + "}\nfinal class Notch: NotchState {\n"
          + declaration(notch, "    var canAcceptFileDrop:")
          + declaration(notch, "    func accept(_ pasteboard:")
          + "}\nfinal class Canvas {\nvar acceptingDrag = false\n"
          + "var dropActions: NotchFileDropActions?\n"
          + declaration(canvas, "    func beginDrop(")
          + declaration(canvas, "    func finishDrop(")
          + "}\n}\n")
    switcher = "Sources/Vorssaint/UI/Switcher/SwitcherView.swift"
    switcher_service = "Sources/Vorssaint/Services/Switcher/AppSwitcher.swift"
    write("SwitcherScroll.swift", "import AppKit\nimport SwiftUI\n"
          + "extension SwitcherScrollContract {\nstruct Strip: View {\n"
          + "@ObservedObject var switcher: Model\n"
          + "var iconRowContentWidth: CGFloat { switcher.iconRowLayout.contentWidth(simpleMode: true, windowRow: false) }\n"
          + "var body: some View {\nif selectedWindow != nil {\nlet appWindows = selectedAppWindows\n"
          + "if switcher.simple {\nGroup {\n"
          + declaration(switcher, "                ScrollViewReader { proxy in")
          + "}\n.frame(width: iconRowContentWidth - 2 * SwitcherIconRowLayout.simpleTitlePanelPadding, "
          + "height: 25 * SwitcherIconRowLayout.scale)\n} else {\n"
          + declaration(switcher, "                    ScrollViewReader { proxy in")
          + "}\n}\n}\n"
          + declaration(switcher, "    private var selectedWindow:")
          + declaration(switcher, "    private var selectedAppWindows:")
          + declaration(switcher, "    private func revealSelection(")
          + "}\n}\nextension SwitcherScrollContract.Model {\n"
          + "func search(_ query: String) { searchQuery = query; applySearchFilter(preferredItemID: selectedItemID) }\n"
          + declaration(switcher_service, "    private var selectedItemID:")
          + declaration(switcher_service, "    private func applySearchFilter(")
          + "}\n")
    service = "Sources/Vorssaint/Services/QuickTools/QuickLauncherService.swift"
    view = "Sources/Vorssaint/UI/QuickLauncher/QuickLauncherView.swift"
    panel_layout = (ROOT / "Sources/Vorssaint/UI/MenuPanel/PanelLayout.swift").read_text()
    protocol = next(line for line in panel_layout.splitlines() if line.startswith("protocol PanelOrderItem:"))
    write("QuickLauncherBodies.swift", "import Foundation\nimport Carbon.HIToolbox\n" + protocol + "\n\nextension QuickLauncherContract {\n"
          + declaration(service, "enum QuickLauncherItem:")
          + "final class Launcher {\nvar isEditing = false\nvar activeUtility: QuickLauncherItem?\n"
          + "var editingOptionsItem: QuickLauncherItem?\nvar selectedIndex: Int?\nvar presentationID = UUID()\n"
          + "var candidates: [QuickLauncherItem] = QuickLauncherItem.allCases\n"
          + "var visibleItems: [QuickLauncherItem] { candidates.filter { $0.feature.isAvailable(in: ReviewDefaults.current) } }\n"
          + 'func hide() { events.append("hide") }\n'
          + availability_declaration(service, "    func run(_ item: QuickLauncherItem)")
          + declaration(service, "    func prepareForPresentation()")
          + availability_declaration(service, "    func refreshAvailability()")
          + declaration(service, "    private func clampSelection()")
          + declaration(service, "    func activateSelection()")
          + declaration(service, "    func activate(at index:")
          + declaration(service, "    func moveSelection(")
          + declaration(service, "    func handlePanelKey(")
          + declaration(service, "    private static func digitIndex(")
          + "}\nstruct Tile {\nvar keepAwake = State()\nvar micMute = State()\nvar recorder = State()\n"
          + declaration(view, "    private func icon(for item: QuickLauncherItem)")
          + declaration(view, "    private func isActive(_ item: QuickLauncherItem)")
          + "func display(_ item: QuickLauncherItem) -> (String, Bool) { (icon(for: item), isActive(item)) }\n}\n}\n")

    preview = "Sources/Vorssaint/Services/QuickTools/ScreenshotQuickPreviewController.swift"
    selection = "Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift"
    refresh_methods = [
        "    private func screenCaptureToolDidChange()",
        "    private func adoptCapturePolicy(",
        "    private func applySource(",
        "    private func loadLiveLoupeImages()",
        "    private func markCapturePending()",
        "    private func captureFullDisplayUnderMouse()",
        "    private func repeatLastRegion()",
        "    fileprivate func confirmWindow(",
        "    fileprivate func confirmRegion(",
        "    fileprivate func confirmColor(",
    ]
    write("ScreenshotSelectionRefresh.swift", "import Foundation\nimport AppKit\n"
          + "extension ScreenshotSelectionRefreshContract.Chooser {\n"
          + declaration(selection, "    fileprivate var acceptsCaptureInput:").replace("fileprivate var", "var", 1)
          + "".join(declaration(selection, prefix).replace("fileprivate func", "func", 1)
                    .replace("private func", "func", 1).replace("UserDefaults.standard", "ReviewDefaults.current")
                    for prefix in refresh_methods)
          + "}\n")
    write("NotchCaptureKeyboard.swift", "import Foundation\nimport Carbon.HIToolbox\n\nextension NotchCaptureKeyboardContract {\n"
          + "final class NotchService {\nstatic var shared = NotchService()\n"
          + "var presentationWindow: NSPanel? = NSPanel()\nvar acceptsSystemFeedback = true\n"
          + "var expanded = true\nvar selected = NotchModule.captures\nvar showingAppPanel = false\n"
          + "var showingSections = false\nvar selectedMetric: Int?\nvar captureControls: Int?\n"
          + "var captureID: UUID?\nvar captureContent: Bool? = true\n"
          + declaration("Sources/Vorssaint/Services/Notch/NotchService.swift", "    func isCaptureVisible(")
          + "}\nfinal class Preview {\n"
          + declaration(preview, "    enum Action {")
          + "var keyMonitor: Any?\nvar closed = false\nvar shownInNotch = true\nlet presentationID = UUID()\n"
          + "var actions: [Action] = []\nfunc perform(_ action: Action) { actions.append(action) }\n"
          + "func close() { closed = true }\nfunc attach(_ panel: NSPanel) { installKeyMonitor(for: panel) }\n"
          + declaration(preview, "    private func installKeyMonitor(for panel:")
          + "}\nfinal class Selection {\n"
          + "final class Options { var controlsInNotch = true; var hasFocusedControl = false }\n"
          + "enum Outcome { case cancelled }\nvar screenCaptureOptions: Options? = Options()\n"
          + "var keyMonitor: Any?\nvar globalKeyMonitor: Any?\nvar spaceIsDown = false\n"
          + "var acceptsWindowClick = true\nvar loupeAcceptsKeyboardActions = false\n"
          + "var actions: [String] = []\nvar draggingPanel: ScreenshotOverlayPanel?\n"
          + 'func finish(_ outcome: Outcome) { actions.append("cancel") }\n'
          + 'func captureFullDisplayUnderMouse() { actions.append("fullDisplay") }\n'
          + "func panelUnderMouse() -> ScreenshotOverlayPanel? { draggingPanel }\n"
          + 'func repeatLastRegion() { actions.append("repeat") }\n'
          + "func selectCaptureTool(for event: NSEvent) -> Bool { false }\n"
          + "static func isScrollingCaptureKey(_ event: NSEvent) -> Bool { false }\n"
          + "static func isLoupeKey(_ event: NSEvent) -> Bool { false }\n"
          + "static func isCopyColorKey(_ event: NSEvent) -> Bool { false }\n"
          + "static func isNudgeKey(_ event: NSEvent) -> Bool { false }\n"
          + "func toggleScrollingCapture() {}\nfunc toggleLoupe() {}\nfunc copyLoupeColor() {}\n"
          + "func nudgePointer(keyCode: Int, fast: Bool) {}\nfunc attach() { installKeyMonitor() }\n"
          + declaration(selection, "    private func installKeyMonitor()")
          + "}\n}\n")

    lyrics = "Sources/Vorssaint/Services/Notch/NotchLyricsService.swift"
    write("NotchLyricsLifecycle.swift", "import Foundation\nimport UniformTypeIdentifiers\n\nextension NotchLyricsContract {\n"
          + "final class Service {\nvar memory = NotchLyricsMemory()\n"
          + "var lyrics: NotchLyrics? { memory.lyrics }\nvar track: NotchMusicIdentity? { memory.track }\n"
          + "var visible = false\nvar online = false\nvar generation = UUID()\nvar state: State = .idle\n"
          + "var session: Session?\nvar importPanel: Panel?\nvar loads: [NotchMusicIdentity] = []\n"
          + "func load(_ track: NotchMusicIdentity) { loads.append(track); state = .loading; session = Session() }\n"
          + declaration(lyrics, "    func update(playback:")
          + declaration(lyrics, "    func playbackChanged(")
          + declaration(lyrics, "    func hide()")
          + declaration(lyrics, "    func stop()")
          + declaration(lyrics, "    private func cancel()")
          + declaration(lyrics, "    func importLyrics()")
          + declaration(lyrics, "    private func canReturnToLyrics(")
          + "}\n}\n")

    music = "Sources/Vorssaint/Services/Notch/NotchMusicService.swift"
    write("NotchMusicControls.swift", "import Foundation\n\nextension NotchMusicCommandContract {\n"
          + "final class Service {\ntypealias Command = NotchPlaybackCommand\n"
          + "var playback: NotchPlayback?\nvar generation = UUID()\nvar queueRequest: UUID?\n"
          + "var queueVisible = true\nvar queueLoading = false\nvar queueActionPending = false\n"
          + "var commandFailed = false\nvar queueActionFailed = false\nvar commandPending = false\n"
          + "var canSeek: Bool { playback?.canSeek == true }\n"
          + "func beginAutomation(_ command: Command, playback: NotchPlayback) -> Bool { false }\nfunc cancelAutomationAction() {}\n"
          + "var process: Process?\nvar input: Pipe?\nlet queue = Scheduler()\n"
          + "lazy var commandWriter = NotchMusicCommandWriter { [queue = self.queue] in queue.async(execute: $0) }\n"
          + "var wantsPlayback = false\nvar restartCount = 0\nvar restartWork: DispatchWorkItem?\nvar launches = 0\n"
          + "func launch() { guard wantsPlayback, process == nil else { return }; launches += 1; process = Process(); input = Pipe(); commandWriter.start() }\n"
          + "func disconnect() { generation = UUID(); commandWriter.stop(); process = nil; input = nil; playback = nil }\n"
          + declaration(music, "    func start()")
          + declaration(music, "    func stop()")
          + declaration(music, "    private func connectionEnded()").replace("private func", "func", 1)
          + declaration(music, "    func seek(")
          + declaration(music, "    func send(_ command: Command)").replace("    func", "    @discardableResult\n    func", 1)
          + declaration(music, "    func send(_ command: Command, context:").replace("    func", "    @discardableResult\n    func", 1)
          + "}\n}\n")
    write("NotchQueueSelection.swift", "import Foundation\n\nextension NotchQueueContract {\n"
          + "final class Service {\nvar queueVisible = true\nvar queueRequest: UUID?\n"
          + "var upcoming: NotchQueueSnapshot?\nvar playback: NotchPlayback?\n"
          + "var queueActionFailed = false\nvar queueActionPending = false\nvar sendAllowed = true\n"
          + "var commands: [NotchPlaybackCommand] = []\n"
          + "func send(_ command: NotchPlaybackCommand) -> Bool { commands.append(command); return sendAllowed && command.message != nil }\n"
          + declaration(music, "    func playQueued(")
          + "}\n}\n")
    write("NotchMusicAutomationBodies.swift", "import Foundation\n\nextension NotchMusicAutomationFlowContract {\n"
          + "final class Service {\ntypealias Command = NotchPlaybackCommand\nvar playback: NotchPlayback?\n"
          + "var automationAvailability: NotchMusicAutomation.Availability?\nvar automationTarget: NotchMusicAutomation.Target?\n"
          + "var generation = UUID()\nvar commandPending = false\nvar commandFailed = false\nvar requestingAutomation = false\n"
          + "var automationCancellation = DispatchWorkItem {}\nvar automationConsentCancellation = DispatchWorkItem {}\n"
          + "var automationTimeout: DispatchWorkItem?\nvar automationAction: AutomationAction?\nvar awaitingAutomationValidation = false\n"
          + "let queue = Scheduler()\nvar refreshes = 0\nfunc refreshAutomation() { refreshes += 1 }\n"
          + "var validationRequests: [Command] = []\nfunc send(_ command: Command) -> Bool { validationRequests.append(command); return true }\n"
          + declaration(music, "    private struct AutomationAction {").replace("private struct", "struct", 1)
          + declaration(music, "    var canSeek:")
          + declaration(music, "    func canPerform(")
          + declaration(music, "    func requestAutomationAccess()")
          + declaration(music, "    private func beginAutomation(").replace("private func", "func", 1)
          + declaration(music, "    private func receiveValidation(").replace("private func", "func", 1)
          + declaration(music, "    private func cancelAutomationAction()").replace("private func", "func", 1)
          + "}\n}\nextension NotchMusicAutomationFlowContract.NotchMusicAutomation {\n"
          + declaration("Sources/Vorssaint/Services/Notch/NotchMusicAutomation.swift", "    static func send(") + "}\n")

    downloads = "Sources/Vorssaint/Services/Notch/NotchDownloadService.swift"
    write("NotchDownloadFolderChoice.swift", "import Foundation\n\nextension NotchDownloadFolderChoiceContract {\n"
          + "final class Service {\nvar chooser: NSOpenPanel?\nvar chooserID = UUID()\n"
          + "var folderUnavailable = false\nvar syncs = 0\nvar stops = 0\n"
          + "func syncWithPreferences() { syncs += 1 }\n"
          + "func stop() { stops += 1; cancelFolderChoice() }\n"
          + declaration(downloads, "    func chooseFolder()")
          + declaration(downloads, "    private func folderPickerParent()")
          + declaration(downloads, "    private func canReturnToDownloads(")
          + declaration(downloads, "    private func cancelFolderChoice()")
          + "}\n}\n")

    factories = []
    pattern = r"static\s+func\s+(\w+)\s*\(\s*_\s+\w+:\s*AppLanguage\s*\)\s*->"
    for path in sorted((ROOT / "Sources/Vorssaint/Core").glob("*Strings.swift")):
        source = path.read_text()
        if "extension FeatureStrings" in source or "enum FeatureStrings" in source:
            scopes = re.findall(r"(?:extension|enum) FeatureStrings \{(.*?)^\}", source, re.S | re.M)
            names = [name for scope in scopes for name in re.findall(pattern, scope)]
            if not names:
                raise ValueError(f"No language factory found in {path}")
            factories.extend(names)
    if not factories or len(factories) != len(set(factories)):
        raise ValueError("Missing or duplicate localization factories")
    write("LocalizationCatalog.swift", "extension LocalizationTests {\n"
          + "static let factories: [(String, (AppLanguage) -> Any)] = [\n"
          + "".join(f'("{name}", {{ FeatureStrings.{name}($0) }}),\n' for name in factories)
          + "]\n}\n")

    # Same-file extensions can exercise the private AppKit content view without
    # widening the production interface or presenting an application window.
    hud = "Sources/Vorssaint/UI/QuitProtection/QuitProtectionHUD.swift"
    checks = "Tests/Fixtures/QuitProtectionHUDChecks.swift"
    write("QuitProtectionHUDBodies.swift",
          f'#sourceLocation(file: {json.dumps(hud)}, line: 1)\n'
          + (ROOT / hud).read_text() + "\n"
          + f'#sourceLocation(file: {json.dumps(checks)}, line: 1)\n'
          + (ROOT / checks).read_text() + "\n#sourceLocation()\n")


if __name__ == "__main__":
    main()
