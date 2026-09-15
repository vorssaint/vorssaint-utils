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


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
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
          + declaration(playback_adapter, "    static func readInfo(")
          + declaration(playback_adapter, "    static func supportedCommands(")
          + declaration(playback_adapter, "    static func send(")
          + declaration(playback_adapter, "    private static func makeTarget(").replace("private static", "static", 1) + "}\n")
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
    write("NotchPresentationRefresh.swift", "import Foundation\nimport Combine\n"
          + "extension NotchPresentationRefreshContract {\nfinal class Service: State {\n"
          + declaration(notch, "    func refreshPresentation(")
          + declaration(notch, "    func updateCaptureHeight(")
          + declaration(notch, "    func removeCapture(")
          + declaration(notch, "    private func clearCapture(")
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
    write("QuickLauncherBodies.swift", "import Foundation\n" + protocol + "\n\nextension QuickLauncherContract {\n"
          + declaration(service, "enum QuickLauncherItem:")
          + "final class Launcher {\nvar isEditing = false\nvar activeUtility: QuickLauncherItem?\n"
          + 'func hide() { events.append("hide") }\n'
          + declaration(service, "    func run(_ item: QuickLauncherItem)")
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
    write("NotchQueueSelection.swift", "import Foundation\n\nextension NotchQueueContract {\n"
          + "final class Service {\nvar queueVisible = true\nvar queueRequest: UUID?\n"
          + "var upcoming: NotchQueueSnapshot?\nvar playback: NotchPlayback?\n"
          + "var queueActionFailed = false\nvar queueActionPending = false\nvar sendAllowed = true\n"
          + "var commands: [NotchPlaybackCommand] = []\n"
          + "func send(_ command: NotchPlaybackCommand) -> Bool { commands.append(command); return sendAllowed && command.message != nil }\n"
          + declaration(music, "    func playQueued(")
          + "}\n}\n")

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
