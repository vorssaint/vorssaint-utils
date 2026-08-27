// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings > Radial menu: profiles, colors, shortcuts, the master switch,
/// opening behavior, placement and list of actions per profile.
struct RadialMenuSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = RadialMenuService.shared
    @AppStorage(DefaultsKey.radialMenuEnabled) private var enabled = false
    @AppStorage(DefaultsKey.radialMenuAtPointer) private var atPointer = true
    @AppStorage(DefaultsKey.radialMenuActivationMode) private var activationModeRaw =
        RadialMenuActivationMode.pressOrHold.rawValue

    @State private var profiles: [RadialMenuProfile] = RadialMenuSupport.decodeProfiles(
        UserDefaults.standard.data(forKey: DefaultsKey.radialMenuProfiles))
    @State private var selectedProfileID: UUID?
    /// The submenu being edited; empty means the root wheel.
    @State private var openSubmenuID: UUID?
    @State private var editing: RadialMenuItem?
    @State private var dragging: RadialMenuItem?

    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }

    private var selectedProfileIndex: Int {
        if let selectedProfileID, let idx = profiles.firstIndex(where: { $0.id == selectedProfileID }) {
            return idx
        }
        return 0
    }

    private var selectedProfile: RadialMenuProfile {
        if profiles.indices.contains(selectedProfileIndex) {
            return profiles[selectedProfileIndex]
        }
        return profiles.first ?? RadialMenuProfilePreset.general.createProfile()
    }

    private var currentProfileItems: [RadialMenuItem] {
        selectedProfile.items
    }

    /// Falls back to the root when the drilled submenu no longer exists (a
    /// restored backup can pull it away), so the list never strands empty.
    private var level: [RadialMenuItem] {
        guard let openSubmenu else { return currentProfileItems }
        return openSubmenu.children
    }

    private var openSubmenu: RadialMenuItem? {
        guard let openSubmenuID else { return nil }
        return currentProfileItems.first { $0.id == openSubmenuID }
    }

    var body: some View {
        Form {
            Section {
                Toggle(text.enableLabel, isOn: $enabled)
                Text(text.hubDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if service.registrationFailed {
                    Text(l10n.s.shortcutInvalid)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Picker(text.activationModeLabel, selection: $activationModeRaw) {
                    Text(text.activationModePressOrHold)
                        .tag(RadialMenuActivationMode.pressOrHold.rawValue)
                    Text(text.activationModePress)
                        .tag(RadialMenuActivationMode.press.rawValue)
                    Text(text.activationModeHold)
                        .tag(RadialMenuActivationMode.hold.rawValue)
                }
                .disabled(!enabled)
                Text(text.activationModeCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(text.positionLabel, selection: $atPointer) {
                    Text(text.positionPointer).tag(true)
                    Text(text.positionCenter).tag(false)
                }
                .pickerStyle(.segmented)
                Button(text.tryButton) {
                    RadialMenuService.shared.presentPreview(for: selectedProfile)
                }
            } header: {
                Text(text.pageTitle)
            }

            if RadialMenuSupport.needsAccessibility(profiles), !permissions.accessibility {
                Section {
                    PermissionRow(kind: .accessibility)
                    Text(RadialMenuSupport.usesWindowLayout(currentProfileItems)
                         ? FeatureStrings.windowLayout(l10n.language).missingPermission
                         : text.permissionCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                profileManagementRow
                profileConfigurationRows
            } header: {
                Text(text.profilesHeader)
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
                                      editing = item
                                  },
                                  remove: { remove(id: item.id) },
                                  openChildren: item.kind == .submenu ? { openSubmenuID = item.id } : nil,
                                  moveHandler: { moved, target in move(moved, before: target) })
                }
                if level.count < RadialMenuSupport.maxItemsPerWheel {
                    Button {
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
        .onAppear {
            if selectedProfileID == nil || !profiles.contains(where: { $0.id == selectedProfileID }) {
                selectedProfileID = profiles.first?.id
            }
        }
        .onDrop(of: [UTType.text], delegate: RadialDragCleanupDelegate(dragging: $dragging))
        .sheet(item: $editing) { item in
            let isNew = !level.contains { $0.id == item.id }
            RadialItemEditor(text: text,
                             item: item,
                             isNew: isNew,
                             allowsSubmenu: openSubmenuID == nil,
                             save: { saved in
                                 upsert(saved)
                                 if isNew, saved.kind == .submenu {
                                     openSubmenuID = saved.id
                                 }
                             },
                             delete: isNew ? nil : { remove(id: item.id) })
        }
        .onChange(of: enabled) { _, on in
            RadialMenuService.shared.syncWithPreferences()
            requestAccessibilityIfNeeded(on)
        }
    }

    // MARK: - Profile Rows

    private var profileManagementRow: some View {
        HStack(spacing: 8) {
            Picker(text.profilePickerLabel, selection: Binding(
                get: { selectedProfile.id },
                set: { newID in
                    selectedProfileID = newID
                    openSubmenuID = nil
                    dragging = nil
                }
            )) {
                ForEach(profiles) { profile in
                    Text(profile.displayName(text))
                        .tag(profile.id)
                }
            }
            .disabled(!enabled)

            Menu {
                ForEach(RadialMenuProfilePreset.allCases) { preset in
                    Button(preset.title(text)) {
                        addProfile(preset: preset)
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(text.addProfileButton)
            .disabled(!enabled)

            Button {
                duplicateProfile()
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(.borderless)
            .help(text.duplicateProfileButton)
            .disabled(!enabled)

            Button {
                deleteProfile()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(text.deleteProfileButton)
            .disabled(!enabled || profiles.count <= 1)
        }
    }

    @ViewBuilder
    private var profileConfigurationRows: some View {
        let profile = selectedProfile
        let pIndex = selectedProfileIndex

        TextField(text.profileNameLabel, text: Binding(
            get: { profile.name },
            set: { newName in
                guard profiles.indices.contains(pIndex) else { return }
                profiles[pIndex].name = newName
                persist()
            }
        ), prompt: Text(text.presetGeneral))
        .disabled(!enabled)

        HStack {
            Text(text.profileColorLabel)
            Spacer()
            RadialMenuColorPicker(
                selection: Binding(
                    get: { profile.color },
                    set: { newColor in
                        guard profiles.indices.contains(pIndex) else { return }
                        profiles[pIndex].color = newColor
                        persist()
                    }
                ),
                strings: text
            )
        }
        .disabled(!enabled)

        ProfileShortcutRow(
            shortcutValue: Binding(
                get: { profile.shortcut },
                set: { newShortcut in
                    guard profiles.indices.contains(pIndex) else { return }
                    profiles[pIndex].shortcut = newShortcut
                    persist()
                }
            ),
            isEnabled: enabled,
            text: text,
            l10n: l10n,
            onChange: {
                persist()
            }
        )

        Picker(text.profileMouseTriggerLabel, selection: Binding(
            get: { profile.mouseButton },
            set: { newTrigger in
                guard profiles.indices.contains(pIndex) else { return }
                profiles[pIndex].mouseButton = newTrigger
                persist()
                if RadialMenuMouseTrigger.sanitized(newTrigger) != .off, !permissions.accessibility {
                    permissions.requestAccessibility()
                }
            }
        )) {
            Text(text.mouseTriggerOff).tag(RadialMenuMouseTrigger.off.rawValue)
            ForEach(Array(MouseButtonShortcutSupport.buttonRange), id: \.self) { button in
                Text(mouseTriggerName(for: button))
                    .tag(RadialMenuMouseTrigger.button(button).rawValue)
            }
        }
        .disabled(!enabled)

        if RadialMenuMouseTrigger.sanitized(profile.mouseButton) != .off {
            if let button = RadialMenuMouseTrigger.sanitized(profile.mouseButton).buttonNumber,
               button == MouseButtonShortcutSupport.backButtonNumber
                || button == MouseButtonShortcutSupport.forwardButtonNumber {
                Text(text.mouseTriggerWarning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            buttonTestRow(for: profile.mouseButton)
        }
    }

    // MARK: - Mutations (every change lands in defaults right away)

    private func addProfile(preset: RadialMenuProfilePreset) {
        let name = preset == .general ? "\(text.presetGeneral) \(profiles.count + 1)" : preset.title(text)
        let newProfile = preset.createProfile(name: name)
        profiles.append(newProfile)
        selectedProfileID = newProfile.id
        openSubmenuID = nil
        dragging = nil
        persist()
    }

    private func duplicateProfile() {
        var copy = selectedProfile
        copy.id = UUID()
        let baseName = copy.name.isEmpty ? text.presetGeneral : copy.name
        copy.name = "\(baseName) 2"
        copy.shortcut = ""
        profiles.append(copy)
        selectedProfileID = copy.id
        openSubmenuID = nil
        dragging = nil
        persist()
    }

    private func deleteProfile() {
        guard profiles.count > 1 else { return }
        let index = selectedProfileIndex
        profiles.remove(at: index)
        let nextIndex = min(index, profiles.count - 1)
        selectedProfileID = profiles[nextIndex].id
        openSubmenuID = nil
        dragging = nil
        persist()
    }

    private func setLevel(_ new: [RadialMenuItem]) {
        guard profiles.indices.contains(selectedProfileIndex) else { return }
        if let openSubmenuID, let index = profiles[selectedProfileIndex].items.firstIndex(where: { $0.id == openSubmenuID }) {
            profiles[selectedProfileIndex].items[index].children = new
        } else {
            profiles[selectedProfileIndex].items = new
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
        UserDefaults.standard.set(RadialMenuSupport.encodeProfiles(profiles), forKey: DefaultsKey.radialMenuProfiles)
        RadialMenuService.shared.syncWithPreferences()
    }

    private func requestAccessibilityIfNeeded(_ on: Bool) {
        guard on, RadialMenuSupport.needsAccessibility(profiles), !permissions.accessibility else { return }
        permissions.requestAccessibility()
    }

    private func mouseTriggerName(for button: Int64) -> String {
        switch button {
        case MouseButtonShortcutSupport.backButtonNumber: return text.mouseTriggerBack
        case MouseButtonShortcutSupport.forwardButtonNumber: return text.mouseTriggerForward
        default:
            return MouseButtonShortcutSupport.buttonName(
                for: button, strings: FeatureStrings.mouseButtons(l10n.language))
        }
    }

    private func buttonTestRow(for triggerRaw: String) -> some View {
        let seen = service.lastMouseButtonSeen
        let expected = RadialMenuMouseTrigger.sanitized(triggerRaw).buttonNumber
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

// MARK: - Color Picker

private struct RadialMenuColorPicker: View {
    @Binding var selection: RadialMenuColor
    let strings: RadialMenuFeatureStrings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(RadialMenuColor.allCases) { color in
                Button {
                    selection = color
                } label: {
                    ZStack {
                        Circle()
                            .fill(color.color(for: colorScheme))
                            .frame(width: 16, height: 16)
                        if selection == color {
                            Circle()
                                .strokeBorder(Color.white.opacity(colorScheme == .light ? 0.9 : 0.8), lineWidth: 2)
                                .frame(width: 12, height: 12)
                            Circle()
                                .strokeBorder(color.color(for: colorScheme), lineWidth: 1.5)
                                .frame(width: 20, height: 20)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(color.title(strings))
                .accessibilityLabel(color.title(strings))
            }
        }
    }
}

// MARK: - Profile Shortcut Row

private struct ProfileShortcutRow: View {
    @Binding var shortcutValue: String
    let isEnabled: Bool
    let text: RadialMenuFeatureStrings
    let l10n: L10n
    let onChange: () -> Void

    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(text.profileShortcutLabel)
                Spacer()
                ShortcutRecorderButton(
                    shortcut: GlobalShortcut(storageValue: shortcutValue) ?? .radialMenuDefault,
                    isEnabled: isEnabled,
                    waitingTitle: l10n.s.shortcutPressKeys,
                    emptyTitle: shortcutValue.isEmpty ? l10n.s.shortcutNone : nil,
                    clearAction: {
                        shortcutValue = ""
                        message = nil
                        onChange()
                    },
                    notCapturedAction: {
                        message = l10n.s.shortcutNotCaptured
                    },
                    recordingChanged: { recording in
                        if recording { message = nil }
                    },
                    invalidAction: {
                        message = l10n.s.shortcutInvalid
                    },
                    captureAction: { newShortcut in
                        shortcutValue = newShortcut.storageValue
                        message = nil
                        onChange()
                    }
                )
                .frame(width: 130)
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
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
        case .quickToggle: return FeatureStrings.quickToggles(L10n.shared.language).pageTitle
        case .windowLayout: return FeatureStrings.windowLayout(L10n.shared.language).title
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
                    HStack(spacing: 5) {
                        Text(text.editActionsButton)
                        Image(systemName: "chevron.forward")
                    }
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
    @State private var isFetchingFavicon = false
    @State private var faviconStatus: FaviconFetchStatus?

    enum FaviconFetchStatus {
        case success
        case error
    }

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

    private var availableQuickToggles: [RadialMenuQuickToggle] {
        AppFeature.quickToggles.isAvailable ? RadialMenuQuickToggle.allCases : []
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
                    if !availableQuickToggles.isEmpty {
                        Text(FeatureStrings.quickToggles(l10n.language).pageTitle)
                            .tag(RadialMenuItem.Kind.quickToggle)
                    }
                    if AppFeature.windowLayout.isAvailable {
                        Text(FeatureStrings.windowLayout(l10n.language).title)
                            .tag(RadialMenuItem.Kind.windowLayout)
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
            faviconStatus = nil
            if kind != .url { item.customIconData = nil }
            switch kind {
            case .tool: item.payload = availableTools.first?.rawValue ?? ""
            case .quickToggle: item.payload = availableQuickToggles.first?.rawValue ?? ""
            case .windowLayout: item.payload = WindowLayoutAction.leftHalf.rawValue
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
            VStack(alignment: .leading, spacing: 6) {
                TextField(text.kindURL, text: $item.payload, prompt: Text(text.urlPlaceholder))
                    .onChange(of: item.payload) { _, _ in
                        faviconStatus = nil
                    }

                HStack(spacing: 8) {
                    Button {
                        fetchWebsiteFavicon()
                    } label: {
                        if isFetchingFavicon {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(text.fetchFaviconLoading)
                            }
                        } else {
                            Text(text.fetchFaviconButton)
                        }
                    }
                    .disabled(isFetchingFavicon || item.payload.trimmingCharacters(in: .whitespaces).isEmpty || urlIsInvalid)

                    if let faviconStatus {
                        switch faviconStatus {
                        case .success:
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(text.fetchFaviconSuccess)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        case .error:
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(text.fetchFaviconError)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Text(text.fetchFaviconDisclaimer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        case .quickToggle:
            let quickToggleText = FeatureStrings.quickToggles(l10n.language)
            Picker(quickToggleText.pageTitle, selection: $item.payload) {
                ForEach(availableQuickToggles) { action in
                    Label(action.radialTitle, systemImage: action.symbolName)
                        .tag(action.rawValue)
                }
            }
        case .windowLayout:
            let windowText = FeatureStrings.windowLayout(l10n.language)
            Picker(windowText.title, selection: $item.payload) {
                ForEach(WindowLayoutAction.allCases) { action in
                    Label(action.title(windowText), systemImage: action.symbolName)
                        .tag(action.rawValue)
                }
            }
        case .media:
            Picker(text.mediaLabel, selection: $item.payload) {
                Text(text.mediaPlayPause).tag(RadialMenuMediaKey.playPause.rawValue)
                Text(text.mediaPrevious).tag(RadialMenuMediaKey.previousTrack.rawValue)
                Text(text.mediaNext).tag(RadialMenuMediaKey.nextTrack.rawValue)
                Text(text.mediaNowPlaying).tag(RadialMenuMediaKey.nowPlaying.rawValue)
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

    private func fetchWebsiteFavicon() {
        guard !item.payload.isEmpty, !urlIsInvalid else { return }
        isFetchingFavicon = true
        faviconStatus = nil

        RadialMenuFaviconFetcher.fetchFavicon(for: item.payload) { result in
            isFetchingFavicon = false
            switch result {
            case .success(let data):
                item.customIconData = data
                item.symbolName = ""
                RadialMenuIconStore.invalidate(item: item)
                faviconStatus = .success
            case .failure:
                faviconStatus = .error
            }
        }
    }
}

// MARK: - Icon picker

/// "Automatic" plus a small curated grid; automatic means the real app or
/// file icon when the target has one, or the action's own symbol.
private struct RadialSymbolPicker: View {
    let text: RadialMenuFeatureStrings
    @Binding var item: RadialMenuItem

    private static let symbols = RadialMenuSupport.symbolNames.filter {
        NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
    }

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
                } else if let customImage = RadialMenuIconStore.customIcon(for: item) {
                    Image(nsImage: customImage)
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
