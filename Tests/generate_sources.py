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


def declaration(path, prefix, scope=None):
    lines = (ROOT / path).read_text().splitlines(keepends=True)
    lower, upper = 0, len(lines)
    if scope is not None:
        scopes = [i for i, line in enumerate(lines) if line.startswith(scope)]
        if len(scopes) != 1:
            raise ValueError(f"Expected one scope {scope!r} in {path}")
        lower = scopes[0] + 1
        upper = next(i for i in range(lower, len(lines)) if lines[i].rstrip() == "}")
    starts = [i for i in range(lower, upper) if lines[i].startswith(prefix)]
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
    write("ClipboardHistoryImageEditor.swift", "import AppKit\n"
          + "extension ClipboardHistoryImageEditorTests {\nfinal class Host: Fixture {\n"
          + declaration("Sources/Vorssaint/Services/Clipboard/ClipboardHistoryService.swift",
                        "    func editImage(")
          + "}\n}\nextension ClipboardHistoryImageEditorTests.ScreenshotService {\n"
          + declaration("Sources/Vorssaint/Services/QuickTools/ScreenshotService.swift",
                        "    static func imageCapture(")
          + "}\n")
    panel = "Sources/Vorssaint/App/AppDelegate.swift"
    write("PostUpdateStatusItemRecovery.swift", "import AppKit\nimport Foundation\n"
          + "extension PostUpdateStatusItemRecoveryTests {\nfinal class Host: Fixture {\n"
          + "".join(declaration(panel, prefix).replace("private ", "") for prefix in [
              "    private func recoverStatusItemAfterUpdate(",
              "    private func verifyPostUpdateStatusItem(",
              "    private func iconIsOnScreen("])
          + "}\n}\n")
    write("MenuPanelRecovery.swift", "import AppKit\nimport Foundation\n"
          + "extension MenuPanelRecoveryTests {\nfinal class Host: Fixture {\n"
          + "".join(declaration(panel, prefix).replace("private ", "") for prefix in [
              "    private struct PanelAnchor", "    private func statusButtonMidX(",
              "    private func correctedPopoverMidX(", "    private func resolvePanelAnchor(",
              "    private func frameStillDescribesMenuBar(", "    private func statusFrameNeedsAnchorOverride(",
              "    private func anchorVisibleFrame(", "    private func applyPopoverDriftFrame(",
              "    private func beginPopoverDriftCorrection(window: NSWindow, anchor: PanelAnchor) {",
              "    private func armPopoverDriftCorrection(", "    private func endPopoverDriftCorrection(",
              "    private func showPopover(", "    func popoverWillClose(", "    func popoverDidClose(",
              "    private func releasePanelResources(", "    private func anchorAfterForeignClose(",
              "    private func reopenPanelAfterForeignClose(", "    private func shouldDismissPopover("])
          + "var popoverAnchor: PanelAnchor?\nvar lastGoodPanelAnchor: PanelAnchor?\n"
          + "}\n}\n")
    brightness = "Sources/Vorssaint/Services/Display/BrightnessService.swift"
    write("DisplayRestoration.swift", "import CoreGraphics\nimport Foundation\n"
          + "extension DisplayRestorationTests {\nfinal class BrightnessService: Fixture {\n"
          + declaration(brightness, "    enum DisplayControlFailure:")
          + "".join(declaration(brightness, prefix).replace("private ", "", 1) for prefix in [
              "    private static func configureDisplay(", "    private func restoreDisplay(",
              "    private func syncLidObserver(", "    private func restoreDeferredDisplays(",
              "    private func restoreManagedDisplays(", "    func restoreDisplaysLeftOff(",
              "    private func commitDisplayToggle(", "    private func finishDisplayToggle(",
              "    private func restoreManagedDisplayIfHeadless("])
          + "}\n}\n")
    write("BrightnessStep.swift", "import CoreGraphics\nimport Foundation\nimport os\n"
          + "extension BrightnessStepTests {\n"
          + "".join(declaration(brightness, prefix).replace("private ", "", 1) for prefix in [
              "    private struct Route", "    private enum DDCProbe"])
          + "final class Service: Fixture {\n"
          + declaration(brightness, "    private func step(").replace("private ", "", 1)
          + "}\n}\n")
    activator = "Sources/Vorssaint/Services/Switcher/WindowActivator.swift"
    write("SwitcherActivationBodies.swift", "import AppKit\nimport ApplicationServices\n"
          + "extension SwitcherActivationTests.Activator {\n"
          + "".join(declaration(activator, prefix).replace("private static", "static", 1)
                    for prefix in ["    private static func activateApp(",
                                   "    private static func activateAppCooperatively(",
                                   "    private static func activateSource("])
          + "}\nextension SwitcherActivationTests.Bridge {\n"
          + declaration("Sources/Vorssaint/Services/Switcher/SpaceWindowBridge.swift",
                        "    static func frontWindow(") + "}\n")
    write("ScratchpadExport.swift", "import AppKit\nimport Foundation\n"
          + "extension ScratchpadExportContract {\nfinal class Service: Fixture {\n"
          + declaration("Sources/Vorssaint/Services/QuickTools/ScratchpadService.swift",
                        "    func exportText(")
          + "}\n}\n")
    write("MusicLaunchBlockerLifecycle.swift", "import AppKit\nimport Foundation\n"
          + "extension MusicLaunchBlockerContract {\nfinal class Service: Fixture {\n"
          + "".join(declaration("Sources/Vorssaint/Services/Audio/MusicLaunchBlocker.swift", prefix)
                    .replace("private ", "", 1) for prefix in [
                        "    func syncWithPreferences(", "    private func start(", "    func stop(",
                        "    private func handleLaunch(", "    private func handleMediaKeyEvent("])
          + "}\n}\n")
    fan_control = "Sources/Vorssaint/Services/FanControl/FanControlService.swift"
    write("FanControlResume.swift", "import Foundation\n"
          + "extension FanControlResumeContract {\nfinal class Service: Fixture {\n"
          + "".join(declaration(fan_control, prefix)
                    .replace("@objc private func", "func", 1)
                    .replace("private static var", "static var", 1)
                    .replace("private func", "func", 1) for prefix in [
                        "    static func recoverIfNeeded(", "    func syncWithPreferences(",
                        "    func returnToSystem(", "    func resumePreferenceDidChange(",
                        "    private static var resumableConfiguration:", "    private func resume(",
                        "    private static var helperAwaitsRegistration:",
                        "    private func rememberForResume(", "    private func stopIdleWorkIfPossible(",
                        "    @objc private func workspaceDidWake("])
          + "}\n}\n")
    write("NotchAudioLevelLifecycle.swift", "import Combine\nimport Foundation\n"
          + "extension NotchAudioLevelLifecycleContract {\n"
          + declaration("Sources/Vorssaint/Services/Notch/NotchAudioLevelService.swift",
                        "final class NotchAudioLevelService:")
          + "}\n")
    clipboard = "Sources/Vorssaint/Services/Clipboard/ClipboardHistoryService.swift"
    write("ClipboardPreview.swift", "import Foundation\nimport Combine\n"
          + "extension ClipboardPreviewContract {\nfinal class Service: Fixture {\n"
          + declaration(clipboard, "    @Published private(set) var entries:")
          + declaration(clipboard, "    func updateText(")
          + "".join(declaration(clipboard, prefix).replace("private ", "", 1) for prefix in [
              "    func togglePin(", "    func copy(_ entry:", "    private func touch(",
              "    private var firstRecentIndex:", "    private func normalizeEntryOrder("])
          + "func setEntries(_ values: [ClipboardHistoryEntry]) { entries = values }\n"
          + "}\n}\n")
    write("CommandBarInputSource.swift", "import Foundation\n"
          + "extension CommandBarInputSourceContract {\nfinal class Service: Fixture {\n"
          + "".join(declaration("Sources/Vorssaint/Services/CommandBar/CommandBarService.swift", prefix)
                    .replace("private func", "func", 1) for prefix in [
                        "    private func adoptASCIIInputSource(",
                        "    private func restoreSuspendedInputSource(",
                        "    func restoreBorrowedInputSource(",
                        "    var hasBorrowedInputSource:"])
          + "}\n}\n")
    write("CommandBarTermination.swift", "import AppKit\nimport Foundation\n"
          + "extension CommandBarTerminationContract {\nfinal class Host: Fixture {\n"
          + declaration("Sources/Vorssaint/App/AppDelegate.swift", "    func applicationShouldTerminate(")
          + "}\n}\n")
    ports = "Sources/Vorssaint/Services/PortManager/PortManagerService.swift"
    write("PortManagerRefresh.swift", "import Darwin\nimport Foundation\n"
          + "extension PortManagerRefreshTests {\nfinal class Service: Fixture {\n"
          + declaration(ports, "    func refresh(")
          + declaration(ports, "    private static func snapshot(").replace("private static", "static", 1)
          + declaration(ports, "    private static func startTimes(").replace("private static", "static", 1)
          + "}\n}\n")
    write("ProcessName.swift", "import Foundation\n"
          + "extension ProcessNameContract {\nfinal class Lookup: Fixture {\n"
          + declaration("Sources/Vorssaint/Services/ResponsibleProcess.swift", "    static func displayName(")
          + "}\n}\n")
    write("SystemMonitorCPU.swift", "import Darwin\nimport Foundation\n"
          + "extension SystemMonitorCPUTests {\nfinal class Monitor: Fixture {\n"
          + declaration("Sources/Vorssaint/Services/SystemMonitor/SystemMonitor.swift",
                        "    private func readCPUUsage(").replace("private func", "func", 1)
          + "}\n}\n")
    uninstall = "Sources/Vorssaint/Services/Uninstall/AppUninstaller.swift"
    bar = "Sources/Vorssaint/Services/CommandBar/CommandBarService.swift"
    write("QuickPaste.swift", "import Foundation\n"
          + "extension ClipboardFeatureTests.QuickPasteHost {\n"
          + declaration("Sources/Vorssaint/Services/Clipboard/ClipboardHistoryService.swift",
                        "    private func pasteIntoPreviousApp(").replace("private func", "func", 1)
          + "}\n")
    write("CommandBarCopyAnswer.swift", "import Foundation\n"
          + "extension CommandBarFeatureTests.CopyAnswerHost {\n"
          + declaration("Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift",
                        "    private static func copyAnswer(").replace("private static", "static", 1)
          + "}\n")
    write("CommandBarBrightness.swift", "import AppKit\n"
          + "extension CommandBarFeatureTests.BrightnessHost {\n"
          + declaration("Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift",
                        "    private static func applyBrightness(").replace("private static", "static", 1)
          + "}\n")
    write("CommandBarEmojiBodies.swift", "import Foundation\n"
          + "extension CommandBarEmojiContract.Catalog {\n"
          + declaration("Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift",
                        "    static func emojiEntries(")
          + "}\nextension CommandBarEmojiContract.Service {\n"
          + "".join(declaration(bar, prefix).replace("private func", "func", 1)
                    for prefix in ["    struct RowAction:", "    private func skinToneActions(",
                                   "    private func recordUsage(", "    private func finish("])
          + "}\n")
    write("UninstallerFlow.swift", "import AppKit\nimport Carbon.HIToolbox\nimport Combine\n"
          + "extension UninstallerFlowTests {\n"
          + declaration(uninstall, "    enum Phase:")
          + declaration(bar, "    enum Mode:")
          + "final class Uninstaller: UninstallerState {\nstatic let shared = Uninstaller()\n"
          + "".join(declaration(uninstall, prefix) for prefix in [
              "    var isRemoving: Bool", "    func select(appURL:",
              "    func reset()", "    func setInclude(", "    struct HomebrewRemovalConfirmation",
              "    var homebrewRemovalConfirmation:", "    func removeSelectedWithHomebrew("])
          + "}\nfinal class Service: ServiceState {\n"
          + "".join(declaration(bar, prefix).replace("private func", "func", 1) for prefix in [
              "    @Published var query", "    private func beginUninstallReview(",
              "    private func handleUninstallKey(", "    func stepBack()",
              "    private func finishUninstallReview()"])
          + "}\n}\nextension UninstallerFlowTests.Finder {\n"
          + declaration("Sources/Vorssaint/Services/Finder/FinderCutPaste.swift", "    static func selectionURLs(")
          + "}\n")
    dock = "Sources/Vorssaint/Services/DockPreview/DockPreviewService.swift"
    write("DockPreviewFrameRetry.swift", "import Foundation\nextension DockPreviewFrameRestorationTests {\n"
          + declaration("Sources/Vorssaint/Services/DockPreview/DockPreviewFrameRestoration.swift",
                        "    private static func restore(").replace("private static func", "static func", 1)
          + "}\n")
    write("DockPreviewScope.swift", "import Foundation\nextension DockPreviewScopeTests.Service {\n"
          + "".join(declaration(dock, prefix).replace("private func", "func", 1)
                    for prefix in ["    private func syncSpaceObservation()",
                                   "    private func stopSpaceObservation()"])
          + "}\nextension DockPreviewScopeTests.WindowEnumerator {\n"
          + declaration("Sources/Vorssaint/Services/Switcher/WindowEnumerator.swift",
                        "    static func dockPreviewMayActivate(")
          + "}\n")
    write("DockAutohideInput.swift", "import CoreGraphics\nimport Foundation\nextension DockAutohideHoldTests.Service {\n"
          + "".join(declaration(dock, prefix, scope="final class DockPreviewService:")
                    .replace("private func", "func", 1)
                    for prefix in ["    private func beginDockAutohideHold()",
                                   "    private func releaseDockAutohideHold()",
                                   "    private func handleDockHoldInput(type:",
                                   "    private func handle(type:",
                                   "    func commit("])
          + "}\n")
    # Entire input/mute services retain their production control flow. Only
    # visibility, scheduling, defaults and HAL transport are replaced by fixtures.
    input_source = "Sources/Vorssaint/Services/Audio/AudioInputDeviceManager.swift"
    mute_source = "Sources/Vorssaint/Services/QuickTools/MicMuteService.swift"
    input_bodies = (declaration(input_source, "struct MixerInputDevice:")
                    + declaration(input_source, "final class AudioInputDeviceManager:")
                    + declaration(mute_source, "final class MicMuteService:"))
    input_bodies = (input_bodies.replace("fileprivate ", "")
                   .replace("private(set) ", "").replace("private ", "")
                   .replace("static let shared =", "static var shared ="))
    for operation in ("HasProperty", "IsPropertySettable", "GetPropertyDataSize",
                      "GetPropertyData", "SetPropertyData", "AddPropertyListener",
                      "RemovePropertyListener"):
        input_bodies = input_bodies.replace("AudioObject" + operation + "(", "HAL." + operation + "(")
    write("MixerInputVolume.swift", "import Foundation\nimport Combine\nimport CoreAudio\nimport AudioToolbox\n"
          + "extension MixerInputVolumeContract {\n" + input_bodies + "}\n")
    mixer = "Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift"
    write("SoundOutputSwitch.swift", "import Foundation\n"
          + "extension SoundOutputSwitchContract {\nfinal class Mixer {\n"
          + "var outputDevices: [Device] = []\nvar currentOutputDeviceUID: String?\nvar switchedTo: [String] = []\n"
          + "func setUniversalOutputDeviceUID(_ uid: String) -> Bool { switchedTo.append(uid); return true }\n"
          + declaration(mixer, "    func switchToNextSoundOutput(") + "}\n}\n")
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
    write("CleanerScanFlow.swift", "import Foundation\nextension CleanerScanFlowTests {\n"
          + declaration(cleaner, "    enum Phase:")
          + "final class Scanner: ScannerState {\nstatic let shared = Scanner()\n"
          + "".join(declaration(cleaner, prefix) for prefix in ["    func reset()", "    func scan()"])
          + "}\n}\n")

    super_key = "Sources/Vorssaint/Services/SuperKey/SuperKeyService.swift"
    write("SuperKeyTap.swift", "import CoreGraphics\nimport Foundation\n"
          + "extension SuperKeyTapContract {\nfinal class SuperKeyService: State {\n"
          + "".join(declaration(super_key, prefix).replace("private func", "func", 1)
                    for prefix in ["    private func runEventTap()", "    private func setMappingFailure("])
            .replace("CGEvent.tapCreate(", "Tap.create(")
          + "}\n}\n")

    write("CleanerLastRun.swift", "import Foundation\nextension CleanerLastRunContract {\n"
          + "final class Scheduler: SchedulerState {\n"
          + declaration("Sources/Vorssaint/Services/Cleaner/CleanerScheduler.swift", "    private func finishRun(")
            .replace("private func", "func", 1)
          + "}\nfinal class Card: CardState {\n"
          + declaration("Sources/Vorssaint/UI/Cleaner/CleanerView.swift", "    private var lastRunLine:")
            .replace("private var", "var", 1)
          + "}\n}\n")

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
    adapter_entry = "Sources/NowPlayingAdapter/NowPlayingAdapter.swift"
    # Only the clock changes, so tests drive the wait for a chosen source's track.
    write("NotchPlaybackRouting.swift", "import Foundation\nimport ObjectiveC\nextension NotchPlaybackRoutingContract {\n"
          + declaration(playback_adapter, "    private struct Identity:").replace("private struct", "struct", 1)
          + declaration(playback_adapter, "    static var target:")
          + declaration(playback_adapter, "    static var sourceReply:")
          + declaration(playback_adapter, "    static func choose(")
          + declaration(playback_adapter, "    static func select()")
            .replace("ProcessInfo.processInfo.systemUptime", "uptime")
          + declaration(playback_adapter, "    static func publish(").replace("    static func", "    @discardableResult\n    static func", 1)
          + declaration(playback_adapter, "    static func validatedTarget(")
          + declaration(playback_adapter, "    static func readInfo(")
          + declaration(playback_adapter, "    static func supportedCommands(")
          + declaration(playback_adapter, "    static func send(")
          + declaration(playback_adapter, "    private static func makeTarget(").replace("private static", "static", 1)
          + declaration(adapter_entry, "private func sendPlaybackCommand(").replace("private func", "static func", 1)
          + declaration(adapter_entry, "func encodedReply(").replace("func encodedReply", "static func encodedReply", 1)
          + "}\n")
    write("NotchActivationButton.swift", "import AppKit\n"
          + declaration("Sources/Vorssaint/Services/Notch/NotchWindowHost.swift", "final class NotchActivationButton:"))
    write("NotchPanel.swift", "import AppKit\n"
          + declaration("Sources/Vorssaint/Services/Notch/NotchWindowHost.swift", "final class NotchPanel:"))
    shelf = "Sources/Vorssaint/Services/Shelf/ShelfService.swift"
    write("ShelfDragCompletion.swift", "import Foundation\n\nextension ShelfDragCompletionContract {\n"
          + "final class Service {\nvar activeInternalDragIDs: [UUID] = []\n"
          + "weak var internalDragWindow: NSWindow?\nvar internalDragWasMerged = false\n"
          + "var panel: NSWindow?\nvar dockedPanel: NSWindow?\n"
          + "var isPinned = false\nvar isVisible = false\nvar dockedVisible = false\n"
          + "var removed: [UUID] = []\nvar protectedIDs: Set<UUID> = []\n"
          + "var floatingClosures = 0\nvar dockedClosures = 0\n"
          + "func endInteraction() {}\nfunc removeItems(_ ids: [UUID]) { removed += ids }\n"
          + "func hide() { floatingClosures += 1; isVisible = false }\n"
          + "func collapseDocked() { dockedClosures += 1; dockedVisible = false }\n"
          + declaration(shelf, "    func beginInternalDrag(")
          + declaration(shelf, "    func finishInternalDrag(")
          + declaration(shelf, "    func completeInternalDrag(")
          + "}\n}\n")
    notch = "Sources/Vorssaint/Services/Notch/NotchService.swift"
    write("NotchFullscreen.swift", "import CoreGraphics\nimport Foundation\nextension NotchFullscreenTests {\n"
          + declaration("Sources/Vorssaint/Services/Switcher/SpaceWindowBridge.swift", "    struct Topology {")
          + "final class Service: State {\n"
          + declaration(notch, "    var acceptsSystemFeedback: Bool {")
          + declaration(notch, "    private func updateFullscreenVisibility(").replace("private func", "func", 1)
          + declaration(notch, "    private func fullscreenEnvironmentDidChange()").replace("private func", "func", 1)
          + "}\nfinal class PreciseVolumeRollerService: VolumeState {\n"
          + "static let shared = PreciseVolumeRollerService()\n"
          + declaration("Sources/Vorssaint/Services/Audio/PreciseVolumeRollerService.swift", "    func syncWithPreferences()")
          + "}\n}\n")
    write("NotchNotice.swift", "import AppKit\n" + declaration(notch, "struct NotchNotice:"))
    recorder = "Sources/Vorssaint/Services/Recorder/RecorderEditorController.swift"
    write("RecorderZoomAiming.swift", "import Foundation\nimport Combine\n"
          + "extension RecorderZoomAimingTests {\nfinal class Model: State {\n"
          + declaration(recorder, "    @Published var document:").replace("@Published var", "override var", 1)
          + declaration(recorder, "    @Published var selectedZoomID:")
          + "".join(declaration(recorder, prefix) for prefix in [
              "    private func documentDidChange(", "    func undo()", "    func redo()",
              "    private func apply(_ next:", "    func zoom(_ id:",
              "    func beginAiming(", "    func endAiming(", "    func aim(",
              "    func setSelectedZoomFocus(", "    private func applyDuringInteraction(",
              "    func beginPickingBlurArea(", "    func endPickingBlurArea("])
          + "}\n}\n")
    write("NotchVolumeFeedback.swift", "import Foundation\nimport Combine\n"
          + "extension NotchVolumeFeedbackTests {\nfinal class Service: State {\n"
          + "".join(declaration(notch, prefix).replace("    private ", "    ", 1) for prefix in [
              "    private func bindVolumeEvents(", "    private func volumeChanged(",
              "    private func showVolume(", "    func showCurrentVolume(", "    func noteOwnVolumeAdjustment("])
          + "}\n}\n")
    scratchpad_service = "Sources/Vorssaint/Services/QuickTools/ScratchpadService.swift"
    scratchpad_view = "Sources/Vorssaint/UI/Notch/NotchScratchpadView.swift"
    write("NotchCompact.swift", "import AppKit\nimport SwiftUI\nextension NotchCompactTests {\n"
          + declaration("Sources/Vorssaint/UI/Notch/NotchCameraView.swift", "struct NotchCameraView:")
          + declaration("Sources/Vorssaint/UI/Notch/NotchCalendarView.swift", "private struct NotchCalendarEventRow:")
              .replace("private struct", "struct", 1)
          + declaration("Sources/Vorssaint/UI/Notch/NotchComponents.swift", "struct NotchRail<")
          + declaration("Sources/Vorssaint/UI/PlainTextEditor.swift", "struct PlainTextEditor:")
          + declaration(scratchpad_view, "struct NotchScratchpadView:")
          + "}\n"
          + declaration("Sources/Vorssaint/UI/Notch/NotchCalendarView.swift", "extension NotchCalendarColor {")
          + "extension NotchCompactTests.ScratchpadService {\n"
          + declaration(scratchpad_service, "    func clear(")
          + "}\nextension NotchCompactTests.Floating {\n"
          + declaration(scratchpad_service, "    private func focusText(").replace("private func", "func", 1)
          + "}\nextension NotchCompactTests.Embedded {\n"
          + declaration(scratchpad_view, "    private func focusEditor(").replace("private func", "func", 1)
          + "}\nextension NotchCompactTests.Page {\n"
          + declaration("Sources/Vorssaint/UI/Notch/NotchView.swift", "    private var pageSize:")
              .replace("private var", "var", 1).replace("NotchSupport.controls()", "controls")
              .replace("NotchTimerService.shared", "NotchCompactTests.NotchTimerService.shared")
          + "}\n")
    update = "Sources/Vorssaint/Services/Update/UpdateService.swift"
    update_view = "Sources/Vorssaint/UI/Notch/NotchUpdateControl.swift"
    write("NotchUpdate.swift", "import AppKit\nimport SwiftUI\nimport Combine\nextension NotchUpdateTests {\n"
          + "final class UpdateService: ObservableObject {\nstatic let shared = UpdateService()\n"
          + declaration(update, "    enum State:")
          + "@Published var state: State = .idle\n}\n"
          + "final class L10n: ObservableObject {\nstatic let shared = L10n()\n@Published var language = AppLanguage.enUS\n"
          + declaration("Sources/Vorssaint/Core/Localization.swift", "    var s: Strings")
          + "}\nfinal class Service: State {\n"
          + declaration(notch, "    func showUpdate()")
          + "}\n"
          + declaration(update_view, "struct NotchUpdateControl:")
          + "}\n")
    write("UpdateAdminInstall.swift", "import Foundation\n\nextension UpdateAdminInstallContract {\n"
          + "final class Service: Fixture {\n"
          + declaration(update, "    private func launchAdminInstaller(").replace("private ", "", 1)
          + "}\n}\n")
    canvas = "Sources/Vorssaint/Services/Notch/NotchWindowHost.swift"
    write("NotchHover.swift", "import AppKit\nextension NotchHoverTests {\nfinal class Service: State {\n"
          + declaration(notch, "    func show(_ incoming:").replace("NotchSupport.routes(incoming.event)", "true")
          + "".join(declaration(notch, prefix).replace("    private ", "    ", 1) for prefix in [
              "    private var hiddenUntilHover:", "    func hover(",
              "    private var holdsNotification:", "    private func holdNotification(",
              "    private func syncNoticeWithPreferences(",
              "    private func releaseNotification(", "    private func scheduleNoticeDismissal(",
              "    private func dismissNotice(", "    private var noticeCanPresent:",
              "    private func syncHiddenHoverMonitoring(", "    private func removeHiddenHoverMonitors("])
          .replace("NotchSupport.routes(notice.event)", "routesNotices")
          + "}\n}\n")
    music_visibility = "".join(declaration(notch, prefix).replace("    private ", "    ", 1) for prefix in [
        "    private var hiddenUntilHover:", "    var idleContent:", "    var hasMusicActivity:", "    var compactActivity:",
        "    var compactActivityGeometry:", "    var surfaceSize:", "    func collapse(", "    func endCaptureControls(",
        "    private func syncVisibleConsumers(", "    private func releaseMonitor("])
    for call in ["NotchSupport.controls", "NotchSupport.watchesMusicActivity", "NotchSupport.idleContent"]:
        music_visibility = music_visibility.replace(call + "()", call + "(in: ReviewDefaults.current)")
    music_visibility = music_visibility.replace("UserDefaults.standard", "ReviewDefaults.current!")
    music_visibility = music_visibility.replace("playback?.isPlaying == true)",
                                                "playback?.isPlaying == true, in: ReviewDefaults.current)")
    music_visibility = music_visibility.replace("captureControls: captureControls != nil)",
                                                "captureControls: captureControls != nil, in: ReviewDefaults.current)")
    music_visibility = music_visibility.replace("AppFeature.monitorDisk.isAvailable",
                                                "AppFeature.monitorDisk.isAvailable(in: ReviewDefaults.current)")
    music_visibility = music_visibility.replace("AppFeature.fanControl.isAvailable",
                                                "AppFeature.fanControl.isAvailable(in: ReviewDefaults.current)")
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
          + declaration(notch, "    private func applicationDidActivate()").replace("private func", "func", 1)
          + declaration(notch, "    private func stopMenuSpaceMonitoring()")
          + declaration(notch, "    private func syncMenuSpaceMonitoring()").replace("private func", "func", 1)
              .replace("AXIsProcessTrusted()", "accessibilityGranted")
              .replace("NotchSupport.coversMenus()", "coversMenus")
          + "}\n}\n")
    write("NotchSectionScrollRoute.swift", "import AppKit\nextension NotchSectionPagingTests {\nfinal class Service: State {\n"
          + "".join(declaration(notch, prefix).replace("    private ", "    ", 1) for prefix in [
              "    private func handleScroll(", "    private func handleSectionScroll("])
          + "}\n}\n")
    write("NotchPresentationRefresh.swift", "import Foundation\nimport Combine\n"
          + "extension NotchPresentationRefreshContract {\nfinal class Service: State {\n"
          + "func hover(_ entered: Bool) {\nlet wasInside = inside\n"
          + "inside = windowHost?.containsHover(NSEvent.mouseLocation) == true\n"
          + "hoverState.update(pointerInside: inside)\nupdateCaptureControlsHover(wasInside: wasInside)\n}\n"
          + "".join(declaration(notch, prefix).replace("    private ", "    ", 1) for prefix in [
              "    func collapseCaptureControls()", "    func expandCaptureControls()",
              "    private func setCaptureSelectionInProgress(", "    func scheduleCaptureControlsCollapse()",
              "    private func updateCaptureControlsHover(", "    private func updateCaptureControlsClickThrough()",
              "    func endCaptureControls()"])
          + declaration(notch, "    private var hiddenUntilHover:").replace("private var", "var", 1)
          + declaration(notch, "    var acceptsSystemFeedback:")
          + declaration(notch, "    var showsSystemFeedback:")
          + declaration(notch, "    var usesGlassSurface:")
          + declaration(notch, "    var expandedGeometry:").replace("var expandedGeometry", "override var expandedGeometry", 1)
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
          + declaration(notch, "    func showScratchpad(")
              .replace("NotchSupport.routesScratchpad()", "NotchSupport.routesScratchpad(in: ReviewDefaults.current)")
          + declaration(notch, "    var reopeningModule:")
              .replace("UserDefaults.standard", "ReviewDefaults.current!")
          + declaration(notch, "    private func updateSession(").replace("private func", "func", 1)
              .replace("AppFeature.mixer.isAvailable", "AppFeature.mixer.isAvailable(in: ReviewDefaults.current)")
          + "}\n}\n")
    write("ShelfDropRouting.swift", "import AppKit\n\nextension ShelfDropRoutingContract {\n"
          + declaration(canvas, "struct NotchFileDropActions {")
          + declaration("Sources/Vorssaint/Services/Notch/NotchFileToolsService.swift", "struct NotchMediaSession:")
          + "final class ShelfService: ShelfState {\nstatic var shared = ShelfService()\n"
          + declaration(shelf, "    func acceptDrop(pasteboard:")
          + declaration(shelf, "    func accept(draggingInfo:")
          + declaration(shelf, "    func fileURLs(from")
          + declaration(shelf, "    private func unique(")
          + "}\nfinal class NotchFileToolsService: FileToolsState {\nstatic var shared = NotchFileToolsService()\n"
          + declaration("Sources/Vorssaint/Services/Notch/NotchFileToolsService.swift", "    var offersMediaDrop:")
          + declaration("Sources/Vorssaint/Services/Notch/NotchFileToolsService.swift", "    var canAcceptMediaDrop:")
          + declaration("Sources/Vorssaint/Services/Notch/NotchFileToolsService.swift", "    func mediaDropContent(")
          + declaration("Sources/Vorssaint/Services/Notch/NotchFileToolsService.swift", "    func openMediaDrop(")
          + declaration("Sources/Vorssaint/Services/Notch/NotchFileToolsService.swift", "    func updateMediaHeight(")
          + declaration("Sources/Vorssaint/Services/Notch/NotchFileToolsService.swift", "    func hideMedia(")
          + declaration("Sources/Vorssaint/Services/Notch/NotchFileToolsService.swift", "    func showMedia(")
          + "}\nfinal class Notch: NotchState {\n"
          + declaration(notch, "    var canAcceptFileDrop:")
          + declaration(notch, "    func beginFileDrop(")
          + declaration(notch, "    func updateFileDrop(")
          + declaration(notch, "    func endFileDrop(")
          + declaration(notch, "    func accept(_ pasteboard:")
          + "}\nfinal class Canvas {\nvar acceptingDrag = false\n"
          + "var dropActions: NotchFileDropActions?\n"
          + "var visibleRect = CGRect(x: 0, y: 0, width: 440, height: 400)\n"
          + "func convert(_ point: CGPoint, from: Int?) -> CGPoint { point }\n"
          + "func containsVisiblePoint(_ point: CGPoint) -> Bool { visibleRect.contains(point) }\n"
          + declaration(canvas, "    func beginDrop(")
          + declaration(canvas, "    func finishDrop(")
          + declaration(canvas, "    override func draggingUpdated(").replace("override func", "func", 1)
          + declaration(canvas, "    override func draggingExited(").replace("override func", "func", 1)
          + declaration(canvas, "    override func performDragOperation(").replace("override func", "func", 1)
          + "}\n}\n")
    write("ShortcutsExpansion.swift", "import SwiftUI\n\nextension FeatureCatalogTests {\n"
          + "final class Expansion { var features: [FeatureGroup: Set<AppFeature>] = [:] }\n"
          + "struct ShortcutsPage {\nlet state: Expansion\n"
          + "var expandedFeatures: [FeatureGroup: Set<AppFeature>] { get { state.features } nonmutating set { state.features = newValue } }\n"
          + declaration("Sources/Vorssaint/UI/Settings/ShortcutsSettings.swift", "    private func expansionBinding(").replace("private func", "func", 1)
          + "}\n}\n")
    media_workspace = "Sources/Vorssaint/UI/Media/MediaWorkspaceView.swift"
    write("MediaWorkspaceLayout.swift", "import AppKit\nimport SwiftUI\nimport UniformTypeIdentifiers\n"
          + "extension MediaWorkspaceLayoutTests {\n"
          + "struct Workspace: View {\nlet compact = true\n@ObservedObject var fixture: Fixture\n"
          + "let onContentHeightChange: ((CGFloat) -> Void)?\n"
          + "var header: some View { Color.clear.frame(height: 22) }\n"
          + "var toolPicker: some View { Color.clear.frame(height: 24) }\n"
          + "var content: some View { Color.clear.frame(height: fixture.height) }\n"
          + "var body: some View { layout }\n"
          + declaration(media_workspace, "    private var layout:")
          + "}\nstruct Input: View {\nlet inNotch: Bool\n@State var isDropTargeted = false\n"
          + "var inputSelector: some View { Color.clear.frame(width: 300, height: 70) }\n"
          + "func acceptDrop(_ providers: [NSItemProvider]) -> Bool { false }\n"
          + "var body: some View { inputDropTarget }\n"
          + declaration(media_workspace, "    @ViewBuilder private var inputDropTarget:")
          + "}\nstruct ToolPicker {\nlet fixture: Selection\nlet onToolChange: (() -> Void)?\n"
          + "var selectedTool: MediaTool { get { fixture.tool } nonmutating set { fixture.tool = newValue } }\n"
          + declaration(media_workspace, "    private var selectedToolBinding:").replace("private var", "var", 1)
          + "}\nfinal class FileView: HeightState {\n"
          + declaration("Sources/Vorssaint/UI/Notch/NotchFilesView.swift", "    private func mediaHeightChanged(").replace("private func", "func", 1)
          + "}\n}\n")
    write("MediaDialogHost.swift", "import AppKit\n\nextension MediaDialogHostContract {\nenum Dialogs {\n"
          + "static var panelModalActive = false\n"
          + declaration(media_workspace, "    private static func runPanelModal(").replace("private static", "static", 1)
          + "}\n}\n")
    write("RecorderExportChip.swift", "import AppKit\nimport SwiftUI\n\nextension RecorderExportChipTests {\n"
          + "struct Chip: View {\n@ObservedObject var model: Model\nlet strings = Strings()\n"
          + "var exportProgressLabel: String { strings.exportingLabel }\n"
          + "var body: some View { exportProgressChip }\n"
          + declaration("Sources/Vorssaint/UI/Recorder/RecorderEditorView.swift", "    private var exportProgressChip:")
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
    write("ScreenshotPreviewHover.swift", "import Foundation\n"
          + "extension ScreenshotPreviewHoverTests {\nfinal class Controller: State {\n"
          + "".join(declaration(preview, prefix).replace("private func", "func", 1)
                    for prefix in ["    private func hoverChanged(", "    private func scheduleAutoDismiss("])
          + "}\nstruct Preview {\nlet embedded: Bool\nlet hoverChanged: (Bool) -> Void\n"
          + declaration(preview, "    private func previewHoverChanged(").replace("private func", "func", 1)
          + "}\n}\n")
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
          + declaration(selection, "    private var repeatTargetPanel:").replace("private var", "var", 1)
          + declaration(selection, "    fileprivate var offersRepeatLastRegion:").replace("fileprivate var", "var", 1)
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
          + declaration(selection, "    private static func isRepeatRegionKey(")
          + declaration(selection, "    private static func matchesShortcutKey(")
          + declaration(selection, "    private func installKeyMonitor()")
          + "}\n}\n")
    hop = "Sources/Vorssaint/Services/Switcher/SpaceHop.swift"
    write("PointerOnDisplay.swift", "import AppKit\n"
          + "extension PointerOnDisplayContract.Bridge {\n"
          + declaration("Sources/Vorssaint/Services/Switcher/SpaceWindowBridge.swift", "    struct Topology {")
          + "}\nextension PointerOnDisplayContract.Hop {\n"
          + "".join(declaration(hop, prefix).replace("private ", "", 1)
                    for prefix in ["    private enum TravelOutcome {", "    private func stepWithSpaceShortcut()"])
          + "}\nextension PointerOnDisplayContract.Overlay {\n"
          + declaration(selection, "    func refreshGuideVisibility()")
          + "}\nextension PointerOnDisplayContract.Dock {\n"
          + declaration(dock, "    private func isNearDock(").replace("private func", "func", 1)
          + "}\n")

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
          + "var sources: [NotchPlaybackSource] = []\nvar sourceIsAutomatic = true\n"
          + "var artwork: NSObject?\nvar artworkTint: NotchArtworkTint?\n"
          + "func updateAutomation(for playback: NotchPlayback?) {}\nfunc setQueueVisible(_ visible: Bool) { queueVisible = visible }\n"
          + "var queueVisible = true\nvar queueLoading = false\nvar queueActionPending = false\n"
          + "var commandFailed = false\nvar queueActionFailed = false\nvar commandPending = false\n"
          + "var canSeek: Bool { playback?.canSeek == true }\n"
          + "func beginAutomation(_ command: Command, playback: NotchPlayback) -> Bool { false }\nfunc cancelAutomationAction() {}\n"
          + "var process: Process?\nvar input: Pipe?\nlet queue = Scheduler()\n"
          + "lazy var commandWriter = NotchMusicCommandWriter { [queue = self.queue] in queue.async(execute: $0) }\n"
          + "var wantsPlayback = false\nvar awaitingPlayback = false\nvar restartCount = 0\nvar restartWork: DispatchWorkItem?\nvar launches = 0\n"
          + "var selectedSourcePID: Int32?\nvar chosenSource: NotchPlaybackSource.Selection?\nvar restoringSource = false\n"
          + "var launchedAt: TimeInterval?\nvar uptime: TimeInterval = 0\n"
          + "func launch() { guard wantsPlayback, process == nil else { return }; launches += 1; process = Process(); input = Pipe(); commandWriter.start(); launchedAt = uptime; restoreSource() }\n"
          + "func disconnect() { generation = UUID(); commandWriter.stop(); process = nil; input = nil; playback = nil }\n"
          + declaration(music, "    func start()")
          + declaration(music, "    func stop()")
          + declaration(music, "    private func connectionEnded()").replace("private func", "func", 1)
            .replace("ProcessInfo.processInfo.systemUptime", "uptime")
          + declaration(music, "    private func restoreSource()").replace("private func", "func", 1)
          + declaration(music, "    private func acceptsSourceReply(").replace("private func", "func", 1)
          + declaration(music, "    func seek(")
          + declaration(music, "    func selectSource(")
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

    brightness_row = "Sources/Vorssaint/UI/MenuPanel/BrightnessSection.swift"
    write("SoftwareDimmingRow.swift", "import CoreGraphics\nimport Foundation\n\n"
          + "extension SoftwareDimmingRouteContract {\n"
          + "final class Row {\nvar display = Display()\nvar chosen = false\n"
          + declaration(brightness_row, "    private var offered:").replace("private var", "var", 1)
          + "}\n}\n")

    brightness = "Sources/Vorssaint/Services/Display/BrightnessService.swift"
    write("SoftwareDimmingRoute.swift", "import CoreGraphics\nimport Foundation\n\n"
          + "extension SoftwareDimmingRouteContract {\n"
          + "final class Service {\nlet stateLock = NSLock()\nlet workQueue = Queue()\n"
          + "static let log = Log()\n"
          + "var routes: [CGDirectDisplayID: Route] = [:]\n"
          + "var lastApplied: [CGDirectDisplayID: Double] = [:]\n"
          + "var levelKnownAt: [CGDirectDisplayID: Foundation.Date] = [:]\n"
          + "var softwareDims: [(id: CGDirectDisplayID, value: Double)] = []\n"
          + "var forgottenWriteOnlyPaths: [String] = []\nvar refreshes = 0\n"
          + "func forgetWriteOnlyDDCPath(_ path: String?) { forgottenWriteOnlyPaths.append(path ?? \"\") }\n"
          + "func applySoftwareDim(_ id: CGDirectDisplayID, value: Double) { softwareDims.append((id, value)) }\n"
          + "func refresh(force: Bool = false) { refreshes += 1 }\n"
          + declaration(brightness, "    func setSoftwareDimmingPreferred(")
          + "}\n}\n")

    keep_awake = "Sources/Vorssaint/Services/KeepAwakeManager.swift"
    keep_awake_methods = [
        "    func refreshPasswordlessStatus(",
        "    private func activate(end:",
        "    func deactivate(reason:",
        "    private func applyClamshellPreference(",
        "    private func prepareClamshellPreference(",
        "    private func finishClamshellSetup(",
        "    private func markClamshellSetupFailed(",
        "    private func enableClamshell(",
        "    private func disableClamshell(",
        "    private func sleepIfLidAlreadyClosed(",
        "    func recoverIfNeeded(",
        "    private func finishRecovery(",
        "    private var clamshellNeedsRestore:",
        "    private func finishClamshellRestore(",
        "    private func recoverDimmedDisplayIfNeeded(",
        "    private func syncLidDimmingObserver(",
        "    private func lidStateMayHaveChangedForDimming(",
        "    private func applyDimmingAction(",
        "    private func attemptDisplayRestore(",
    ]
    write("KeepAwakeLidSleep.swift", "import Foundation\nimport os\n\nextension KeepAwakeLidSleepContract {\n"
          # The extracted dimming bodies unwrap `Unmanaged<KeepAwakeManager>`
          # for the IOKit callback's context; this makes that name resolve to
          # the fixture's own class instead of leaving it undefined.
          + "typealias KeepAwakeManager = Service\n"
          + "final class Service {\n"
          + "static let log = Logger(subsystem: \"vorssaint.tests\", category: \"keep-awake\")\n"
          + "var isActive = false\nvar sessionPausedForScreenLock = false\n"
          + "var isTerminating = false\nvar clamshellEnablePending = false\nvar clamshellRestorePending = false\n"
          + "var clamshellOperationGeneration = 0\nvar clamshellSetupID: UUID?\n"
          + "var lidSleepGeneration = 0\nvar lidSleepAttemptsRemaining = 0\n"
          + "var clamshellSetupInProgress = false\nvar clamshellSetupFailed = false\n"
          + "var clamshellSetupRetried = false\nvar passwordlessClamshell = true\n"
          + "var recoveryCompleted = false\nvar screenLocked = false\nvar assertionsHeld = false\n"
          + "var endTimer: Timer?\nvar endDate: Date?\nvar sessionTrigger: SessionTrigger?\n"
          + "var activeAutomationConditions = Set<KeepAwakeAutomationCondition>()\n"
          + "var onSessionEnded: ((EndReason) -> Void)?\n"
          + "var lidDimmingNotificationPort: IONotificationPortRef?\nvar lidDimmingNotification: io_object_t = 0\n"
          + "var lidClosedForDimming: Bool?\nvar savedDisplayBrightness: Double?\n"
          + declaration(keep_awake, "    @Published private(set) var clamshellActive = false {")
                .replace("@Published private(set) ", "", 1)
          + declaration(keep_awake, "    @Published var clamshellPreferred:").replace("@Published ", "", 1)
          + declaration(keep_awake, "    @Published var dimScreenOnLidClose: Bool {").replace("@Published ", "", 1)
          + "init() { clamshellPreferred = true; dimScreenOnLidClose = false }\n"
          + "func syncScreenLockMonitoring() {}\nfunc applyAssertions() { assertionsHeld = true }\n"
          + "func releaseAssertions() { assertionsHeld = false }\nfunc scheduleEnd(at date: Date) {}\n"
          + "func startBatteryWatch() {}\nfunc stopBatteryWatch() {}\nfunc syncMouseJiggleTimer() {}\n"
          + "func stopMouseJiggleTimer() {}\nfunc stopAutomationMonitoring() {}\nfunc syncWithPreferences() {}\n"
          + "static func lidSleepIsAllowed() -> Bool { KeepAwakeAutomationSupport.lidSleepIsAllowed("
          + "systemAllowsSleep: policy, assertions: assertions) }\n"
          + "".join(declaration(keep_awake, prefix).replace("private ", "", 1) for prefix in keep_awake_methods)
          + "}\n}\n"
          + "extension KeepAwakeLidSleepContract.Sudoers {\n"
          + declaration("Sources/Vorssaint/Services/ShellSupport.swift", "    static func isConfigured()")
          + declaration("Sources/Vorssaint/Services/ShellSupport.swift", "    static func restoreSleepWithAuthorization(")
          + "}\n")
    write("KeepAwakeTimerHandoff.swift", "import Foundation\n\nextension KeepAwakeTimerHandoffContract {\n"
          + "final class Service {\nvar sessionTrigger = SessionTrigger.manual\n"
          + "var automationSuppressedUntilConditionsClear = false\n"
          + "var activeAutomationConditions: Set<KeepAwakeAutomationCondition> = []\n"
          + "var enabled: Set<KeepAwakeAutomationCondition> = []\n"
          + "var matching: Set<KeepAwakeAutomationCondition> = []\n"
          + "var requireAll = false\nvar batteryAllows = true\n"
          + "var activations: [(end: Date?, trigger: SessionTrigger)] = []\n"
          + "func automaticSessionAllowedByBatteryProtection() -> Bool { batteryAllows }\n"
          + "func currentMatchingAutomationConditions() -> Set<KeepAwakeAutomationCondition> { matching }\n"
          + "func currentEnabledAutomationConditions() -> Set<KeepAwakeAutomationCondition> { enabled }\n"
          + "func automationRequiresAllConditions() -> Bool { requireAll }\n"
          + "func activate(end: Date?, trigger: SessionTrigger) { activations.append((end, trigger)) }\n"
          + declaration(keep_awake, "    private func continueAutomaticallyAfterTimerIfNeeded()")
            .replace("private func", "func", 1)
          + "}\n}\n")

    self_uninstall = "Sources/Vorssaint/Services/SelfUninstall.swift"
    write("SelfUninstallRemoval.swift", "import Foundation\n\nextension SelfUninstallContract {\nenum Host {\n"
          + "static let bundleID = \"test\"\n"
          + "static func suspendInputInterceptors() -> Bool { events.append(\"suspend\"); return true }\n"
          + "static func restoreSleepBeforeRemoval() -> Bool { events.append(\"sleep\"); return true }\n"
          + "@discardableResult static func detachFromSystem() -> Bool { events.append(\"detach\"); return true }\n"
          + "static func removePreferences() { events.append(\"preferences\") }\n"
          + "static func trashOwnBundleAndQuit() { events.append(\"trash\") }\n"
          + declaration(self_uninstall, "    static func clearPermissions(")
          + declaration(self_uninstall, "    static func uninstallCompletely(")
          + declaration(self_uninstall, "    private static func removeSudoersRuleIfPresent(")
          + declaration(self_uninstall, "    private static func resetTCC(")
            .replace("private static", "@discardableResult static", 1)
          + "}\n}\n")

    downloads = "Sources/Vorssaint/Services/Notch/NotchDownloadService.swift"
    write("NotchDownloadFolderChoice.swift", "import Foundation\n\nextension NotchDownloadFolderChoiceContract {\n"
          + "final class Service {\nvar chooser: NSOpenPanel?\nvar chooserID = UUID()\nvar chooserInNotch = false\n"
          + "var folderUnavailable = false\nvar syncs = 0\nvar stops = 0\n"
          + "func syncWithPreferences() { syncs += 1 }\n"
          + "func stop() { stops += 1; cancelFolderChoice() }\n"
          + declaration(downloads, "    func chooseFolder()")
          + declaration(downloads, "    private func folderPickerParent()")
          + declaration(downloads, "    private func canReturnToDownloads(")
          + declaration(downloads, "    private func cancelFolderChoice()")
          + declaration(downloads, "    func cancelNotchFolderChoice()")
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
