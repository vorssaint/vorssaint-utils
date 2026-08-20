// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The quarantine manager, embedded as a Settings page: pick files or apps
/// (drag them in, use the Finder selection, or browse), review which ones
/// still carry the com.apple.quarantine flag, then clear it from the ones
/// selected.
struct QuarantineManagerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var manager = QuarantineManagerService.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.quarantineManagerCommandBarEnabled) private var commandBarEnabled = true
    @State private var dropTargeted = false
    @State private var detailEntry: QuarantineManagerService.Entry?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(item: $detailEntry) { entry in
                QuarantineDetailView(entry: entry) { detailEntry = nil }
            }
    }

    private var commandBarToggle: some View {
        Form {
            Section {
                Toggle(l10n.s.quarantineManagerCommandBarToggle, isOn: $commandBarEnabled)
                Text(l10n.s.quarantineManagerCommandBarCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 420)
    }

    @ViewBuilder
    private var content: some View {
        switch manager.phase {
        case .empty: emptyState
        case .scanning: busyState(l10n.s.quarantineManagerScanning)
        case .results: resultsState
        case .removing: busyState(l10n.s.quarantineManagerRemoving)
        case let .done(cleared, failed): doneState(cleared: cleared, failed: failed)
        }
    }

    // MARK: Empty / drop

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(l10n.s.quarantineManagerIntroTitle)
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(l10n.s.quarantineManagerIntroBody)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 420)

            dropZoneOption

            HStack(spacing: 12) {
                Button(l10n.s.quarantineManagerPick) { manager.browseForTargets() }
                    .controlSize(.large)

                scanApplicationsOption
            }

            commandBarToggle

            if !permissions.fullDiskAccess {
                FullDiskAccessNote().frame(width: 420)
            }
            Spacer()
        }
        .padding(28)
    }

    private var scanApplicationsOption: some View {
        Button {
            manager.scanApplications()
        } label: {
            Label(l10n.s.quarantineManagerScanApplications, systemImage: "square.grid.2x2")
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 200)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var dropZoneOption: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
            .foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(dropTargeted ? Color.accentColor.opacity(0.06) : Color.clear)
            )
            .frame(maxWidth: 460)
            .frame(height: 220)
            .overlay(
                VStack(spacing: 12) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
                    Text(l10n.s.quarantineManagerDropTitle)
                        .font(.system(size: 16, weight: .semibold))
                    Text(l10n.s.quarantineManagerDropHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            )
            .animation(.easeOut(duration: 0.15), value: dropTargeted)
            .dropDestination(for: URL.self) { urls, _ in
                guard !urls.isEmpty else { return false }
                manager.scan(paths: urls)
                return true
            } isTargeted: { dropTargeted = $0 }
    }

    // MARK: Busy

    private func busyState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(message).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Results

    private var resultsState: some View {
        VStack(spacing: 0) {
            resultsHeader
            Divider()
            List(manager.entries) { entry in row(entry) }
                .listStyle(.inset)
            Divider()
            footer
        }
    }

    private var resultsHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.s.quarantineManagerFoundTitle).font(.system(size: 16, weight: .semibold))
                    if manager.totalFound > manager.entries.count {
                        Text("\(manager.entries.count) / \(manager.totalFound)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button { manager.refreshScan() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button(l10n.s.quarantineManagerSelectAll) { manager.selectAll() }
                .buttonStyle(.link)
                .disabled(manager.selection.count == manager.entries.count)
            Button(l10n.s.quarantineManagerClearSelection) { manager.selectNone() }
                .buttonStyle(.link)
                .disabled(manager.selection.isEmpty)
            Button { manager.reset() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    private func row(_ entry: QuarantineManagerService.Entry) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: selectionBinding(entry.id)).labelsHidden().toggleStyle(.checkbox)
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.path))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                Text(entry.relativePath)
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Button {
                detailEntry = entry
            } label: {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        HStack {
            Text(String(format: l10n.s.quarantineManagerSelectedFormat,
                        manager.selection.count, manager.entries.count))
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button(l10n.s.uninstallerCancel) { manager.reset() }
                .buttonStyle(.bordered)
            Button(l10n.s.quarantineManagerRemoveSelected) {
                manager.removeQuarantineFromSelected()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(manager.selection.isEmpty)
        }
        .padding(16)
    }

    // MARK: Done

    private func doneState(cleared: Int, failed: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
            Text(l10n.s.quarantineManagerDoneTitle).font(.system(size: 20, weight: .bold))
            Text(String(format: l10n.s.quarantineManagerClearedFormat, cleared))
                .font(.system(size: 13)).foregroundStyle(.secondary)
            if failed > 0 {
                Text(l10n.s.quarantineManagerSomeFailed)
                    .font(.caption).foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button(l10n.s.quarantineManagerContinue) { manager.continueAfterDone() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            Spacer()
        }
        .padding(28)
    }

    // MARK: Helpers

    private func selectionBinding(_ id: QuarantineManagerService.Entry.ID) -> Binding<Bool> {
        Binding(
            get: { manager.selection.contains(id) },
            set: { _ in manager.toggle(id) }
        )
    }
}

struct QuarantineDetailView: View {
    @ObservedObject private var l10n = L10n.shared
    let entry: QuarantineManagerService.Entry
    var onClose: () -> Void

    @State private var attributes: [QuarantineManagerSupport.XattrInfo] = []
    @State private var loadingAttributes = true
    @State private var showRemoveAllConfirm = false
    @State private var removingAll = false
    @State private var removingAttributeID: QuarantineManagerSupport.XattrInfo.ID?
    /// Attributes a real removal attempt confirmed the kernel silently
    /// ignores - discovered at runtime, since only `com.apple.provenance` is
    /// known up front. Locks the row so a second attempt isn't offered.
    @State private var confirmedProtected: Set<String> = []

    private var parsed: QuarantineManagerSupport.ParsedQuarantine? {
        QuarantineManagerSupport.parseQuarantineValue(entry.quarantineValue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(l10n.s.quarantineManagerDetailTitle).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text(entry.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Divider()
                if let parsed {
                    detailRow(l10n.s.quarantineManagerSource, parsed.source)
                    detailRow(l10n.s.quarantineManagerDownloadDate, parsed.date)
                    detailRow(l10n.s.quarantineManagerFlags, parsed.flags.joined(separator: ", "))
                    Divider()
                }
                detailRow(l10n.s.quarantineManagerRawValue, entry.quarantineValue)
                Divider()
                HStack(spacing: 10) {
                    Button(l10n.s.quarantineManagerCopyPath) { copy(entry.path) }
                    Button(l10n.s.quarantineManagerCopyCommand) {
                        let flag = entry.isApp ? "-dr" : "-d"
                        copy("xattr \(flag) com.apple.quarantine \(Self.shellQuote(entry.path))")
                    }
                    Spacer()
                }
                Divider()
                allAttributesSection
            }
            .padding(20)
        }
        .frame(width: 420, height: 480)
        .onAppear { loadAttributes() }
        .alert(l10n.s.quarantineManagerRemoveAllConfirmTitle, isPresented: $showRemoveAllConfirm) {
            Button(l10n.s.uninstallerCancel, role: .cancel) {}
            Button(l10n.s.quarantineManagerRemoveAllAttributes, role: .destructive) { removeAllAttributes() }
        } message: {
            Text(l10n.s.quarantineManagerRemoveAllConfirmBody)
        }
    }

    private var allAttributesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.s.quarantineManagerAllAttributesTitle)
                .font(.system(size: 12, weight: .semibold))
            if loadingAttributes {
                ProgressView().controlSize(.small)
            } else {
                ForEach(attributes) { attribute in
                    attributeRow(attribute)
                }
            }
            Button(role: .destructive) {
                showRemoveAllConfirm = true
            } label: {
                Label(l10n.s.quarantineManagerRemoveAllAttributes, systemImage: "trash")
            }
            .disabled(removingAll || loadingAttributes || attributes.isEmpty)
            .padding(.top, 4)
        }
    }

    private func attributeRow(_ attribute: QuarantineManagerSupport.XattrInfo) -> some View {
        let removable = QuarantineManagerSupport.isRemovable(attribute.name)
            && !confirmedProtected.contains(attribute.name)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(attribute.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                    if attribute.isBinaryDisplay {
                        Image(systemName: "number").font(.system(size: 8)).foregroundStyle(.tertiary)
                            .help(l10n.s.quarantineManagerBinaryValueHint)
                    }
                }
                Text(attribute.value)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            if removable {
                Button {
                    removeAttribute(attribute)
                } label: {
                    Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(removingAttributeID != nil)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .help(l10n.s.quarantineManagerAttributeProtected)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
        }
    }

    private func loadAttributes() {
        loadingAttributes = true
        let path = entry.path
        DispatchQueue.global(qos: .userInitiated).async {
            let found = QuarantineManagerService.readAllAttributes(at: path)
            DispatchQueue.main.async {
                attributes = found
                loadingAttributes = false
            }
        }
    }

    private func removeAttribute(_ attribute: QuarantineManagerSupport.XattrInfo) {
        removingAttributeID = attribute.id
        let path = entry.path
        let recursive = entry.isApp
        let name = attribute.name
        DispatchQueue.global(qos: .userInitiated).async {
            let removed = QuarantineManagerService.removeAttribute(named: name, at: path, recursive: recursive)
            DispatchQueue.main.async {
                removingAttributeID = nil
                if !removed { confirmedProtected.insert(name) }
                loadAttributes()
                if removed, name == "com.apple.quarantine" {
                    QuarantineManagerService.shared.removeEntryFromList(entry.id)
                }
            }
        }
    }

    private func removeAllAttributes() {
        removingAll = true
        let path = entry.path
        let recursive = entry.isApp
        DispatchQueue.global(qos: .userInitiated).async {
            _ = QuarantineManagerService.removeAllAttributes(at: path, recursive: recursive)
            DispatchQueue.main.async {
                removingAll = false
                onClose()
                QuarantineManagerService.shared.removeEntryFromList(entry.id)
            }
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private static func shellQuote(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
