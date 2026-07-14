// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The quick toggles tab of the menu panel: one-click system actions, each an
/// action row that can be hidden and reordered in the section's edit mode.
struct QuickTogglesSection: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var draggingItem: QuickToggleAction?
    var collapsible = true

    var body: some View {
        PanelSection(.toggles,
                     title: FeatureStrings.quickToggles(l10n.language).pageTitle,
                     collapsible: collapsible,
                     supportsEditing: true,
                     resetAction: QuickTogglesList.resetPanelDefaults) { editing in
            QuickTogglesList(editing: editing, draggingItem: $draggingItem) {
                appDelegate()?.closePopover()
            }
            // Actions here activate other apps (the Finder restarting, System
            // Events, the Trash confirmation), which would dismiss the panel
            // mid-flow; holding it open keeps a toggle-back one click away.
            // The status icon and switching tabs still close as always.
            .onAppear { PanelInteractionState.shared.keepsPopoverOpen = true }
            .onDisappear { PanelInteractionState.shared.keepsPopoverOpen = false }
        }
    }
}

/// The toggles hosted inside the quick panel (⌃⌘V), replacing the grid like
/// the other utilities do.
struct PanelQuickTogglesView: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var draggingItem: QuickToggleAction?

    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            QuickTogglesList(editing: false, draggingItem: $draggingItem) {
                QuickLauncherService.shared.hide()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(FeatureStrings.quickToggles(l10n.language).pageTitle, systemImage: "togglepower")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(l10n.s.uninstallerCancel)
        }
    }
}

/// The shared row list: the menu panel tab and the quick panel host render
/// the same actions, honoring the same order and per-item visibility.
struct QuickTogglesList: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var toggles = QuickTogglesService.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DefaultsKey.panelToggleDarkMode) private var showDarkMode = true
    @AppStorage(DefaultsKey.panelToggleEmptyTrash) private var showEmptyTrash = true
    @AppStorage(DefaultsKey.panelToggleEjectDisks) private var showEjectDisks = true
    @AppStorage(DefaultsKey.panelToggleHiddenFiles) private var showHiddenFiles = true
    @AppStorage(DefaultsKey.panelToggleDesktopIcons) private var showDesktopIcons = true
    @AppStorage(DefaultsKey.panelToggleLockScreen) private var showLockScreen = true
    @AppStorage(DefaultsKey.panelToggleDisplayOff) private var showDisplayOff = true
    @AppStorage(DefaultsKey.panelToggleScreenSaver) private var showScreenSaver = true
    @AppStorage(DefaultsKey.panelToggleOrder) private var toggleOrderRaw = ""

    let editing: Bool
    @Binding var draggingItem: QuickToggleAction?
    /// Closes whatever surface hosts the list, so actions that take over the
    /// screen (lock, Trash confirmation) never fight the open panel.
    let dismissSurface: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                PanelReorderableItem(item: item,
                                     isEnabled: editing,
                                     order: itemOrderBinding,
                                     dragging: $draggingItem) {
                    itemView(item)
                        .disabled(toggles.state(for: item) == .running)
                }
            }
        }
        .onAppear {
            toggles.refreshPermissionStates()
        }
    }

    static func resetPanelDefaults() {
        PanelLayout.resetItemOrder(key: DefaultsKey.panelToggleOrder)
        let defaults = UserDefaults.standard
        for key in [DefaultsKey.panelToggleDarkMode, DefaultsKey.panelToggleEmptyTrash,
                    DefaultsKey.panelToggleEjectDisks, DefaultsKey.panelToggleHiddenFiles,
                    DefaultsKey.panelToggleDesktopIcons, DefaultsKey.panelToggleLockScreen,
                    DefaultsKey.panelToggleDisplayOff, DefaultsKey.panelToggleScreenSaver] {
            defaults.set(true, forKey: key)
        }
    }

    // MARK: - Items

    private var orderedItems: [QuickToggleAction] {
        _ = toggleOrderRaw
        return PanelLayout.itemOrder(QuickToggleAction.self, key: DefaultsKey.panelToggleOrder)
    }

    private var itemOrderBinding: Binding<[QuickToggleAction]> {
        Binding {
            orderedItems
        } set: { newValue in
            PanelLayout.setItemOrder(newValue, key: DefaultsKey.panelToggleOrder)
        }
    }

    private var items: [QuickToggleAction] {
        orderedItems.filter { editing || isVisible($0) }
    }

    private func isVisible(_ item: QuickToggleAction) -> Bool {
        visibilityBinding(item).wrappedValue
    }

    private func visibilityBinding(_ item: QuickToggleAction) -> Binding<Bool> {
        switch item {
        case .darkMode: return $showDarkMode
        case .emptyTrash: return $showEmptyTrash
        case .ejectDisks: return $showEjectDisks
        case .hiddenFiles: return $showHiddenFiles
        case .desktopIcons: return $showDesktopIcons
        case .lockScreen: return $showLockScreen
        case .displayOff: return $showDisplayOff
        case .screenSaver: return $showScreenSaver
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func itemView(_ item: QuickToggleAction) -> some View {
        let strings = FeatureStrings.quickToggles(l10n.language)
        switch item {
        case .darkMode:
            UtilityActionButton(title: colorScheme == .dark ? strings.darkModeToLight : strings.darkModeToDark,
                                caption: caption(for: item, idle: strings.darkModeCaption),
                                systemImage: colorScheme == .dark ? "sun.max.fill" : "moon.fill",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: visibilityBinding(item),
                                action: {
                                    QuickTogglesService.shared.toggleDarkMode()
                                })
        case .emptyTrash:
            UtilityActionButton(title: strings.emptyTrashTitle,
                                caption: caption(for: item, idle: strings.emptyTrashCaption),
                                systemImage: "trash",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: visibilityBinding(item),
                                needsAttention: needsPermission(item),
                                permissionButtonTitle: permissionButtonTitle(item),
                                permissionAction: permissionAction(item),
                                action: {
                                    // The confirmation alert opens centered and
                                    // key; the panel stays put behind it.
                                    QuickTogglesService.shared.emptyTrash()
                                })
        case .ejectDisks:
            UtilityActionButton(title: strings.ejectTitle,
                                caption: ejectCaption(strings),
                                systemImage: "eject.fill",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: visibilityBinding(item),
                                action: {
                                    QuickTogglesService.shared.ejectAllDisks()
                                })
        case .hiddenFiles:
            UtilityActionButton(title: toggles.hiddenFilesShown ? strings.hiddenFilesHide : strings.hiddenFilesShow,
                                caption: caption(for: item, idle: strings.finderRestartCaption),
                                systemImage: toggles.hiddenFilesShown ? "eye.slash" : "eye",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: visibilityBinding(item),
                                action: {
                                    QuickTogglesService.shared.toggleHiddenFiles()
                                })
        case .desktopIcons:
            UtilityActionButton(title: toggles.desktopIconsShown ? strings.desktopIconsHide : strings.desktopIconsShow,
                                caption: caption(for: item, idle: strings.finderRestartCaption),
                                systemImage: "desktopcomputer",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: visibilityBinding(item),
                                action: {
                                    QuickTogglesService.shared.toggleDesktopIcons()
                                })
        case .lockScreen:
            UtilityActionButton(title: strings.lockScreenTitle,
                                caption: strings.lockScreenCaption,
                                systemImage: "lock.fill",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: visibilityBinding(item),
                                action: {
                                    dismissSurface()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        QuickTogglesService.shared.lockScreen()
                                    }
                                })
        case .displayOff:
            UtilityActionButton(title: strings.displayOffTitle,
                                caption: caption(for: item, idle: strings.displayOffCaption),
                                systemImage: "display",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: visibilityBinding(item),
                                action: {
                                    dismissSurface()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        QuickTogglesService.shared.turnDisplayOff()
                                    }
                                })
        case .screenSaver:
            UtilityActionButton(title: strings.screenSaverTitle,
                                caption: strings.screenSaverCaption,
                                systemImage: "sparkles.tv",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: visibilityBinding(item),
                                action: {
                                    dismissSurface()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        QuickTogglesService.shared.startScreenSaver()
                                    }
                                })
        }
    }

    // MARK: - Row state

    /// The idle caption, replaced by a short-lived failure note; success needs
    /// no caption, the row itself already reflects the new state.
    private func caption(for item: QuickToggleAction, idle: String) -> String {
        let strings = FeatureStrings.quickToggles(l10n.language)
        switch toggles.state(for: item) {
        case .failed: return strings.actionFailed
        case .needsPermission:
            return "\(l10n.s.permissionRequired): \(permissionName(item))"
        case .running, .none: return idle
        }
    }

    private func ejectCaption(_ strings: QuickToggleFeatureStrings) -> String {
        switch toggles.state(for: .ejectDisks) {
        case .running: return l10n.s.diskEjecting
        case .failed: return l10n.s.diskEjectFailed
        case .needsPermission, .none:
            return toggles.ejectableVolumeCount() > 0 ? strings.ejectCaption : l10n.s.diskNoExternal
        }
    }

    private func needsPermission(_ item: QuickToggleAction) -> Bool {
        toggles.state(for: item) == .needsPermission
    }

    /// Only the Trash talks to another app (the Finder); everything else
    /// works without a permission.
    private func permissionName(_ item: QuickToggleAction) -> String {
        FeatureStrings.hub(l10n.language).permAutomationFinder
    }

    private func permissionButtonTitle(_ item: QuickToggleAction) -> String? {
        needsPermission(item) ? l10n.s.permissionOpenSettings : nil
    }

    /// A declined Automation consent never re-prompts by itself; the row
    /// swaps into a button that opens the Automation pane instead.
    private func permissionAction(_ item: QuickToggleAction) -> (() -> Void)? {
        guard needsPermission(item) else { return nil }
        return {
            Permissions.shared.openAutomationSettings()
        }
    }
}
