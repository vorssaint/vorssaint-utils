// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The routing trigger and the undo boundary, exercised as pure decisions.
/// Nothing here touches a real Downloads folder: the point of both rules is
/// that they can be checked without one.
enum DownloadRoutingTests {
    private static let downloads = URL(fileURLWithPath: "/Users/test/Downloads")
    private static let chosen = URL(fileURLWithPath: "/Users/test/Archive")

    private static func record(_ path: String,
                               digest: String,
                               size: Int64 = 4,
                               organizedAt: TimeInterval = 1_000) -> WhatsAppDownloadSupport.Record {
        WhatsAppDownloadSupport.Record(digest: digest, destinationPath: path,
                            originalName: URL(fileURLWithPath: path).lastPathComponent,
                            size: size, organizedAt: Date(timeIntervalSince1970: organizedAt))
    }

    private static func transaction(before: [WhatsAppDownloadSupport.Record],
                                    after: [WhatsAppDownloadSupport.Record]) -> WhatsAppDownloadSupport.UndoTransaction {
        WhatsAppDownloadSupport.UndoTransaction(id: UUID(), actions: [], recordsBefore: before,
                        recordsAfter: after, createdAt: Date(timeIntervalSince1970: 1_000))
    }

    static func run(_ suite: TestSuite) {
        runRouting(suite)
        runUndo(suite)
        runDuplicateResolution(suite)
        runDefaults(suite)
        runCleanupScope(suite)
    }

    private static func runRouting(_ suite: TestSuite) {
        let sources = WhatsAppDownloadSupport.decodedSources(
            Defaults.registeredDefaults[DefaultsKey.downloadOrganizerSources] as? String)
        suite.expect(WhatsAppDownloadSupport.matchesAgent("WhatsApp", configured: sources),
                     "the default source list routes the app it shipped with")
        suite.expect(!WhatsAppDownloadSupport.matchesAgent("SomeBrowser", configured: sources)
                     && !WhatsAppDownloadSupport.matchesAgent(nil, configured: sources)
                     && !WhatsAppDownloadSupport.matchesAgent("", configured: sources),
                     "an app nobody configured is never routed")

        let padded = [" WhatsApp ", "SomeMessenger"]
        suite.expect(WhatsAppDownloadSupport.matchesAgent("whatsapp", configured: padded)
                     && WhatsAppDownloadSupport.matchesAgent("  WHATSAPP\n", configured: padded)
                     && WhatsAppDownloadSupport.matchesAgent("SomeMessenger", configured: padded)
                     && !WhatsAppDownloadSupport.matchesAgent("whatsapp desktop", configured: padded),
                     "surrounding whitespace and letter case never decide a route")

        let matching = DownloadCandidate(url: downloads.appendingPathComponent("a.pdf"),
                                         agent: "WhatsApp", destination: chosen)
        suite.expect(WhatsAppDownloadSupport.destination(for: matching, configured: sources,
                                                extensionWhitelist: nil) != nil,
                     "the shipped configuration still routes what it routed before")
        suite.expect(WhatsAppDownloadSupport.destination(for: matching, configured: [],
                                                extensionWhitelist: nil) == nil,
                     "with no source configured nothing moves, even for a matching app")
        suite.expect(WhatsAppDownloadSupport.destination(for: matching, configured: [],
                                                extensionWhitelist: ["pdf"]) == nil,
                     "an empty source list refuses the file before the extension rule runs")

        let openRouter = DownloadCandidate(
            url: downloads.appendingPathComponent("photo.PNG"), agent: "whatsapp",
            destination: chosen)
        let zip = DownloadCandidate(url: downloads.appendingPathComponent("archive.zip"),
                                    agent: "whatsapp", destination: chosen)
        let extensionless = DownloadCandidate(
            url: downloads.appendingPathComponent("README"), agent: "whatsapp",
            destination: chosen)
        let unfiltered = WhatsAppDownloadSupport.destination(for: openRouter, configured: sources,
                                                    extensionWhitelist: nil)
        let png = WhatsAppDownloadSupport.destination(for: openRouter, configured: sources,
                                             extensionWhitelist: ["png"])
        suite.expect(unfiltered != nil && png != nil
                     && WhatsAppDownloadSupport.destination(for: zip, configured: sources,
                                                    extensionWhitelist: ["png"]) == nil
                     && WhatsAppDownloadSupport.destination(for: extensionless, configured: sources,
                                                    extensionWhitelist: ["png"]) == nil,
                     "a whitelist admits the listed extensions whatever their case and refuses the rest")

        let alreadyThere = DownloadCandidate(url: chosen.appendingPathComponent("a.pdf"),
                                             agent: "WhatsApp", destination: chosen)
        suite.expect(WhatsAppDownloadSupport.destination(for: alreadyThere, configured: sources,
                                                extensionWhitelist: nil) == nil,
                     "a file already in the chosen folder is not a route")

        let messy = DownloadCandidate(
            url: downloads.appendingPathComponent("sub").appendingPathComponent("..")
                .appendingPathComponent("b.pdf"),
            agent: "WhatsApp", destination: chosen.appendingPathComponent("."))
        suite.expect(WhatsAppDownloadSupport.destination(for: messy, configured: sources,
                                                extensionWhitelist: nil)?.path == chosen.path,
                     "the returned folder is standardized, not the shape it was handed")

        suite.expect(WhatsAppDownloadSupport.decodedSources(nil).isEmpty
                     && WhatsAppDownloadSupport.decodedSources("").isEmpty
                     && WhatsAppDownloadSupport.decodedSources(" , ").isEmpty,
                     "no stored source decodes to no route at all")
        suite.expect(WhatsAppDownloadSupport.decodedSources(" WhatsApp , SomeMessenger ,WHATSAPP") == ["WhatsApp", "SomeMessenger"],
                     "a repeated source differing only in case is one route, first spelling kept")
        suite.expect(WhatsAppDownloadSupport.decodedExtensionWhitelist(nil) == nil
                     && WhatsAppDownloadSupport.decodedExtensionWhitelist("") == nil
                     && WhatsAppDownloadSupport.decodedExtensionWhitelist(" , ") == nil,
                     "an absent extension rule is no extension rule, not an empty allow-list")
        suite.expect(WhatsAppDownloadSupport.decodedExtensionWhitelist("PNG, jpg") == ["png", "jpg"],
                     "a stored extension list decodes case-insensitively")
    }

    private static func runUndo(_ suite: TestSuite) {
        let replacedBefore = record("/Archive/doc.pdf", digest: "old", size: 4, organizedAt: 1_000)
        let replacedAfter = record("/Archive/doc.pdf", digest: "new", size: 8, organizedAt: 2_000)
        let merge = transaction(before: [replacedBefore], after: [replacedAfter])
        suite.expect(WhatsAppDownloadSupport.affectedRecordPaths(merge) == ["/Archive/doc.pdf"],
                     "only a record the pass changed counts as affected")
        suite.expect(WhatsAppDownloadSupport.recordsAllowUndo(merge, current: [replacedAfter]),
                     "a pass whose file is untouched since can be undone")
        suite.expect(WhatsAppDownloadSupport.recordsAfterUndo(merge, current: [replacedAfter])
                     == [replacedBefore],
                     "undo restores the exact pre-pass record for the path the pass touched")

        let bystander = record("/Archive/kept.pdf", digest: "aaa", organizedAt: 500)
        let added = record("/Archive/photo.png", digest: "bbb", organizedAt: 2_000)
        let pass = transaction(before: [bystander], after: [bystander, added])
        suite.expect(WhatsAppDownloadSupport.recordsAllowUndo(pass, current: [bystander, added]),
                     "an added record that is still there keeps the pass undoable")
        suite.expect(WhatsAppDownloadSupport.recordsAfterUndo(pass, current: [bystander, added])
                     == [bystander],
                     "undo drops the record a pass added and leaves the rest alone")

        let sinceEdited = record("/Archive/photo.png", digest: "bbb", size: 999,
                                 organizedAt: 3_000)
        suite.expect(!WhatsAppDownloadSupport.recordsAllowUndo(pass, current: [bystander, sinceEdited]),
                     "a file the person changed since the pass blocks the undo")
        suite.expect(!WhatsAppDownloadSupport.recordsAllowUndo(pass, current: [bystander]),
                     "a record that disappeared since the pass blocks the undo")
        suite.expect(WhatsAppDownloadSupport.affectedRecordPaths(pass)
                     .isDisjoint(with: ["/Archive/kept.pdf"]),
                     "a stale record the pass never involved cannot block an undo")

        let rewritten = transaction(before: [bystander, added],
                                    after: [bystander, added])
        suite.expect(WhatsAppDownloadSupport.affectedRecordPaths(rewritten).isEmpty,
                     "a pass whose records are identical before and after touched nothing")
    }

    private static func runDuplicateResolution(_ suite: TestSuite) {
        let wanted = record("/Archive/second.png", digest: "dup")
        let other = record("/Archive/other.png", digest: "other")

        var noMatch = [other]
        suite.expect(WhatsAppDownloadSupport.firstValidRecordIndex(digest: "dup", records: &noMatch,
                                                          isIntact: { _ in true }) == nil
                     && noMatch == [other],
                     "no record sharing the digest means nothing is a duplicate")

        var staleFirst = [record("/Archive/first.png", digest: "dup"), other, wanted]
        let later = WhatsAppDownloadSupport.firstValidRecordIndex(digest: "dup", records: &staleFirst) {
            $0.destinationPath == "/Archive/second.png"
        }
        suite.expect(later == 1 && staleFirst.map(\.destinationPath) == ["/Archive/other.png",
                                                                          "/Archive/second.png"],
                     "a record whose file is gone is dropped and the search continues past it")

        var changedOnly = [record("/Archive/only.png", digest: "dup")]
        suite.expect(WhatsAppDownloadSupport.firstValidRecordIndex(digest: "dup", records: &changedOnly,
                                                          isIntact: { _ in false }) == nil
                     && changedOnly.isEmpty,
                     "a record that claims the digest but not the bytes is not a duplicate")

        var intact = [wanted, other]
        suite.expect(WhatsAppDownloadSupport.firstValidRecordIndex(digest: "dup", records: &intact,
                                                          isIntact: { _ in true }) == 0
                     && intact.count == 2,
                     "the first intact match is the duplicate and nothing else is disturbed")
    }

    private static func runDefaults(_ suite: TestSuite) {
        let raw = Defaults.registeredDefaults[DefaultsKey.downloadOrganizerSources] as? String
        suite.expect(raw != nil, "the routing sources have a registered default")
        suite.expect(WhatsAppDownloadSupport.decodedSources(raw) == ["WhatsApp"],
                     "an untouched installation routes exactly the app it routed before")
        suite.expect(WhatsAppDownloadSupport.decodedExtensionWhitelist(
                        Defaults.registeredDefaults[DefaultsKey.downloadOrganizerExtensions] as? String) == nil,
                     "an untouched installation filters no extension at all")
    }

    /// The cleanup and the router answer different questions, and a
    /// preference that says where a download is moved to must not also say
    /// what may be trashed.
    private static func runCleanupScope(_ suite: TestSuite) {
        suite.expect(WhatsAppDownloadSupport.cleanupSources == ["WhatsApp"],
                     "the cleanup's scope is the WhatsApp app and nothing else")
        suite.expect(WhatsAppDownloadSupport.matchesAgent("WhatsApp",
                                                            configured: WhatsAppDownloadSupport.cleanupSources),
                     "the cleanup still reaches the app it always reached")
        suite.expect(!WhatsAppDownloadSupport.matchesAgent("SomeBrowser",
                                                            configured: WhatsAppDownloadSupport.cleanupSources),
                     "no other app is in the cleanup's scope, whatever the routing list says")
        suite.expect(WhatsAppDownloadSupport.cleanupSources.count == 1,
                     "the cleanup's scope is one fixed app, not a list the person can widen")
    }
}
