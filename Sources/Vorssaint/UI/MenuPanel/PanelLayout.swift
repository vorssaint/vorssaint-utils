// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

protocol PanelOrderItem: RawRepresentable, CaseIterable, Hashable where RawValue == String {}

/// The major, user-customizable sections of the menu panel. Raw values are the
/// stable identifiers persisted in the saved order and the collapsed set, so
/// renaming a case would orphan a user's stored layout — keep them stable.
enum PanelSectionID: String, CaseIterable, Identifiable {
    case keepAwake, mixer, system, network, disk, power, fanControl, utilities, controls

    var id: String { rawValue }

    /// Localized display name, reused from the existing section titles.
    func title(_ s: Strings) -> String {
        switch self {
        case .keepAwake: return s.keepAwakeTitle
        case .mixer: return s.mixerSection
        case .system: return s.systemSection
        case .network: return s.networkSection
        case .disk: return s.diskSection
        case .power: return s.powerSection
        case .fanControl: return s.fanControlBetaSection
        case .utilities: return s.utilitiesSection
        case .controls: return s.quickControlsSection
        }
    }

    var symbolName: String {
        switch self {
        case .keepAwake: return "moon.zzz.fill"
        case .mixer: return "slider.horizontal.3"
        case .system: return "cpu"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .power: return "bolt.fill"
        case .fanControl: return "fanblades.fill"
        case .utilities: return "wrench.and.screwdriver.fill"
        case .controls: return "switch.2"
        }
    }

    /// The UserDefaults key that controls whether this section shows in the panel.
    /// The monitoring blocks reuse their existing `monitorShow*` keys; the rest
    /// get a dedicated `panelShow*` key so every section is hideable.
    var visibilityKey: String {
        switch self {
        case .keepAwake: return DefaultsKey.panelShowKeepAwake
        case .mixer: return DefaultsKey.monitorShowMixer
        case .system: return DefaultsKey.monitorShowSystem
        case .network: return DefaultsKey.monitorShowNetwork
        case .disk: return DefaultsKey.monitorShowDisk
        case .power: return DefaultsKey.monitorShowPower
        case .fanControl: return DefaultsKey.monitorShowFanControlBeta
        case .utilities: return DefaultsKey.panelShowUtilities
        case .controls: return DefaultsKey.panelShowControls
        }
    }

    /// Fan Control is a beta opt-in (default hidden); everything else shows by default.
    var shownByDefault: Bool { self != .fanControl }
}

/// Persisted panel layout: the order the sections appear in and which ones are
/// collapsed. The order is a comma-joined list of ids; any section missing from
/// a saved order (e.g. one added in a later version) is appended in its canonical
/// position, so a section can never silently disappear. Collapsed sections are a
/// comma-joined set of ids.
enum PanelLayout {
    private static var defaults: UserDefaults { .standard }

    /// The sections in display order: the user's saved order first, then any not
    /// yet listed, in their canonical order.
    static var order: [PanelSectionID] {
        let saved = (defaults.string(forKey: DefaultsKey.panelSectionOrder) ?? "")
            .split(separator: ",")
            .compactMap { PanelSectionID(rawValue: String($0)) }
        var seen = Set<PanelSectionID>()
        var result: [PanelSectionID] = []
        for id in saved where seen.insert(id).inserted { result.append(id) }
        for id in PanelSectionID.allCases where seen.insert(id).inserted {
            if id == .disk, let networkIndex = result.firstIndex(of: .network) {
                result.insert(id, at: networkIndex + 1)
            } else if id == .controls, let utilitiesIndex = result.firstIndex(of: .utilities) {
                result.insert(id, at: utilitiesIndex + 1)
            } else {
                result.append(id)
            }
        }
        return result
    }

    static func setOrder(_ ids: [PanelSectionID]) {
        defaults.set(ids.map(\.rawValue).joined(separator: ","), forKey: DefaultsKey.panelSectionOrder)
    }

    static func itemOrder<Item: PanelOrderItem>(_ type: Item.Type, key: String) -> [Item] {
        let defaultOrder = type.allCases.map(\.rawValue)
        let raw = defaults.string(forKey: key) ?? ""
        return Defaults.sanitizedPanelItemOrder(raw, defaultOrder: defaultOrder).compactMap(Item.init(rawValue:))
    }

    static func setItemOrder<Item: PanelOrderItem>(_ ids: [Item], key: String) {
        defaults.set(ids.map(\.rawValue).joined(separator: ","), forKey: key)
    }

    static func resetItemOrder(key: String) {
        defaults.removeObject(forKey: key)
    }

    static func isShown(_ id: PanelSectionID) -> Bool {
        defaults.object(forKey: id.visibilityKey) as? Bool ?? id.shownByDefault
    }

    static func setShown(_ shown: Bool, for id: PanelSectionID) {
        defaults.set(shown, forKey: id.visibilityKey)
    }

    static func isCollapsed(_ id: PanelSectionID) -> Bool {
        collapsedSet().contains(id.rawValue)
    }

    static func setCollapsed(_ collapsed: Bool, for id: PanelSectionID) {
        var set = collapsedSet()
        if collapsed { set.insert(id.rawValue) } else { set.remove(id.rawValue) }
        defaults.set(set.sorted().joined(separator: ","), forKey: DefaultsKey.panelCollapsedSections)
    }

    static func resetCollapsedSectionsOnce(for version: String) {
        guard defaults.string(forKey: DefaultsKey.panelCollapsedResetVersion) != version else { return }
        defaults.removeObject(forKey: DefaultsKey.panelCollapsedSections)
        defaults.set(version, forKey: DefaultsKey.panelCollapsedResetVersion)
    }

    private static func collapsedSet() -> Set<String> {
        Set((defaults.string(forKey: DefaultsKey.panelCollapsedSections) ?? "")
            .split(separator: ",").map(String.init))
    }
}

/// A major panel section with a collapsible header. The header row (the section
/// title plus a chevron) toggles a persisted collapsed state; collapsing hides
/// the body but keeps the header so it can be reopened. Every major component in
/// the panel uses this so they all collapse and reorder consistently.
struct PanelSection<Content: View>: View {
    @ObservedObject private var l10n = L10n.shared
    private let id: PanelSectionID
    private let title: String
    private let collapsible: Bool
    private let supportsEditing: Bool
    private let editButtonVisible: Bool
    private let resetAction: (() -> Void)?
    private let content: (Bool) -> Content
    @State private var collapsed: Bool
    @State private var editing = false

    init(_ id: PanelSectionID, title: String, collapsible: Bool = true,
         @ViewBuilder content: @escaping () -> Content) {
        self.id = id
        self.title = title
        self.collapsible = collapsible
        self.supportsEditing = false
        self.editButtonVisible = false
        self.resetAction = nil
        self.content = { _ in content() }
        _collapsed = State(initialValue: PanelLayout.isCollapsed(id))
    }

    init(_ id: PanelSectionID, title: String, collapsible: Bool = true,
         supportsEditing: Bool,
         editButtonVisible: Bool = true,
         resetAction: (() -> Void)? = nil,
         @ViewBuilder content: @escaping (Bool) -> Content) {
        self.id = id
        self.title = title
        self.collapsible = collapsible
        self.supportsEditing = supportsEditing
        self.editButtonVisible = editButtonVisible
        self.resetAction = resetAction
        self.content = content
        _collapsed = State(initialValue: PanelLayout.isCollapsed(id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if !collapsible || !collapsed {
                content(isEditing)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if collapsible {
                Button(action: toggle) {
                    HStack(spacing: 6) {
                        sectionTitle(title)
                        Spacer(minLength: 0)
                        collapseIcon
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                sectionTitle(title)
                Spacer(minLength: 0)
            }
            if supportsEditing {
                if isEditing, let resetAction {
                    resetButton(resetAction)
                        .opacity(editButtonVisible ? 1 : 0)
                        .disabled(!editButtonVisible)
                        .accessibilityHidden(!editButtonVisible)
                }
                editButton
                    .opacity(editButtonVisible ? 1 : 0)
                    .disabled(!editButtonVisible)
                    .accessibilityHidden(!editButtonVisible)
            }
        }
    }

    private var collapseIcon: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(collapsed ? 0 : 90))
    }

    private var editButton: some View {
        Button(action: toggleEditing) {
            if isEditing {
                Label("OK", systemImage: "checkmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 18)
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEditing ? Color.white : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: isEditing ? 8 : 6, style: .continuous)
                .fill(isEditing ? Color.accentColor : Color.clear)
        )
        .help(isEditing ? l10n.s.uninstallerDoneTitle : l10n.s.menuEdit)
    }

    private func resetButton(_ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) {
                action()
            }
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
        .help(l10n.s.mixerOutputDefault)
    }

    private var isEditing: Bool { supportsEditing && editButtonVisible && editing }

    private func toggleEditing() {
        withAnimation(.easeOut(duration: 0.16)) {
            if collapsed {
                collapsed = false
                PanelLayout.setCollapsed(false, for: id)
            }
            editing.toggle()
        }
    }

    private func toggle() {
        withAnimation(.easeOut(duration: 0.18)) { collapsed.toggle() }
        PanelLayout.setCollapsed(collapsed, for: id)
    }
}

struct PanelDragHandle: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 16, height: 22)
            .contentShape(Rectangle())
            .help(L10n.shared.s.monitorOrderHint)
    }
}

struct PanelReorderableItem<Item: PanelOrderItem, Content: View>: View {
    let item: Item
    var isEnabled = true
    @Binding var order: [Item]
    @Binding var dragging: Item?
    let content: () -> Content

    var body: some View {
        if isEnabled {
            content()
                .onDrag {
                    dragging = item
                    return NSItemProvider(object: item.rawValue as NSString)
                }
                .onDrop(of: [UTType.text], delegate: PanelItemDropDelegate(item: item,
                                                                           order: $order,
                                                                           dragging: $dragging))
        } else {
            content()
        }
    }
}

private struct PanelItemDropDelegate<Item: PanelOrderItem>: DropDelegate {
    let item: Item
    @Binding var order: [Item]
    @Binding var dragging: Item?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != item,
              let from = order.firstIndex(of: dragging),
              let to = order.firstIndex(of: item) else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

struct PanelInlineHideButton: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var isVisible: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.14)) {
                isVisible.toggle()
            }
        } label: {
            Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isVisible ? Color.secondary : Color.accentColor)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill((isVisible ? Color.primary : Color.accentColor).opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .help(isVisible ? l10n.s.panelHideItem : l10n.s.panelShowItem)
    }
}

struct PanelHiddenBadge: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Label(l10n.s.panelHiddenItem, systemImage: "eye.slash.fill")
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.08))
            )
    }
}

struct PanelHiddenItemRow: View {
    let title: String
    let systemImage: String
    @Binding var isVisible: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            PanelHiddenBadge()
            PanelInlineHideButton(isVisible: $isVisible)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }
}
