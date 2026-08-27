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
    @ObservedObject private var updates = UpdateService.shared
    @ObservedObject private var panelFocus = MenuPanelFocus.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DefaultsKey.monitorShowMixer) private var showMixer = true
    @AppStorage(DefaultsKey.monitorShowSystem) private var showSystem = true
    @AppStorage(DefaultsKey.monitorShowNetwork) private var showNetwork = true
    @AppStorage(DefaultsKey.monitorShowDisk) private var showDisk = true
    @AppStorage(DefaultsKey.monitorShowPower) private var showPower = true
    @AppStorage(DefaultsKey.panelShowFanControl) private var showFanControl = true
    @AppStorage(DefaultsKey.panelShowKeepAwake) private var showKeepAwake = true
    @AppStorage(DefaultsKey.panelShowBrightness) private var showBrightness = true
    @AppStorage(DefaultsKey.brightnessControlEnabled) private var brightnessEnabled = false
    @AppStorage(DefaultsKey.panelShowUtilities) private var showUtilities = true
    @AppStorage(DefaultsKey.panelShowControls) private var showControls = true
    @AppStorage(DefaultsKey.panelShowToggles) private var showToggles = true
    @AppStorage(DefaultsKey.panelSectionOrder) private var sectionOrderRaw = ""
    @State private var navigableContentHeight: CGFloat = 0
    @State private var metricContentHeight: CGFloat = 0
    @State private var updateBannerHeight: CGFloat = 0
    @State private var selectedSection: PanelSectionID = PanelLayout.order.first ?? .keepAwake
    @State private var selectedMetric: MetricDetailKind?
    @FocusState private var focusedSection: PanelSectionID?

    /// Cap the panel to the usable screen height so it never overflows the menu
    /// bar; taller content scrolls inside. Measured against the display the
    /// menu bar icon is on, which is not always the one holding the key window.
    private var maxHeight: CGFloat {
        let anchored = PanelInteractionState.shared.anchorScreen
            .flatMap { anchor in anchor.isStillAttached ? anchor : nil }
        return max(360, ((anchored ?? NSScreen.withMenuBar)?.visibleFrame.height ?? 760) - 24)
    }

    var body: some View {
        Group {
            if selectedMetric != nil {
                metricPanel
            } else {
                navigablePanel
            }
        }
        .onAppear {
            applyFocus(panelFocus.request)
            KeepAwakeManager.shared.refreshPasswordlessStatus()
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
        .onChange(of: focusedSection) { _, section in
            if let section { selectedSection = section }
        }
    }

    private var monitorNeeds: SystemMonitorPanelNeeds {
        if let selectedMetric {
            return selectedMetric.monitorNeeds
        }
        switch activeSection {
        case .system: return SystemMonitorPanelNeeds(system: true)
        case .network: return SystemMonitorPanelNeeds(network: true)
        case .disk: return SystemMonitorPanelNeeds(disk: true)
        case .power: return SystemMonitorPanelNeeds(power: true)
        default: return .none
        }
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
            focusedSection = section
        case .metric(let metric):
            focusedSection = nil
            selectedMetric = metric
            selectedSection = metric.panelSection
        }
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
        return 180 + bannerHeight
    }

    private var estimatedNavigableContentHeight: CGFloat {
        switch activeSection {
        case .keepAwake: return 250
        case .brightness: return 140
        case .mixer: return 250
        case .system: return 460
        case .network: return 190
        case .disk: return 360
        case .power: return 170
        case .fanControl: return 220
        case .utilities: return 500
        case .controls: return 360
        case .toggles: return 420
        }
    }

    private var estimatedMetricContentHeight: CGFloat {
        guard let selectedMetric else { return 320 }
        switch selectedMetric {
        case .cpu, .gpu, .memory: return 430
        case .network: return 330
        case .disk: return 360
        case .battery, .power: return 360
        case .fan: return 240
        }
    }

    /// Renders the section for an id, honoring its "show in panel" toggle. Each
    /// section self-hides when it has nothing to show, so the order is stable
    /// whether or not a section is currently populated.
    @ViewBuilder
    private func section(for id: PanelSectionID, collapsible: Bool = true) -> some View {
        switch id {
        case .keepAwake: KeepAwakeCard(collapsible: collapsible)
        case .brightness: if showBrightness { BrightnessSection(collapsible: collapsible) }
        case .mixer: if showMixer { MixerSection(collapsible: collapsible) }
        case .system: if showSystem { SystemSection(collapsible: collapsible) }
        case .network: if showNetwork { NetworkSection(collapsible: collapsible) }
        case .disk: if showDisk { DiskSection(collapsible: collapsible) }
        case .power: if showPower { PowerSection(collapsible: collapsible) }
        case .fanControl: if showFanControl { FanControlSection(collapsible: collapsible) }
        case .utilities: UtilitiesSection(collapsible: collapsible, startCleaning: startCleaning)
        case .controls: QuickControlsSection(collapsible: collapsible)
        case .toggles: QuickTogglesSection(collapsible: collapsible)
        }
    }

    private func isSectionVisible(_ id: PanelSectionID) -> Bool {
        guard id.isAvailable else { return false }
        switch id {
        case .keepAwake: return showKeepAwake
        // The section only earns its navigation tab while the feature is on;
        // it is switched on in Settings, not from an empty panel screen.
        case .brightness: return showBrightness && brightnessEnabled
        case .mixer: return showMixer
        case .system: return showSystem
        case .network: return showNetwork
        case .disk: return showDisk
        case .power: return showPower
        case .fanControl: return showFanControl
        case .utilities: return showUtilities
        case .controls: return showControls
        case .toggles: return showToggles
        }
    }

    private var sectionNavigation: some View {
        HStack(spacing: 2) {
            ForEach(visibleSections) { id in
                let isActive = activeSection == id
                Button {
                    selectedSection = id
                    focusedSection = id
                } label: {
                    Image(systemName: id.symbolName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .focused($focusedSection, equals: id)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.86))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? navigationActiveFill : Color.clear)
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

    private var navigationActiveFill: Color {
        colorScheme == .light ? Color.accentColor.opacity(0.13) : Color.accentColor.opacity(0.20)
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
        MenuPanelHeader()
    }

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton(l10n.s.panelSettings,
                         systemImage: "gearshape",
                         horizontalPadding: 7) {
                appDelegate()?.openSettingsWindow()
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

private struct MenuPanelHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ZStack {
            BrandMark(width: 48, tint: markTint)
                .frame(height: 28)
                .accessibilityHidden(true)

            if AppInfo.isBeta {
                HStack {
                    Text(l10n.s.betaBadgeLabel.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.18))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())

                    Spacer()

                    Button {
                        appDelegate()?.openFeedbackWindow()
                    } label: {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(FeatureStrings.feedback(l10n.language).openButton)
                }
            }
        }
        .frame(height: 28)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }

    private var markTint: Color {
        colorScheme == .light ? Color(white: 0.03) : .white
    }
}

private enum UtilityPanelItem: String, PanelOrderItem, Identifiable {
    // Case order IS the default panel order (PanelLayout.itemOrder falls back
    // to allCases). Screenshot leads in 3.1.13; existing orders that predate it
    // are migrated once without disturbing the rest of the user's layout.
    case screenshot, quickLauncher, appUpdates, cleaner, homebrew, media, clipboard, windowLayout,
         uninstaller, cleanURL, cleaning, screenOCR, colorPicker, cameraPreview, scratchpad,
         commandBar, screenRecorder

    var id: String { rawValue }

    /// The hub feature behind the tile; off in the hub removes it everywhere,
    /// including the edit and hidden lists.
    var feature: AppFeature {
        switch self {
        case .quickLauncher: return .quickLauncher
        case .cleaner: return .cleaner
        case .homebrew: return .homebrew
        case .appUpdates: return .appUpdates
        case .media: return .mediaTools
        case .clipboard: return .clipboardHistory
        case .windowLayout: return .windowLayout
        case .uninstaller: return .uninstaller
        case .cleanURL: return .urlCleaner
        case .cleaning: return .cleaningMode
        case .screenOCR: return .screenOCR
        case .colorPicker: return .colorPicker
        case .screenshot: return .screenshot
        case .screenRecorder: return .screenRecorder
        case .cameraPreview: return .cameraPreview
        case .scratchpad: return .scratchpad
        case .commandBar: return .commandBar
        }
    }
}

struct UtilitiesSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @State private var showUninstaller = false
    @State private var showCleanerPanel = false
    @State private var showURLCleaner = false
    @State private var showHomebrewPanel = false
    @State private var showAppUpdatesPanel = false
    @State private var showMediaPanel = false
    @State private var showClipboardPanel = false
    @State private var showRecentCapturesPanel = false
    @State private var showWindowLayoutPanel = false
    @AppStorage(DefaultsKey.panelUtilityCleaning) private var showCleaning = true
    @AppStorage(DefaultsKey.panelUtilityURLCleaner) private var showCleanURL = true
    @AppStorage(DefaultsKey.panelUtilityUninstaller) private var showUninstallerAction = true
    @AppStorage(DefaultsKey.panelUtilityCleaner) private var showCleanerAction = true
    @AppStorage(DefaultsKey.panelUtilityHomebrew) private var showHomebrew = true
    @AppStorage(DefaultsKey.panelUtilityAppUpdates) private var showAppUpdates = true
    @AppStorage(DefaultsKey.panelUtilityMedia) private var showMedia = true
    @AppStorage(DefaultsKey.panelUtilityClipboard) private var showClipboard = true
    @AppStorage(DefaultsKey.panelUtilityWindowLayout) private var showWindowLayout = true
    @AppStorage(DefaultsKey.panelUtilityScreenOCR) private var showScreenOCR = true
    @AppStorage(DefaultsKey.panelUtilityScreenshot) private var showScreenshot = true
    @AppStorage(DefaultsKey.panelUtilityQuickLauncher) private var showQuickLauncher = true
    @AppStorage(DefaultsKey.panelUtilityColorPicker) private var showColorPicker = true
    @AppStorage(DefaultsKey.panelUtilityCameraPreview) private var showCameraPreview = true
    @AppStorage(DefaultsKey.panelUtilityScratchpad) private var showScratchpad = true
    @AppStorage(DefaultsKey.panelUtilityCommandBar) private var showCommandBar = true
    @AppStorage(DefaultsKey.panelUtilityScreenRecorder) private var showScreenRecorder = true
    @ObservedObject private var recorder = ScreenRecorderService.shared
    @AppStorage(DefaultsKey.clipboardHistoryEnabled) private var clipboardEnabled = false
    @AppStorage(DefaultsKey.panelUtilityOrder) private var utilityOrderRaw = ""
    @State private var draggingItem: UtilityPanelItem?
    var collapsible = true
    var startCleaning: () -> Void

    var body: some View {
        PanelSection(.utilities, title: l10n.s.utilitiesSection, collapsible: collapsible,
                     supportsEditing: true,
                     editButtonVisible: !isHostingUtility,
                     resetAction: resetPanelDefaults) { editing in
            if showUninstaller {
                PanelUninstallerView {
                    showUninstaller = false
                }
            } else if showCleanerPanel {
                PanelCleanerView {
                    showCleanerPanel = false
                }
            } else if showURLCleaner {
                PanelURLCleanerView {
                    showURLCleaner = false
                }
            } else if showHomebrewPanel {
                PanelHomebrewView {
                    showHomebrewPanel = false
                }
            } else if showMediaPanel {
                PanelMediaView {
                    PanelInteractionState.shared.viewKeepsPopoverOpen = false
                    showMediaPanel = false
                }
            } else if showClipboardPanel {
                PanelClipboardView {
                    PanelInteractionState.shared.viewKeepsPopoverOpen = false
                    showClipboardPanel = false
                }
            } else if showRecentCapturesPanel {
                PanelRecentCapturesView {
                    PanelInteractionState.shared.viewKeepsPopoverOpen = false
                    showRecentCapturesPanel = false
                }
            } else if showWindowLayoutPanel {
                PanelWindowLayoutView {
                    PanelInteractionState.shared.viewKeepsPopoverOpen = false
                    showWindowLayoutPanel = false
                }
            } else if showAppUpdatesPanel {
                PanelAppUpdatesView {
                    PanelInteractionState.shared.viewKeepsPopoverOpen = false
                    showAppUpdatesPanel = false
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
        .onChange(of: hostedUtilityKeepsPopoverOpen) { _, keepsOpen in
            PanelInteractionState.shared.viewKeepsPopoverOpen = keepsOpen
        }
        .onDisappear {
            PanelInteractionState.shared.viewKeepsPopoverOpen = false
        }
    }

    /// True while the section is showing one of the tools instead of its own
    /// list. A hosted tool turns the panel into a work surface, so clicks
    /// elsewhere in the app must not dismiss it.
    private var isHostingUtility: Bool {
        showUninstaller || showCleanerPanel || showURLCleaner || showHomebrewPanel
            || showMediaPanel || showClipboardPanel || showRecentCapturesPanel
            || showWindowLayoutPanel || showAppUpdatesPanel
    }

    /// Homebrew browsing behaves like an ordinary popover. Other hosted tools
    /// intentionally span interaction with apps and windows outside the panel.
    private var hostedUtilityKeepsPopoverOpen: Bool {
        isHostingUtility && !showHomebrewPanel
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
        orderedItems.filter { $0.feature.isAvailable && (editing || isVisible($0)) }
    }

    private func isVisible(_ item: UtilityPanelItem) -> Bool {
        switch item {
        case .homebrew: return showHomebrew
        case .appUpdates: return showAppUpdates
        case .media: return showMedia
        case .clipboard: return showClipboard
        case .windowLayout: return showWindowLayout
        case .uninstaller: return showUninstallerAction
        case .cleaner: return showCleanerAction
        case .cleanURL: return showCleanURL
        case .cleaning: return showCleaning
        case .screenOCR: return showScreenOCR
        case .colorPicker: return showColorPicker
        case .cameraPreview: return showCameraPreview
        case .scratchpad: return showScratchpad
        case .commandBar: return showCommandBar
        case .quickLauncher: return showQuickLauncher
        case .screenshot: return showScreenshot
        case .screenRecorder: return showScreenRecorder
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
                                    showHomebrewPanel = true
                                })
        case .appUpdates:
            UtilityActionButton(title: FeatureStrings.appUpdates(l10n.language).pageTitle,
                                caption: FeatureStrings.appUpdates(l10n.language).panelCaption,
                                systemImage: "arrow.down.app",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showAppUpdates,
                                action: {
                                    showAppUpdatesPanel = true
                                })
        case .media:
            UtilityActionButton(title: l10n.s.mediaName,
                                caption: l10n.s.mediaEnableCaption,
                                systemImage: "photo.on.rectangle.angled",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showMedia,
                                action: {
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
                                shortcutHint: shortcutHint(.clipboard),
                                action: {
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
                                    showUninstaller = true
                                })
        case .cleaner:
            UtilityActionButton(title: l10n.s.cleanerName,
                                caption: l10n.s.cleanerPanelCaption,
                                systemImage: "sparkle",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showCleanerAction,
                                action: {
                                    showCleanerPanel = true
                                })
        case .cleanURL:
            UtilityActionButton(title: l10n.s.urlCleanerName,
                                caption: l10n.s.urlCleanerEnableCaption,
                                systemImage: "link",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showCleanURL,
                                action: {
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
        case .screenOCR:
            UtilityActionButton(title: l10n.s.ocrName,
                                caption: ocrCaption,
                                systemImage: "text.viewfinder",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showScreenOCR,
                                needsAttention: !permissions.screenRecording,
                                permissionButtonTitle: l10n.s.permissionRequest,
                                permissionAction: permissions.screenRecording ? nil : grantScreenRecordingPermission,
                                shortcutHint: shortcutHint(.screenOCR),
                                action: {
                                    appDelegate()?.closePopover()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        ScreenTextService.shared.capture()
                                    }
                                })
        case .screenshot:
            UtilityActionButton(title: FeatureStrings.screenshot(l10n.language).pageTitle,
                                caption: screenshotCaption,
                                systemImage: "camera.viewfinder",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showScreenshot,
                                needsAttention: !permissions.screenRecording,
                                permissionButtonTitle: l10n.s.permissionRequest,
                                permissionAction: permissions.screenRecording ? nil : grantScreenRecordingPermission,
                                shortcutHint: shortcutHint(.screenshot),
                                accessoryTitle: FeatureStrings.recentCaptures(l10n.language).title,
                                accessorySystemImage: "clock.arrow.circlepath",
                                accessoryAction: showRecentCaptures,
                                action: {
                                    appDelegate()?.closePopover()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        ScreenshotService.shared.capture()
                                    }
                                })
        case .screenRecorder:
            UtilityActionButton(title: screenRecorderTitle,
                                caption: screenRecorderCaption,
                                systemImage: recorder.isRecording ? "stop.circle" : "record.circle",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showScreenRecorder,
                                needsAttention: !permissions.screenRecording,
                                permissionButtonTitle: l10n.s.permissionRequest,
                                permissionAction: permissions.screenRecording ? nil : grantScreenRecordingPermission,
                                shortcutHint: shortcutHint(.screenRecorder),
                                accessoryTitle: recorder.isRecording
                                    ? nil
                                    : FeatureStrings.recentCaptures(l10n.language).title,
                                accessorySystemImage: "clock.arrow.circlepath",
                                accessoryAction: recorder.isRecording ? nil : showRecentCaptures,
                                action: {
                                    appDelegate()?.closePopover()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        ScreenRecorderService.shared.toggle()
                                    }
                                })
        case .colorPicker:
            UtilityActionButton(title: l10n.s.colorPickerName,
                                caption: l10n.s.colorPickerCaption,
                                systemImage: "eyedropper",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showColorPicker,
                                shortcutHint: shortcutHint(.colorPicker),
                                action: {
                                    appDelegate()?.closePopover()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        ColorSamplerService.shared.pick()
                                    }
                                })
        case .cameraPreview:
            UtilityActionButton(title: FeatureStrings.cameraPreview(l10n.language).pageTitle,
                                caption: cameraPreviewCaption,
                                systemImage: "web.camera",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showCameraPreview,
                                needsAttention: permissions.camera == .denied,
                                permissionButtonTitle: l10n.s.permissionOpenSettings,
                                permissionAction: permissions.camera == .denied
                                    ? { Permissions.shared.openCameraSettings() }
                                    : nil,
                                shortcutHint: shortcutHint(.cameraPreview),
                                action: {
                                    appDelegate()?.closePopover()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        CameraPreviewService.shared.show()
                                    }
                                })
        case .scratchpad:
            UtilityActionButton(title: FeatureStrings.scratchpad(l10n.language).pageTitle,
                                caption: FeatureStrings.scratchpad(l10n.language).panelCaption,
                                systemImage: "note.text",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showScratchpad,
                                shortcutHint: shortcutHint(.scratchpad),
                                action: {
                                    appDelegate()?.closePopover()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        ScratchpadService.shared.show()
                                    }
                                })
        case .quickLauncher:
            UtilityActionButton(title: l10n.s.launcherName,
                                caption: l10n.s.launcherCaption,
                                systemImage: "square.grid.2x2",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showQuickLauncher,
                                shortcutHint: shortcutHint(.quickLauncher),
                                action: {
                                    appDelegate()?.closePopover()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        QuickLauncherService.shared.show()
                                    }
                                })
        case .commandBar:
            UtilityActionButton(title: FeatureStrings.commandBar(l10n.language).pageTitle,
                                caption: FeatureStrings.commandBar(l10n.language).panelCaption,
                                systemImage: "command",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showCommandBar,
                                shortcutHint: shortcutHint(.commandBar),
                                action: {
                                    appDelegate()?.closePopover()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        CommandBarService.shared.show()
                                    }
                                })
        }
    }

    /// The row's key hint: only when the shortcut is actually REGISTERED,
    /// using the same gates the services use (the clipboard needs both the
    /// feature and its shortcut toggle), so the badge never advertises a
    /// combo that does nothing.
    private func shortcutHint(_ role: GlobalShortcutRole) -> String? {
        guard role.isAvailable(using: { $0.isAvailable }),
              role.requiredEnableKeys.allSatisfy({ UserDefaults.standard.bool(forKey: $0) })
        else { return nil }
        return role.savedShortcut.displayString
    }

    private var ocrCaption: String {
        permissions.screenRecording
            ? l10n.s.ocrCaption
            : "\(l10n.s.permissionRequired): \(l10n.s.permissionScreenRecording)"
    }

    /// While a recording runs the tile becomes the way to end it, so the
    /// panel never shows an action the person cannot take.
    private var screenRecorderTitle: String {
        let strings = FeatureStrings.recorder(l10n.language)
        return recorder.isRecording ? strings.stopButton : strings.pageTitle
    }

    private var screenRecorderCaption: String {
        guard permissions.screenRecording else {
            return "\(l10n.s.permissionRequired): \(l10n.s.permissionScreenRecording)"
        }
        let strings = FeatureStrings.recorder(l10n.language)
        return recorder.isRecording
            ? RecorderSupport.elapsedLabel(seconds: recorder.elapsedSeconds)
            : strings.panelCaption
    }

    private var screenshotCaption: String {
        permissions.screenRecording
            ? FeatureStrings.screenshot(l10n.language).panelCaption
            : "\(l10n.s.permissionRequired): \(l10n.s.permissionScreenRecording)"
    }

    private var cameraPreviewCaption: String {
        permissions.camera == .denied
            ? "\(l10n.s.permissionRequired): \(FeatureStrings.cameraPreview(l10n.language).permName)"
            : FeatureStrings.cameraPreview(l10n.language).panelCaption
    }

    private func grantScreenRecordingPermission() {
        Permissions.shared.requestScreenRecording()
    }

    private func showRecentCaptures() {
        showRecentCapturesPanel = true
    }

    private func resetPanelDefaults() {
        PanelLayout.resetItemOrder(key: DefaultsKey.panelUtilityOrder)
        utilityOrderRaw = ""
        showHomebrew = true
        showAppUpdates = true
        showMedia = true
        showClipboard = true
        showWindowLayout = true
        showUninstallerAction = true
        showCleanerAction = true
        showCleanURL = true
        showCleaning = true
        showScreenOCR = true
        showScreenshot = true
        showColorPicker = true
        showCameraPreview = true
        showScratchpad = true
        showQuickLauncher = true
        showCommandBar = true
    }

    private func grantAccessibility() {
        Permissions.shared.requestAccessibility()
        Permissions.shared.openAccessibilitySettings()
    }
}

private enum ControlPanelItem: String, PanelOrderItem, Identifiable {
    case mouseScroll, focusFollowsMouse, mouseNavigation, switcher, cutPaste, autoQuit, shelf, windowMaximize, dockPreview, keyDebounce,
         dockClick, dockClickHide, dockClickCycle, middleClick, textSnippets, radialMenu, mouseButtonShortcuts, superKey

    var id: String { rawValue }

    /// The hub feature behind the toggle; off in the hub removes the row
    /// everywhere, including the edit and hidden lists.
    var feature: AppFeature {
        switch self {
        case .mouseScroll: return .scrollInverter
        case .focusFollowsMouse: return .focusFollowsMouse
        case .mouseNavigation: return .mouseNavigation
        case .switcher: return .switcher
        case .cutPaste: return .finderCutPaste
        case .autoQuit: return .autoQuit
        case .shelf: return .shelf
        case .windowMaximize: return .windowMaximizer
        case .dockPreview: return .dockPreview
        case .keyDebounce: return .keyboardDebounce
        case .dockClick, .dockClickHide, .dockClickCycle: return .dockClick
        case .middleClick: return .middleClick
        case .textSnippets: return .textSnippets
        case .radialMenu: return .radialMenu
        case .mouseButtonShortcuts: return .mouseButtonShortcuts
        case .superKey: return .superKey
        }
    }
}

/// Groups the quick controls so the section stays short: categories start
/// collapsed and remember whether the user opened them.
private enum ControlCategory: String, CaseIterable, Identifiable {
    case windows, inputDevices, files

    var id: String { rawValue }

    static func category(for item: ControlPanelItem) -> ControlCategory {
        switch item {
        case .switcher, .dockPreview, .dockClick, .dockClickHide, .dockClickCycle, .windowMaximize, .autoQuit:
            return .windows
        case .mouseScroll, .focusFollowsMouse, .mouseNavigation, .mouseButtonShortcuts, .middleClick, .keyDebounce,
             .textSnippets, .radialMenu, .superKey:
            return .inputDevices
        case .cutPaste, .shelf:
            return .files
        }
    }
}

struct QuickControlsSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var inverter = ScrollInverter.shared
    @ObservedObject private var switcher = AppSwitcher.shared
    @ObservedObject private var dockPreview = DockPreviewService.shared
    @ObservedObject private var cutPaste = FinderCutPaste.shared
    @ObservedObject private var autoQuit = AutoQuitService.shared
    @ObservedObject private var windowMaximizer = WindowMaximizer.shared
    @ObservedObject private var keyDebounce = KeyboardDebounceService.shared
    @ObservedObject private var middleClick = MiddleClickService.shared
    @ObservedObject private var shelf = ShelfService.shared
    @AppStorage(DefaultsKey.scrollInverterEnabled) private var invertVertical = false
    @AppStorage(DefaultsKey.scrollInverterHorizontalEnabled) private var invertHorizontal = false
    @AppStorage(DefaultsKey.focusFollowsMouseEnabled) private var focusFollowsMouseEnabled = false
    @AppStorage(DefaultsKey.mouseNavigationEnabled) private var mouseNavigationEnabled = false
    @AppStorage(DefaultsKey.switcherEnabled) private var switcherEnabled = true
    @AppStorage(DefaultsKey.switcherShortcut) private var switcherShortcutStorage = GlobalShortcut.switcherDefault.storageValue
    @AppStorage(DefaultsKey.switcherIconRowMode) private var switcherIconRowMode = false
    @AppStorage(DefaultsKey.switcherSimpleMode) private var switcherSimpleMode = false
    @AppStorage(DefaultsKey.dockPreviewEnabled) private var dockPreviewEnabled = false
    @AppStorage(DefaultsKey.finderCutPasteEnabled) private var cutPasteEnabled = false
    @AppStorage(DefaultsKey.autoQuitEnabled) private var autoQuitEnabled = false
    @AppStorage(DefaultsKey.shelfEnabled) private var shelfEnabled = false
    @AppStorage(DefaultsKey.windowMaximizeEnabled) private var windowMaximizeEnabled = false
    @AppStorage(DefaultsKey.keyboardDebounceEnabled) private var keyDebounceEnabled = false
    @AppStorage(DefaultsKey.keyboardDebounceWindowMs) private var keyDebounceWindow = Defaults.defaultKeyboardDebounceWindowMs
    @AppStorage(DefaultsKey.dockClickMinimize) private var dockClickEnabled = false
    @AppStorage(DefaultsKey.dockClickHide) private var dockClickHideEnabled = false
    @AppStorage(DefaultsKey.dockClickCycleWindows) private var dockClickCycleEnabled = false
    @AppStorage(DefaultsKey.middleClickEnabled) private var middleClickEnabled = false
    @AppStorage(DefaultsKey.textSnippetsEnabled) private var textSnippetsEnabled = false
    @AppStorage(DefaultsKey.radialMenuEnabled) private var radialMenuEnabled = false
    @AppStorage(DefaultsKey.mouseButtonShortcutsEnabled) private var mouseButtonShortcutsEnabled = false
    @AppStorage(DefaultsKey.superKeyEnabled) private var superKeyEnabled = false
    @AppStorage(DefaultsKey.superKeyModifiers) private var superKeyModifierStorage =
        SuperKeySupport.defaultModifierStorageValue
    @AppStorage(DefaultsKey.superKeySource) private var superKeySourceRaw =
        SuperKeySource.capsLock.rawValue
    @AppStorage(DefaultsKey.panelControlMouseScroll) private var showScroll = true
    @AppStorage(DefaultsKey.panelControlFocusFollowsMouse) private var showFocusFollowsMouse = true
    @AppStorage(DefaultsKey.panelControlMouseNavigation) private var showMouseNavigation = true
    @AppStorage(DefaultsKey.panelControlSwitcher) private var showSwitcher = true
    @AppStorage(DefaultsKey.panelControlDockPreview) private var showDockPreview = true
    @AppStorage(DefaultsKey.panelControlCutPaste) private var showCutPaste = true
    @AppStorage(DefaultsKey.panelControlAutoQuit) private var showAutoQuit = true
    @AppStorage(DefaultsKey.panelControlShelf) private var showShelf = true
    @AppStorage(DefaultsKey.panelControlWindowMaximize) private var showWindowMaximize = true
    @AppStorage(DefaultsKey.panelControlKeyDebounce) private var showKeyDebounce = true
    @AppStorage(DefaultsKey.panelControlDockClick) private var showDockClick = true
    @AppStorage(DefaultsKey.panelControlDockClickHide) private var showDockClickHide = true
    @AppStorage(DefaultsKey.panelControlDockClickCycle) private var showDockClickCycle = true
    @AppStorage(DefaultsKey.panelControlMiddleClick) private var showMiddleClick = true
    @AppStorage(DefaultsKey.panelControlTextSnippets) private var showTextSnippets = true
    @AppStorage(DefaultsKey.panelControlRadialMenu) private var showRadialMenu = true
    @AppStorage(DefaultsKey.panelControlMouseButtonShortcuts) private var showMouseButtonShortcuts = true
    @AppStorage(DefaultsKey.panelControlSuperKey) private var showSuperKey = true
    @AppStorage(DefaultsKey.panelControlWindowsExpanded) private var windowsExpanded = false
    @AppStorage(DefaultsKey.panelControlInputExpanded) private var inputExpanded = false
    @AppStorage(DefaultsKey.panelControlFilesExpanded) private var filesExpanded = false
    @AppStorage(DefaultsKey.panelControlOrder) private var controlOrderRaw = ""
    @State private var draggingItem: ControlPanelItem?
    var collapsible = true

    var body: some View {
        PanelSection(.controls, title: l10n.s.quickControlsSection, collapsible: collapsible,
                     supportsEditing: true,
                     resetAction: resetPanelDefaults) { editing in
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ControlCategory.allCases) { category in
                    categoryView(category, editing: editing)
                }
            }
            .onAppear {
                MiddleClickService.shared.refreshDragGestureConflict()
            }
        }
    }

    @ViewBuilder
    private func categoryView(_ category: ControlCategory, editing: Bool) -> some View {
        let categoryItems = items(editing: editing).filter { ControlCategory.category(for: $0) == category }
        if !categoryItems.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                categoryHeader(category, items: categoryItems, editing: editing)
                if editing || isExpanded(category) {
                    ForEach(categoryItems) { item in
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
    }

    private func categoryHeader(_ category: ControlCategory,
                                items categoryItems: [ControlPanelItem],
                                editing: Bool) -> some View {
        let enabledCount = categoryItems.filter(isEnabled).count
        return Button {
            guard !editing else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                setExpanded(category, !isExpanded(category))
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(editing || isExpanded(category) ? 90 : 0))
                Text(title(for: category).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                Spacer(minLength: 0)
                Text("\(enabledCount)/\(categoryItems.count)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(enabledCount > 0 ? Color.accentColor : Color.secondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(editing)
    }

    private func title(for category: ControlCategory) -> String {
        switch category {
        case .windows: return l10n.s.panelCategoryWindows
        case .inputDevices: return l10n.s.panelCategoryInput
        case .files: return l10n.s.panelCategoryFiles
        }
    }

    private func isExpanded(_ category: ControlCategory) -> Bool {
        switch category {
        case .windows: return windowsExpanded
        case .inputDevices: return inputExpanded
        case .files: return filesExpanded
        }
    }

    private func setExpanded(_ category: ControlCategory, _ expanded: Bool) {
        switch category {
        case .windows: windowsExpanded = expanded
        case .inputDevices: inputExpanded = expanded
        case .files: filesExpanded = expanded
        }
    }

    private func isEnabled(_ item: ControlPanelItem) -> Bool {
        switch item {
        case .mouseScroll: return scrollDirectionEnabled
        case .focusFollowsMouse: return focusFollowsMouseEnabled
        case .mouseNavigation: return mouseNavigationEnabled
        case .switcher: return switcherEnabled
        case .cutPaste: return cutPasteEnabled
        case .autoQuit: return autoQuitEnabled
        case .shelf: return shelfEnabled
        case .windowMaximize: return windowMaximizeEnabled
        case .dockPreview: return dockPreviewEnabled
        case .keyDebounce: return keyDebounceEnabled
        case .dockClick: return dockClickEnabled
        case .dockClickHide: return dockClickHideEnabled
        case .dockClickCycle: return dockClickCycleEnabled
        case .middleClick: return middleClickEnabled
        case .textSnippets: return textSnippetsEnabled
        case .radialMenu: return radialMenuEnabled
        case .mouseButtonShortcuts: return mouseButtonShortcutsEnabled
        case .superKey: return superKeyEnabled
        }
    }

    /// The simple layout never captures the screen, so the panel must not
    /// nag for Screen Recording while it is active (the Settings page
    /// already follows the same rule).
    private var switcherNeedsScreenRecording: Bool {
        SwitcherSupport.needsScreenRecording(switcherEnabled: switcherEnabled,
                                             simpleMode: switcherSimpleMode,
                                             dockPreviewEnabled: false)
    }

    private var switcherCaption: String {
        guard switcherEnabled else { return l10n.s.switcherEnableCaption }
        if !permissions.accessibility { return missingPermission(l10n.s.permissionAccessibility) }
        if switcherNeedsScreenRecording, !permissions.screenRecording {
            return missingPermission(l10n.s.permissionScreenRecording)
        }
        return l10n.s.switcherEnableCaption
    }

    private var dockPreviewCaption: String {
        guard dockPreviewEnabled else { return l10n.s.dockPreviewEnableCaption }
        if !permissions.accessibility { return missingPermission(l10n.s.permissionAccessibility) }
        if !permissions.screenRecording { return missingPermission(l10n.s.permissionScreenRecording) }
        switch dockPreview.blockedReason {
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
        orderedItems.filter { $0.feature.isAvailable && (editing || isVisible($0)) }
    }

    private func isVisible(_ item: ControlPanelItem) -> Bool {
        switch item {
        case .mouseScroll: return showScroll
        case .focusFollowsMouse: return showFocusFollowsMouse
        case .mouseNavigation: return showMouseNavigation
        case .switcher: return showSwitcher
        case .keyDebounce: return showKeyDebounce
        case .cutPaste: return showCutPaste
        case .autoQuit: return showAutoQuit
        case .shelf: return showShelf
        case .windowMaximize: return showWindowMaximize
        case .dockPreview: return showDockPreview
        case .dockClick: return showDockClick
        case .dockClickHide: return showDockClickHide
        case .dockClickCycle: return showDockClickCycle
        case .middleClick: return showMiddleClick
        case .textSnippets: return showTextSnippets
        case .radialMenu: return showRadialMenu
        case .mouseButtonShortcuts: return showMouseButtonShortcuts
        case .superKey: return showSuperKey
        }
    }

    @ViewBuilder
    private func itemView(_ item: ControlPanelItem, editing: Bool) -> some View {
        switch item {
        case .mouseScroll:
            PanelToggleRow(title: l10n.s.invertMouseScroll,
                           caption: caption(l10n.s.invertMouseScrollCaption,
                                            needsAccessibility: scrollDirectionEnabled),
                           systemImage: "computermouse",
                           isOn: scrollDirectionBinding,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showScroll,
                           needsAttention: scrollDirectionEnabled && !permissions.accessibility,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: accessibilityPermissionAction(scrollDirectionEnabled))
                .onChange(of: scrollDirectionEnabled) { _, enabled in
                    ScrollInverter.shared.syncWithPreferences()
                    requestAccessibilityIfNeeded(enabled)
                }
        case .focusFollowsMouse:
            PanelToggleRow(title: l10n.s.focusFollowsMouseName,
                           caption: caption(l10n.s.focusFollowsMouseCaption,
                                            needsAccessibility: focusFollowsMouseEnabled),
                           systemImage: "cursorarrow.and.square.on.square.dashed",
                           isOn: $focusFollowsMouseEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showFocusFollowsMouse,
                           needsAttention: focusFollowsMouseEnabled && !permissions.accessibility,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: accessibilityPermissionAction(focusFollowsMouseEnabled))
                .onChange(of: focusFollowsMouseEnabled) { _, enabled in
                    FocusFollowsMouseService.shared.syncWithPreferences()
                    requestAccessibilityIfNeeded(enabled)
                }
        case .mouseNavigation:
            PanelToggleRow(title: l10n.s.mouseNavigationEnable,
                           caption: caption(l10n.s.mouseNavigationCaption,
                                            needsAccessibility: mouseNavigationEnabled),
                           systemImage: "arrow.left.arrow.right",
                           isOn: $mouseNavigationEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showMouseNavigation,
                           needsAttention: mouseNavigationEnabled && !permissions.accessibility,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: accessibilityPermissionAction(mouseNavigationEnabled))
                .onChange(of: mouseNavigationEnabled) { _, enabled in
                    MouseNavigationService.shared.syncWithPreferences()
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
                               needsAttention: switcherEnabled && (!permissions.accessibility
                                   || (switcherNeedsScreenRecording && !permissions.screenRecording)),
                               permissionButtonTitle: l10n.s.permissionRequest,
                               permissionAction: switcherPermissionAction)
                    .onChange(of: switcherEnabled) { _, enabled in
                        AppSwitcher.shared.syncWithPreferences()
                        guard enabled else { return }
                        if !permissions.accessibility {
                            grantAccessibility()
                        } else if switcherNeedsScreenRecording, !permissions.screenRecording {
                            grantScreenRecording()
                        }
                    }
                if switcherEnabled && !editing {
                    switcherIconRowOption
                }
            }
        case .keyDebounce:
            VStack(alignment: .leading, spacing: 5) {
                PanelToggleRow(title: l10n.s.keyDebounceName,
                               caption: keyDebounceCaption,
                               systemImage: "keyboard",
                               isOn: $keyDebounceEnabled,
                               isEditing: editing,
                               showsDragHandle: true,
                               visibility: $showKeyDebounce,
                               needsAttention: keyDebounceEnabled && !permissions.accessibility,
                               permissionButtonTitle: l10n.s.permissionRequest,
                               permissionAction: accessibilityPermissionAction(keyDebounceEnabled))
                    .onChange(of: keyDebounceEnabled) { _, enabled in
                        KeyboardDebounceService.shared.syncWithPreferences()
                        requestAccessibilityIfNeeded(enabled)
                    }
                if keyDebounceEnabled && !editing {
                    keyDebounceWindowControl
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
                           accessoryTitle: shelfEnabled && shelf.itemCount > 0
                               ? "\(l10n.s.shelfMenuItem) (\(shelf.itemCount))" : nil,
                           accessoryAction: {
                               appDelegate()?.closePopover()
                               ShelfService.shared.expandDocked()
                           })
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
        case .dockClick:
            PanelToggleRow(title: l10n.s.dockClickMinimize,
                           caption: caption(l10n.s.dockClickMinimizeCaption, needsAccessibility: dockClickEnabled),
                           systemImage: "dock.arrow.down.rectangle",
                           isOn: $dockClickEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showDockClick,
                           needsAttention: dockClickEnabled && !permissions.accessibility,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: accessibilityPermissionAction(dockClickEnabled))
                .onChange(of: dockClickEnabled) { _, enabled in
                    if enabled { dockClickHideEnabled = false }
                    DockClickService.shared.syncWithPreferences()
                    requestAccessibilityIfNeeded(enabled)
                }
        case .dockClickHide:
            PanelToggleRow(title: l10n.s.dockClickHide,
                           caption: caption(l10n.s.dockClickHideCaption, needsAccessibility: dockClickHideEnabled),
                           systemImage: "eye.slash",
                           isOn: $dockClickHideEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showDockClickHide,
                           needsAttention: dockClickHideEnabled && !permissions.accessibility,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: accessibilityPermissionAction(dockClickHideEnabled))
                .onChange(of: dockClickHideEnabled) { _, enabled in
                    if enabled { dockClickEnabled = false }
                    DockClickService.shared.syncWithPreferences()
                    requestAccessibilityIfNeeded(enabled)
                }
        case .dockClickCycle:
            PanelToggleRow(title: l10n.s.dockClickCycleWindows,
                           caption: caption(l10n.s.dockClickCycleWindowsCaption, needsAccessibility: dockClickCycleEnabled),
                           systemImage: "dock.rectangle",
                           isOn: $dockClickCycleEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showDockClickCycle,
                           needsAttention: dockClickCycleEnabled && !permissions.accessibility,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: accessibilityPermissionAction(dockClickCycleEnabled))
                .onChange(of: dockClickCycleEnabled) { _, enabled in
                    DockClickService.shared.syncWithPreferences()
                    requestAccessibilityIfNeeded(enabled)
                }
        case .middleClick:
            PanelToggleRow(title: l10n.s.middleClickEnable,
                           caption: middleClickCaption,
                           systemImage: "cursorarrow.click.2",
                           isOn: $middleClickEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showMiddleClick,
                           needsAttention: middleClickEnabled
                               && (!permissions.accessibility || middleClick.systemDragGestureConflict),
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: accessibilityPermissionAction(middleClickEnabled))
                .onChange(of: middleClickEnabled) { _, enabled in
                    MiddleClickService.shared.syncWithPreferences()
                    requestAccessibilityIfNeeded(enabled)
                }
        case .textSnippets:
            let snippetStrings = FeatureStrings.snippets(l10n.language)
            PanelToggleRow(title: snippetStrings.pageTitle,
                           caption: caption(snippetStrings.enableCaption, needsAccessibility: textSnippetsEnabled),
                           systemImage: "text.append",
                           isOn: $textSnippetsEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showTextSnippets,
                           needsAttention: textSnippetsEnabled && !permissions.accessibility,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: accessibilityPermissionAction(textSnippetsEnabled),
                           accessoryTitle: textSnippetsEnabled ? snippetStrings.manageButton : nil,
                           accessoryAction: {
                               SettingsRouter.shared.page = .textSnippets
                               appDelegate()?.openSettingsWindow()
                           })
                .onChange(of: textSnippetsEnabled) { _, enabled in
                    TextSnippetService.shared.syncWithPreferences()
                    requestAccessibilityIfNeeded(enabled)
                }
        case .radialMenu:
            let radialStrings = FeatureStrings.radialMenu(l10n.language)
            // Only wheels that press keys for the user (shortcut or media
            // slices) or watch a side button involve Accessibility.
            let needsAccessibility = RadialMenuSupport.needsAccessibility(
                RadialMenuSupport.decodeProfiles(UserDefaults.standard.data(forKey: DefaultsKey.radialMenuProfiles)))
            PanelToggleRow(title: radialStrings.pageTitle,
                           caption: radialMenuEnabled && needsAccessibility && !permissions.accessibility
                               ? missingPermission(l10n.s.permissionAccessibility)
                               : radialStrings.panelCaption,
                           systemImage: "circle.grid.cross",
                           isOn: $radialMenuEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showRadialMenu,
                           needsAttention: radialMenuEnabled && needsAccessibility
                               && !permissions.accessibility,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: needsAccessibility
                               ? accessibilityPermissionAction(radialMenuEnabled)
                               : nil,
                           accessoryTitle: radialMenuEnabled ? radialStrings.manageButton : nil,
                           accessoryAction: {
                               SettingsRouter.shared.page = .radialMenu
                               appDelegate()?.openSettingsWindow()
                           })
                .onChange(of: radialMenuEnabled) { _, enabled in
                    RadialMenuService.shared.syncWithPreferences()
                    if needsAccessibility {
                        requestAccessibilityIfNeeded(enabled)
                    }
                }
        case .mouseButtonShortcuts:
            let buttonStrings = FeatureStrings.mouseButtons(l10n.language)
            PanelToggleRow(title: buttonStrings.pageTitle,
                           caption: caption(buttonStrings.panelCaption,
                                            needsAccessibility: mouseButtonShortcutsEnabled),
                           systemImage: "button.programmable",
                           isOn: $mouseButtonShortcutsEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showMouseButtonShortcuts,
                           needsAttention: mouseButtonShortcutsEnabled && !permissions.accessibility,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: accessibilityPermissionAction(mouseButtonShortcutsEnabled),
                           accessoryTitle: mouseButtonShortcutsEnabled ? buttonStrings.manageButton : nil,
                           accessoryAction: {
                               SettingsRouter.shared.page = .mouse
                               appDelegate()?.openSettingsWindow()
                           })
                .onChange(of: mouseButtonShortcutsEnabled) { _, enabled in
                    MouseButtonShortcutService.shared.syncWithPreferences()
                    requestAccessibilityIfNeeded(enabled)
                }
        case .superKey:
            let superKeyStrings = FeatureStrings.superKey(l10n.language)
            let superKeySource = SuperKeySource.sanitized(superKeySourceRaw)
            let modifierCaption = String(
                format: superKeyStrings.panelCaptionFormat,
                superKeyStrings.sourceLabel(superKeySource),
                SuperKeySupport.modifiers(from: superKeyModifierStorage).keyCaps.joined()
            )
            PanelToggleRow(title: superKeyStrings.pageTitle,
                           caption: caption(modifierCaption,
                                            needsAccessibility: superKeyEnabled),
                           systemImage: superKeySource.systemImage,
                           isOn: $superKeyEnabled,
                           isEditing: editing,
                           showsDragHandle: true,
                           visibility: $showSuperKey,
                           needsAttention: superKeyEnabled && !permissions.accessibility,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: accessibilityPermissionAction(superKeyEnabled),
                           accessoryTitle: superKeyEnabled ? superKeyStrings.manageButton : nil,
                           accessoryAction: {
                               SettingsRouter.shared.page = .superKey
                               appDelegate()?.openSettingsWindow()
                           })
                .onChange(of: superKeyEnabled) { _, enabled in
                    SuperKeyService.shared.syncWithPreferences()
                    requestAccessibilityIfNeeded(enabled)
                }
        }
    }

    private var middleClickCaption: String {
        guard middleClickEnabled else { return l10n.s.middleClickEnableCaption }
        if !permissions.accessibility { return missingPermission(l10n.s.permissionAccessibility) }
        if middleClick.systemDragGestureConflict { return l10n.s.middleClickDragConflict }
        return l10n.s.middleClickEnableCaption
    }

    private func resetPanelDefaults() {
        PanelLayout.resetItemOrder(key: DefaultsKey.panelControlOrder)
        controlOrderRaw = ""
        showScroll = true
        showFocusFollowsMouse = true
        showMouseNavigation = true
        showSwitcher = true
        showCutPaste = true
        showAutoQuit = true
        showShelf = true
        showWindowMaximize = true
        showDockPreview = true
        showKeyDebounce = true
        showDockClick = true
        showDockClickHide = true
        showDockClickCycle = true
        showMiddleClick = true
        showTextSnippets = true
        showRadialMenu = true
        showMouseButtonShortcuts = true
        showSuperKey = true
        windowsExpanded = false
        inputExpanded = false
        filesExpanded = false
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

    private var keyDebounceCaption: String {
        guard keyDebounceEnabled else { return l10n.s.keyDebounceCaption }
        guard permissions.accessibility else { return missingPermission(l10n.s.permissionAccessibility) }
        let window = Defaults.sanitizedKeyboardDebounceWindow(keyDebounceWindow)
        return "\(l10n.s.keyDebounceGlobalWindow): \(window) ms"
    }

    private var keyDebounceWindowControl: some View {
        Stepper(value: keyDebounceWindowBinding, in: Defaults.allowedKeyboardDebounceWindowRange, step: 5) {
            HStack(spacing: 6) {
                Text(l10n.s.keyDebounceGlobalWindow)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(Defaults.sanitizedKeyboardDebounceWindow(keyDebounceWindow)) ms")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .controlSize(.small)
        .padding(.leading, 28)
    }

    private var keyDebounceWindowBinding: Binding<Int> {
        Binding {
            Defaults.sanitizedKeyboardDebounceWindow(keyDebounceWindow)
        } set: { value in
            keyDebounceWindow = Defaults.sanitizedKeyboardDebounceWindow(value)
            KeyboardDebounceService.shared.syncWithPreferences()
        }
    }

    private var scrollDirectionEnabled: Bool {
        invertVertical || invertHorizontal
    }

    private var scrollDirectionBinding: Binding<Bool> {
        Binding {
            scrollDirectionEnabled
        } set: { enabled in
            invertVertical = enabled
            invertHorizontal = enabled
        }
    }

    private func accessibilityPermissionAction(_ enabled: Bool) -> (() -> Void)? {
        guard enabled, !permissions.accessibility else { return nil }
        return { grantAccessibility() }
    }

    private var switcherShortcutDisplayString: String {
        (GlobalShortcut(storageValue: switcherShortcutStorage) ?? .switcherDefault).displayString
    }

    private var switcherIconRowOption: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(String(format: l10n.s.switcherIconRowMode, switcherShortcutDisplayString))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Toggle("", isOn: $switcherIconRowMode)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(switcherSimpleMode)
                    .onChange(of: switcherIconRowMode) { _, _ in
                        AppSwitcher.shared.syncWithPreferences()
                    }
            }
            Text(l10n.s.switcherIconRowModeCaption)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
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
        if switcherNeedsScreenRecording, !permissions.screenRecording {
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

// Internal (not private): the quick toggles tab builds its rows from the same
// component, so every action row in the panel looks and behaves the same.
struct UtilityActionButton: View {
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
    /// The feature's enabled global shortcut, shown as a quiet key hint so
    /// the panel row doubles as a reminder that the keyboard path exists.
    var shortcutHint: String? = nil
    var accessoryTitle: String? = nil
    var accessorySystemImage: String? = nil
    var accessoryAction: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Group {
            if isEditing {
                rowContent(showChevron: false)
                    .panelCard()
            } else if permissionAction != nil || accessoryAction != nil {
                VStack(alignment: .leading, spacing: 7) {
                    if permissionAction != nil {
                        rowContent(showChevron: false)
                        permissionButton
                    } else {
                        mainButton
                    }
                    accessoryButton
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

    private var mainButton: some View {
        Button(action: action) {
            rowContent(showChevron: true)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var accessoryButton: some View {
        if let accessoryTitle, let accessoryAction {
            Button(action: accessoryAction) {
                Label(accessoryTitle, systemImage: accessorySystemImage ?? "clock")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .padding(.leading, 31)
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
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let badge {
                        PanelBetaBadge(text: badge)
                    }
                }
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(captionColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if isEditing, let visibility {
                if !visibility.wrappedValue {
                    PanelHiddenBadge()
                }
                PanelInlineHideButton(isVisible: visibility)
            } else {
                if let shortcutHint {
                    Text(shortcutHint)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
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


/// Shared switch row used by Quick Controls and Quick toggles.
struct PanelToggleRow: View {
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
    /// Optional inline action under the caption (e.g. "Open the shelf (3)"),
    /// shown only outside edit mode.
    var accessoryTitle: String? = nil
    var accessoryAction: (() -> Void)? = nil

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
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let badge {
                        PanelBetaBadge(text: badge)
                    }
                }
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(captionColor)
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
                if !isEditing, let accessoryTitle, let accessoryAction {
                    Button {
                        accessoryAction()
                    } label: {
                        Label(accessoryTitle, systemImage: "arrow.up.forward.square")
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
            let isBeta = UpdateServiceSupport.SemanticVersion(raw: version)?.isPrerelease ?? false
            let tintColor: Color = isBeta ? .orange : .accentColor

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
                        // The title above already says an update is waiting,
                        // so this line carries the version instead of saying
                        // the same words a second time.
                        Text("\(l10n.s.versionPrefix) \(version)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    Text(l10n.s.updateBannerAction)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tintColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tintColor)
                )
            }
            .buttonStyle(.plain)
        case let .downloading(progress):
            progressRow(l10n.s.updateDownloading, fraction: progress)
        case .installing:
            progressRow(l10n.s.updateInstalling)
        default:
            EmptyView()
        }
    }

    /// With a known fraction the row shows a real bar and percentage; while
    /// the size is unknown (or for the install step) it keeps the spinner.
    private func progressRow(_ text: String, fraction: Double? = nil) -> some View {
        HStack(spacing: 8) {
            if fraction == nil {
                ProgressView().controlSize(.small)
            }
            Text(text).font(.system(size: 11.5, weight: .medium))
            if let fraction {
                ProgressView(value: fraction)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                Text("\(Int(fraction * 100))%")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Spacer()
            }
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
    @AppStorage(DefaultsKey.keepAwakeAllowDisplaySleep) private var keepAwakeAllowDisplaySleep = false
    @AppStorage(DefaultsKey.keepAwakeExternalDisplay) private var keepAwakeExternalDisplay = false
    @AppStorage(DefaultsKey.keepAwakeConnectedToPower) private var keepAwakeConnectedToPower = false
    @AppStorage(DefaultsKey.keepAwakeIconTint) private var keepAwakeIconTint = KeepAwakeIconTint.orange.rawValue
    @AppStorage(DefaultsKey.keepAwakeActiveIcon) private var keepAwakeActiveIcon = KeepAwakeActiveIcon.vorssaint.rawValue
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleEnabled) private var keepAwakeMouseJiggle = false
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleInterval) private var keepAwakeMouseJiggleInterval = 5
    @State private var optionsExpanded = false
    @State private var automationExpanded = false
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
            keepAwakeActiveIcon = Defaults.sanitizedKeepAwakeActiveIcon(keepAwakeActiveIcon).rawValue
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
                    KeepAwakeIconPicker(iconValue: $keepAwakeActiveIcon,
                                        tintValue: $keepAwakeIconTint,
                                        compact: true)
                    compactOptionToggle(
                        icon: "display",
                        title: displaySleepStrings.allowDisplaySleep,
                        isOn: $keepAwakeAllowDisplaySleep
                    )
                    compactOptionToggle(
                        icon: "play.circle",
                        title: l10n.s.keepAwakeAutoStart,
                        isOn: $keepAwakeAutoStart
                    )
                    automationDisclosure
                    compactOptionToggle(
                        icon: "cursorarrow.motionlines",
                        title: l10n.s.keepAwakeMouseJiggle,
                        isOn: $keepAwakeMouseJiggle,
                        errorText: mouseJiggleNeedsAccessibility ? mouseJiggleCaption : nil
                    )
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

    private var automationDisclosure: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                automationExpanded.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 15)
                    Text(automationStrings.automationSection)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    automationSummaryBadges
                    Image(systemName: automationExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if automationExpanded {
                KeepAwakeAutomationEditor(compact: true)
                    .padding(.leading, 22)
            }
        }
    }

    @ViewBuilder
    private var automationSummaryBadges: some View {
        if !keepAwakeExternalDisplay,
           !keepAwakeConnectedToPower {
            Text(automationStrings.automationOff)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 4) {
                if keepAwakeExternalDisplay {
                    automationSystemBadge("display")
                }
                if keepAwakeConnectedToPower {
                    automationSystemBadge("powerplug.fill")
                }
            }
        }
    }

    private func automationSystemBadge(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 17, height: 17)
            .background(Circle().fill(Color.accentColor.opacity(0.12)))
    }

    private func compactOptionToggle(icon: String,
                                     title: String,
                                     isOn: Binding<Bool>,
                                     errorText: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.red)
                    .padding(.leading, 22)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var statusLine: some View {
        Group {
            if awake.isActive {
                if awake.sessionTrigger == .automation {
                    Text(automationStrings.activeStatus(for: awake.activeAutomationConditions))
                } else if let end = awake.endDate {
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

    private var automationStrings: KeepAwakeAutomationStrings {
        FeatureStrings.keepAwakeAutomation(l10n.language)
    }

    private var displaySleepStrings: KeepAwakeDisplaySleepStrings {
        FeatureStrings.keepAwakeDisplaySleep(l10n.language)
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
                } else if awake.isActive {
                    awake.toggle()
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
