// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuickLookUI
import SwiftUI

/// No window or session is constructed while this optional feature is absent.
final class DuplicateFinderWindow: NSObject, NSWindowDelegate {
    private static var current: DuplicateFinderWindow?
    private let session = DuplicateFinderSession()
    private var window: NSWindow?
    static func show() {
        guard AppFeature.duplicateFinder.isAvailable else { return }
        if let existing = current { existing.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let controller = DuplicateFinderWindow()
        current = controller
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = FeatureStrings.duplicateFinder(L10n.shared.language).title
        window.minSize = NSSize(width: 800, height: 500)
        window.isReleasedWhenClosed = false; window.delegate = controller
        window.contentView = NSHostingView(rootView: DuplicateFinderView(session: controller.session))
        controller.window = window
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    static func closeExisting() { current?.window?.close() }
    func windowWillClose(_ notification: Notification) {
        session.close(); window?.contentView = nil; window = nil; Self.current = nil
    }
}

struct DuplicateFinderSettings: View {
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        let text = FeatureStrings.duplicateFinder(l10n.language)
        VStack(alignment: .leading, spacing: 16) {
            Text(text.title).font(.title2.bold())
            Text(text.intro).foregroundStyle(.secondary)
            Button(text.open, action: DuplicateFinderWindow.show)
                .disabled(!AppFeature.duplicateFinder.isAvailable)
            Text(text.scope).font(.callout).foregroundStyle(.secondary)
            Text(text.privacy).font(.callout).foregroundStyle(.secondary)
            Spacer()
        }.padding(24)
    }
}

private struct DuplicateFinderView: View {
    @ObservedObject var session: DuplicateFinderSession
    @ObservedObject private var l10n = L10n.shared
    private var text: DuplicateFinderStrings { FeatureStrings.duplicateFinder(l10n.language) }
    private func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(text.add, action: session.addFolders).disabled(session.busy || session.confirmation)
                Button(text.scan, action: session.scan).disabled(session.busy || session.roots.isEmpty || session.confirmation)
                if session.busy { Button(text.cancel, action: session.cancel) }
                Spacer()
                Button(text.trash, action: session.review).disabled(!session.canTrash)
            }.padding(12)
            Divider()
            HSplitView {
                folders.frame(minWidth: 180, idealWidth: 210, maxWidth: 270)
                groups.frame(minWidth: 330, maxWidth: .infinity)
                inspector.frame(minWidth: 240, idealWidth: 300, maxWidth: 400)
            }
            Divider()
            status.padding(12)
        }
        .sheet(isPresented: $session.confirmation, onDismiss: session.dismissReview) { review }
    }
    private var folders: some View {
        VStack(alignment: .leading) {
            Text(text.folders).font(.headline).padding([.top, .horizontal], 12)
            List {
                ForEach(session.roots, id: \.self) { root in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(root.lastPathComponent, systemImage: "folder")
                        Text(root.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Button(text.remove) { session.remove(root) }.disabled(session.busy || session.confirmation)
                    }.padding(.vertical, 4)
                }
            }
            Text(text.scope).font(.caption).foregroundStyle(.secondary).padding(12)
        }
    }
    private var groups: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let report = session.report, report.groups.isEmpty {
                    Text(report.cancelled ? text.cancelled : text.noDuplicates).foregroundStyle(.secondary).padding()
                } else if session.report == nil && !session.busy {
                    Text(text.intro).foregroundStyle(.secondary).padding()
                }
                ForEach(session.report?.groups ?? []) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(group.files.count) · \(bytes(group.duplicateBytes))").font(.headline)
                        ForEach(group.files) { file in
                            HStack(alignment: .top, spacing: 8) {
                                Toggle(isOn: Binding(get: { session.selection.contains(file.url) }, set: { session.select(file, enabled: $0) })) {
                                    Text(text.trash + ": " + file.url.lastPathComponent)
                                }.labelsHidden().toggleStyle(.checkbox)
                                    .disabled(session.busy || session.confirmation || (!session.selection.contains(file.url) && group.files.filter { !session.selection.contains($0.url) }.count <= 1))
                                Button { session.preview = file } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(file.url.lastPathComponent).fontWeight(.medium)
                                        Text(file.url.path).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                        Text("\(bytes(file.identity.size)) · \(file.modified.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain).disabled(session.busy)
                                    .accessibilityLabel(text.preview + ": " + file.url.path)
                            }.padding(8).background(session.preview?.url == file.url ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    Divider()
                }
            }.padding(12)
        }
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text.preview).font(.headline)
            if let file = session.preview {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().frame(width: 40, height: 40)
                Text(file.url.lastPathComponent).fontWeight(.medium)
                Text(file.url.path).font(.caption).textSelection(.enabled)
                Text("\(bytes(file.identity.size)) · \(file.modified.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                if DuplicateFinderSupport.stillMatches(file) {
                    DuplicateQuickLook(file: file).frame(minHeight: 200, maxHeight: .infinity)
                    Button(text.reveal) {
                        guard DuplicateFinderSupport.stillMatches(file) else { return }
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    }
                } else { Text(text.reason(.changed)).foregroundStyle(.secondary) }
            } else { Text(text.choosePreview).foregroundStyle(.secondary); Spacer() }
        }.padding(12)
    }
    private var status: some View {
        VStack(alignment: .leading, spacing: 6) {
            if session.busy {
                ProgressView().controlSize(.small)
                if let progress = session.progress {
                    Text("\(progress.phase == .enumerating ? text.enumerating : text.comparing): \(progress.completed)" + (progress.total.map { " / \($0)" } ?? ""))
                } else { Text(text.working) }
            } else {
                Text(text.logicalSize + ": " + bytes(session.selectedBytes))
                Text(text.keepNote).font(.caption).foregroundStyle(.secondary)
            }
            if !session.outcomes.isEmpty {
                Text("\(text.moved): \(session.outcomes.filter(\.moved).count) · \(text.notMoved): \(session.outcomes.filter { !$0.moved }.count)")
                ScrollView { VStack(alignment: .leading) {
                    ForEach(Array(session.outcomes.enumerated()), id: \.offset) { _, result in
                        Text(result.file.url.path + " · " + (result.reason.map(text.reason) ?? text.moved)).font(.caption).textSelection(.enabled)
                    }
                }}.frame(maxHeight: 80)
            }
            if let issues = session.report?.issues, !issues.isEmpty {
                DisclosureGroup("\(text.skipped): \(issues.count)") {
                    ScrollView { LazyVStack(alignment: .leading) {
                        ForEach(issues) { issue in Text(issue.url.path + " · " + text.reason(issue.reason)).font(.caption).textSelection(.enabled) }
                    }}.frame(maxHeight: 100)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var review: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text.confirm).font(.title2.bold())
            Text("\(session.selectedFiles.count) · \(bytes(session.selectedBytes))")
            Text(text.trashNote).foregroundStyle(.secondary)
            ScrollView { VStack(alignment: .leading, spacing: 8) {
                ForEach(session.selectedFiles) { Text($0.url.path).textSelection(.enabled) }
            }.frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 220)
            HStack {
                Button(text.cancel, action: session.dismissReview).keyboardShortcut(.cancelAction)
                Spacer()
                Button(text.trash, action: session.trashConfirmed).disabled(!session.canTrash)
            }
        }.padding(24).frame(width: 600)
    }
}

private struct DuplicateQuickLook: NSViewRepresentable {
    let file: DuplicateFinderSupport.File
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = false; view.shouldCloseWithWindow = false
        return view
    }
    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = DuplicateFinderSupport.stillMatches(file) ? file.url as NSURL : nil
    }
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) { view.previewItem = nil; view.close() }
}
