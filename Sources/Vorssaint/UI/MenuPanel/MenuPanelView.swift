// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    static let menuPanelWillShow = Notification.Name("VorssaintMenuPanelWillShow")
}

struct MenuPanelFocusRequest: Equatable {
    let target: MenuPanelFocusTarget
    let serial: Int
}

enum MenuPanelFocusTarget: Equatable {
    case normal
    case section(PanelSectionID)
    case metric(MetricDetailKind)
}

final class MenuPanelFocus: ObservableObject {
    static let shared = MenuPanelFocus()

    @Published private(set) var request: MenuPanelFocusRequest?
    @Published private(set) var activeMetric: MetricDetailKind?
    @Published private(set) var isSwitchingMetricAnchor = false
    private var serial = 0

    private init() {}

    func showNormalPanel() {
        serial += 1
        activeMetric = nil
        request = MenuPanelFocusRequest(target: .normal, serial: serial)
    }

    func focus(_ section: PanelSectionID) {
        serial += 1
        activeMetric = nil
        request = MenuPanelFocusRequest(target: .section(section), serial: serial)
    }

    func focus(_ metric: MetricDetailKind) {
        serial += 1
        activeMetric = metric
        request = MenuPanelFocusRequest(target: .metric(metric), serial: serial)
    }

    func clearMetricFocus() {
        activeMetric = nil
    }

    func setSwitchingMetricAnchor(_ switching: Bool) {
        isSwitchingMetricAnchor = switching
    }
}

/// Content of the menu bar popover: keep-awake controls, the volume mixer and
/// the system monitor.
struct MenuPanelView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var updates = UpdateService.shared
    @ObservedObject private var panelFocus = MenuPanelFocus.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DefaultsKey.monitorShowMixer) private var showMixer = true
    @AppStorage(DefaultsKey.monitorShowSystem) private var showSystem = true
    @AppStorage(DefaultsKey.monitorShowNetwork) private var showNetwork = true
    @AppStorage(DefaultsKey.monitorShowDisk) private var showDisk = true
    @AppStorage(DefaultsKey.monitorShowPower) private var showPower = true
    @AppStorage(DefaultsKey.monitorShowFanControlBeta) private var showFanControlBeta = false
    @AppStorage(DefaultsKey.panelShowKeepAwake) private var showKeepAwake = true
    @AppStorage(DefaultsKey.panelShowUtilities) private var showUtilities = true
    @AppStorage(DefaultsKey.panelShowControls) private var showControls = true
    @AppStorage(DefaultsKey.panelNavigationEnabled) private var panelNavigationEnabled = true
    @AppStorage(DefaultsKey.panelSectionOrder) private var sectionOrderRaw = ""
    @State private var contentHeight: CGFloat = 0
    @State private var navigableContentHeight: CGFloat = 0
    @State private var metricContentHeight: CGFloat = 0
    @State private var updateBannerHeight: CGFloat = 0
    @State private var selectedSection: PanelSectionID = .keepAwake
    @State private var selectedMetric: MetricDetailKind?

    /// Cap the panel to the usable screen height so it never overflows the menu
    /// bar; taller content scrolls inside.
    private var maxHeight: CGFloat {
        max(360, (NSScreen.main?.visibleFrame.height ?? 760) - 24)
    }

    var body: some View {
        Group {
            if selectedMetric != nil {
                metricPanel
            } else if panelNavigationEnabled {
                navigablePanel
            } else {
                classicPanel
            }
        }
        .onAppear {
            applyFocus(panelFocus.request)
            awake.refreshPasswordlessStatus()
            syncMonitorSampling()
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuPanelWillShow)) { _ in
            syncMonitorSampling()
        }
        .onDisappear {
            if !panelFocus.isSwitchingMetricAnchor {
                SystemMonitor.shared.setMenuPanelNeeds(.none)
            }
        }
        .onChange(of: monitorNeeds) { _, _ in
            syncMonitorSampling()
        }
        .onChange(of: updates.state) { _, state in
            if !state.showsMenuPanelBanner {
                updateBannerHeight = 0
            }
        }
        .onChange(of: panelFocus.request) { _, request in
            applyFocus(request)
        }
    }

    private var monitorNeeds: SystemMonitorPanelNeeds {
        if let selectedMetric {
            return selectedMetric.monitorNeeds
        }
        if panelNavigationEnabled {
            switch activeSection {
            case .system: return SystemMonitorPanelNeeds(system: true)
            case .network: return SystemMonitorPanelNeeds(network: true)
            case .disk: return SystemMonitorPanelNeeds(disk: true)
            case .power: return SystemMonitorPanelNeeds(power: true)
            default: return .none
            }
        }
        return SystemMonitorPanelNeeds(system: showSystem,
                                       network: showNetwork,
                                       disk: showDisk,
                                       power: showPower)
    }

    private func syncMonitorSampling() {
        SystemMonitor.shared.setMenuPanelNeeds(monitorNeeds)
    }

    private func applyFocus(_ request: MenuPanelFocusRequest?) {
        guard let request else { return }
        switch request.target {
        case .normal:
            selectedMetric = nil
        case .section(let section):
            guard isSectionVisible(section) else { return }
            selectedMetric = nil
            selectedSection = section
        case .metric(let metric):
            selectedMetric = metric
            selectedSection = metric.panelSection
        }
    }

    private var classicPanel: some View {
        // Hosted in a custom overlay-scroller container. SwiftUI's own ScrollView
        // reserves a legacy scroller gutter on the right when the system is set to
        // always show scroll bars, pushing the fixed-width content off-center. An
        // overlay scroller floats over the content and reserves no space, so the
        // panel stays centered whether or not it needs to scroll. The hosting
        // view reports its natural height after layout so section changes resize
        // the popover without reserving a scroller gutter.
        OverlayScrollView(measuredHeight: $contentHeight) {
            VStack(alignment: .leading, spacing: 12) {
                UpdateBanner()
                header
                ForEach(visibleSections) { id in
                    section(for: id)
                }
                footer
            }
            .padding(12)
            .frame(width: 332)
        }
        .frame(width: 332, height: min(contentHeight == 0 ? 480 : contentHeight, maxHeight))
        .panelGlassSurface()
    }

    private var navigablePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            UpdateBanner()
                .reportHeight($updateBannerHeight)
            header
            sectionNavigation

            OverlayScrollView(measuredHeight: $navigableContentHeight) {
                VStack(alignment: .leading, spacing: 12) {
                    section(for: activeSection, collapsible: false)
                }
                .frame(width: 308)
            }
            .frame(width: 308, height: navigableScrollHeight)

            footer
        }
        .padding(12)
        .frame(width: 332, height: navigablePanelHeight)
        .panelGlassSurface()
    }

    private var metricPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            UpdateBanner()
                .reportHeight($updateBannerHeight)
            header

            if let selectedMetric {
                metricNavigationHeader(selectedMetric)
                OverlayScrollView(measuredHeight: $metricContentHeight) {
                    MetricDetailView(kind: selectedMetric)
                        .frame(width: 308)
                }
                .frame(width: 308, height: metricScrollHeight)
            }

            footer
        }
        .padding(12)
        .frame(width: 332, height: metricPanelHeight)
        .panelGlassSurface()
    }

    /// The major sections in the user's saved order. Reading `sectionOrderRaw`
    /// (the @AppStorage backing) establishes the dependency so reordering in
    /// Settings refreshes the live panel; PanelLayout fills in any sections the
    /// saved order omits.
    private var orderedSections: [PanelSectionID] {
        _ = sectionOrderRaw
        return PanelLayout.order
    }

    private var visibleSections: [PanelSectionID] {
        orderedSections.filter(isSectionVisible)
    }

    private var activeSection: PanelSectionID {
        visibleSections.contains(selectedSection) ? selectedSection : (visibleSections.first ?? .keepAwake)
    }

    private var navigableScrollHeight: CGFloat {
        let measured = navigableContentHeight == 0 ? estimatedNavigableContentHeight : navigableContentHeight
        return min(measured, max(80, maxHeight - navigableChromeHeight))
    }

    private var navigablePanelHeight: CGFloat {
        min(maxHeight, max(220, navigableScrollHeight + navigableChromeHeight))
    }

    private var metricScrollHeight: CGFloat {
        let measured = metricContentHeight == 0 ? estimatedMetricContentHeight : metricContentHeight
        return min(measured, max(80, maxHeight - navigableChromeHeight))
    }

    private var metricPanelHeight: CGFloat {
        min(maxHeight, max(220, metricScrollHeight + navigableChromeHeight))
    }

    private var navigableChromeHeight: CGFloat {
        let bannerHeight = updates.state.showsMenuPanelBanner
            ? (max(updateBannerHeight, 48) + 12)
            : 0
        return 166 + bannerHeight
    }

    private var estimatedNavigableContentHeight: CGFloat {
        switch activeSection {
        case .keepAwake: return 250
        case .mixer: return 250
        case .system: return 460
        case .network: return 190
        case .disk: return 360
        case .power: return 170
        case .fanControl: return 92
        case .utilities: return 500
        case .controls: return 360
        }
    }

    private var estimatedMetricContentHeight: CGFloat {
        guard let selectedMetric else { return 320 }
        switch selectedMetric {
        case .cpu, .gpu, .memory: return 430
        case .network: return 330
        case .disk: return 360
        case .battery, .power: return 360
        }
    }

    /// Renders the section for an id, honoring its "show in panel" toggle. Each
    /// section self-hides when it has nothing to show, so the order is stable
    /// whether or not a section is currently populated.
    @ViewBuilder
    private func section(for id: PanelSectionID, collapsible: Bool = true) -> some View {
        switch id {
        case .keepAwake: KeepAwakeCard(collapsible: collapsible)
        case .mixer: if showMixer { MixerSection(collapsible: collapsible) }
        case .system: if showSystem { SystemSection(collapsible: collapsible) }
        case .network: if showNetwork { NetworkSection(collapsible: collapsible) }
        case .disk: if showDisk { DiskSection(collapsible: collapsible) }
        case .power: if showPower { PowerSection(collapsible: collapsible) }
        case .fanControl: if showFanControlBeta { FanControlSection(collapsible: collapsible) }
        case .utilities: UtilitiesSection(collapsible: collapsible, startCleaning: startCleaning)
        case .controls: QuickControlsSection(collapsible: collapsible)
        }
    }

    private func isSectionVisible(_ id: PanelSectionID) -> Bool {
        switch id {
        case .keepAwake: return showKeepAwake
        case .mixer: return showMixer
        case .system: return showSystem
        case .network: return showNetwork
        case .disk: return showDisk
        case .power: return showPower
        case .fanControl: return showFanControlBeta
        case .utilities: return showUtilities
        case .controls: return showControls
        }
    }

    private var sectionNavigation: some View {
        HStack(spacing: 2) {
            ForEach(visibleSections) { id in
                Button {
                    selectedSection = id
                } label: {
                    Image(systemName: id.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(activeSection == id ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(activeSection == id ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .help(id.title(l10n.s))
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PanelSurface.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
        )
    }

    private func metricNavigationHeader(_ kind: MetricDetailKind) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedMetric = nil
                selectedSection = kind.panelSection
                MenuPanelFocus.shared.clearMetricFocus()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(PanelSurface.cardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
            )

            Label(kind.title(l10n.s), systemImage: kind.symbolName)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Starts cleaning mode and closes the panel so the lock overlay is the only
    /// thing on screen. The footer button and the right-click menu both call this.
    private func startCleaning() {
        // Close the panel first so, if activate() has to show the Accessibility
        // alert, it isn't stranded on top of the still-open panel.
        appDelegate()?.closePopover()
        CleaningModeManager.shared.activate()
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandBadge(size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppInfo.name)
                    .font(.system(size: 15, weight: .bold))
                keepAwakeStatusIndicator
            }
            Spacer()
        }
    }

    private var keepAwakeStatusIndicator: some View {
        let color = keepAwakeStatusColor
        return HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(awake.isActive ? 0.55 : 0), radius: 2)
            Text(awake.isActive ? l10n.s.panelAwake : l10n.s.panelNormalSleep)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(awake.isActive ? color : Color.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(awake.isActive ? 0.15 : 0.09))
        )
    }

    private var keepAwakeStatusColor: Color {
        if !awake.isActive { return .secondary }
        return awake.clamshellActive
            ? PanelMetricColor.yellow(for: colorScheme)
            : PanelMetricColor.green(for: colorScheme)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton(l10n.s.panelSettings,
                         systemImage: "gearshape",
                         horizontalPadding: 7) {
                appDelegate()?.openSettingsWindow()
            }

            footerButton(panelModeTitle,
                         systemImage: panelModeSymbol,
                         horizontalPadding: 7) {
                selectedMetric = nil
                MenuPanelFocus.shared.clearMetricFocus()
                panelNavigationEnabled.toggle()
            }

            footerButton(l10n.s.panelQuit,
                         systemImage: "power",
                         horizontalPadding: 7) {
                NSApp.terminate(nil)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .padding(.top, 4)
    }

    private var panelModeTitle: String {
        panelNavigationEnabled ? l10n.s.panelFooterList : l10n.s.panelFooterSections
    }

    private var panelModeSymbol: String {
        panelNavigationEnabled ? "list.bullet" : "square.grid.2x2"
    }

    private func footerButton(_ title: String, systemImage: String,
                              horizontalPadding: CGFloat = 8,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.78)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(PanelSurface.cardFill(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

private enum UtilityPanelItem: String, PanelOrderItem, Identifiable {
    case homebrew, media, clipboard, windowLayout, uninstaller, cleanURL, cleaning

    var id: String { rawValue }
}

struct UtilitiesSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var showUninstaller = false
    @State private var showURLCleaner = false
    @State private var showHomebrewPanel = false
    @State private var showMediaPanel = false
    @State private var showClipboardPanel = false
    @State private var showWindowLayoutPanel = false
    @AppStorage(DefaultsKey.panelUtilityCleaning) private var showCleaning = true
    @AppStorage(DefaultsKey.panelUtilityURLCleaner) private var showCleanURL = true
    @AppStorage(DefaultsKey.panelUtilityUninstaller) private var showUninstallerAction = true
    @AppStorage(DefaultsKey.panelUtilityHomebrew) private var showHomebrew = true
    @AppStorage(DefaultsKey.panelUtilityMedia) private var showMedia = true
    @AppStorage(DefaultsKey.panelUtilityClipboard) private var showClipboard = true
    @AppStorage(DefaultsKey.panelUtilityWindowLayout) private var showWindowLayout = true
    @AppStorage(DefaultsKey.clipboardHistoryEnabled) private var clipboardEnabled = false
    @AppStorage(DefaultsKey.panelUtilityOrder) private var utilityOrderRaw = ""
    @State private var draggingItem: UtilityPanelItem?
    var collapsible = true
    var startCleaning: () -> Void

    var body: some View {
        PanelSection(.utilities, title: l10n.s.utilitiesSection, collapsible: collapsible,
                     supportsEditing: true,
                     editButtonVisible: !showUninstaller
                        && !showURLCleaner
                        && !showHomebrewPanel
                        && !showMediaPanel
                        && !showClipboardPanel
                        && !showWindowLayoutPanel,
                     resetAction: resetPanelDefaults) { editing in
            if showUninstaller {
                PanelUninstallerView {
                    showUninstaller = false
                }
            } else if showURLCleaner {
                PanelURLCleanerView {
                    showURLCleaner = false
                }
            } else if showHomebrewPanel {
                PanelHomebrewView {
                    PanelInteractionState.shared.keepsPopoverOpen = false
                    showHomebrewPanel = false
                }
            } else if showMediaPanel {
                PanelMediaView {
                    PanelInteractionState.shared.keepsPopoverOpen = false
                    showMediaPanel = false
                }
            } else if showClipboardPanel {
                PanelClipboardView {
                    PanelInteractionState.shared.keepsPopoverOpen = false
                    showClipboardPanel = false
                }
            } else if showWindowLayoutPanel {
                PanelWindowLayoutView {
                    PanelInteractionState.shared.keepsPopoverOpen = false
                    showWindowLayoutPanel = false
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items(editing: editing)) { item in
                        PanelReorderableItem(item: item,
                                             isEnabled: editing,
                                             order: itemOrderBinding,
                                             dragging: $draggingItem) {
                            itemView(item, editing: editing)
                        }
                    }
                }
            }
        }
        .onChange(of: showHomebrewPanel) { _, shown in
            if shown {
                PanelInteractionState.shared.keepsPopoverOpen = true
            } else if !showUninstaller && !showURLCleaner && !showMediaPanel && !showClipboardPanel && !showWindowLayoutPanel {
                PanelInteractionState.shared.keepsPopoverOpen = false
            }
        }
        .onChange(of: showMediaPanel) { _, shown in
            if shown {
                PanelInteractionState.shared.keepsPopoverOpen = true
            } else if !showUninstaller && !showURLCleaner && !showHomebrewPanel && !showClipboardPanel && !showWindowLayoutPanel {
                PanelInteractionState.shared.keepsPopoverOpen = false
            }
        }
        .onChange(of: showClipboardPanel) { _, shown in
            if shown {
                PanelInteractionState.shared.keepsPopoverOpen = true
            } else if !showUninstaller && !showURLCleaner && !showHomebrewPanel && !showMediaPanel && !showWindowLayoutPanel {
                PanelInteractionState.shared.keepsPopoverOpen = false
            }
        }
        .onChange(of: showWindowLayoutPanel) { _, shown in
            if shown {
                PanelInteractionState.shared.keepsPopoverOpen = true
            } else if !showUninstaller && !showURLCleaner && !showHomebrewPanel && !showMediaPanel && !showClipboardPanel {
                PanelInteractionState.shared.keepsPopoverOpen = false
            }
        }
        .onDisappear {
            if !showUninstaller
                && !showURLCleaner
                && !showHomebrewPanel
                && !showMediaPanel
                && !showClipboardPanel
                && !showWindowLayoutPanel {
                PanelInteractionState.shared.keepsPopoverOpen = false
            }
        }
    }

    private var cleaningNeedsAccessibility: Bool {
        showCleaning && !permissions.accessibility
    }

    private var cleaningCaption: String {
        cleaningNeedsAccessibility
            ? "\(l10n.s.permissionRequired): \(l10n.s.permissionAccessibility)"
            : l10n.s.cleaningPanelCaption
    }

    private var orderedItems: [UtilityPanelItem] {
        _ = utilityOrderRaw
        return PanelLayout.itemOrder(UtilityPanelItem.self, key: DefaultsKey.panelUtilityOrder)
    }

    private var itemOrderBinding: Binding<[UtilityPanelItem]> {
        Binding {
            orderedItems
        } set: { newValue in
            PanelLayout.setItemOrder(newValue, key: DefaultsKey.panelUtilityOrder)
        }
    }

    private func items(editing: Bool) -> [UtilityPanelItem] {
        orderedItems.filter { editing || isVisible($0) }
    }

    private func isVisible(_ item: UtilityPanelItem) -> Bool {
        switch item {
        case .homebrew: return showHomebrew
        case .media: return showMedia
        case .clipboard: return showClipboard
        case .windowLayout: return showWindowLayout
        case .uninstaller: return showUninstallerAction
        case .cleanURL: return showCleanURL
        case .cleaning: return showCleaning
        }
    }

    @ViewBuilder
    private func itemView(_ item: UtilityPanelItem, editing: Bool) -> some View {
        switch item {
        case .homebrew:
            UtilityActionButton(title: l10n.s.homebrewName,
                                caption: l10n.s.homebrewEnableCaption,
                                systemImage: "shippingbox",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showHomebrew,
                                action: {
                                    PanelInteractionState.shared.keepsPopoverOpen = true
                                    showHomebrewPanel = true
                                })
        case .media:
            UtilityActionButton(title: l10n.s.mediaName,
                                caption: l10n.s.mediaEnableCaption,
                                systemImage: "photo.on.rectangle.angled",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showMedia,
                                action: {
                                    PanelInteractionState.shared.keepsPopoverOpen = true
                                    showMediaPanel = true
                                })
        case .clipboard:
            UtilityActionButton(title: FeatureStrings.clipboard(l10n.language).title,
                                caption: clipboardEnabled
                                    ? FeatureStrings.clipboard(l10n.language).caption
                                    : FeatureStrings.clipboard(l10n.language).disabled,
                                systemImage: "doc.on.clipboard",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showClipboard,
                                action: {
                                    PanelInteractionState.shared.keepsPopoverOpen = true
                                    showClipboardPanel = true
                                })
        case .windowLayout:
            UtilityActionButton(title: FeatureStrings.windowLayout(l10n.language).title,
                                caption: FeatureStrings.windowLayout(l10n.language).caption,
                                systemImage: "rectangle.3.group",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showWindowLayout,
                                action: {
                                    PanelInteractionState.shared.keepsPopoverOpen = true
                                    showWindowLayoutPanel = true
                                })
        case .uninstaller:
            UtilityActionButton(title: l10n.s.uninstallerName,
                                caption: l10n.s.uninstallerEnableCaption,
                                systemImage: "trash",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showUninstallerAction,
                                action: {
                                    PanelInteractionState.shared.keepsPopoverOpen = true
                                    showUninstaller = true
                                })
        case .cleanURL:
            UtilityActionButton(title: l10n.s.urlCleanerName,
                                caption: l10n.s.urlCleanerEnableCaption,
                                systemImage: "link",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showCleanURL,
                                action: {
                                    PanelInteractionState.shared.keepsPopoverOpen = true
                                    showURLCleaner = true
                                })
        case .cleaning:
            UtilityActionButton(title: l10n.s.cleaningMenuItem,
                                caption: cleaningCaption,
                                systemImage: "keyboard",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showCleaning,
                                needsAttention: cleaningNeedsAccessibility,
                                permissionButtonTitle: l10n.s.permissionRequest,
                                permissionAction: cleaningNeedsAccessibility ? grantAccessibility : nil,
                                action: startCleaning)
        }
    }

    private func resetPanelDefaults() {
        PanelLayout.resetItemOrder(key: DefaultsKey.panelUtilityOrder)
        utilityOrderRaw = ""
        showHomebrew = true
        showMedia = true
        showClipboard = true
        showWindowLayout = true
        showUninstallerAction = true
        showCleanURL = true
        showCleaning = true
    }

    private func grantAccessibility() {
        Permissions.shared.requestAccessibility()
        Permissions.shared.openAccessibilitySettings()
    }
}

private enum ControlPanelItem: String, PanelOrderItem, Identifiable {
    case mouseScroll, switcher, cutPaste, autoQuit, shelf, windowMaximize, dockPreview

    var id: String { rawValue }
}

struct QuickControlsSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var inverter = ScrollInverter.shared
    @ObservedObject private var switcher = AppSwitcher.shared
    @ObservedObject private var dockPreview = DockPreviewService.shared
    @ObservedObject private var cutPaste = FinderCutPaste.shared
    @ObservedObject private var autoQuit = AutoQuitService.shared
    @ObservedObject private var windowMaximizer = WindowMaximizer.shared
    @AppStorage(DefaultsKey.scrollInverterEnabled) private var scrollEnabled = false
    @AppStorage(DefaultsKey.switcherEnabled) private var switcherEnabled = true
    @AppStorage(DefaultsKey.switcherIconRowMode) private var switcherIconRowMode = false
    @AppStorage(DefaultsKey.dockPreviewEnabled) private var dockPreviewEnabled = false
    @AppStorage(DefaultsKey.finderCutPasteEnabled) private var cutPasteEnabled = false
    @AppStorage(DefaultsKey.autoQuitEnabled) private var autoQuitEnabled = false
    @AppStorage(DefaultsKey.shelfEnabled) private var shelfEnabled = false
    @AppStorage(DefaultsKey.windowMaximizeEnabled) private var windowMaximizeEnabled = false
    @AppStorage(DefaultsKey.panelControlMouseScroll) private var showScroll = true
    @AppStorage(DefaultsKey.panelControlSwitcher) private var showSwitcher = true
    @AppStorage(DefaultsKey.panelControlDockPreview) private var showDockPreview = true
    @AppStorage(DefaultsKey.panelControlCutPaste) private var showCutPaste = true
    @AppStorage(DefaultsKey.panelControlAutoQuit) private var showAutoQuit = true
    @AppStorage(DefaultsKey.panelControlShelf) private var showShelf = true
    @AppStorage(DefaultsKey.panelControlWindowMaximize) private var showWindowMaximize = true
    @AppStorage(DefaultsKey.panelControlOrder) private var controlOrderRaw = ""
    @State private var draggingItem: ControlPanelItem?
    var collapsible = true

    var body: some View {
        PanelSection(.controls, title: l10n.s.quickControlsSection, collapsible: collapsible,
                     supportsEditing: true,
                     resetAction: resetPanelDefaults) { editing in
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items(editing: editing).enumerated()), id: \.element) { index, item in
                    if item == .dockPreview, index > 0 {
                        PanelSubgroupDivider()
                    }
                    PanelReorderableItem(item: item,
                                         isEnabled: editing,
                                         order: itemOrderBinding,
                                         dragging: $draggingItem) {
                        itemView(item, editing: editing)
                    }
                }
            }
        }
    }

    private var switcherCaption: String {
        guard switcherEnabled else { return l10n.s.switcherEnableCaption }
        if !permissions.accessibility { return missingPermission(l10n.s.permissionAccessibility) }
        if !permissions.screenRecording { return missingPermission(l10n.s.permissionScreenRecording) }
        return l10n.s.switcherEnableCaption
    }

    private var dockPreviewCaption: String {
        guard dockPreviewEnabled else { return l10n.s.dockPreviewEnableCaption }
        if !permissions.accessibility { return missingPermission(l10n.s.permissionAccessibility) }
        if !permissions.screenRecording { return missingPermission(l10n.s.permissionScreenRecording) }
        switch dockPreview.blockedReason {
        case .magnification: return l10n.s.dockPreviewMagnificationBlocked
        case .dockUnavailable: return l10n.s.dockPreviewDockUnavailable
        default:
            return l10n.s.dockPreviewEnableCaption
        }
    }

    private var dockPreviewNeedsAttention: Bool {
        !permissions.accessibility
            || !permissions.screenRecording
            || dockPreview.blockedReason != nil
    }

    private var orderedItems: [ControlPanelItem] {
        _ = controlOrderRaw
        return PanelLayout.itemOrder(ControlPanelItem.self, key: DefaultsKey.panelControlOrder)
    }

    private var itemOrderBinding: Binding<[ControlPanelItem]> {
        Binding {
            orderedItems
        } set: { newValue in
            PanelLayout.setItemOrder(newValue, key: DefaultsKey.panelControlOrder)
        }
    }

    private func items(editing: Bool) -> [ControlPanelItem] {
        orderedItems.filter { editing || isVisible($0) }
    }

    private func isVisible(_ item: ControlPanelItem) -> Bool {
        switch item {
        case .mouseScroll: return showScroll
        case .switcher: return showSwitcher
        case .cutPaste: return showCutPaste
        case .autoQuit: return showAutoQuit
        case .shelf: return showShelf
        case .windowMaximize: return showWindowMaximize
        case .dockPreview: return showDockPreview
        }
    }

    @ViewBuilder
    private func itemView(_ item: ControlPanelItem, editing: Bool) -> some View {
        switch item {
        case .mouseScroll:
            PanelToggleRow(title: l10n.s.invertMouseScroll,
                           caption: caption(l10n.s.invertMouseScrollCaption, needsAccessibility: scrollEnabled),
                           systemImage: "computermouse",
                           isOn: $scrollEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showScroll,
                           isActive: scrollEnabled && inverter.isRunning,
                           activeText: l10n.s.scrollActiveNow,
                           needsAttention: scrollEnabled && !permissions.accessibility,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: accessibilityPermissionAction(scrollEnabled))
                .onChange(of: scrollEnabled) { _, enabled in
                    ScrollInverter.shared.syncWithPreferences()
                    requestAccessibilityIfNeeded(enabled)
                }
        case .switcher:
            VStack(alignment: .leading, spacing: 5) {
                PanelToggleRow(title: l10n.s.switcherSection,
                               caption: switcherCaption,
                               systemImage: "rectangle.on.rectangle",
                               isOn: $switcherEnabled,
                               isEditing: editing,
                               showsDragHandle: true,
                               visibility: $showSwitcher,
                               isActive: switcherEnabled && switcher.isRunning,
                               needsAttention: switcherEnabled && (!permissions.accessibility || !permissions.screenRecording),
                               permissionButtonTitle: l10n.s.permissionRequest,
                               permissionAction: switcherPermissionAction)
                    .onChange(of: switcherEnabled) { _, enabled in
                        AppSwitcher.shared.syncWithPreferences()
                        guard enabled else { return }
                        if !permissions.accessibility {
                            grantAccessibility()
                        } else if !permissions.screenRecording {
                            grantScreenRecording()
                        }
                    }
                if switcherEnabled && !editing {
                    switcherIconRowOption
                }
            }
        case .cutPaste:
            PanelToggleRow(title: l10n.s.cutPasteName,
                           caption: caption(l10n.s.cutPasteEnableCaption, needsAccessibility: cutPasteEnabled),
                           systemImage: "scissors",
                           isOn: $cutPasteEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showCutPaste,
                           isActive: cutPasteEnabled && cutPaste.isRunning,
                           activeText: l10n.s.cutPasteActiveNow,
                           needsAttention: cutPasteEnabled && !permissions.accessibility,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: accessibilityPermissionAction(cutPasteEnabled))
                .onChange(of: cutPasteEnabled) { _, enabled in
                    FinderCutPaste.shared.syncWithPreferences()
                    requestAccessibilityIfNeeded(enabled)
                }
        case .autoQuit:
            PanelToggleRow(title: l10n.s.autoQuitName,
                           caption: caption(l10n.s.autoQuitEnableCaption, needsAccessibility: autoQuitEnabled),
                           systemImage: "xmark.rectangle",
                           isOn: $autoQuitEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showAutoQuit,
                           isActive: autoQuitEnabled && autoQuit.isRunning,
                           activeText: l10n.s.autoQuitActiveNow,
                           needsAttention: autoQuitEnabled && !permissions.accessibility,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: accessibilityPermissionAction(autoQuitEnabled))
                .onChange(of: autoQuitEnabled) { _, enabled in
                    AutoQuitService.shared.syncWithPreferences()
                    requestAccessibilityIfNeeded(enabled)
                }
        case .shelf:
            PanelToggleRow(title: l10n.s.shelfName,
                           caption: l10n.s.shelfEnableCaption,
                           systemImage: "tray.full",
                           isOn: $shelfEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showShelf,
                           isActive: shelfEnabled)
                .onChange(of: shelfEnabled) { _, _ in
                    ShelfService.shared.syncWithPreferences()
                }
        case .windowMaximize:
            PanelToggleRow(title: l10n.s.windowMaximizeName,
                           caption: caption(l10n.s.windowMaximizeCaption, needsAccessibility: windowMaximizeEnabled),
                           systemImage: "arrow.up.left.and.arrow.down.right",
                           isOn: $windowMaximizeEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showWindowMaximize,
                           isActive: windowMaximizeEnabled && windowMaximizer.isRunning,
                           activeText: l10n.s.windowMaximizeActiveNow,
                           needsAttention: windowMaximizeEnabled && !permissions.accessibility,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: accessibilityPermissionAction(windowMaximizeEnabled))
                .onChange(of: windowMaximizeEnabled) { _, enabled in
                    WindowMaximizer.shared.syncWithPreferences()
                    requestAccessibilityIfNeeded(enabled)
                }
        case .dockPreview:
            PanelToggleRow(title: l10n.s.dockPreviewName,
                           caption: dockPreviewCaption,
                           systemImage: "dock.rectangle",
                           isOn: $dockPreviewEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showDockPreview,
                           isActive: dockPreviewEnabled && dockPreview.isRunning,
                           activeText: l10n.s.dockPreviewActiveNow,
                           needsAttention: dockPreviewEnabled && dockPreviewNeedsAttention,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: dockPreviewPermissionAction)
                .onChange(of: dockPreviewEnabled) { _, enabled in
                    DockPreviewService.shared.syncWithPreferences()
                    guard enabled else { return }
                    if !permissions.accessibility {
                        grantAccessibility()
                    } else if !permissions.screenRecording {
                        grantScreenRecording()
                    }
                }
        }
    }

    private func resetPanelDefaults() {
        PanelLayout.resetItemOrder(key: DefaultsKey.panelControlOrder)
        controlOrderRaw = ""
        showScroll = true
        showSwitcher = true
        showCutPaste = true
        showAutoQuit = true
        showShelf = true
        showWindowMaximize = true
        showDockPreview = true
    }

    private func caption(_ text: String, needsAccessibility: Bool) -> String {
        needsAccessibility && !permissions.accessibility
            ? missingPermission(l10n.s.permissionAccessibility)
            : text
    }

    private func missingPermission(_ name: String) -> String {
        "\(l10n.s.permissionRequired): \(name)"
    }

    private func requestAccessibilityIfNeeded(_ enabled: Bool) {
        guard enabled, !permissions.accessibility else { return }
        grantAccessibility()
    }

    private func accessibilityPermissionAction(_ enabled: Bool) -> (() -> Void)? {
        guard enabled, !permissions.accessibility else { return nil }
        return { grantAccessibility() }
    }

    private var switcherIconRowOption: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(l10n.s.switcherIconRowMode)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Toggle("", isOn: $switcherIconRowMode)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: switcherIconRowMode) { _, _ in
                        AppSwitcher.shared.syncWithPreferences()
                    }
            }
            Text(l10n.s.switcherIconRowModeCaption)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 31)
        .padding(.trailing, 4)
        .padding(.bottom, 2)
    }

    private var switcherPermissionAction: (() -> Void)? {
        guard switcherEnabled else { return nil }
        if !permissions.accessibility {
            return { grantAccessibility() }
        }
        if !permissions.screenRecording {
            return { grantScreenRecording() }
        }
        return nil
    }

    private var dockPreviewPermissionAction: (() -> Void)? {
        guard dockPreviewEnabled else { return nil }
        if !permissions.accessibility {
            return { grantAccessibility() }
        }
        if !permissions.screenRecording {
            return { grantScreenRecording() }
        }
        return nil
    }

    private func grantAccessibility() {
        Permissions.shared.requestAccessibility()
        Permissions.shared.openAccessibilitySettings()
    }

    private func grantScreenRecording() {
        Permissions.shared.requestScreenRecording()
        Permissions.shared.openScreenRecordingSettings()
    }
}

private struct UtilityActionButton: View {
    let title: String
    let caption: String
    let systemImage: String
    var badge: String? = nil
    var isEditing = false
    var showsDragHandle = false
    var visibility: Binding<Bool>? = nil
    var needsAttention = false
    var permissionButtonTitle: String? = nil
    var permissionAction: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Group {
            if isEditing {
                rowContent(showChevron: false)
                    .panelCard()
            } else if permissionAction != nil {
                VStack(alignment: .leading, spacing: 7) {
                    rowContent(showChevron: false)
                    permissionButton
                }
                .panelCard()
            } else {
                Button(action: action) {
                    rowContent(showChevron: true)
                        .panelCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rowContent(showChevron: Bool) -> some View {
        HStack(spacing: 9) {
            if isEditing && showsDragHandle {
                PanelDragHandle()
            }
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isHiddenInEditor ? Color.secondary : Color.primary)
                        .lineLimit(1)
                    if let badge {
                        PanelBetaBadge(text: badge)
                    }
                }
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(captionColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if isEditing, let visibility {
                if !visibility.wrappedValue {
                    PanelHiddenBadge()
                }
                PanelInlineHideButton(isVisible: visibility)
            } else if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var permissionButton: some View {
        Button {
            permissionAction?()
        } label: {
            Label(permissionButtonTitle ?? "", systemImage: "hand.raised.fill")
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
    }

    private var iconColor: Color {
        if isHiddenInEditor { return .secondary }
        return needsAttention ? .orange : .accentColor
    }

    private var captionColor: Color {
        if isHiddenInEditor { return Color.secondary.opacity(0.55) }
        return needsAttention ? .orange : .secondary
    }

    private var isHiddenInEditor: Bool {
        isEditing && visibility?.wrappedValue == false
    }
}

private struct PanelToggleRow: View {
    let title: String
    let caption: String
    let systemImage: String
    @Binding var isOn: Bool
    var badge: String? = nil
    var isEditing = false
    var showsDragHandle = false
    var visibility: Binding<Bool>? = nil
    var isActive = false
    var activeText: String? = nil
    var needsAttention = false
    var permissionButtonTitle: String? = nil
    var permissionAction: (() -> Void)? = nil

    var body: some View {
        rowContent
            .panelCard()
    }

    private var rowContent: some View {
        HStack(spacing: 9) {
            if isEditing && showsDragHandle {
                PanelDragHandle()
            }
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isHiddenInEditor ? Color.secondary : Color.primary)
                        .lineLimit(1)
                    if let badge {
                        PanelBetaBadge(text: badge)
                    }
                }
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(captionColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if isActive, let activeText {
                    Label(activeText, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
                if needsAttention, let permissionAction {
                    Button {
                        permissionAction()
                    } label: {
                        Label(permissionButtonTitle ?? "", systemImage: "hand.raised.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            Spacer(minLength: 0)
            trailingControl
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isEditing, let visibility {
            if !visibility.wrappedValue {
                PanelHiddenBadge()
            }
            PanelInlineHideButton(isVisible: visibility)
        } else {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .controlSize(.small)
                .toggleStyle(.switch)
        }
    }

    private var iconColor: Color {
        if isHiddenInEditor { return .secondary }
        if needsAttention { return .orange }
        return isOn ? .accentColor : .secondary
    }

    private var captionColor: Color {
        if isHiddenInEditor { return Color.secondary.opacity(0.55) }
        return needsAttention ? .orange : .secondary
    }

    private var isHiddenInEditor: Bool {
        isEditing && visibility?.wrappedValue == false
    }
}

/// A small "Beta" pill, used to flag a control as still experimental.
struct PanelBetaBadge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                Capsule(style: .continuous).fill(Color.orange.opacity(0.16))
            )
            .overlay(
                Capsule(style: .continuous).strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.5)
            )
            .accessibilityLabel(text)
    }
}

/// A thin separator that sets the experimental group apart from the stable
/// quick controls. The row's own "Beta" badge does the labelling, so this just
/// provides the visual break.
private struct PanelSubgroupDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.16))
            .frame(height: 1)
            .padding(.vertical, 3)
    }
}

// MARK: - Overlay scroll container

/// A vertical scroll container that always uses an overlay scroller, so it never
/// reserves a legacy gutter on the right (which, when the system is set to always
/// show scroll bars, would push the fixed-width panel content off-center). The
/// content is pinned to the full width and reports its natural height back after
/// every layout pass, so the popover sizes itself to fit and only scrolls once the
/// content is taller than the screen.
private struct OverlayScrollView<Content: View>: NSViewRepresentable {
    @Binding var measuredHeight: CGFloat
    let content: Content

    init(measuredHeight: Binding<CGFloat>, @ViewBuilder content: () -> Content) {
        _measuredHeight = measuredHeight
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let host = HeightReportingHostingView(rootView: content)
        host.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = host
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: clip.topAnchor),
            host.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            host.widthAnchor.constraint(equalTo: clip.widthAnchor),
        ])
        context.coordinator.host = host
        installReporter(on: host)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        scroll.scrollerStyle = .overlay
        guard let host = context.coordinator.host else { return }
        host.rootView = content
        installReporter(on: host)               // re-bind to the latest measuredHeight
        let h = host.fittingSize.height          // catch content changes with no new layout pass
        if h > 1, abs(h - measuredHeight) > 0.5 {
            DispatchQueue.main.async { measuredHeight = h }
        }
    }

    /// Wire the hosting view to report its natural height into `measuredHeight`
    /// after every AppKit layout pass — including the frames of a collapse/expand
    /// animation — so the popover tracks the real content height instead of a
    /// single stale reading taken when SwiftUI happened to re-run updateNSView.
    /// The 0.5pt guard also breaks the measure → resize → measure feedback loop.
    private func installReporter(on host: HeightReportingHostingView<Content>) {
        let binding = $measuredHeight
        host.onLayout = { [weak host] in
            guard let host else { return }
            let h = host.fittingSize.height
            guard h > 1, abs(h - binding.wrappedValue) > 0.5 else { return }
            DispatchQueue.main.async { binding.wrappedValue = h }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var host: HeightReportingHostingView<Content>? }
}

/// An `NSHostingView` that fires `onLayout` after each AppKit layout pass. The
/// menu panel uses it because collapsing or expanding a section flips state inside
/// this view's own SwiftUI graph and never re-runs the surrounding `updateNSView`
/// — so the height has to be read from here, where the change actually lands.
private final class HeightReportingHostingView<Content: View>: NSHostingView<Content> {
    var onLayout: (() -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        onLayout?()
    }
}

private struct MenuPanelHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension View {
    func reportHeight(_ height: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: MenuPanelHeightPreferenceKey.self,
                                       value: proxy.size.height)
            }
        )
        .onPreferenceChange(MenuPanelHeightPreferenceKey.self) { value in
            guard abs(value - height.wrappedValue) > 0.5 else { return }
            DispatchQueue.main.async {
                height.wrappedValue = value
            }
        }
    }
}

private extension UpdateService.State {
    var showsMenuPanelBanner: Bool {
        switch self {
        case .available, .downloading, .installing:
            return true
        default:
            return false
        }
    }
}

// MARK: - Update banner

/// Discreet "update available" row shown above everything when a newer release
/// is found. Tapping it installs the update (which quits and relaunches).
struct UpdateBanner: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var updates = UpdateService.shared

    var body: some View {
        switch updates.state {
        case let .available(version):
            Button {
                appDelegate()?.showUpdatePreview()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l10n.s.updateBannerTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("\(l10n.s.updateAvailablePrefix) \(version)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    Text(l10n.s.updateBannerAction)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor)
                )
            }
            .buttonStyle(.plain)
        case .downloading:
            progressRow(l10n.s.updateDownloading)
        case .installing:
            progressRow(l10n.s.updateInstalling)
        default:
            EmptyView()
        }
    }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 11.5, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

// MARK: - Keep awake

struct KeepAwakeCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.defaultDuration) private var defaultDuration: Int = 0
    @AppStorage(DefaultsKey.keepAwakeAutoStart) private var keepAwakeAutoStart = false
    @AppStorage(DefaultsKey.keepAwakeIconTint) private var keepAwakeIconTint = KeepAwakeIconTint.orange.rawValue
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleEnabled) private var keepAwakeMouseJiggle = false
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleInterval) private var keepAwakeMouseJiggleInterval = 5
    @State private var optionsExpanded = false
    var collapsible = true

    var body: some View {
        // The collapsible header supplies the "Keep awake" title, so the card's
        // first row is just the live status and the on/off switch.
        PanelSection(.keepAwake, title: l10n.s.keepAwakeTitle, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    statusLine
                    Spacer()
                    Toggle("", isOn: activeBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                if awake.isActive, awake.endDate != nil {
                    HStack(spacing: 6) {
                        extendButton(15)
                        extendButton(30)
                        extendButton(60)
                        Spacer()
                    }
                }

                if !awake.isActive {
                    HStack {
                        Text(l10n.s.durationLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        DurationPicker(selection: $defaultDuration)
                    }
                }

                optionsDisclosure

                Divider()

                optionRow(title: l10n.s.clamshellTitle,
                          caption: clamshellCaption,
                          isOn: $awake.clamshellPreferred,
                          disabled: awake.clamshellSetupInProgress,
                          captionIsError: awake.clamshellSetupFailed)
            }
            .panelCard()
        }
        .onAppear {
            defaultDuration = Defaults.sanitizedDefaultDuration(defaultDuration)
            keepAwakeIconTint = Defaults.sanitizedKeepAwakeIconTint(keepAwakeIconTint).rawValue
            keepAwakeMouseJiggleInterval = Defaults.sanitizedKeepAwakeMouseJiggleInterval(keepAwakeMouseJiggleInterval)
        }
    }

    private var optionsDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                optionsExpanded.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: optionsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(l10n.s.keepAwakeOptions)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if optionsExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    iconTintRow
                    optionRow(title: l10n.s.keepAwakeAutoStart,
                              caption: l10n.s.keepAwakeAutoStartCaption,
                              isOn: $keepAwakeAutoStart,
                              disabled: false)
                    optionRow(title: l10n.s.keepAwakeMouseJiggle,
                              caption: mouseJiggleCaption,
                              isOn: $keepAwakeMouseJiggle,
                              disabled: false,
                              captionIsError: mouseJiggleNeedsAccessibility)
                    if keepAwakeMouseJiggle {
                        mouseJiggleIntervalRow
                        if mouseJiggleNeedsAccessibility {
                            Button(l10n.s.permissionRequest) {
                                grantAccessibility()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.leading, 19)
            }
        }
    }

    private var mouseJiggleIntervalRow: some View {
        HStack(spacing: 8) {
            Text(l10n.s.keepAwakeMouseJiggleInterval)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            KeepAwakeMouseJiggleIntervalPicker(selection: $keepAwakeMouseJiggleInterval)
        }
    }

    private var mouseJiggleNeedsAccessibility: Bool {
        keepAwakeMouseJiggle && !permissions.accessibility
    }

    private var mouseJiggleCaption: String {
        mouseJiggleNeedsAccessibility
            ? "\(l10n.s.permissionRequired): \(l10n.s.permissionAccessibility)"
            : l10n.s.keepAwakeMouseJiggleCaption
    }

    private var iconTintRow: some View {
        let tint = Defaults.sanitizedKeepAwakeIconTint(keepAwakeIconTint)
        return HStack(spacing: 8) {
            if let color = iconTintColor(tint) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
            } else {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.8), lineWidth: 1.2)
                    .frame(width: 10, height: 10)
            }
            Text(l10n.s.keepAwakeIconTintLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Picker("", selection: $keepAwakeIconTint) {
                ForEach(KeepAwakeIconTint.allCases) { option in
                    Text(option.title(l10n.s)).tag(option.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: 138)
        }
    }

    private func iconTintColor(_ tint: KeepAwakeIconTint) -> Color? {
        switch tint {
        case .orange: return .orange
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .none: return nil
        }
    }

    private var statusLine: some View {
        Group {
            if awake.isActive {
                if let end = awake.endDate {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("\(l10n.s.keepAwakeEndsIn) \(Self.remainingText(until: end))")
                    }
                } else {
                    Text(l10n.s.keepAwakeUntilDisabled)
                }
            } else {
                Text(l10n.s.keepAwakeNormalRules)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private var clamshellCaption: String {
        if awake.clamshellSetupInProgress {
            return l10n.s.configuring
        }
        if awake.clamshellSetupFailed {
            return l10n.s.sudoersFailed
        }
        if awake.clamshellActive {
            return l10n.s.clamshellOnCaption
        }
        if awake.clamshellPreferred {
            return l10n.s.clamshellNeedsSession
        }
        return awake.passwordlessClamshell ? l10n.s.clamshellReady : l10n.s.clamshellNeedsPassword
    }

    private var activeBinding: Binding<Bool> {
        Binding(
            get: { awake.isActive },
            set: { on in
                if on {
                    awake.activate(minutes: defaultDuration)
                } else {
                    awake.deactivate(reason: .manual)
                }
            }
        )
    }

    private func grantAccessibility() {
        Permissions.shared.requestAccessibility()
        Permissions.shared.openAccessibilitySettings()
    }

    private func optionRow(title: String,
                           caption: String?,
                           isOn: Binding<Bool>,
                           disabled: Bool,
                           captionIsError: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12))
                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(captionIsError ? Color.red : Color.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(disabled)
        }
    }

    private func extendButton(_ minutes: Int) -> some View {
        Button("+\(minutes) min") {
            awake.extend(minutes: minutes)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.system(size: 10))
    }

    private static func remainingText(until end: Date) -> String {
        let total = max(0, Int(end.timeIntervalSinceNow))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d h %02d min", hours, minutes) }
        if minutes > 0 { return String(format: "%d min %02d s", minutes, seconds) }
        return "\(seconds) s"
    }
}

/// Session duration picker shared by the panel and Settings.
struct DurationPicker: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var selection: Int

    var body: some View {
        Picker("", selection: $selection) {
            Text(l10n.s.minutes15).tag(15)
            Text(l10n.s.minutes30).tag(30)
            Text(l10n.s.hour1).tag(60)
            Text(l10n.s.hours2).tag(120)
            Text(l10n.s.hours4).tag(240)
            Text(l10n.s.hours8).tag(480)
            Text(l10n.s.indefinite).tag(0)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
    }
}

struct KeepAwakeMouseJiggleIntervalPicker: View {
    @Binding var selection: Int

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(Defaults.allowedKeepAwakeMouseJiggleIntervals, id: \.self) { minutes in
                Text(Self.label(for: minutes)).tag(minutes)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
    }

    static func label(for minutes: Int) -> String {
        "\(minutes) min"
    }
}
