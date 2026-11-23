// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import UniformTypeIdentifiers

/// What the paste-plain watcher does with one clipboard change.
enum PastePlainDecision: Equatable {
    /// The clipboard carries formatting it can lose: rewrite it as plain text.
    case strip
    /// The copy carries a picture, clip or PDF beside its text: strip only
    /// when the plain string turns out to be real text rather than the
    /// media's own link or file name. Answered by the service after one
    /// string read, which is the only flavor that can be judged without
    /// rendering the media.
    case stripWhenTextIsReal
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
        /// A file being copied or promised: stripping would turn "copy this
        /// file" into "paste a name".
        case protectedContent
        /// A media copy whose text is only the picture's own link or file
        /// name, or no text at all: the picture is the copy.
        case mediaFallback
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

    /// Decides from raw pasteboard type names alone, so a picture or a file
    /// is never fetched only to be left alone. The one exception is a copy
    /// that also carries a picture of its own text — a document's snapshot of
    /// a selection — which answers `.stripWhenTextIsReal` and is confirmed
    /// against the copy's plain string, the only flavor whose text can be
    /// judged without rendering anything.
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
        // A file copy is left before anything else is even considered, and
        // nothing is read from it: the name it carries as text is not text
        // the user asked to have stripped.
        if rawTypes.contains(where: isFileContent) { return .leaveAlone(.protectedContent) }
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
        // A picture, clip or PDF beside text is judged by the text: spreadsheets,
        // slides and documents put a snapshot of the selection on the
        // pasteboard next to the real rich text, and those copies are exactly
        // the ones the feature exists to strip. A picture copied on its own
        // carries only its link or file name as text, which answers the media
        // check below and keeps the copy whole.
        if rawTypes.contains(where: isMedia) { return .stripWhenTextIsReal }
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

    /// A file being copied or promised, under the names that are not types
    /// the system knows and would otherwise pass as private notes. A file URL
    /// beside its name as text is still a file copy.
    static func isFileContent(_ rawType: String) -> Bool {
        if legacyFileTypes.contains(rawType) { return true }
        guard let type = UTType(rawType), type.isDeclared else { return false }
        return type.conforms(to: .fileURL)
    }

    /// A picture, a movie, an audio clip or a PDF — content that may be the
    /// copy itself, or just a preview of the text beside it.
    static func isMedia(_ rawType: String) -> Bool {
        guard let type = UTType(rawType), type.isDeclared else { return false }
        return type.conforms(to: .image) || type.conforms(to: .movie)
            || type.conforms(to: .video) || type.conforms(to: .audio)
            || type.conforms(to: .pdf)
    }

    /// Whether a media copy should be stripped, judged by its plain string:
    /// real text means the picture is only a preview of it (a cell, a slide),
    /// while a link or a file name is what a browser or a chat writes when
    /// the picture itself is the copy — that copy stays whole.
    static func mediaCopyStrips(plain: String) -> Bool {
        let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !isMediaTextFallback(trimmed)
    }

    /// The text a picture or clip copied on its own carries beside it: nothing,
    /// or one link or media file name, as a browser or a chat copies an image.
    /// Anything else, a cell's "example.com" or "2.4GHz" included, is text
    /// that came with a picture of itself and still strips to plain text.
    static func isMediaTextFallback(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard !trimmed.contains(where: { $0.isWhitespace }) else { return false }
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("data:") || lowercased.hasPrefix("blob:")
            || (trimmed.contains("://") && URL(string: trimmed)?.scheme != nil) { return true }
        let name = trimmed as NSString
        guard !name.deletingPathExtension.isEmpty, !name.pathExtension.isEmpty,
              let type = UTType(filenameExtension: name.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .audiovisualContent)
            || type.conforms(to: .pdf)
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
