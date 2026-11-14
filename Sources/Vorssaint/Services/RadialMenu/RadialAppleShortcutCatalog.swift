// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The shortcuts in the Shortcuts app, read through its command line tool.
/// Slices store a shortcut's identifier; this is where the name the wheel and
/// the editor show comes from. The list is read in the background and kept
/// until the next read, so a failed or slow read never blanks the names.
final class RadialAppleShortcutCatalog: ObservableObject {
    static let shared = RadialAppleShortcutCatalog()

    @Published private(set) var shortcuts: [RadialAppleShortcut] = []
    /// True once a read has answered, so the editor can tell an empty
    /// library apart from one that has not been read yet.
    @Published private(set) var hasLoaded = false
    private var isLoading = false

    private init() {}

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let (status, output) = Shell.run(RadialMenuSupport.shortcutsToolPath,
                                             ["list", "--show-identifiers"])
            let listed = status == 0 ? RadialMenuSupport.appleShortcuts(fromList: output) : nil
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isLoading = false
                guard let listed else { return }
                if self.shortcuts != listed { self.shortcuts = listed }
                if !self.hasLoaded { self.hasLoaded = true }
            }
        }
    }

    func name(for identifier: String) -> String? {
        shortcuts.first { $0.id == identifier }?.name
    }
}
