// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings > Radial menu: the switch, the shortcut, where the wheel opens
/// and the list of actions, with drill-down into submenus and an editor sheet
/// per action.
struct RadialMenuSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = RadialMenuService.shared
    @AppStorage(DefaultsKey.radialMenuEnabled) private var enabled = false
    @AppStorage(DefaultsKey.radialMenuAtPointer) private var atPointer = true
    @AppStorage(DefaultsKey.radialMenuMouseButton) private var mouseTriggerRaw = RadialMenuMouseTrigger.off.rawValue

    @State private var items = RadialMenuSupport.decode(
        UserDefaults.standard.data(forKey: DefaultsKey.radialMenuItems))
    /// The submenu being edited; empty means the root wheel.
    @State private var openSubmenuID: UUID?
    @State private var editing: RadialMenuItem?
    @State private var editingIsNew = false
    @State private var dragging: RadialMenuItem?

    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }

    /// Falls back to the root when the drilled submenu no longer exists (a
    /// restored backup can pull it away), so the list never strands empty.
    private var level: [RadialMenuItem] {
        guard let openSubmenu else { return items }
        return openSubmenu.children
    }

    private var openSubmenu: RadialMenuItem? {
        guard let openSubmenuID else { return nil }
        return items.first { $0.id == openSubmenuID }
    }

    var body: some View {
        Form {
            Section {
                Toggle(text.enableLabel, isOn: $enabled)
                Text(text.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ShortcutPreferenceRow(role: .radialMenu, isEnabled: enabled) {
                    RadialMenuService.shared.syncWithPreferences()
                }
                if service.registrationFailed {
                    Text(l10n.s.shortcutInvalid)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Picker(text.mouseTriggerLabel, selection: $mouseTriggerRaw) {
                    Text(text.mouseTriggerOff).tag(RadialMenuMouseTrigger.off.rawValue)
                    Text(text.mouseTriggerBack).tag(RadialMenuMouseTrigger.back.rawValue)
                    Text(text.mouseTriggerForward).tag(RadialMenuMouseTrigger.forward.rawValue)
                }
                .disabled(!enabled)
                .onChange(of: mouseTriggerRaw) { _, raw in
                    RadialMenuService.shared.syncWithPreferences()
                    if RadialMenuMouseTrigger.sanitized(raw) != .off, !permissions.accessibility {
                        permissions.requestAccessibility()
                    }
                }
                if RadialMenuMouseTrigger.sanitized(mouseTriggerRaw) != .off {
                    Text(text.mouseTriggerWarning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // A button the mouse's own software has turned into
                    // something else never reaches any app, and from the
                    // outside that looks exactly like a wrong setting. This
                    // tells the two apart without asking anyone to guess.
                    buttonTestRow
                }
                Picker(text.positionLabel, selection: $atPointer) {
                    Text(text.positionPointer).tag(true)
                    Text(text.positionCenter).tag(false)
                }
                .pickerStyle(.segmented)
                Button(text.tryButton) {
                    RadialMenuService.shared.presentPreview()
                }
            } header: {
                Text(text.pageTitle)
            }

            if RadialMenuSupport.needsAccessibility(items)
                || RadialMenuMouseTrigger.sanitized(mouseTriggerRaw) != .off,
               !permissions.accessibility {
                Section {
                    PermissionRow(kind: .accessibility)
                    Text(text.permissionCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if let openSubmenu {
                    Button {
                        openSubmenuID = nil
                        dragging = nil
                    } label: {
                        Label("\(text.backButton)  \(openSubmenu.displayName(text))",
                              systemImage: "chevron.backward")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
                if level.isEmpty {
                    Text(text.emptyCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(level) { item in
                    RadialItemRow(item: item,
                                  text: text,
                                  dragging: $dragging,
                                  edit: {
                                      editingIsNew = false
                                      editing = item
                                  },
                                  remove: { remove(id: item.id) },
                                  openChildren: item.kind == .submenu ? { openSubmenuID = item.id } : nil,
                                  moveHandler: { moved, target in move(moved, before: target) })
                }
                if level.count < RadialMenuSupport.maxItemsPerWheel {
                    Button {
                        // A fresh draft per tap: the sheet keys its identity
                        // to the item id, so state can never leak from one
                        // add into the next (a leaked id made every save
                        // replace the previous action instead of appending).
                        editingIsNew = true
                        editing = RadialMenuItem(kind: .app)
                    } label: {
                        Label(text.addButton, systemImage: "plus")
                    }
                }
            } header: {
                Text(text.actionsHeader)
            } footer: {
                Text(level.count >= RadialMenuSupport.maxItemsPerWheel ? text.limitCaption : text.hubDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // A drag released outside every row lands here, so the lifted row
        // never stays stuck at reduced opacity.
        .onDrop(of: [UTType.text], delegate: RadialDragCleanupDelegate(dragging: $dragging))
        .sheet(item: $editing) { item in
            RadialItemEditor(text: text,
                             item: item,
                             isNew: editingIsNew,
                             allowsSubmenu: openSubmenuID == nil,
                             save: { upsert($0) },
                             delete: editingIsNew ? nil : { remove(id: item.id) })
        }
        .onChange(of: enabled) { _, on in
            RadialMenuService.shared.syncWithPreferences()
            requestAccessibilityIfNeeded(on)
        }
    }

    // MARK: - Mutations (every change lands in defaults right away)

    private func setLevel(_ new: [RadialMenuItem]) {
        if let openSubmenuID, let index = items.firstIndex(where: { $0.id == openSubmenuID }) {
            items[index].children = new
        } else {
            items = new
        }
        persist()
    }

    private func upsert(_ item: RadialMenuItem) {
        RadialMenuIconStore.invalidate(item.payload)
        var new = level
        if let index = new.firstIndex(where: { $0.id == item.id }) {
            new[index] = item
        } else {
            new.append(item)
        }
        setLevel(new)
    }

    private func remove(id: UUID) {
        setLevel(level.filter { $0.id != id })
    }

    private func move(_ moved: RadialMenuItem, before target: RadialMenuItem) {
        var new = level
        guard let from = new.firstIndex(where: { $0.id == moved.id }),
              let to = new.firstIndex(where: { $0.id == target.id }),
              from != to else { return }
        new.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        setLevel(new)
    }

    private func persist() {
        UserDefaults.standard.set(RadialMenuSupport.encode(items), forKey: DefaultsKey.radialMenuItems)
    }

    private func requestAccessibilityIfNeeded(_ on: Bool) {
        guard on, RadialMenuSupport.needsAccessibility(items), !permissions.accessibility else { return }
        permissions.requestAccessibility()
    }

    private var buttonTestRow: some View {
        let seen = service.lastMouseButtonSeen
        let expected = RadialMenuMouseTrigger.sanitized(mouseTriggerRaw).buttonNumber
        let state: (icon: String, tint: Color, message: String) = {
            if !service.isWatchingMouseButton {
                return ("exclamationmark.circle.fill", .orange, text.buttonTestBlind)
            }
            guard let seen else {
                return ("circle.dashed", .secondary, text.buttonTestWaiting)
            }
            if let expected, Int64(seen) == expected {
                return ("checkmark.circle.fill", .green, text.buttonTestSeen)
            }
            return ("exclamationmark.circle.fill", .orange, text.buttonTestOther)
        }()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: state.icon)
                    .foregroundStyle(state.tint)
                Text(text.buttonTestLabel)
                Spacer()
                Text(state.message)
                    .foregroundStyle(.secondary)
            }
            Text(text.buttonTestHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { RadialMenuService.shared.setReportingMouseButtons(true) }
        .onDisappear { RadialMenuService.shared.setReportingMouseButtons(false) }
    }
}

// MARK: - Row

private struct RadialItemRow: View {
    let item: RadialMenuItem
    let text: RadialMenuFeatureStrings
    @Binding var dragging: RadialMenuItem?
    let edit: () -> Void
    let remove: () -> Void
    let openChildren: (() -> Void)?
    let moveHandler: (RadialMenuItem, RadialMenuItem) -> Void

    private var kindLabel: String {
        switch item.kind {
        case .app: return text.kindApp
        case .file: return text.kindFile
        case .url: return text.kindURL
        case .shortcut: return text.kindShortcut
        case .tool: return text.kindTool
        case .media: return text.kindMedia
        case .submenu: return text.kindSubmenu
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            Button(action: edit) {
                HStack(spacing: 10) {
                    badge
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.displayName(text))
                        Text(kindLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let openChildren {
                Button(action: openChildren) {
                    Label(text.editActionsButton, systemImage: "chevron.forward")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(text.editActionsButton)
            }
        }
        .opacity(dragging == item ? 0.45 : 1)
        .contentShape(Rectangle())
        .onDrag {
            dragging = item
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: RadialItemDropDelegate(target: item,
                                                                    dragging: $dragging,
                                                                    moveHandler: moveHandler))
        .contextMenu {
            Button(text.deleteButton, role: .destructive) {
                dragging = nil
                remove()
            }
        }
    }

    @ViewBuilder
    private var badge: some View {
        if item.usesFileIcon {
            Image(nsImage: RadialMenuIconStore.fileIcon(for: item.payload))
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .frame(width: 30, height: 30)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.spaceGradient)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: item.effectiveSymbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
    }
}

private struct RadialDragCleanupDelegate: DropDelegate {
    @Binding var dragging: RadialMenuItem?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

private struct RadialItemDropDelegate: DropDelegate {
    let target: RadialMenuItem
    @Binding var dragging: RadialMenuItem?
    let moveHandler: (RadialMenuItem, RadialMenuItem) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.easeInOut(duration: 0.12)) {
            moveHandler(dragging, target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

// MARK: - Editor sheet

private struct RadialItemEditor: View {
    let text: RadialMenuFeatureStrings
    @State var item: RadialMenuItem
    let isNew: Bool
    let allowsSubmenu: Bool
    let save: (RadialMenuItem) -> Void
    let delete: (() -> Void)?

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.dismiss) private var dismiss
    @State private var shortcutMessage: ShortcutMessage?

    /// What the line under the form is saying about the shortcut field: the
    /// calm hint while it listens, or the reason a press did not stick.
    enum ShortcutMessage {
        case hint(String)
        case problem(String)

        var text: String {
            switch self {
            case .hint(let text), .problem(let text): return text
            }
        }

        var isProblem: Bool {
            if case .problem = self { return true }
            return false
        }
    }

    private var availableTools: [RadialMenuTool] {
        RadialMenuTool.allCases.filter { $0.isRunnable() }
    }

    private var urlIsInvalid: Bool {
        item.kind == .url && RadialMenuSupport.normalizedURL(item.payload) == nil
    }

    // The same rule sanitized() applies, so the editor can never save an item
    // the wheel would silently drop.
    private var saveDisabled: Bool {
        !RadialMenuSupport.isValidPayload(item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? text.addButton : item.displayName(text))
                .font(.headline)

            Form {
                Picker(text.actionLabel, selection: kindBinding) {
                    Text(text.kindApp).tag(RadialMenuItem.Kind.app)
                    Text(text.kindFile).tag(RadialMenuItem.Kind.file)
                    Text(text.kindURL).tag(RadialMenuItem.Kind.url)
                    Text(text.kindShortcut).tag(RadialMenuItem.Kind.shortcut)
                    if !availableTools.isEmpty {
                        Text(text.kindTool).tag(RadialMenuItem.Kind.tool)
                    }
                    Text(text.kindMedia).tag(RadialMenuItem.Kind.media)
                    if allowsSubmenu {
                        Text(text.kindSubmenu).tag(RadialMenuItem.Kind.submenu)
                    }
                }

                payloadEditor

                TextField(text.nameLabel, text: $item.name, prompt: Text(text.automaticLabel))

                RadialSymbolPicker(text: text, item: $item)
            }
            .formStyle(.columns)

            if urlIsInvalid, !item.payload.isEmpty {
                Text(text.urlInvalid)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if item.kind == .shortcut, let shortcutMessage {
                Text(shortcutMessage.text)
                    .font(.caption)
                    .foregroundStyle(shortcutMessage.isProblem ? AnyShapeStyle(.orange)
                                                               : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if item.kind == .submenu {
                Text(text.submenuCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if let delete {
                    Button(role: .destructive) {
                        delete()
                        dismiss()
                    } label: {
                        Text(text.deleteButton)
                    }
                }
                Spacer()
                Button(l10n.s.uninstallerCancel) { dismiss() }
                Button(text.saveButton) {
                    var saved = item
                    saved.name = item.name.trimmingCharacters(in: .whitespaces)
                    save(saved)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(saveDisabled)
            }
        }
        .padding(18)
        .frame(width: 440)
    }

    /// Changing the action type clears targets that no longer make sense but
    /// keeps the custom name and icon.
    private var kindBinding: Binding<RadialMenuItem.Kind> {
        Binding(get: { item.kind }, set: { kind in
            guard kind != item.kind else { return }
            item.kind = kind
            shortcutMessage = nil
            switch kind {
            case .tool: item.payload = availableTools.first?.rawValue ?? ""
            case .media: item.payload = RadialMenuMediaKey.playPause.rawValue
            default: item.payload = ""
            }
            if kind != .submenu { item.children = [] }
        })
    }

    @ViewBuilder
    private var payloadEditor: some View {
        switch item.kind {
        case .app:
            LabeledContent(text.kindApp) {
                Button(chooseTitle) { choose(applications: true) }
            }
        case .file:
            LabeledContent(text.kindFile) {
                Button(chooseTitle) { choose(applications: false) }
            }
        case .url:
            TextField(text.kindURL, text: $item.payload, prompt: Text(text.urlPlaceholder))
        case .shortcut:
            LabeledContent(text.kindShortcut) {
                ShortcutRecorderButton(shortcut: GlobalShortcut(storageValue: item.payload) ?? .radialMenuDefault,
                                       isEnabled: true,
                                       waitingTitle: l10n.s.shortcutPressKeys,
                                       emptyTitle: item.payload.isEmpty ? l10n.s.shortcutNone : nil,
                                       clearAction: {
                                           item.payload = ""
                                           shortcutMessage = nil
                                       },
                                       notCapturedAction: {
                                           shortcutMessage = .problem(l10n.s.shortcutNotCaptured)
                                       },
                                       recordingChanged: { recording in
                                           shortcutMessage = recording
                                               ? .hint(ShortcutRecordingCaption.text(l10n.s, canClear: true))
                                               : nil
                                       },
                                       invalidAction: {
                                           shortcutMessage = .problem(l10n.s.shortcutInvalid)
                                       },
                                       captureAction: {
                                           item.payload = $0.storageValue
                                           shortcutMessage = nil
                                       })
                    .frame(width: 108)
            }
        case .tool:
            Picker(text.toolLabel, selection: $item.payload) {
                ForEach(availableTools) { tool in
                    Text(tool.feature.hubTitle(l10n.s, hub: FeatureStrings.hub(l10n.language)))
                        .tag(tool.rawValue)
                }
            }
        case .media:
            Picker(text.mediaLabel, selection: $item.payload) {
                Text(text.mediaPlayPause).tag(RadialMenuMediaKey.playPause.rawValue)
                Text(text.mediaPrevious).tag(RadialMenuMediaKey.previousTrack.rawValue)
                Text(text.mediaNext).tag(RadialMenuMediaKey.nextTrack.rawValue)
            }
        case .submenu:
            EmptyView()
        }
    }

    private var chooseTitle: String {
        if item.payload.isEmpty { return text.chooseButton }
        return RadialMenuIconStore.fileName(for: item.payload)
    }

    private func choose(applications: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = !applications
        if applications {
            panel.allowedContentTypes = [.applicationBundle]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        RadialMenuIconStore.invalidate(item.payload)
        item.payload = url.path
    }
}

// MARK: - Icon picker

/// "Automatic" plus a small curated grid; automatic means the real app or
/// file icon when the target has one, or the action's own symbol.
private struct RadialSymbolPicker: View {
    let text: RadialMenuFeatureStrings
    @Binding var item: RadialMenuItem

    private static let symbols = [
        "star.fill", "heart.fill", "bolt.fill", "flame.fill", "sparkles",
        "folder.fill", "doc.fill", "tray.full.fill", "terminal.fill", "globe",
        "envelope.fill", "message.fill", "music.note", "headphones", "camera.fill",
        "photo.fill", "video.fill", "gamecontroller.fill", "calendar", "clock.fill",
        "house.fill", "cart.fill", "hammer.fill", "paintbrush.fill", "book.fill",
        "keyboard", "magnifyingglass", "airplane",
    ]

    private let columns = [GridItem(.adaptive(minimum: 34), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text.iconLabel)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                iconButton(symbol: nil)
                ForEach(Self.symbols, id: \.self) { symbol in
                    iconButton(symbol: symbol)
                }
            }
        }
    }

    @ViewBuilder
    private func iconButton(symbol: String?) -> some View {
        let selected = symbol == nil ? item.symbolName.isEmpty : item.symbolName == symbol
        Button {
            item.symbolName = symbol ?? ""
        } label: {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                } else if item.kind == .app || item.kind == .file, !item.payload.isEmpty {
                    Image(nsImage: RadialMenuIconStore.fileIcon(for: item.payload))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: item.defaultSymbolName)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .frame(width: 34, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.13),
                                  lineWidth: selected ? 1.2 : 1)
            )
        }
        .buttonStyle(.plain)
        .help(symbol ?? text.automaticLabel)
    }

}
