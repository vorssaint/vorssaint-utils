// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

/// The Menu Bar Organizer page: the switch, the collapser's icon, where the
/// hidden icons show (the bar or a shelf), a drawing of the bar in three tiers
/// (always shown, hidden behind the collapser, never shown) and the auto
/// re-hide delay. Row choices apply immediately; dragging commits on drop.
struct MenuBarOrganizerSettings: View {
    private typealias Editor = MenuBarOrganizerEditorSupport

    private static let autoRehideChoices = [5, 10, 30, 60]

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = MenuBarOrganizerService.shared
    @AppStorage(DefaultsKey.menuBarOrganizerEnabled) private var enabled = false
    @AppStorage(DefaultsKey.menuBarOrganizerAutoRehideSeconds) private var autoRehideSeconds = 0
    @AppStorage(DefaultsKey.menuBarOrganizerIcon) private var icon = MenuBarOrganizerIcon.chevron
    @AppStorage(DefaultsKey.menuBarOrganizerReveal) private var reveal = MenuBarOrganizerReveal.menuBar
    @AppStorage(DefaultsKey.menuBarOrganizerShelfMonochrome) private var shelfMonochrome = true
    /// The row being dragged, so a drop target knows what entered it.
    @State private var dragging: MenuBarItemIdentity?

    private let ownBundleID = Bundle.main.bundleIdentifier ?? ""

    private var strings: MenuBarOrganizerFeatureStrings { FeatureStrings.menuBarOrganizer(l10n.language) }

    var body: some View {
        Form {
            Section(strings.title) {
                // Installing the feature turns the switch on; where hiding
                // cannot work it must not read as on.
                Toggle(strings.enable, isOn: service.isSupported ? $enabled : .constant(false))
                    .disabled(!service.isSupported)
                    .onChange(of: enabled) { _, value in
                        service.syncWithPreferences()
                        guard value, service.isSupported, !permissions.accessibility else { return }
                        permissions.requestAccessibility()
                        permissions.openAccessibilitySettings()
                    }
                if let unsupported = service.unsupportedReason {
                    warning(unsupportedText(unsupported))
                } else {
                    caption(strings.enableCaption)
                }
                Picker(strings.icon, selection: $icon) {
                    ForEach(MenuBarOrganizerIcon.allCases, id: \.self) { choice in
                        Label(iconName(choice), systemImage: choice.symbol(collapsed: true, reveal: reveal,
                                                                           shelfOpen: false)).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!service.isSupported)
                .onChange(of: icon) { _, _ in service.refreshIcon() }
                Picker(strings.reveal, selection: $reveal) {
                    Text(strings.revealMenuBar).tag(MenuBarOrganizerReveal.menuBar)
                    Text(strings.revealShelf).tag(MenuBarOrganizerReveal.shelf)
                }
                .pickerStyle(.segmented)
                .disabled(!service.isSupported)
                .onChange(of: reveal) { _, _ in
                    service.refreshIcon()
                    service.refreshAutoRehide()
                }
                caption(reveal == .shelf ? strings.revealShelfCaption : strings.revealMenuBarCaption)
                if reveal == .menuBar {
                    Picker(strings.autoRehide, selection: $autoRehideSeconds) {
                        Text(strings.autoRehideNever).tag(0)
                        ForEach(Self.autoRehideChoices, id: \.self) { seconds in
                            Text(String(format: strings.autoRehideSecondsFormat, seconds)).tag(seconds)
                        }
                    }
                    .disabled(!service.isSupported)
                    .onChange(of: autoRehideSeconds) { _, _ in service.refreshAutoRehide() }
                }
                if reveal == .shelf {
                    Toggle(strings.shelfMonochrome, isOn: $shelfMonochrome)
                        .disabled(!service.isSupported)
                }
                ForEach(service.runningManagers, id: \.self) { manager in
                    warning(String(format: strings.otherManagerFormat, manager))
                }
                if let status {
                    caption(status)
                }
                if let problem = service.problem {
                    warning(problemText(problem))
                }
            }

            if enabled, service.isSupported, !permissions.accessibility {
                Section(l10n.s.permissionRequired) {
                    PermissionRow(kind: .accessibility)
                }
            }

            if service.state != .off {
                Group {
                    behaviorNotes
                    tierSection(.show, items: baseline.visible, title: strings.showSection,
                                caption: strings.showCaption, empty: strings.showEmpty)
                    tierSection(.hide, items: baseline.hidden, title: strings.hideSection,
                                caption: strings.hideCaption, empty: strings.hideEmpty)
                    tierSection(.never, items: baseline.neverShown, title: strings.neverSection,
                                caption: strings.neverCaption, empty: strings.neverEmpty)
                    layoutStatus
                }
                .disabled(service.state == .applying)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            service.refreshInventory()
        }
    }

    // MARK: - Layout

    private func tierSection(_ tier: Editor.Tier, items: [MenuBarItemIdentity], title: String,
                             caption: String, empty: String) -> some View {
        Section {
            if items.isEmpty {
                Text(empty)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onDrop(of: [UTType.text], delegate: dropDelegate(tier, before: nil))
            } else {
                ForEach(items, id: \.self) { identity in
                    row(identity, tier: tier)
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                self.caption(caption)
            }
        }
    }

    /// Every row takes a drop, locked ones too, so a dragged row can land
    /// anywhere in a list; only rows that may move can be dragged.
    @ViewBuilder
    private func row(_ identity: MenuBarItemIdentity, tier: Editor.Tier) -> some View {
        let locked = lockReason(identity)
        let note = locked ?? unsignedNote(identity)
        let content = HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .opacity(locked == nil ? 1 : 0)
            presentation.icon(identity)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(presentation.name(identity, among: baseline.hidden + baseline.visible + baseline.neverShown))
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if locked == nil {
                Menu(tierName(tier)) {
                    ForEach(Editor.Tier.allCases.filter { $0 != tier }, id: \.self) { other in
                        Button(tierName(other)) { move(identity, to: other, before: nil) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .contentShape(Rectangle())
        let target = dropDelegate(tier, before: identity)
        if locked == nil {
            content
                .onDrag {
                    dragging = identity
                    // Never decoded: `dragging` carries the row.
                    return NSItemProvider(object: "\(identity.bundleID)\u{1F}\(identity.title)" as NSString)
                }
                .onDrop(of: [UTType.text], delegate: target)
        } else {
            content
                .onDrop(of: [UTType.text], delegate: target)
        }
    }

    private func dropDelegate(_ tier: Editor.Tier, before identity: MenuBarItemIdentity?) -> MenuBarOrganizerDropDelegate {
        MenuBarOrganizerDropDelegate(dragging: $dragging) { move($0, to: tier, before: identity) }
    }

    private func move(_ identity: MenuBarItemIdentity, to tier: Editor.Tier, before target: MenuBarItemIdentity?) {
        guard service.state != .applying, lockReason(identity) == nil else { return }
        let current = baseline
        let updated = Editor.moving(identity, to: tier, before: target, in: current) { lockReason($0) != nil }
        guard updated != current else { return }
        service.apply(updated, collapseAfterApplying: tier == .hide)
    }

    private var layoutStatus: some View {
        Section {
            HStack(spacing: 8) {
                if service.state == .applying {
                    ProgressView()
                        .controlSize(.small)
                    Text(strings.applying)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let report = service.lastApplyReport {
                    Text(String(format: strings.applyReportFormat, report.moved, report.failed))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(strings.refresh) {
                    service.refreshInventory()
                }
            }
        }
    }

    private var behaviorNotes: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(strings.behaviorNoteTitle, systemImage: "info.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(strings.mouseHint)
                Text(strings.dragHint)
                Text(strings.perAppNote)
                Text(strings.systemExtrasNote)
            }
            .font(.callout)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
            }
        }
    }

    /// The current bar, including remembered items absent while it is hidden.
    private var baseline: MenuBarLayout {
        Editor.baseline(layout: service.layout, lastHidden: service.lastHidden,
                        neverShown: service.neverShown, collapsed: service.state == .collapsed)
    }

    // MARK: - Rows

    private var presentation: MenuBarOrganizerItemPresentation {
        MenuBarOrganizerItemPresentation(inventory: service.inventory, lastHidden: service.lastHidden,
                                         neverShown: service.neverShown, strings: strings)
    }

    /// Why a row cannot be hidden, dragged or kept out of the bar, nil when it can.
    private func lockReason(_ identity: MenuBarItemIdentity) -> String? {
        if let system = MenuBarSystemItem.item(for: identity) {
            return system.isPinned ? strings.lockedPinned : nil
        }
        if identity.bundleID == MenuBarOrganizerPolicy.agentBundleID { return strings.lockedSystem }
        if identity.bundleID == ownBundleID { return strings.lockedOwn }
        // Only items that hide are remembered, so one without a snapshot does.
        guard let item = presentation.snapshot(identity),
              !MenuBarOrganizerPolicy.canHide(item, ownBundleID: ownBundleID) else { return nil }
        return strings.lockedHelper
    }

    /// Says that macOS hides the row's icon along with any other, whatever
    /// its tier. Unlike a lock reason it leaves the row free to move.
    private func unsignedNote(_ identity: MenuBarItemIdentity) -> String? {
        switch presentation.snapshot(identity).flatMap(Editor.note(for:)) {
        case .unsigned: strings.lockedUnsigned
        case nil: nil
        }
    }

    // MARK: - Texts

    private var status: String? {
        switch service.state {
        case .off: return nil
        case .expanded: return strings.statusExpanded
        case .collapsed: return strings.statusCollapsed
        case .applying: return strings.applying
        }
    }

    private func iconName(_ icon: MenuBarOrganizerIcon) -> String {
        switch icon {
        case .chevron: return strings.iconChevron
        case .dots: return strings.iconDots
        case .lines: return strings.iconLines
        case .grid: return strings.iconGrid
        }
    }

    private func tierName(_ tier: Editor.Tier) -> String {
        switch tier {
        case .show: return strings.tierShow
        case .hide: return strings.tierHide
        case .never: return strings.tierNever
        }
    }

    private func unsupportedText(_ reason: MenuBarOrganizerAvailability.Unsupported) -> String {
        switch reason {
        case .requiresMacOS27(let current): return String(format: strings.unsupportedOSFormat, current)
        case .apiMissing: return strings.unsupportedAPI
        }
    }

    private func problemText(_ problem: MenuBarOrganizerService.Problem) -> String {
        switch problem {
        case .accessibilityMissing: return strings.problemAccessibility
        case .collapserNotFound: return strings.problemCollapserNotFound
        case .activationFailed(let reason): return String(format: strings.problemActivationFormat, reason)
        case .nothingToHide: return strings.problemNothingToHide
        case .peekFailed(let name): return String(format: strings.problemPeekFailedFormat, name)
        }
    }

    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Commits only a completed drop, using the same move as the row menu.
/// Hovering or cancelling a drag must not reorder the real menu bar.
private struct MenuBarOrganizerDropDelegate: DropDelegate {
    @Binding var dragging: MenuBarItemIdentity?
    let moved: (MenuBarItemIdentity) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let identity = dragging else { return false }
        dragging = nil
        moved(identity)
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
