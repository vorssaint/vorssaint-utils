// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The combo mode page: the switch, the trigger shortcut (none until one is
/// recorded) and the keymap as a collapsible tree. Every edit goes through
/// `ComboKeymap`, which keeps keys unique within each group, and is saved at
/// once so the next combo uses it.
struct ComboModeSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ComboModeService.shared
    @AppStorage(DefaultsKey.comboModeEnabled) private var enabled = false
    @AppStorage(DefaultsKey.comboModeTrigger) private var triggerRaw = ComboTrigger.clearedStorageValue
    @AppStorage(DefaultsKey.comboModePresentation) private var presentationRaw = ComboPresentation.defaultValue.rawValue
    @AppStorage(DefaultsKey.notchEnabled) private var notchEnabled = false
    @ObservedObject private var features = FeatureRuntime.shared
    @State private var keymap = ComboModeService.shared.loadKeymap()
    @State private var collapsed: Set<UUID> = []
    @State private var keyErrors: [UUID: String] = [:]
    @State private var editor: ComboActionDraft?

    private var text: ComboModeFeatureStrings { FeatureStrings.comboMode(l10n.language) }

    var body: some View {
        Form {
            Section {
                Toggle(text.enableToggle, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in service.syncWithPreferences() }
                Text(text.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ComboTriggerRow(rawValue: $triggerRaw, isEnabled: enabled, text: text)
                if enabled, ComboTrigger.shortcut(storedValue: triggerRaw) == nil {
                    Text(text.triggerNeeded)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if enabled, service.shortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            presentationSection

            Section {
                if keymap.nodes.isEmpty {
                    Text(text.emptyKeymap)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    rowView(row)
                }
                HStack(spacing: 8) {
                    addButtons(parentID: nil)
                    Spacer()
                }
            } header: {
                Text(text.keymapTitle)
            } footer: {
                Text(text.keymapCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { keymap = service.loadKeymap() }
        .sheet(item: $editor) { draft in
            ComboActionEditor(text: text, draft: draft) { app in
                apply(draft, app: app)
            }
        }
    }

    // MARK: Presentation

    /// Dynamic Island is installed and on; otherwise an island choice opens
    /// centered, as `ComboPresentation.resolved` decides.
    private var islandEnabled: Bool { features.isAvailable(.notch) && notchEnabled }

    private var presentationSection: some View {
        let selected = ComboPresentation.stored(presentationRaw)
        return Section {
            HStack(spacing: 10) {
                ForEach(ComboPresentation.allCases) { item in
                    NotchMascotChoiceTile(title: title(for: item), selected: selected == item) {
                        presentationRaw = item.rawValue
                    } preview: {
                        ComboPresentationSample(presentation: item)
                    }
                }
            }
            if selected == .island, !islandEnabled {
                Text(text.presentationIslandOff)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(text.presentationTitle)
        }
    }

    private func title(for presentation: ComboPresentation) -> String {
        switch presentation {
        case .centered: return text.presentationCentered
        case .island: return text.presentationIsland
        case .chip: return text.presentationChip
        }
    }

    // MARK: Rows

    private struct Row: Identifiable {
        let node: ComboNode
        let parentID: UUID?
        let depth: Int
        let index: Int
        let siblingCount: Int
        /// An empty group shows a hint row under itself.
        var isEmptyHint = false
        var id: String { isEmptyHint ? "empty-\(node.id)" : node.id.uuidString }
    }

    private var rows: [Row] {
        var result: [Row] = []
        func walk(_ level: [ComboNode], parentID: UUID?, depth: Int) {
            for (index, node) in level.enumerated() {
                result.append(Row(node: node, parentID: parentID, depth: depth,
                                  index: index, siblingCount: level.count))
                guard node.isGroup, !collapsed.contains(node.id) else { continue }
                if node.children.isEmpty {
                    result.append(Row(node: node, parentID: parentID, depth: depth + 1,
                                      index: 0, siblingCount: 0, isEmptyHint: true))
                } else {
                    walk(node.children, parentID: node.id, depth: depth + 1)
                }
            }
        }
        walk(keymap.nodes, parentID: nil, depth: 0)
        return result
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        if row.isEmptyHint {
            Text(text.emptyGroup)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, indent(row.depth) + 22)
        } else {
            let node = row.node
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    disclosure(node)
                    ComboKeyField(key: node.key,
                                  flagged: keyErrors[node.id] != nil
                                      || keymap.nodesWithKeyIssues.contains(node.id),
                                  accessibilityLabel: text.keyLabel) { typed in
                        setKey(typed, for: node, parentID: row.parentID)
                    }
                    icon(for: node)
                    TextField(text.labelPlaceholder,
                              text: labelBinding(node),
                              prompt: Text(node.displayLabel.isEmpty ? text.labelPlaceholder : node.displayLabel))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(minWidth: 90)
                    if node.isGroup {
                        addButtons(parentID: node.id)
                    } else if let action = node.action {
                        ComboActionPill(action: action, text: text)
                        Button(text.edit) {
                            editor = ComboActionDraft(nodeID: node.id, parentID: row.parentID, action: action)
                        }
                    }
                    Button {
                        delete(node)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(text.delete)
                    .accessibilityLabel(text.delete)
                }
                if let error = keyErrors[node.id] {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.leading, 22)
                }
            }
            .padding(.leading, indent(row.depth))
            .contextMenu {
                Button(text.moveUp) { move(node, parentID: row.parentID, to: row.index - 1) }
                    .disabled(row.index == 0)
                Button(text.moveDown) { move(node, parentID: row.parentID, to: row.index + 2) }
                    .disabled(row.index >= row.siblingCount - 1)
                Divider()
                Button(text.delete, role: .destructive) { delete(node) }
            }
        }
    }

    private func indent(_ depth: Int) -> CGFloat { CGFloat(depth) * 20 }

    @ViewBuilder
    private func disclosure(_ node: ComboNode) -> some View {
        if node.isGroup {
            Button {
                if collapsed.contains(node.id) { collapsed.remove(node.id) } else { collapsed.insert(node.id) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(collapsed.contains(node.id) ? 0 : 90))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        } else {
            Color.clear.frame(width: 14, height: 14)
        }
    }

    @ViewBuilder
    private func icon(for node: ComboNode) -> some View {
        if let symbol = node.groupSymbol {
            Menu {
                ForEach(ComboNode.groupSymbols, id: \.self) { candidate in
                    Button {
                        edit(node.id) { $0.content = .group(symbol: candidate, children: $0.children) }
                    } label: {
                        Image(systemName: candidate)
                    }
                }
            } label: {
                Image(systemName: symbol)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(text.groupIcon)
            .accessibilityLabel(text.groupIcon)
        } else {
            ComboNodeIcon(node: node, size: 18)
        }
    }

    private func addButtons(parentID: UUID?) -> some View {
        HStack(spacing: 6) {
            Button {
                editor = ComboActionDraft(nodeID: nil, parentID: parentID, action: nil)
            } label: {
                Label(text.addAction, systemImage: "plus")
            }
            Button {
                addGroup(parentID: parentID)
            } label: {
                Label(text.addGroup, systemImage: "plus")
            }
        }
        .controlSize(.small)
    }

    private func labelBinding(_ node: ComboNode) -> Binding<String> {
        Binding {
            keymap.node(id: node.id)?.label ?? ""
        } set: { newValue in
            edit(node.id) { $0.label = newValue }
        }
    }

    // MARK: Edits

    private func persist() {
        service.saveKeymap(keymap)
    }

    private func edit(_ id: UUID, _ change: (inout ComboNode) -> Void) {
        if keymap.update(id: id, change) { persist() }
    }

    private func setKey(_ typed: String, for node: ComboNode, parentID: UUID?) {
        if let issue = keymap.keyIssue(typed, parentID: parentID, excluding: node.id) {
            switch issue {
            case .empty: keyErrors[node.id] = text.keyEmpty
            case .invalid: keyErrors[node.id] = text.keyInvalid
            case .duplicate: keyErrors[node.id] = String(format: text.keyDuplicateFormat, ComboKey.display(typed))
            }
            return
        }
        keyErrors[node.id] = nil
        edit(node.id) { $0.key = typed }
    }

    private func addGroup(parentID: UUID?) {
        let group = ComboNode.group(key: keymap.nextFreeKey(parentID: parentID) ?? "",
                                    label: text.newGroup)
        if keymap.insert(group, into: parentID) {
            if let parentID { collapsed.remove(parentID) }
            persist()
        }
    }

    private func delete(_ node: ComboNode) {
        if keymap.remove(id: node.id) != nil {
            keyErrors[node.id] = nil
            persist()
        }
    }

    private func move(_ node: ComboNode, parentID: UUID?, to index: Int) {
        if keymap.move(id: node.id, to: parentID, at: max(0, index)) { persist() }
    }

    private func apply(_ draft: ComboActionDraft, app: ComboAppReference) {
        let action = ComboAction.openApplication(app)
        if let id = draft.nodeID {
            edit(id) { node in
                // A label still naming the old app follows the new one.
                if case .action(.openApplication(let old)) = node.content,
                   node.label == ComboModeService.name(for: old) {
                    node.label = ComboModeService.name(for: app)
                }
                node.content = .action(action)
            }
        } else {
            let node = ComboNode.action(key: keymap.nextFreeKey(parentID: draft.parentID) ?? "",
                                        label: ComboModeService.name(for: app),
                                        action)
            if keymap.insert(node, into: draft.parentID) {
                if let parentID = draft.parentID { collapsed.remove(parentID) }
                persist()
            }
        }
    }
}

// MARK: - Trigger

/// The trigger recorder. Same rules as the other recorders, but with no
/// default: clearing leaves no shortcut at all.
private struct ComboTriggerRow: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var rawValue: String
    let isEnabled: Bool
    let text: ComboModeFeatureStrings
    @State private var errorText: String?
    @State private var isRecording = false
    @State private var pendingTakeOver: GlobalShortcut?

    private var shortcut: GlobalShortcut? { ComboTrigger.shortcut(storedValue: rawValue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(text.triggerLabel)
                Spacer()
                ShortcutRecorderButton(shortcut: pendingTakeOver ?? shortcut ?? .quickLauncherDefault,
                                       isEnabled: isEnabled,
                                       waitingTitle: l10n.s.shortcutPressKeys,
                                       emptyTitle: pendingTakeOver == nil && shortcut == nil ? l10n.s.shortcutNone : nil,
                                       clearAction: clear,
                                       notCapturedAction: { errorText = l10n.s.shortcutNotCaptured },
                                       recordingChanged: { recording in
                                           isRecording = recording
                                           if recording {
                                               errorText = nil
                                               pendingTakeOver = nil
                                           }
                                       },
                                       invalidAction: { errorText = l10n.s.shortcutInvalid },
                                       captureAction: save)
                    .frame(width: 108)
                    .disabled(!isEnabled)
                Button {
                    clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled || shortcut == nil)
                .help(l10n.s.shortcutClear)
                .accessibilityLabel(l10n.s.shortcutClear)
            }
            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if isRecording {
                Text(ShortcutRecordingCaption.text(l10n.s, canClear: true))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(text.triggerCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let pendingTakeOver {
                SystemShortcutTakeOverOffer(
                    shortcut: pendingTakeOver,
                    onAccept: {
                        rawValue = pendingTakeOver.storageValue
                        SystemShortcutTakeover.setTakeOver(DefaultsKey.comboModeTrigger, true)
                        self.pendingTakeOver = nil
                        ComboModeService.shared.syncWithPreferences()
                    },
                    onDismiss: {
                        self.pendingTakeOver = nil
                        errorText = String(format: l10n.s.shortcutConflictFormat, "macOS")
                    }
                )
            }
        }
        .onChange(of: l10n.language) { _, _ in errorText = nil }
    }

    private func clear() {
        rawValue = ComboTrigger.clearedStorageValue
        errorText = nil
        pendingTakeOver = nil
        SystemShortcutTakeover.setTakeOver(DefaultsKey.comboModeTrigger, false)
        ComboModeService.shared.syncWithPreferences()
    }

    private func save(_ shortcut: GlobalShortcut) {
        if let conflict = GlobalShortcutRole.conflict(for: shortcut, excluding: nil) {
            errorText = String(format: l10n.s.shortcutConflictFormat, conflict.title(l10n.s))
            return
        }
        if let conflict = WindowLayoutService.shared.shortcutConflictTitle(shortcut, excluding: nil) {
            errorText = String(format: l10n.s.shortcutConflictFormat, conflict)
            return
        }
        switch SystemShortcutTakeoverSupport.recorderDecision(
            shortcut: shortcut,
            conflictsWithMacOS: SystemShortcutTakeover.conflictsWithMacOS(shortcut),
            takenOver: SystemShortcutTakeover.isTakenOver(DefaultsKey.comboModeTrigger),
            current: ComboTrigger.shortcut(storedValue: rawValue)) {
        case .offer:
            pendingTakeOver = shortcut
            errorText = nil
            return
        case .save(let clearTakeOver):
            rawValue = shortcut.storageValue
            errorText = nil
            if clearTakeOver { SystemShortcutTakeover.setTakeOver(DefaultsKey.comboModeTrigger, false) }
        }
        ComboModeService.shared.syncWithPreferences()
    }
}

// MARK: - Key field

/// A keycap that records the next key pressed after a click. A rejected key
/// leaves the saved one in place. It is a button rather than a text field:
/// a field rewriting its own text from its change handler sent the grouped
/// form into a layout loop that AppKit ends with an exception.
private struct ComboKeyField: View {
    let key: String
    let flagged: Bool
    let accessibilityLabel: String
    let commit: (String) -> Void
    @State private var monitor: Any?

    private var isRecording: Bool { monitor != nil }

    var body: some View {
        Button(action: toggleRecording) {
            Text(isRecording ? "…" : ComboKey.display(key))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .frame(minWidth: 18)
        }
        .frame(width: 34)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(isRecording ? Color.accentColor : Color.orange,
                              lineWidth: isRecording || flagged ? 1.5 : 0)
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(ComboKey.display(key))
        .onDisappear(perform: stopRecording)
    }

    private func toggleRecording() {
        if isRecording { stopRecording(); return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let press = ComboKeyPress.classify(
                keyCode: event.keyCode,
                characters: event.characters,
                isRepeat: event.isARepeat,
                hasCommandOrControl: !event.modifierFlags.intersection([.command, .control]).isEmpty
            )
            switch press {
            case .ignore:
                // ⌘ and ⌃ combinations keep their usual meaning.
                return event.isARepeat ? nil : event
            case .cancel, .back:
                stopRecording()
            case .key(let typed):
                stopRecording()
                // Applied after the key event finishes, outside any update.
                DispatchQueue.main.async { commit(typed) }
            case .unusable:
                NSSound.beep()
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - Action pill and editor

private struct ComboActionPill: View {
    let action: ComboAction
    let text: ComboModeFeatureStrings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            switch action {
            case .openApplication(let app):
                Image(nsImage: ComboModeService.icon(for: app))
                    .resizable()
                    .frame(width: 14, height: 14)
                Text(ComboModeService.url(for: app) == nil
                     ? text.appMissing
                     : "\(ComboModeService.name(for: app)) · \(text.openVerb)")
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(PanelSurface.controlFill(for: colorScheme)))
        .overlay(Capsule().strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.5))
        .fixedSize()
    }
}

/// What the action editor sheet is editing: an existing action, or a new one
/// to add under `parentID`.
struct ComboActionDraft: Identifiable {
    let id = UUID()
    let nodeID: UUID?
    let parentID: UUID?
    let action: ComboAction?
}

private struct ComboActionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let text: ComboModeFeatureStrings
    let draft: ComboActionDraft
    let save: (ComboAppReference) -> Void
    @State private var app: ComboAppReference?

    init(text: ComboModeFeatureStrings, draft: ComboActionDraft, save: @escaping (ComboAppReference) -> Void) {
        self.text = text
        self.draft = draft
        self.save = save
        if case .openApplication(let app) = draft.action {
            _app = State(initialValue: app)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text.actionEditorTitle)
                .font(.headline)
            Form {
                Picker(text.actionTypeLabel, selection: .constant(0)) {
                    Text(text.openApplication).tag(0)
                }
                LabeledContent(text.openApplication) {
                    HStack(spacing: 8) {
                        if let app {
                            Image(nsImage: ComboModeService.icon(for: app))
                                .resizable()
                                .frame(width: 18, height: 18)
                            Text(ComboModeService.url(for: app) == nil
                                 ? text.appMissing
                                 : ComboModeService.name(for: app))
                                .lineLimit(1)
                        } else {
                            Text(text.noAppChosen)
                                .foregroundStyle(.secondary)
                        }
                        Button(text.chooseApp) {
                            if let chosen = ComboModeService.chooseApplication() { app = chosen }
                        }
                    }
                }
            }
            .formStyle(.columns)
            HStack {
                Spacer()
                Button(text.cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(text.done) {
                    if let app { save(app) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(app == nil)
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}

/// A small screen with the combo where it would appear: a panel in the
/// middle, the opened island at the top, or a pill at the bottom.
private struct ComboPresentationSample: View {
    let presentation: ComboPresentation

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
            }
            .frame(width: 84, height: 50)
            .overlay(alignment: alignment) { mark }
            .frame(height: 50)
            .accessibilityHidden(true)
    }

    private var alignment: Alignment {
        switch presentation {
        case .centered: return .center
        case .island: return .top
        case .chip: return .bottom
        }
    }

    @ViewBuilder private var mark: some View {
        switch presentation {
        case .centered:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.55))
                .frame(width: 34, height: 24)
                .overlay { lines(count: 3) }
        case .island:
            NotchShape(attached: true, radius: NotchLayout.surfaceRadius(height: 18))
                .islandSample()
                .frame(width: 50, height: 18)
                .overlay(alignment: .bottom) { lines(count: 1).padding(.bottom, 4) }
        case .chip:
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.55))
                .frame(width: 46, height: 9)
                .padding(.bottom, 5)
        }
    }

    private func lines(count: Int) -> some View {
        VStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { _ in
                Capsule().fill(.white.opacity(0.5)).frame(width: 22, height: 2)
            }
        }
    }
}
