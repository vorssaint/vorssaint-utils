// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

struct MenuBarOrganizerSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = MenuBarOrganizerService.shared
    @ObservedObject private var permissions = Permissions.shared

    @AppStorage(DefaultsKey.menuBarOrganizerEnabled) private var enabled = false
    @AppStorage(DefaultsKey.menuBarOrganizerSetupComplete) private var setupComplete = false
    @AppStorage(DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled) private var alwaysHiddenEnabled = false
    @AppStorage(DefaultsKey.menuBarOrganizerShowDividers) private var showDividers = false
    @AppStorage(DefaultsKey.menuBarOrganizerCapturePreviews) private var capturePreviews = true
    @AppStorage(DefaultsKey.menuBarOrganizerPresentationMode) private var presentationMode =
        MenuBarOrganizerPresentationMode.menuBar.rawValue
    @AppStorage(DefaultsKey.menuBarOrganizerRehideMode) private var rehideMode =
        MenuBarOrganizerRehideMode.afterDelay.rawValue
    @AppStorage(DefaultsKey.menuBarOrganizerRehideDelay) private var rehideDelay = 10
    @AppStorage(DefaultsKey.menuBarOrganizerShowOnHover) private var showOnHover = false
    @AppStorage(DefaultsKey.menuBarOrganizerShowOnEmptyClick) private var showOnEmptyClick = false
    @AppStorage(DefaultsKey.menuBarOrganizerShowOnScroll) private var showOnScroll = false
    @AppStorage(DefaultsKey.menuBarOrganizerSmartNotchMode) private var smartNotchMode = true
    @AppStorage(DefaultsKey.menuBarOrganizerGroupStatusItems) private var groupStatusItems = true
    @AppStorage(DefaultsKey.menuBarOrganizerAutoHideGroupedItems) private var autoHideGroupedItems = false
    @AppStorage(DefaultsKey.menuBarOrganizerSpacerCount) private var spacerCount = 0
    @AppStorage(DefaultsKey.menuBarOrganizerSpacerWidth) private var spacerWidth = 16
    @AppStorage(DefaultsKey.menuBarOrganizerBarStyle) private var barStyle =
        MenuBarOrganizerBarStyle.system.rawValue
    @AppStorage(DefaultsKey.menuBarOrganizerTriggerLowBatteryEnabled) private var lowBatteryTrigger = false
    @AppStorage(DefaultsKey.menuBarOrganizerTriggerLowBatteryThreshold) private var lowBatteryThreshold = 25
    @AppStorage(DefaultsKey.menuBarOrganizerTriggerLowBatteryPreset) private var lowBatteryPreset =
        MenuBarOrganizerPresetSlot.minimal.rawValue
    @AppStorage(DefaultsKey.menuBarOrganizerTriggerChargingEnabled) private var chargingTrigger = false
    @AppStorage(DefaultsKey.menuBarOrganizerTriggerChargingPreset) private var chargingPreset =
        MenuBarOrganizerPresetSlot.home.rawValue
    @AppStorage(DefaultsKey.menuBarOrganizerTriggerExternalDisplayEnabled) private var externalDisplayTrigger = false
    @AppStorage(DefaultsKey.menuBarOrganizerTriggerExternalDisplayPreset) private var externalDisplayPreset =
        MenuBarOrganizerPresetSlot.work.rawValue
    @AppStorage(DefaultsKey.menuBarOrganizerTriggerWorkHoursEnabled) private var workHoursTrigger = false
    @AppStorage(DefaultsKey.menuBarOrganizerTriggerWorkHoursPreset) private var workHoursPreset =
        MenuBarOrganizerPresetSlot.work.rawValue
    @AppStorage(DefaultsKey.menuBarOrganizerTriggerWorkHoursStart) private var workHoursStart = 9
    @AppStorage(DefaultsKey.menuBarOrganizerTriggerWorkHoursEnd) private var workHoursEnd = 17
    @AppStorage(DefaultsKey.menuBarOrganizerTriggerWorkHoursWeekdaysOnly) private var workHoursWeekdays = true
    @AppStorage(DefaultsKey.menuBarOrganizerToggleShortcutEnabled) private var toggleShortcutEnabled = false
    @AppStorage(DefaultsKey.menuBarOrganizerAlwaysShortcutEnabled) private var alwaysShortcutEnabled = false
    @AppStorage(DefaultsKey.menuBarOrganizerSearchShortcutEnabled) private var searchShortcutEnabled = false

    @State private var editingBegun = false
    @State private var namedPresetName = ""
    @State private var customGroupName = ""
    @State private var customGroupSymbol = "folder"

    private var text: MenuBarOrganizerStrings {
        FeatureStrings.menuBarOrganizer(l10n.language)
    }

    var body: some View {
        Form {
            Section {
                Toggle(text.enable, isOn: $enabled)
                Text(text.enableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(text.pageTitle)
            }

            if enabled {
                if !setupComplete {
                    Section {
                        Label(text.setupTitle, systemImage: "menubar.rectangle")
                            .font(.headline)
                        Text(text.setupCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(text.finishSetup) {
                            setupComplete = true
                            service.completeSetup()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                permissionSection
                editorSection
                presetsSection
                groupsSection
                spacingAndStyleSection
                behaviorSections
            }

            Section {
                Text(text.inspiredByIce)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            service.syncWithPreferences()
            updateEditingSession()
        }
        .onDisappear {
            if editingBegun {
                service.endEditing()
                editingBegun = false
            }
        }
        .onChange(of: enabled) { _, _ in
            service.syncWithPreferences()
            updateEditingSession()
        }
        .onChange(of: preferenceSignature) { _, _ in
            sanitizePreferences()
            service.syncWithPreferences()
        }
    }

    private var preferenceSignature: String {
        [
            alwaysHiddenEnabled, showDividers, capturePreviews,
            showOnHover, showOnEmptyClick, showOnScroll, smartNotchMode,
            groupStatusItems, autoHideGroupedItems, lowBatteryTrigger,
            chargingTrigger, externalDisplayTrigger, workHoursTrigger,
            workHoursWeekdays, toggleShortcutEnabled, alwaysShortcutEnabled,
            searchShortcutEnabled,
        ].map(String.init).joined(separator: "|")
        + "|"
        + [
            presentationMode, rehideMode, String(rehideDelay),
            String(spacerCount), String(spacerWidth), barStyle,
            String(lowBatteryThreshold), lowBatteryPreset, chargingPreset,
            externalDisplayPreset, workHoursPreset, String(workHoursStart),
            String(workHoursEnd),
        ].joined(separator: "|")
    }

    private func sanitizePreferences() {
        let sanitizedDelay = MenuBarOrganizerSupport.sanitizedRehideDelay(rehideDelay)
        if sanitizedDelay != rehideDelay { rehideDelay = sanitizedDelay }
        let sanitizedSpacerCount = MenuBarOrganizerSupport.sanitizedSpacerCount(spacerCount)
        if sanitizedSpacerCount != spacerCount { spacerCount = sanitizedSpacerCount }
        let sanitizedSpacerWidth = MenuBarOrganizerSupport.sanitizedSpacerWidth(spacerWidth)
        if sanitizedSpacerWidth != spacerWidth { spacerWidth = sanitizedSpacerWidth }
        let sanitizedStyle = MenuBarOrganizerBarStyle.sanitized(barStyle).rawValue
        if sanitizedStyle != barStyle { barStyle = sanitizedStyle }
        lowBatteryThreshold = min(max(lowBatteryThreshold, 1), 100)
        workHoursStart = min(max(workHoursStart, 0), 23)
        workHoursEnd = min(max(workHoursEnd, 0), 23)
    }

    @ViewBuilder
    private var permissionSection: some View {
        if !permissions.accessibility || (capturePreviews && !permissions.screenRecording) {
            Section {
                if !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                    Text(text.accessibilityCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if capturePreviews, !permissions.screenRecording {
                    PermissionRow(kind: .screenRecording)
                    Text(text.screenRecordingCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !service.capabilities.automaticEditorAvailable {
                    Label(text.automaticMoveUnavailable, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var editorSection: some View {
        Section {
            HStack {
                Button(text.refresh) { service.refresh() }
                Button(text.undo) { service.undoLastMove() }
                    .disabled(!service.canUndo)
                Spacer()
                Button(text.search) { service.showSearch() }
                Button(text.secondaryBar) { service.showSecondaryBar() }
            }

            organizerLane(.visible, title: text.visible)
            organizerLane(.hidden, title: text.hidden)
            if alwaysHiddenEnabled {
                organizerLane(.alwaysHidden, title: text.alwaysHidden)
            }

            Text(text.dragHint)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text.manualHint)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message = service.operationMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .onTapGesture { service.clearOperationMessage() }
            }
        } header: {
            Text(text.sectionsTitle)
        }
    }

    private var presetsSection: some View {
        Section {
            Text(text.presetsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(MenuBarOrganizerPresetSlot.allCases) { slot in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(presetTitle(slot))
                        if let preset = service.presets[slot] {
                            Text(preset.savedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(text.presetUnsaved)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Button(text.presetSave) { service.savePreset(slot: slot) }
                    Button(text.presetApply) { service.applyPreset(slot: slot) }
                        .disabled(service.presets[slot] == nil)
                    Button(text.presetClear, role: .destructive) {
                        service.clearPreset(slot: slot)
                    }
                    .disabled(service.presets[slot] == nil)
                }
            }
            Divider()
            Text(text.namedPresetsTitle)
                .font(.subheadline.weight(.semibold))
            HStack {
                TextField(text.namedPresetName, text: $namedPresetName)
                Button(text.namedPresetSave) {
                    service.saveNamedPreset(name: namedPresetName)
                    namedPresetName = ""
                }
                .disabled(namedPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(service.namedPresets) { preset in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preset.name)
                        Text(preset.savedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(text.presetApply) { service.applyNamedPreset(id: preset.id) }
                    Button(text.namedPresetDelete, role: .destructive) {
                        service.deleteNamedPreset(id: preset.id)
                    }
                }
            }
        } header: {
            Text(text.presetsTitle)
        }
    }

    private var groupsSection: some View {
        Section {
            Toggle(text.groupStatusItems, isOn: $groupStatusItems)
            Text(text.groupStatusItemsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(text.groupAutoHide, isOn: $autoHideGroupedItems)
            Text(text.groupAutoHideCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text.groupsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(MenuBarOrganizerGroupSlot.allCases) { slot in
                groupRow(slot)
            }
            Divider()
            Text(text.customGroupsTitle)
                .font(.subheadline.weight(.semibold))
            HStack {
                TextField(text.customGroupName, text: $customGroupName)
                TextField(text.customGroupSymbol, text: $customGroupSymbol)
                    .frame(maxWidth: 120)
                Button(text.customGroupCreate) {
                    service.createCustomGroup(name: customGroupName,
                                              symbolName: customGroupSymbol)
                    customGroupName = ""
                    customGroupSymbol = "folder"
                }
                .disabled(customGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ForEach(service.customGroups) { group in
                customGroupRow(group)
            }
        } header: {
            Text(text.groupsTitle)
        }
    }

    private func groupRow(_ slot: MenuBarOrganizerGroupSlot) -> some View {
        let groupItems = service.items(inGroup: slot)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label(groupTitle(slot), systemImage: "folder")
                Spacer()
                Button(text.groupOpen) { service.showGroup(slot: slot) }
                    .disabled(groupItems.isEmpty)
                Button(text.groupClear, role: .destructive) { service.clearGroup(slot: slot) }
                    .disabled(groupItems.isEmpty)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if groupItems.isEmpty {
                        Text(text.groupEmpty)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(minWidth: 180, minHeight: 34, alignment: .leading)
                    }
                    ForEach(groupItems) { item in
                        MenuBarOrganizerEditorItem(item: item)
                            .contextMenu {
                                Button(role: .destructive) {
                                    service.removeFromGroup(itemID: item.id)
                                } label: {
                                    Label(text.groupRemoveFrom, systemImage: "minus.circle")
                                }
                            }
                    }
                }
                .padding(7)
            }
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.16)))
        }
        .padding(.vertical, 2)
    }

    private func customGroupRow(_ group: MenuBarOrganizerCustomGroup) -> some View {
        let reference = MenuBarOrganizerGroupReference.custom(group.id)
        let groupItems = service.items(inGroup: reference)
        return VStack(alignment: .leading, spacing: 7) {
            MenuBarOrganizerCustomGroupControls(
                service: service,
                group: group,
                hasItems: !groupItems.isEmpty,
                text: text)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if groupItems.isEmpty {
                        Text(text.groupEmpty)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(minWidth: 180, minHeight: 34, alignment: .leading)
                    }
                    ForEach(groupItems) { item in
                        MenuBarOrganizerEditorItem(item: item)
                            .contextMenu {
                                Button(role: .destructive) {
                                    service.removeFromGroup(itemID: item.id)
                                } label: {
                                    Label(text.groupRemoveFrom, systemImage: "minus.circle")
                                }
                            }
                    }
                }
                .padding(7)
            }
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.16)))
        }
        .padding(.vertical, 2)
    }

    private var spacingAndStyleSection: some View {
        Section {
            Stepper("\(text.spacerCount): \(spacerCount)", value: $spacerCount, in: 0...6)
            Picker(text.spacerWidth, selection: $spacerWidth) {
                ForEach(MenuBarOrganizerSupport.allowedSpacerWidths, id: \.self) { width in
                    Text("\(width) px").tag(width)
                }
            }
            Picker(text.barStyle, selection: $barStyle) {
                Text(text.barStyleSystem).tag(MenuBarOrganizerBarStyle.system.rawValue)
                Text(text.barStyleTinted).tag(MenuBarOrganizerBarStyle.tinted.rawValue)
                Text(text.barStyleGraphite).tag(MenuBarOrganizerBarStyle.graphite.rawValue)
                Text(text.barStyleVibrant).tag(MenuBarOrganizerBarStyle.vibrant.rawValue)
            }
        } header: {
            Text(text.spacingTitle)
        }
    }

    @ViewBuilder
    private var behaviorSections: some View {
        Section(text.sectionsTitle) {
            Toggle(text.alwaysHiddenToggle, isOn: $alwaysHiddenEnabled)
            Toggle(text.showDividers, isOn: $showDividers)
            Toggle(text.capturePreviews, isOn: $capturePreviews)
        }

        Section(text.presentationTitle) {
            Picker(text.presentationTitle, selection: $presentationMode) {
                Text(text.presentationAutomatic).tag(MenuBarOrganizerPresentationMode.automatic.rawValue)
                Text(text.presentationMenuBar).tag(MenuBarOrganizerPresentationMode.menuBar.rawValue)
                Text(text.presentationSecondary).tag(MenuBarOrganizerPresentationMode.secondaryBar.rawValue)
            }
            .pickerStyle(.segmented)
        }

        Section(text.rehideTitle) {
            Picker(text.rehideTitle, selection: $rehideMode) {
                Text(text.rehideNever).tag(MenuBarOrganizerRehideMode.never.rawValue)
                Text(text.rehideDelay).tag(MenuBarOrganizerRehideMode.afterDelay.rawValue)
                Text(text.rehideFocusedApp).tag(MenuBarOrganizerRehideMode.focusedApp.rawValue)
            }
            if MenuBarOrganizerRehideMode.sanitized(rehideMode) == .afterDelay {
                Picker(text.rehideDelay, selection: $rehideDelay) {
                    ForEach(MenuBarOrganizerSupport.allowedRehideDelays, id: \.self) {
                        Text(String(format: text.delayFormat, $0)).tag($0)
                    }
                }
            }
        }

        Section(text.triggersTitle) {
            Toggle(text.showOnHover, isOn: $showOnHover)
            Toggle(text.showOnEmptyClick, isOn: $showOnEmptyClick)
            Toggle(text.showOnScroll, isOn: $showOnScroll)
            Toggle(text.smartNotchMode, isOn: $smartNotchMode)
            Text(text.smartNotchCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text(text.advancedTriggersCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            triggerRow(title: text.triggerLowBattery,
                       enabled: $lowBatteryTrigger,
                       preset: $lowBatteryPreset)
            if lowBatteryTrigger {
                Stepper("\(text.triggerLowBattery): \(lowBatteryThreshold)%",
                        value: $lowBatteryThreshold,
                        in: 1...100)
            }
            triggerRow(title: text.triggerCharging,
                       enabled: $chargingTrigger,
                       preset: $chargingPreset)
            triggerRow(title: text.triggerExternalDisplay,
                       enabled: $externalDisplayTrigger,
                       preset: $externalDisplayPreset)
            triggerRow(title: text.triggerWorkHours,
                       enabled: $workHoursTrigger,
                       preset: $workHoursPreset)
            if workHoursTrigger {
                Stepper("\(workHoursStart):00", value: $workHoursStart, in: 0...23)
                Stepper("\(workHoursEnd):00", value: $workHoursEnd, in: 0...23)
                Toggle(text.triggerWorkHoursWeekdays, isOn: $workHoursWeekdays)
            }
        }

        Section(text.shortcutsTitle) {
            shortcutRow(title: text.toggleHiddenShortcut,
                        enabled: $toggleShortcutEnabled,
                        role: .menuBarOrganizerToggle)
            shortcutRow(title: text.toggleAlwaysShortcut,
                        enabled: $alwaysShortcutEnabled,
                        role: .menuBarOrganizerAlways)
                .disabled(!alwaysHiddenEnabled)
            shortcutRow(title: text.searchShortcut,
                        enabled: $searchShortcutEnabled,
                        role: .menuBarOrganizerSearch)
            if service.hotkeyRegistrationFailed {
                Text(L10n.shared.s.shortcutUnavailable)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func shortcutRow(title: String,
                             enabled: Binding<Bool>,
                             role: GlobalShortcutRole) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(title, isOn: enabled)
            ShortcutPreferenceRow(role: role, isEnabled: enabled.wrappedValue) {
                service.syncWithPreferences()
            }
            .disabled(!enabled.wrappedValue)
        }
    }

    private func triggerRow(title: String,
                            enabled: Binding<Bool>,
                            preset: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: enabled)
            Picker(text.triggerPreset, selection: preset) {
                ForEach(MenuBarOrganizerPresetSlot.allCases) { slot in
                    Text(presetTitle(slot)).tag(slot.rawValue)
                }
            }
            .disabled(!enabled.wrappedValue)
        }
    }

    private func presetTitle(_ slot: MenuBarOrganizerPresetSlot) -> String {
        switch slot {
        case .work: return text.presetWork
        case .home: return text.presetHome
        case .presenting: return text.presetPresenting
        case .minimal: return text.presetMinimal
        }
    }

    private func groupTitle(_ slot: MenuBarOrganizerGroupSlot) -> String {
        switch slot {
        case .cloud: return text.groupCloud
        case .audio: return text.groupAudio
        case .work: return text.groupWork
        case .custom: return text.groupCustom
        }
    }

    private func organizerLane(_ section: MenuBarOrganizerSection, title: String) -> some View {
        let laneItems = MenuBarOrganizerSupport.orderedItems(service.items, in: section)
        return VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if laneItems.isEmpty {
                        Text(text.emptySection)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(minWidth: 180, minHeight: 38)
                    }
                    ForEach(laneItems) { item in
                        MenuBarOrganizerEditorItem(item: item)
                            .onDrag {
                                NSItemProvider(object: item.id.storageValue as NSString)
                            }
                            .onDrop(of: [UTType.text],
                                    delegate: MenuBarOrganizerDropDelegate(
                                        section: section,
                                        target: item.id,
                                        service: service))
                            .contextMenu {
                                sectionMoveButton(for: item, to: .visible, title: text.visible)
                                sectionMoveButton(for: item, to: .hidden, title: text.hidden)
                                if alwaysHiddenEnabled {
                                    sectionMoveButton(for: item,
                                                      to: .alwaysHidden,
                                                      title: text.alwaysHidden)
                                }
                                Divider()
                                Menu(text.groupAddTo) {
                                    ForEach(MenuBarOrganizerGroupSlot.allCases) { slot in
                                        Button(groupTitle(slot)) {
                                            service.addToGroup(itemID: item.id, slot: slot)
                                        }
                                    }
                                    if !service.customGroups.isEmpty {
                                        Divider()
                                        ForEach(service.customGroups) { group in
                                            Button(group.name) {
                                                service.addToGroup(
                                                    itemID: item.id,
                                                    reference: .custom(group.id))
                                            }
                                        }
                                    }
                                }
                                if service.group(for: item.id) != nil {
                                    Button(role: .destructive) {
                                        service.removeFromGroup(itemID: item.id)
                                    } label: {
                                        Label(text.groupRemoveFrom, systemImage: "minus.circle")
                                    }
                                }
                            }
                    }
                }
                .padding(7)
            }
            .frame(height: 60)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.16)))
            .onDrop(of: [UTType.text],
                    delegate: MenuBarOrganizerDropDelegate(
                        section: section,
                        target: nil,
                        service: service))
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func sectionMoveButton(for item: ManagedMenuBarItem,
                                   to section: MenuBarOrganizerSection,
                                   title: String) -> some View {
        Button {
            service.move(itemID: item.id, before: nil, to: section)
        } label: {
            Label(title, systemImage: section == .visible
                  ? "eye"
                  : (section == .hidden ? "eye.slash" : "lock"))
        }
        .disabled(!item.isMovable || item.section == section)
    }

    private func updateEditingSession() {
        if enabled, !editingBegun {
            service.beginEditing()
            editingBegun = true
        } else if !enabled, editingBegun {
            service.endEditing()
            editingBegun = false
        }
    }
}

private struct MenuBarOrganizerCustomGroupControls: View {
    @ObservedObject var service: MenuBarOrganizerService
    let group: MenuBarOrganizerCustomGroup
    let hasItems: Bool
    let text: MenuBarOrganizerStrings
    @State private var name: String
    @State private var symbolName: String

    init(service: MenuBarOrganizerService,
         group: MenuBarOrganizerCustomGroup,
         hasItems: Bool,
         text: MenuBarOrganizerStrings) {
        self.service = service
        self.group = group
        self.hasItems = hasItems
        self.text = text
        _name = State(initialValue: group.name)
        _symbolName = State(initialValue: group.symbolName)
    }

    private var reference: MenuBarOrganizerGroupReference { .custom(group.id) }
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanSymbolName: String { symbolName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasUnsavedChanges: Bool {
        cleanName != group.name || cleanSymbolName != group.symbolName
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: group.symbolName)
                .frame(width: 18)
            TextField(text.customGroupName, text: $name)
                .frame(minWidth: 120)
            TextField(text.customGroupSymbol, text: $symbolName)
                .frame(maxWidth: 120)
            Button(text.presetSave) {
                service.updateCustomGroup(id: group.id, name: name, symbolName: symbolName)
            }
            .disabled(cleanName.isEmpty || !hasUnsavedChanges)
            Spacer()
            Button(text.groupOpen) { service.showGroup(reference: reference) }
                .disabled(!hasItems)
            Button(text.groupClear, role: .destructive) { service.clearGroup(reference: reference) }
                .disabled(!hasItems)
            Button(text.customGroupDelete, role: .destructive) {
                service.deleteCustomGroup(id: group.id)
            }
        }
        .onChange(of: group.name) { _, newValue in name = newValue }
        .onChange(of: group.symbolName) { _, newValue in symbolName = newValue }
    }
}

private struct MenuBarOrganizerEditorItem: View {
    let item: ManagedMenuBarItem

    var body: some View {
        HStack(spacing: 5) {
            MenuBarOrganizerItemIcon(item: item, size: 18)
            Text(item.ownerName.isEmpty ? item.title : item.ownerName)
                .font(.caption)
                .lineLimit(1)
            if !item.isMovable {
                Image(systemName: "lock.fill").font(.caption2)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
        .help(item.displayName)
        .opacity(item.isMovable ? 1 : 0.62)
    }
}

private struct MenuBarOrganizerDropDelegate: DropDelegate {
    let section: MenuBarOrganizerSection
    let target: MenuBarItemIdentity?
    let service: MenuBarOrganizerService

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String else { return }
            DispatchQueue.main.async {
                guard let source = service.items.first(where: { $0.id.storageValue == raw }),
                      source.isMovable
                else { return }
                service.move(itemID: source.id, before: target, to: section)
            }
        }
        return true
    }
}
