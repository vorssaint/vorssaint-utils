// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The Cleaner tools that need more room than the menu panel has.
enum CleanerExtraTool: Hashable {
    case largeFiles, duplicates, startup
}

final class CleanerToolsSelection: ObservableObject {
    @Published var tool = CleanerExtraTool.largeFiles
}

/// A large, resizable window for the lists-heavy Cleaner tools (large files,
/// duplicates, startup items). The menu panel stays small for the quick system
/// cleaner and opens this window for the rest. Closing the window stops any
/// scan it started.
final class CleanerToolsWindowController: NSObject, NSWindowDelegate {
    static let shared = CleanerToolsWindowController()

    private let selection = CleanerToolsSelection()
    private var window: NSWindow?
    private var keepsAppRegular = false

    private override init() { super.init() }

    func show(_ tool: CleanerExtraTool) {
        selection.tool = tool
        if window == nil {
            let host = NSHostingController(rootView: CleanerToolsWindowView(selection: selection))
            // The window owns its size; the lists inside must not drive it.
            host.sizingOptions = []
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 800, height: 640))
            window.contentMinSize = NSSize(width: 560, height: 420)
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.delegate = self
            window.center()
            self.window = window
        }
        window?.title = L10n.shared.s.cleanerName
        // A menu bar app only brings a window to the front when it is
        // temporarily a regular app, the same step the Settings window takes.
        if !keepsAppRegular {
            keepsAppRegular = true
            WindowActivationPolicy.retain()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        if keepsAppRegular {
            keepsAppRegular = false
            WindowActivationPolicy.release()
        }
        if LargeFileFinder.shared.phase == .scanning { LargeFileFinder.shared.reset() }
        if DuplicateFileFinder.shared.phase == .scanning { DuplicateFileFinder.shared.reset() }
    }
}

struct CleanerToolsWindowView: View {
    @ObservedObject var selection: CleanerToolsSelection
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selection.tool) {
                Label(l10n.s.largeFilesName, systemImage: "doc.badge.clock").tag(CleanerExtraTool.largeFiles)
                Label(l10n.s.duplicatesName, systemImage: "doc.on.doc").tag(CleanerExtraTool.duplicates)
                Label(l10n.s.startupName, systemImage: "power").tag(CleanerExtraTool.startup)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider()

            switch selection.tool {
            case .largeFiles: LargeFilesView()
            case .duplicates: DuplicatesView()
            case .startup: StartupItemsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
