// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine

/// Window zones: hold Shift while dragging a window and the layout of that
/// display appears; drop the window and it takes the zone under the pointer.
/// Control (or a middle click) spans several zones, the scroll wheel switches
/// between the quick-switch layouts, and keyboard shortcuts move the focused
/// window between zones.
///
/// The pointer tap only listens: it copies scalars and returns, and the drag
/// is decided on the main queue from the window server's frames, so a press
/// inside an app never asks that app anything. Accessibility is used once a
/// drop lands on a zone, through the same placement path as Window Layout.
final class WindowZonesService: ObservableObject {
    static let shared = WindowZonesService()

    @Published private(set) var configuration = WindowZonesConfiguration()
    @Published private(set) var failedShortcuts: Set<String> = []

    /// True while a drag shows zones, so edge snapping stands aside.
    private(set) var isShowingZones = false

    private struct Display {
        let key: String
        let screen: NSScreen
        let workArea: WindowZoneRect
        let space: UInt64?
    }

    private struct PendingPress {
        let candidate: WindowServerWindowCandidate
        let origin: CGPoint
        let inTitleBar: Bool
        var checks = 0
    }

    private struct ActiveDrag {
        let candidate: WindowServerWindowCandidate
        var pointer: CGPoint
        var flags: CGEventFlags
        var spanToggled = false
        var anchor: [Int]?
        var displayKey: String?
        var highlighted: [Int] = []
    }

    /// A window this service placed, with what it needs to come back to it.
    private struct ZonedWindow {
        let target: WindowLayoutTarget
        var assignment: WindowZoneAssignment
        /// The size it had before its first zone, for dragging it out again.
        let unzonedSize: CGSize
    }

    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var pending: PendingPress?
    private var drag: ActiveDrag?
    private var zoned: [CGWindowID: ZonedWindow] = [:]
    private var extensionState: WindowZoneNavigation.Extension?
    private var history = WindowZoneHistory()
    private var overlays: [String: NSPanel] = [:]
    private var flashGeneration = 0

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var hotKeyHandler: EventHandlerRef?
    private var registeredShortcuts: [UInt32: GlobalShortcut] = [:]

    private var appObservers: [pid_t: AXObserver] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var running = false

    private static let hotKeySignature: OSType = 0x565A_4F4E // 'VZON'
    private static let editorHotKey: UInt32 = 20
    private static let quickLayoutHotKeyBase: UInt32 = 10
    private static let moveHotKeys: [UInt32: WindowZoneDirection] = [1: .left, 2: .right, 3: .up, 4: .down]
    private static let extendHotKeys: [UInt32: WindowZoneDirection] = [5: .left, 6: .right, 7: .up, 8: .down]
    private static let digitKeyCodes: [Int] = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                                               kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
    /// Window Layout owns Control-Option with the arrows, so zone moves add Shift.
    static let moveModifiers: GlobalShortcutModifiers = [.control, .option, .shift]
    static let extendModifiers: GlobalShortcutModifiers = [.control, .option, .shift, .command]
    static let quickLayoutModifiers: GlobalShortcutModifiers = [.control, .option, .shift]

    private init() {
        configuration = WindowZonesConfiguration.decode(
            UserDefaults.standard.data(forKey: DefaultsKey.windowZonesConfiguration))
        history = WindowZoneHistory.decode(UserDefaults.standard.data(forKey: DefaultsKey.windowZonesHistory))
    }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let wanted = AppFeature.windowLayout.isAvailable && defaults.bool(forKey: DefaultsKey.windowZonesEnabled)
        let trusted = SessionActivitySupport.tapShouldRun(featureWanted: wanted,
                                                          accessibilityGranted: AXIsProcessTrusted(),
                                                          sessionIsActive: SessionActivity.shared.isActive)
        let frontmost = NSWorkspace.shared.frontmostApplication
        let inputAllowed = !WindowLayoutIgnoredApps.shared.contains(
            bundleID: frontmost?.bundleIdentifier, executablePath: frontmost?.executableURL?.path)
        guard wanted, trusted else {
            suspend()
            return
        }
        running = true
        inputAllowed ? startTap() : stopTap()
        if inputAllowed, !ShortcutCapture.isCapturing { registerHotKeys() } else { unregisterHotKeys() }
        syncAppObservers(wanted: defaults.bool(forKey: DefaultsKey.windowZonesMoveNewWindows))
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                // Displays settle over a moment after a change.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.replaceZonedWindows(onDisplay: nil) }
            }
        }
    }

    /// Stops every hook. Idempotent, like Window Layout's own suspend.
    func suspend() {
        running = false
        stopTap()
        unregisterHotKeys()
        syncAppObservers(wanted: false)
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        endDrag()
        zoned.removeAll()
    }

    // MARK: - Configuration

    func updateConfiguration(_ change: (inout WindowZonesConfiguration) -> Void) {
        var next = configuration
        change(&next)
        guard next != configuration else { return }
        let previous = configuration
        configuration = next
        UserDefaults.standard.set(next.encoded, forKey: DefaultsKey.windowZonesConfiguration)
        // Windows follow a layout that changed under them.
        for display in displays() where layout(for: display, in: previous) != layout(for: display, in: next) {
            replaceZonedWindows(onDisplay: display.key)
        }
    }

    private var perSpace: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.windowZonesPerSpace) }

    private func layout(for display: Display, in configuration: WindowZonesConfiguration? = nil) -> WindowZoneLayout {
        let configuration = configuration ?? self.configuration
        return configuration.refreshed(configuration.layout(forDisplay: display.key, space: display.space,
                                                            perSpace: perSpace))
    }

    private func zones(for display: Display) -> [WindowZoneRect] {
        WindowZoneGeometry.zones(for: layout(for: display), in: display.workArea,
                                 customLayouts: configuration.customLayouts)
    }

    /// The layout and zones of every connected display, for the settings and
    /// the editor.
    struct DisplaySummary: Identifiable, Equatable {
        let id: String
        let name: String
        let size: CGSize
        let space: UInt64?
        let layout: WindowZoneLayout
    }

    func displaySummaries() -> [DisplaySummary] {
        displays().map {
            DisplaySummary(id: $0.key, name: $0.screen.localizedName,
                           size: CGSize(width: $0.workArea.width, height: $0.workArea.height),
                           space: $0.space, layout: layout(for: $0))
        }
    }

    /// Applies `layout` to a display: to its current Space only while layouts
    /// follow Spaces and `currentSpaceOnly`, to all of them otherwise.
    func apply(_ layout: WindowZoneLayout, toDisplay key: String, currentSpaceOnly: Bool) {
        let space = displays().first { $0.key == key }?.space
        updateConfiguration {
            $0.setLayout(layout, forDisplay: key, space: currentSpaceOnly ? space : nil,
                         perSpace: currentSpaceOnly && perSpace)
        }
        flashZones(onDisplay: key)
    }

    // MARK: - Displays

    private func displays() -> [Display] {
        let screens = NSScreen.screens
        let mainTop = screens.first?.frame.maxY ?? 0
        let topology = perSpace ? SpaceWindowBridge.topology() : nil
        return screens.compactMap { screen in
            guard let key = Self.displayKey(for: screen.displayID) else { return nil }
            let visible = screen.windowLayoutVisibleFrame
            let area = WindowZoneRect(CGRect(x: visible.minX, y: mainTop - visible.maxY,
                                             width: visible.width, height: visible.height))
            let space = topology?.displays.first { $0.displayID == screen.displayID }?.currentSpace
            return Display(key: key, screen: screen, workArea: area, space: space)
        }
    }

    private func display(containing point: CGPoint, in displays: [Display]) -> Display? {
        let mainTop = NSScreen.screens.first?.frame.maxY ?? 0
        return displays.first { display in
            let frame = display.screen.frame
            return CGRect(x: frame.minX, y: mainTop - frame.maxY, width: frame.width, height: frame.height)
                .contains(point)
        }
    }

    private func display(for rect: WindowZoneRect, in displays: [Display]) -> Display? {
        func overlap(_ display: Display) -> CGFloat {
            let shared = display.workArea.cgRect.intersection(rect.cgRect)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        return displays.max { overlap($0) < overlap($1) }
    }

    static func displayKey(for displayID: CGDirectDisplayID) -> String? {
        guard displayID != 0, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let text = CFUUIDCreateString(nil, uuid) else { return nil }
        return text as String
    }

    // MARK: - Pointer tap

    private func startTap() {
        guard tap == nil else { return }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged,
                                    .otherMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<WindowZonesService>.fromOpaque(userInfo).takeUnretainedValue()
                service.observe(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        tap = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        tapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func stopTap() {
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
        tapSource = nil
        endDrag()
    }

    private enum PointerInput {
        case down(CGPoint), dragged(CGPoint, CGEventFlags), up, flags(CGEventFlags), middle, wheel(up: Bool)
    }

    /// Runs on the tap: copies what it needs and leaves.
    private func observe(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            DispatchQueue.main.async { [weak self] in self?.endDrag() }
            return
        }
        let input: PointerInput
        switch type {
        case .leftMouseDown: input = .down(event.location)
        case .leftMouseDragged: input = .dragged(event.location, event.flags)
        case .leftMouseUp: input = .up
        case .flagsChanged: input = .flags(event.flags)
        case .otherMouseDown:
            guard event.getIntegerValueField(.mouseEventButtonNumber) == 2 else { return }
            input = .middle
        case .scrollWheel:
            let delta = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            guard delta != 0 else { return }
            input = .wheel(up: delta > 0)
        default: return
        }
        DispatchQueue.main.async { [weak self] in self?.handle(input) }
    }

    private func handle(_ input: PointerInput) {
        switch input {
        case .down(let location):
            endDrag()
            guard running,
                  let candidate = WindowServerWindowHitTest.candidate(at: location, pidIsEligible: { pid in
                      guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
                      return !app.isTerminated && app.activationPolicy == .regular
                          && !WindowLayoutIgnoredApps.shared.contains(bundleID: app.bundleIdentifier,
                                                                      executablePath: app.executableURL?.path)
                  })
            else { return }
            pending = PendingPress(candidate: candidate, origin: location,
                                   inTitleBar: WindowZoneDragClassifier.pressIsInTitleBar(location,
                                                                                          frame: candidate.frame))
        case .dragged(let location, let flags):
            if drag != nil {
                drag?.pointer = location
                drag?.flags = flags
                updateDrag()
                return
            }
            guard var press = pending,
                  abs(location.x - press.origin.x) + abs(location.y - press.origin.y) >= 4 else { return }
            press.checks += 1
            guard let now = WindowServerSupport.frame(ofWindowID: press.candidate.windowID) else {
                pending = nil
                return
            }
            switch WindowZoneDragClassifier.classify(start: press.candidate.frame, now: now,
                                                     pressInTitleBar: press.inTitleBar) {
            case .resizing:
                pending = nil
            case .moving:
                pending = nil
                drag = ActiveDrag(candidate: press.candidate, pointer: location, flags: flags)
                updateDrag()
            case .undecided:
                // A drag inside the window's content, not a move of it.
                pending = press.checks > 40 ? nil : press
            }
        case .flags(let flags):
            guard drag != nil else { return }
            drag?.flags = flags
            updateDrag()
        case .middle:
            guard drag != nil else { return }
            drag?.spanToggled.toggle()
            updateDrag()
        case .wheel(let up):
            guard isShowingZones, UserDefaults.standard.bool(forKey: DefaultsKey.windowZonesWheelSwitch),
                  let key = drag?.displayKey, let display = displays().first(where: { $0.key == key }),
                  let next = configuration.cycled(from: layout(for: display), forward: up) else { return }
            updateConfiguration { $0.setLayout(next, forDisplay: key, space: display.space, perSpace: perSpace) }
            drag?.anchor = nil
            updateDrag()
        case .up:
            pending = nil
            guard let finished = drag else { return }
            let shown = isShowingZones
            endDrag()
            // One turn later the app has finished its own move.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                self?.drop(finished, zonesShown: shown)
            }
        }
    }

    private func zonesWanted(for flags: CGEventFlags) -> Bool {
        let shiftDrag = UserDefaults.standard.bool(forKey: DefaultsKey.windowZonesShiftDrag)
        return flags.contains(.maskShift) == shiftDrag
    }

    private func updateDrag() {
        guard var current = drag else { return }
        guard zonesWanted(for: current.flags) else {
            current.anchor = nil
            current.highlighted = []
            drag = current
            isShowingZones = false
            hideOverlays()
            return
        }
        let all = displays()
        guard let display = display(containing: current.pointer, in: all) else { return }
        let zones = zones(for: display)
        if current.displayKey != display.key {
            current.anchor = nil
            current.displayKey = display.key
        }
        let layout = layout(for: display)
        let under = WindowZoneGeometry.zones(at: current.pointer, in: zones,
                                             sensitivity: layout.sensitivityRadius, policy: overlapPolicy)
        let spanning = current.flags.contains(.maskControl) != current.spanToggled
        if spanning {
            if current.anchor == nil, !under.isEmpty { current.anchor = under }
            current.highlighted = WindowZoneGeometry.combinedRange(current.anchor ?? [], under, in: zones)
        } else {
            current.anchor = nil
            current.highlighted = under
        }
        drag = current
        isShowingZones = true
        let showAll = UserDefaults.standard.bool(forKey: DefaultsKey.windowZonesShowAllDisplays)
        for each in all {
            if each.key == display.key {
                showOverlay(on: each, zones: zones, highlighted: current.highlighted)
            } else if showAll {
                showOverlay(on: each, zones: self.zones(for: each), highlighted: [])
            } else {
                overlays[each.key]?.orderOut(nil)
            }
        }
    }

    private func endDrag() {
        drag = nil
        pending = nil
        isShowingZones = false
        hideOverlays()
    }

    private var overlapPolicy: WindowZoneOverlapPolicy {
        WindowZoneOverlapPolicy(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.windowZonesOverlapPolicy)
                                ?? "") ?? .smallest
    }

    private func drop(_ finished: ActiveDrag, zonesShown: Bool) {
        let windowID = finished.candidate.windowID
        guard let target = WindowLayoutService.shared.zoneTarget(processID: finished.candidate.pid,
                                                                 windowID: windowID) else { return }
        if zonesShown, let key = finished.displayKey, !finished.highlighted.isEmpty,
           let display = displays().first(where: { $0.key == key }) {
            place(target, on: display, zones: finished.highlighted,
                  historyFrame: WindowLayoutFrame(origin: finished.candidate.frame.origin,
                                                  size: finished.candidate.frame.size))
            return
        }
        // Dragged out of its zone: back to the size it had before.
        guard let previous = zoned.removeValue(forKey: windowID),
              UserDefaults.standard.bool(forKey: DefaultsKey.windowZonesRestoreSize),
              previous.unzonedSize != target.frame.size,
              let display = displays().first(where: { $0.key == previous.assignment.displayKey }),
              WindowZoneGeometry.window(WindowZoneRect(finished.candidate.frame), fills: previous.assignment.zones,
                                        of: zones(for: display)) else { return }
        WindowLayoutService.shared.placeInZone(target, rect: CGRect(origin: target.frame.origin,
                                                                   size: previous.unzonedSize))
    }

    @discardableResult
    private func place(_ target: WindowLayoutTarget, on display: Display, zones ids: [Int],
                       historyFrame: WindowLayoutFrame? = nil) -> Bool {
        let zones = zones(for: display)
        guard let bounds = WindowZoneGeometry.bounds(of: ids, in: zones),
              WindowLayoutService.shared.placeInZone(target, rect: bounds.cgRect, historyFrame: historyFrame)
        else { return false }
        let windowID = target.key.windowID
        let unzoned = zoned[windowID]?.unzonedSize ?? historyFrame?.size ?? target.frame.size
        zoned[windowID] = ZonedWindow(target: target,
                                      assignment: WindowZoneAssignment(displayKey: display.key, zones: ids),
                                      unzonedSize: unzoned)
        if let app = NSRunningApplication(processIdentifier: target.key.processID),
           let bundleID = app.bundleIdentifier {
            history.record(.init(displayKey: display.key, layout: layout(for: display), zones: ids), for: bundleID)
            UserDefaults.standard.set(history.encoded, forKey: DefaultsKey.windowZonesHistory)
            if UserDefaults.standard.bool(forKey: DefaultsKey.windowZonesMoveNewWindows) { observe(app) }
        }
        return true
    }

    /// Puts zoned windows back into their zones after a display or layout
    /// change. A window whose zones no longer exist is let go.
    private func replaceZonedWindows(onDisplay key: String?) {
        guard running, !zoned.isEmpty else { return }
        let all = displays()
        let alive = Set((CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
        for (windowID, window) in zoned {
            guard alive.contains(windowID) else {
                zoned[windowID] = nil
                continue
            }
            guard key == nil || window.assignment.displayKey == key else { continue }
            guard let display = all.first(where: { $0.key == window.assignment.displayKey }),
                  window.assignment.zones.allSatisfy({ zones(for: display).indices.contains($0) }),
                  let target = WindowLayoutService.shared.zoneTarget(processID: window.target.key.processID,
                                                                     windowID: windowID)
            else {
                zoned[windowID] = nil
                continue
            }
            place(target, on: display, zones: window.assignment.zones)
        }
    }

    // MARK: - Overlay

    private func colors() -> WindowZoneColors {
        let defaults = UserDefaults.standard
        return WindowZoneColors(
            fill: defaults.string(forKey: DefaultsKey.windowZonesFillColor) ?? WindowZoneColors.standard.fill,
            border: defaults.string(forKey: DefaultsKey.windowZonesBorderColor) ?? WindowZoneColors.standard.border,
            highlight: defaults.string(forKey: DefaultsKey.windowZonesHighlightColor)
                ?? WindowZoneColors.standard.highlight,
            opacity: defaults.object(forKey: DefaultsKey.windowZonesOpacity) as? Double
                ?? WindowZoneColors.standard.opacity)
    }

    private func showOverlay(on display: Display, zones: [WindowZoneRect], highlighted: [Int]) {
        let panel = overlays[display.key] ?? makeOverlayPanel()
        overlays[display.key] = panel
        if panel.frame != display.screen.frame { panel.setFrame(display.screen.frame, display: false) }
        guard let view = panel.contentView as? WindowZonesOverlayView else { return }
        let mainTop = NSScreen.screens.first?.frame.maxY ?? 0
        let origin = CGPoint(x: display.screen.frame.minX, y: mainTop - display.screen.frame.maxY)
        view.update(zones: zones.map { $0.cgRect.offsetBy(dx: -origin.x, dy: -origin.y) },
                    highlighted: Set(highlighted), colors: colors(),
                    showNumbers: UserDefaults.standard.bool(forKey: DefaultsKey.windowZonesShowNumbers))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func hideOverlays() {
        flashGeneration += 1
        for panel in overlays.values { panel.orderOut(nil) }
    }

    /// Shows a display's zones for a moment after its layout changed.
    func flashZones(onDisplay key: String) {
        guard drag == nil, let display = displays().first(where: { $0.key == key }) else { return }
        showOverlay(on: display, zones: zones(for: display), highlighted: [])
        flashGeneration += 1
        let generation = flashGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, generation == self.flashGeneration, self.drag == nil else { return }
            self.overlays[key]?.orderOut(nil)
        }
    }

    private func makeOverlayPanel() -> NSPanel {
        let panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none
        panel.contentView = WindowZonesOverlayView(frame: .zero)
        return panel
    }

    // MARK: - Keyboard

    private func wantedShortcuts() -> [UInt32: GlobalShortcut] {
        let defaults = UserDefaults.standard
        var shortcuts: [UInt32: GlobalShortcut] = [:]
        if defaults.bool(forKey: DefaultsKey.windowZonesKeyboardEnabled) {
            let arrows = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow]
            for (index, keyCode) in arrows.enumerated() {
                shortcuts[UInt32(index + 1)] = GlobalShortcut(keyCode: Int64(keyCode), modifiers: Self.moveModifiers)
                shortcuts[UInt32(index + 5)] = GlobalShortcut(keyCode: Int64(keyCode), modifiers: Self.extendModifiers)
            }
        }
        if defaults.bool(forKey: DefaultsKey.windowZonesQuickSwitchEnabled) {
            for (digit, keyCode) in Self.digitKeyCodes.enumerated()
            where configuration.quickLayouts[String(digit)] != nil {
                shortcuts[Self.quickLayoutHotKeyBase + UInt32(digit)] =
                    GlobalShortcut(keyCode: Int64(keyCode), modifiers: Self.quickLayoutModifiers)
            }
        }
        shortcuts[Self.editorHotKey] = GlobalShortcut.saved(for: DefaultsKey.windowZonesEditorShortcut,
                                                            fallback: .windowZonesEditorDefault)
        return shortcuts
    }

    /// Shortcut ids by how the settings name them, for the failure notice.
    static func shortcutName(_ id: UInt32) -> String {
        switch id {
        case editorHotKey: return "editor"
        case quickLayoutHotKeyBase..<(quickLayoutHotKeyBase + 10): return "layout\(id - quickLayoutHotKeyBase)"
        default: return extendHotKeys[id] != nil ? "extend" : "move"
        }
    }

    private func registerHotKeys() {
        let wanted = wantedShortcuts()
        guard wanted != registeredShortcuts || hotKeyRefs.count != wanted.count else { return }
        unregisterHotKeys()
        if hotKeyHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                guard hotKeyID.signature == WindowZonesService.hotKeySignature else {
                    return OSStatus(eventNotHandledErr)
                }
                let service = Unmanaged<WindowZonesService>.fromOpaque(userData).takeUnretainedValue()
                let id = hotKeyID.id
                DispatchQueue.main.async { service.perform(hotKey: id) }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        }
        var failed = Set<String>()
        for (id, shortcut) in wanted {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.modifiers.carbonFlags,
                                             EventHotKeyID(signature: Self.hotKeySignature, id: id),
                                             GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref { hotKeyRefs[id] = ref } else { failed.insert(Self.shortcutName(id)) }
        }
        registeredShortcuts = wanted
        if failed != failedShortcuts { failedShortcuts = failed }
    }

    private func unregisterHotKeys() {
        for ref in hotKeyRefs.values { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        registeredShortcuts.removeAll()
    }

    private func perform(hotKey id: UInt32) {
        guard running else { return }
        if id == Self.editorHotKey {
            WindowZonesEditorWindow.shared.show()
        } else if let direction = Self.moveHotKeys[id] {
            moveFocusedWindow(direction, extend: false)
        } else if let direction = Self.extendHotKeys[id] {
            moveFocusedWindow(direction, extend: true)
        } else if id >= Self.quickLayoutHotKeyBase, id < Self.quickLayoutHotKeyBase + 10 {
            applyQuickLayout(String(id - Self.quickLayoutHotKeyBase))
        }
    }

    private func applyQuickLayout(_ key: String) {
        guard let layout = configuration.quickLayouts[key] else { return }
        let all = displays()
        let point = NSEvent.mouseLocation
        let mainTop = NSScreen.screens.first?.frame.maxY ?? 0
        guard let display = display(containing: CGPoint(x: point.x, y: mainTop - point.y), in: all) else { return }
        apply(configuration.refreshed(layout), toDisplay: display.key, currentSpaceOnly: true)
    }

    private func moveFocusedWindow(_ direction: WindowZoneDirection, extend: Bool) {
        guard let target = WindowLayoutService.shared.focusedZoneTarget(),
              let app = NSRunningApplication(processIdentifier: target.key.processID),
              !WindowLayoutIgnoredApps.shared.contains(bundleID: app.bundleIdentifier,
                                                       executablePath: app.executableURL?.path)
        else { return }
        let all = displays()
        let rect = WindowZoneRect(CGRect(origin: target.frame.origin, size: target.frame.size))
        // A window moved or resized since (by hand, a layout shortcut or
        // another tool) no longer sits in its zones, so it starts afresh.
        var assignment = zoned[target.key.windowID]?.assignment
        if let current = assignment,
           !WindowZoneGeometry.window(rect, fills: current.zones,
                                      of: all.first { $0.key == current.displayKey }.map(zones(for:)) ?? []) {
            assignment = nil
            zoned[target.key.windowID] = nil
            extensionState = nil
        }
        let currentKey = assignment?.displayKey ?? display(for: rect, in: all)?.key
        guard let currentIndex = all.firstIndex(where: { $0.key == currentKey }) else { return }
        let areas = all.map { WindowZoneArea(displayKey: $0.key, workArea: $0.workArea, zones: zones(for: $0)) }
        if extend {
            guard let ids = WindowZoneNavigation.extend(window: rect, windowID: target.key.windowID,
                                                        area: areas[currentIndex],
                                                        assigned: assignment?.zones ?? [],
                                                        state: &extensionState, direction: direction) else { return }
            place(target, on: all[currentIndex], zones: ids)
            return
        }
        extensionState = nil
        guard let next = WindowZoneNavigation.snap(
            window: rect, current: currentIndex, areas: areas, assigned: assignment, direction: direction,
            acrossDisplays: UserDefaults.standard.bool(forKey: DefaultsKey.windowZonesAcrossDisplays)),
              let display = all.first(where: { $0.key == next.displayKey }) else { return }
        place(target, on: display, zones: next.zones)
    }

    // MARK: - New windows

    private func syncAppObservers(wanted: Bool) {
        guard wanted, running else {
            for observer in appObservers.values {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            }
            appObservers.removeAll()
            for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            workspaceObservers.removeAll()
            return
        }
        if workspaceObservers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            workspaceObservers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                         object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.observe(app)
            })
            workspaceObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                                         object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let observer = self?.appObservers.removeValue(forKey: app.processIdentifier) else { return }
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            })
        }
        for app in NSWorkspace.shared.runningApplications { observe(app) }
    }

    /// Only apps with a zone to go back to are watched, so most apps are
    /// never asked anything.
    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard appObservers[pid] == nil, app.activationPolicy == .regular,
              pid != ProcessInfo.processInfo.processIdentifier,
              let bundleID = app.bundleIdentifier, history.apps[bundleID] != nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, element, _, refcon in
            guard let refcon else { return }
            let service = Unmanaged<WindowZonesService>.fromOpaque(refcon).takeUnretainedValue()
            var pid = pid_t(0)
            AXUIElementGetPid(element, &pid)
            // Apps often place a new window themselves first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { service.windowCreated(element, processID: pid) }
        }, &observer) == .success, let observer else { return }
        let element = AXUIElementCreateApplication(pid)
        guard AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString,
                                        Unmanaged.passUnretained(self).toOpaque()) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        appObservers[pid] = observer
    }

    private func windowCreated(_ window: AXUIElement, processID: pid_t) {
        guard running, UserDefaults.standard.bool(forKey: DefaultsKey.windowZonesMoveNewWindows),
              let app = NSRunningApplication(processIdentifier: processID),
              let bundleID = app.bundleIdentifier, let entry = history.apps[bundleID],
              !WindowLayoutIgnoredApps.shared.contains(bundleID: bundleID, executablePath: app.executableURL?.path),
              let display = displays().first(where: { $0.key == entry.displayKey }),
              layout(for: display).isSameLayout(as: entry.layout),
              let target = WindowLayoutService.shared.zoneTarget(for: window, processID: processID),
              zoned[target.key.windowID] == nil
        else { return }
        place(target, on: display, zones: entry.zones)
    }
}

/// Draws one display's zones: a translucent fill, a border, the zone number,
/// and the zones the drop would take in the highlight color.
final class WindowZonesOverlayView: NSView {
    private var zones: [CGRect] = []
    private var highlighted: Set<Int> = []
    private var colors = WindowZoneColors.standard
    private var showNumbers = true

    override var isFlipped: Bool { true }

    func update(zones: [CGRect], highlighted: Set<Int>, colors: WindowZoneColors, showNumbers: Bool) {
        guard zones != self.zones || highlighted != self.highlighted || colors != self.colors
                || showNumbers != self.showNumbers else { return }
        self.zones = zones
        self.highlighted = highlighted
        self.colors = colors
        self.showNumbers = showNumbers
        needsDisplay = true
    }

    private func color(_ hex: String, alpha: Double) -> NSColor {
        guard let parts = WindowZoneColors.components(hex) else { return NSColor.controlAccentColor.withAlphaComponent(alpha) }
        return NSColor(srgbRed: parts.red, green: parts.green, blue: parts.blue, alpha: alpha)
    }

    override func draw(_ dirtyRect: NSRect) {
        let opacity = min(max(colors.opacity, 0.05), 1)
        for (index, zone) in zones.enumerated() {
            let rect = zone.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
            let isHighlighted = highlighted.contains(index)
            color(isHighlighted ? colors.highlight : colors.fill, alpha: opacity).setFill()
            path.fill()
            color(colors.border, alpha: min(opacity + 0.3, 1)).setStroke()
            path.lineWidth = 2
            path.stroke()
            guard showNumbers else { continue }
            let text = "\(index + 1)" as NSString
            let size = min(max(min(rect.width, rect.height) / 4, 14), 64)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.85),
            ]
            let measured = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2),
                      withAttributes: attributes)
        }
    }
}
