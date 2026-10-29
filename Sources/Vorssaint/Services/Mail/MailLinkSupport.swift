// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Decisions behind the email link option, kept apart from Launch Services
/// so they can be tested without changing this Mac's default mail app.
enum MailLinkSupport {
    static let scheme = "mailto"
    static let mailBundleID = "com.apple.mail"

    /// What a `mailto:` link does while Vorssaint holds the scheme.
    enum Action: String, CaseIterable {
        case ignore, openApp, copyAddress

        static func sanitized(_ raw: String?) -> Action {
            raw.flatMap(Action.init(rawValue:)) ?? .ignore
        }
    }

    static func isMailLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
    }

    /// Recipients from the address part and every `to` field (RFC 6068), in
    /// order and without repeats. Copies and blind copies are left out: the
    /// address someone clicked is the one they asked for.
    static func recipients(in url: URL) -> [String] {
        guard isMailLink(url) else { return [] }
        let text = url.absoluteString.dropFirst(scheme.count + 1)
        let parts = text.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var fields = [String(parts.first ?? "")]
        if parts.count > 1 {
            for pair in parts[1].split(separator: "&") {
                let field = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard field.count == 2, field[0].lowercased() == "to" else { continue }
                fields.append(String(field[1]))
            }
        }
        var seen = Set<String>()
        return fields
            .flatMap { $0.split(separator: ",") }
            .compactMap { String($0).removingPercentEncoding?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// An app may open email links in Mail's place unless it is Mail itself
    /// or this app, either of which would bring the link straight back.
    static func canOpenLinks(bundleID: String?, ownBundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return bundleID.caseInsensitiveCompare(mailBundleID) != .orderedSame && bundleID != ownBundleID
    }

    /// How long after a link is passed on the same link coming back counts
    /// as the chosen app handing it to the system's mail app, which is this.
    static let returnWindow: TimeInterval = 2

    /// An app that can't send mail itself may pass the link on to the system,
    /// which sends it straight back here. Dropping that return ends the loop.
    static func isReturnedLink(_ url: URL, now: TimeInterval,
                               lastPassedOn: URL?, passedOnAt: TimeInterval?) -> Bool {
        guard let lastPassedOn, let passedOnAt else { return false }
        return lastPassedOn == url && now >= passedOnAt && now - passedOnAt < returnWindow
    }

    /// The handler to give the scheme back to: the one saved when the option
    /// took it, while it still exists and is not this app. Nil means Mail,
    /// the system's own handler.
    static func restoreTarget(savedPath: String?, ownBundleID: String?,
                              bundleID: (String) -> String?, exists: (String) -> Bool) -> String? {
        guard let savedPath, !savedPath.isEmpty, exists(savedPath),
              let savedID = bundleID(savedPath), savedID != ownBundleID else { return nil }
        return savedPath
    }
}
