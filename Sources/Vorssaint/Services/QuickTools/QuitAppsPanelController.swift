// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// The Quit apps window (issue #855): every open app with its own Quit button,
/// plus Quit all and Quit all except the front app. Every entry point opens
/// it, so nothing quits in bulk without the list in front of the user first.
final class QuitAppsPanelController {
    static let shared = QuitAppsPanelController()

    private var panel: QuitAppsPanel?
    private var model: QuitAppsModel?
    private var keyMonitor: Any?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var rowsSubscription: AnyCancellable?
    private var typedPrefix = ""
    private var lastTypedAt = Date.distantPast

    /// How long a row shows its spinner before an app that is still running
    /// (it asked to save, or refused) gets its Quit button back.
    private static let quitSettleDelay: TimeInterval = 4
    /// A pause this long starts a new type-to-jump prefix, as in Finder.
    private static let typeAheadReset: TimeInterval = 1

    private init() {}

    func show(scope: QuitAppsScope, frontmostPID: pid_t?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.show(scope: scope, frontmostPID: frontmostPID) }
            return
        }
        if let panel, let model {
            model.scope = scope
            model.frontmostPID = frontmostPID
            model.reload()
            model.focus = .button(model.restingButton)
            panel.orderFrontRegardless()
            panel.makeKey()
            return
        }

        let model = QuitAppsModel(scope: scope, frontmostPID: frontmostPID)
        model.reload()
        model.focus = .button(model.restingButton)
        self.model = model

        let content = QuitAppsView(
            model: model,
            strings: FeatureStrings.quickToggles(L10n.shared.language),
            cancelTitle: L10n.shared.s.uninstallerCancel,
            quitOne: { [weak self] pid in self?.quitOne(pid) },
            activate: { [weak self] focus in self?.activate(focus) })
        let host = NSHostingController(rootView: content)
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize

        let panel = QuitAppsPanel(
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
        // The originating island can stay pinned above the status bar.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .transient, .ignoresCycle]

        // Centered a little above the middle of the screen under the pointer,
        // where a launcher's confirmation sits.
        let visible = NSScreen.pointerVisibleFrame
        let origin = CGPoint(x: visible.midX - size.width / 2,
                             y: visible.midY - size.height / 2 + visible.height * 0.12)
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
        self.panel = panel

        installMonitors(for: panel)
        observeWorkspace(model)
        rowsSubscription = model.$rows
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.fitToContent() }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        for monitor in [keyMonitor, localMonitor, globalMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        localMonitor = nil
        globalMonitor = nil
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { center.removeObserver(observer) }
        workspaceObservers = []
        rowsSubscription = nil
        typedPrefix = ""
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    /// Return on the highlight, or a click on a batch button.
    private func activate(_ focus: QuitAppsFocus) {
        switch focus {
        case .row(let pid): quitOne(pid)
        case .button(.cancel): close()
        case .button(.all): quitAll(.all)
        case .button(.allExceptFront): quitAll(.allExceptFront)
        }
    }

    private func quitOne(_ pid: pid_t) {
        guard let model, !model.quitting.contains(pid) else { return }
        model.quitting.insert(pid)
        guard QuickTogglesService.shared.quitApp(pid: pid) else {
            model.quitting.remove(pid)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.quitSettleDelay) { [weak model] in
            model?.quitting.remove(pid)
        }
    }

    private func quitAll(_ scope: QuitAppsScope) {
        let keeping = scope == .allExceptFront ? model?.frontmostPID : nil
        // A button's own action may still be on the stack; tear the host down after it.
        DispatchQueue.main.async { [weak self] in
            self?.close()
            QuickTogglesService.shared.quitAllApps(keepingPID: keeping)
        }
    }

    /// Keeps the top edge where it is while rows come and go.
    private func fitToContent() {
        guard let panel, let view = panel.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    private func observeWorkspace(_ model: QuitAppsModel) {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [NSWorkspace.didLaunchApplicationNotification,
                              NSWorkspace.didTerminateApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak model] _ in
                model?.reload()
            }
        }
    }

    // MARK: - Keyboard

    /// Every key that reaches the window is handled or swallowed here, so a
    /// stray key never beeps.
    private func handleKey(_ event: NSEvent) {
        guard let model else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case kVK_Escape:
            close()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard !event.isARepeat else { return }
            if flags.contains(.command), flags.contains(.option) {
                if model.buttons.contains(.allExceptFront) { quitAll(.allExceptFront) }
            } else if flags.contains(.command) {
                if model.buttons.contains(.all) { quitAll(.all) }
            } else {
                activate(model.focus)
            }
        case kVK_Delete where flags.contains(.command):
            guard !event.isARepeat else { return }
            if case .row(let pid) = model.focus { quitOne(pid) }
        case kVK_UpArrow: model.move(.up)
        case kVK_DownArrow: model.move(.down)
        case kVK_LeftArrow: model.move(.left)
        case kVK_RightArrow: model.move(.right)
        case kVK_Tab: model.move(flags.contains(.shift) ? .previous : .next)
        default:
            guard flags.isDisjoint(with: [.command, .control]),
                  let typed = event.characters, !typed.isEmpty,
                  typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else { return }
            let now = Date()
            if now.timeIntervalSince(lastTypedAt) > Self.typeAheadReset { typedPrefix = "" }
            lastTypedAt = now
            typedPrefix += typed
            if let pid = QuickTogglesSupport.quitAppsRow(
                matching: typedPrefix, in: model.rows.map { ($0.pid, $0.name) }) {
                model.focus = .row(pid)
            }
        }
    }

    private func installMonitors(for panel: NSPanel) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.window === panel else { return event }
            self?.handleKey(event)
            return nil
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.window !== self?.panel { self?.close() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if !AssistiveKeyboard.ownsCocoaPoint(NSEvent.mouseLocation) { self?.close() }
        }
    }
}

/// The open apps the window lists, rebuilt whenever an app launches or quits,
/// and the one highlight that moves through rows and buttons.
final class QuitAppsModel: ObservableObject {
    struct Row: Identifiable {
        let pid: pid_t
        let name: String
        let icon: NSImage
        let isKept: Bool
        let isFrontmost: Bool

        var id: pid_t { pid }
    }

    @Published private(set) var rows: [Row] = []
    @Published var quitting: Set<pid_t> = []
    @Published var focus: QuitAppsFocus = .button(.cancel)
    @Published var scope: QuitAppsScope
    var frontmostPID: pid_t?

    init(scope: QuitAppsScope, frontmostPID: pid_t?) {
        self.scope = scope
        self.frontmostPID = frontmostPID
    }

    /// The front app, when it has a row and is not a kept app. A kept front app
    /// makes "Quit all except" the same as Quit all, so it gets no button.
    var exceptFrontName: String? {
        rows.first { $0.isFrontmost && !$0.isKept }?.name
    }

    var buttons: [QuitAppsButton] {
        QuickTogglesSupport.quitAppsButtons(
            offersExceptFront: exceptFrontName != nil && hasBatchTarget(keepingFrontmost: true),
            canQuitAll: hasBatchTarget(keepingFrontmost: false))
    }

    /// Opened as "except the front app" while the front app is kept, Quit all
    /// keeps the same apps and takes the highlight; with no listed front app it
    /// rests on Cancel, since Quit all could quit the app the user meant to keep.
    var restingButton: QuitAppsButton {
        var scope: QuitAppsScope? = self.scope
        if scope == .allExceptFront, exceptFrontName == nil {
            scope = rows.contains { $0.isFrontmost && $0.isKept } ? .all : nil
        }
        return QuickTogglesSupport.restingQuitAppsButton(scope: scope, buttons: buttons)
    }

    func move(_ move: QuitAppsMove) {
        focus = QuickTogglesSupport.movedQuitAppsFocus(
            focus, move, rows: rows.map(\.pid), buttons: buttons, resting: restingButton)
    }

    private func hasBatchTarget(keepingFrontmost: Bool) -> Bool {
        rows.contains { !$0.isKept && !(keepingFrontmost && $0.isFrontmost) }
    }

    func reload() {
        let previousRows = rows.map(\.pid)
        let exceptions = Set(QuickTogglesService.shared.quitAllExceptions)
        let listed = NSWorkspace.shared.runningApplications.filter {
            QuickTogglesSupport.listsApp(bundleIdentifier: $0.bundleIdentifier,
                                         activationPolicyRawValue: $0.activationPolicy.rawValue,
                                         isTerminated: $0.isTerminated)
        }
        rows = listed.map { app in
            Row(pid: app.processIdentifier,
                name: app.localizedName ?? app.bundleIdentifier ?? "",
                icon: app.icon ?? NSWorkspace.shared.icon(for: .application),
                isKept: app.bundleIdentifier.map(exceptions.contains) ?? false,
                isFrontmost: app.processIdentifier == frontmostPID)
        }
        .sorted { lhs, rhs in
            if lhs.isFrontmost != rhs.isFrontmost { return lhs.isFrontmost }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        quitting.formIntersection(rows.map(\.pid))
        focus = QuickTogglesSupport.quitAppsFocusAfterListChange(
            focus, previousRows: previousRows, rows: rows.map(\.pid),
            buttons: buttons, resting: restingButton)
    }
}

/// A non-activating panel that can still take key focus, so the keyboard
/// reaches it without pulling the front app (the one "except" keeps) backward.
private final class QuitAppsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct QuitAppsView: View {
    @ObservedObject var model: QuitAppsModel
    let strings: QuickToggleFeatureStrings
    let cancelTitle: String
    let quitOne: (pid_t) -> Void
    let activate: (QuitAppsFocus) -> Void

    private static let width: CGFloat = 460
    private static let cornerRadius: CGFloat = 22
    private static let rowHeight: CGFloat = 42
    private static let visibleRows = 8

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.rows.isEmpty {
                Text(strings.quitAppsEmpty)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                list
            }
            Divider()
                .padding(.top, 6)
            buttonBar
        }
        .frame(width: Self.width)
        .background(HUDBackdrop(cornerRadius: Self.cornerRadius, contrast: .high))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(strings.quitAppsHeader)
                .font(.system(size: 13, weight: .semibold))
            Text("\(model.rows.count)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 17)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        QuitAppsRowView(row: row,
                                        isFocused: model.focus == .row(row.pid),
                                        isQuitting: model.quitting.contains(row.pid),
                                        strings: strings,
                                        quit: { quitOne(row.pid) },
                                        focus: { model.focus = .row(row.pid) })
                            .id(row.pid)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: Self.rowHeight * CGFloat(min(model.rows.count, Self.visibleRows)))
            .onChange(of: model.focus) { _, focus in
                if case .row(let pid) = focus { proxy.scrollTo(pid) }
            }
        }
    }

    private var buttonBar: some View {
        HStack(spacing: 8) {
            barButton(cancelTitle, keys: "Esc", .cancel)
            Spacer(minLength: 0)
            if let front = model.exceptFrontName, model.buttons.contains(.allExceptFront) {
                barButton(String(format: strings.quitAppsQuitAllExcept, front), keys: "⌥⌘↩",
                          .allExceptFront)
            }
            if model.buttons.contains(.all) {
                barButton(strings.quitAppsQuitAll, keys: "⌘↩", .all)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Each button carries the key that works from anywhere; blue marks the
    /// highlighted one only, so it always says what Return does.
    @ViewBuilder
    private func barButton(_ title: String, keys: String,
                           _ button: QuitAppsButton) -> some View {
        let isFocused = model.focus == .button(button)
        let base = Button { activate(.button(button)) } label: {
            HStack(spacing: 6) {
                Text(title)
                Text(keys)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.6)
                    .accessibilityHidden(true)
            }
            .lineLimit(1)
        }
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        if isFocused {
            base.buttonStyle(.borderedProminent)
        } else {
            base.buttonStyle(.bordered)
        }
    }
}

private struct QuitAppsRowView: View {
    let row: QuitAppsModel.Row
    let isFocused: Bool
    let isQuitting: Bool
    let strings: QuickToggleFeatureStrings
    let quit: () -> Void
    let focus: () -> Void
    @State private var hoveringQuit = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: row.icon)
                .resizable()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text(row.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            if row.isFrontmost { badge(strings.quitAppsFrontBadge) }
            if row.isKept {
                badge(strings.quitAppsKeptBadge)
                    .help(strings.exceptionsCaption)
            }
            Spacer(minLength: 12)
            if isQuitting {
                ProgressView()
                    .controlSize(.small)
            } else {
                // One quit control, on the highlighted row only: the pointer
                // highlights the row it rests on, so the mouse always finds it,
                // and Return quits that same row. Laid out on every row so
                // nothing shifts as the highlight moves.
                Button(action: quit) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(hoveringQuit ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .onHover { hoveringQuit = $0 }
                .opacity(isFocused ? 1 : 0)
                .allowsHitTesting(isFocused)
                .help(String(format: strings.quitAppsQuitOne, row.name))
                .accessibilityLabel(String(format: strings.quitAppsQuitOne, row.name))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isFocused ? Color.accentColor.opacity(0.14) : .clear)
        )
        .onHover { if $0 { focus() } }
        .onTapGesture(perform: focus)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.08), in: Capsule())
    }
}
