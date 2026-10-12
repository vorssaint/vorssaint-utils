// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum DockProcessIdentity {
    /// NUL-separated KERN_PROCARGS2 strings stay local. Match an exact launch
    /// identity or a bounded path component, never an arbitrary substring.
    static func matches(_ strings: String, launcher: String?, storage: String?) -> Bool {
        let values = strings.split(separator: "\0").map(String.init)
        if let launcher, !launcher.isEmpty, values.contains("__CFBundleIdentifier=" + launcher) { return true }
        guard let storage, !storage.isEmpty else { return false }
        let path = (storage as NSString).standardizingPath
        return values.contains { $0 == path || $0.hasSuffix("=" + path) || $0.contains("=" + path + "/") || $0.hasPrefix(path + "/") }
    }
}
