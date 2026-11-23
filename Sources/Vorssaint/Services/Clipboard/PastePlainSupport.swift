// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import UniformTypeIdentifiers

/// What the paste-plain watcher does with one clipboard change.
enum PastePlainDecision: Equatable {
    /// The clipboard carries formatting it can lose: rewrite it as plain text.
    case strip
    /// The clipboard is left exactly as the user made it, for the reason below.
    case leaveAlone(PastePlainSupport.LeaveReason)
}

/// The pure decisions and text transforms of paste as plain text, kept free of
/// AppKit so a unit test can run them without a pasteboard of its own. The
/// service owns everything that touches one.
enum PastePlainSupport {
    enum LeaveReason: Equatable {
        /// An empty clipboard: nothing to strip, nothing to keep.
        case empty
        /// No copy of this ever pastes as text (a picture, a file, a sound).
        case notText
        /// The copy is text beside its own picture, a document snapshot or a
        /// file — the text alone would lose the rest.
        case protectedContent
        /// A password manager handing over a secret.
        case concealed
        /// Content an app made up or is about to take back.
        case transient
        /// The clipboard still holds a write of our own, or an app named
        /// itself as the source and that app is this one.
        case ownWrite
        /// The copying app is on the user's exclusion list.
        case excludedApp
        /// Plain text already: stripping would rewrite the clipboard without
        /// changing it, so no write happens and the change count stays.
        case alreadyPlain
    }

    // MARK: - The decision

    /// Decides from raw pasteboard type names alone — no data is read — so a
    /// picture or a file is never fetched only to be left alone.
    ///
    /// A copy that arrived over Universal Clipboard is stripped too, even
    /// though writing the stripped text locally clears the remote marker and
    /// the copy disappears from the other device (a known Pure Paste
    /// limitation): the alternative would be keeping formatted text on the
    /// clipboard here.
    static func decision(types rawTypes: [String],
                         itemCount: Int,
                         declaredSource: String?,
                         ownBundleID: String?,
                         frontmostBundleID: String?,
                         excludedApps: Set<String>,
                         isOwnLastWrite: Bool) -> PastePlainDecision {
        guard !rawTypes.isEmpty else { return .leaveAlone(.empty) }
        if isOwnLastWrite { return .leaveAlone(.ownWrite) }
        if rawTypes.contains(concealedType) { return .leaveAlone(.concealed) }
        if rawTypes.contains(where: transientTypes.contains) { return .leaveAlone(.transient) }
        if rawTypes.contains(where: isProtectedContent) { return .leaveAlone(.protectedContent) }
        guard rawTypes.contains(where: isTextBearing) else { return .leaveAlone(.notText) }
        // The pasteboard says what was copied, never who copied it, so the
        // frontmost app is only consulted when no app named itself: the same
        // guess the clipboard history makes for the same reason.
        let source = declaredSource?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let source {
            if source == ownBundleID { return .leaveAlone(.ownWrite) }
            if excludedApps.contains(source) { return .leaveAlone(.excludedApp) }
        } else if let frontmost = frontmostBundleID, excludedApps.contains(frontmost) {
            return .leaveAlone(.excludedApp)
        }
        guard isRich(rawTypes, itemCount: itemCount) else { return .leaveAlone(.alreadyPlain) }
        return .strip
    }

    /// Whether a strip has anything to lose: rich text of any flavor, or more
    /// than one item, whose plain parts would otherwise paste run together.
    static func isRich(_ rawTypes: [String], itemCount: Int) -> Bool {
        itemCount > 1 || rawTypes.contains(where: isRichType)
    }

    static func isRichType(_ rawType: String) -> Bool {
        if legacyRichTypes.contains(rawType) { return true }
        guard let type = UTType(rawType), type.isDeclared else { return false }
        return type.conforms(to: .rtf) || type.conforms(to: .rtfd) || type.conforms(to: .flatRTFD)
            || type.conforms(to: .html) || type.conforms(to: .webArchive)
    }

    /// Whether an app pasting the copy would put text on the page. Plain text,
    /// formatted text and a bare link all qualify; the plain text is later
    /// read out of whichever of them carries it.
    static func isTextBearing(_ rawType: String) -> Bool {
        if legacyTextTypes.contains(rawType) { return true }
        guard let type = UTType(rawType), type.isDeclared else { return false }
        return type.conforms(to: .text) || type.conforms(to: .url)
    }

    /// A copy whose content is not text at all, or is text plus the thing the
    /// text is about: a file, a picture of a spreadsheet's cells, a PDF
    /// preview. Stripping would turn "copy this file/image" into "paste a
    /// name", which is never what the user asked for.
    static func isProtectedContent(_ rawType: String) -> Bool {
        if legacyFileTypes.contains(rawType) { return true }
        guard let type = UTType(rawType), type.isDeclared else { return false }
        return type.conforms(to: .fileURL) || type.conforms(to: .image)
            || type.conforms(to: .movie) || type.conforms(to: .video)
            || type.conforms(to: .audio) || type.conforms(to: .pdf)
    }

    // MARK: - Type names

    /// The nspasteboard.org mark saying the content is a secret.
    static let concealedType = "org.nspasteboard.ConcealedType"
    /// The marks saying the content was made up or is about to be taken back.
    static let transientTypes: Set<String> = [
        "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
    ]
    /// Written by clipboard managers so they do not keep a second copy of the
    /// stripped text next to the rich original.
    static let modifiedTypeMarker = "x.nspasteboard.ModifiedType"
    /// Marks that this feature has already processed the copy.
    static let hasRunMarker = "com.vorssaint.PastePlain.hasRun"

    private static let legacyTextTypes: Set<String> = [
        "NSStringPboardType", "NSRTFPboardType", "NSHTMLPboardType",
    ]
    private static let legacyRichTypes: Set<String> = [
        "NSRTFPboardType", "NSRTFDPboardType", "NSHTMLPboardType",
    ]
    private static let legacyFileTypes: Set<String> = [
        "NSFilenamesPboardType", "NSFileContentsPboardType",
        "com.apple.NSFilePromiseItemMetaData", "Apple files promise pasteboard type",
        "com.apple.pasteboard.promised-file-url",
    ]

    // MARK: - Text transforms

    /// What the enabled optional cleanups do to a stripped text.
    struct TransformOptions {
        var cleanInvisible = false
        var trimWhitespace = false
        var cleanLinks = false
        var rules: URLCleaning.Rules = .none
    }

    /// The order matters and is fixed: invisible characters go first, because
    /// removing them can expose runs of whitespace to trim; whitespace is
    /// trimmed next, so what a link has to be measured against is already the
    /// final text; a whole-copy link is cleaned last, when the text is settled.
    /// Every step is idempotent, so a text that is stripped twice — a rich
    /// paste restoring the original before the watcher strips it again, for
    /// one — comes out the same as one stripped once.
    static func applyTransforms(_ text: String, options: TransformOptions) -> String {
        var result = text
        if options.cleanInvisible { result = removingInvisibleCharacters(result) }
        if options.trimWhitespace { result = result.trimmingCharacters(in: .whitespacesAndNewlines) }
        if options.cleanLinks,
           let cleaned = URLCleaning.clean(result, rules: options.rules),
           !cleaned.removed.isEmpty {
            result = cleaned.url
        }
        return result
    }

    /// Zero-width space, byte-order mark, word joiner, soft hyphen and the
    /// Unicode tag block, which AI text uses as a watermark. U+200C, U+200D
    /// and the directional marks stay: removing those breaks emoji sequences,
    /// joined Arabic and Indic shaping, and right-to-left punctuation.
    static func removingInvisibleCharacters(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x200B, 0xFEFF, 0x2060, 0x00AD: return false
            case 0xE0000...0xE007F: return false
            default: return true
            }
        }))
    }
}
