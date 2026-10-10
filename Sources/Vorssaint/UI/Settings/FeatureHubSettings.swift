// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Features hub. One switch per feature, grouped in plain language: off
/// means the feature disappears from the whole app (Settings, panel, menu
/// bar, shortcuts) and costs nothing; its configuration is kept for its
/// return. The Permissions tab is the transparency portal: what each system
/// permission does, which features use it right now, and a gentle nudge when
/// one is granted with nothing using it.
struct FeatureHubSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var router = SettingsRouter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: Tab = .features
    @AppStorage(DefaultsKey.settingsExperience) private var experienceRaw = SettingsExperience.expert.rawValue
    @State private var catalogQuery = ""
    @State private var selectedGroup: FeatureGroup?
    @State private var includedOnly = false
    @State private var enabledFirst = false
    @State private var revealedFeature: AppFeature?
    /// Tracks the feature-target request currently being revealed, so a
    /// delayed retry from an older request cannot act after a newer one has
    /// already taken over (same convention as `SettingsSectionFocusModifier`).
    @State private var revealID = UUID()
    /// The row briefly tinted after a search or Command Bar selection lands
    /// on it, mirroring the section highlight `SettingsSectionFocusModifier`
    /// gives an ordinary page anchor.
    @State private var highlightedFeature: AppFeature?
    @State private var expandedGroups = Set(FeatureGroup.allCases)
    /// Installed switches never once turned on, read when the page appears
    /// and after every install change rather than on every redraw.
    @State private var neverUsed: [AppFeature] = []

    /// Below this, the offer would be more to read than it saves.
    private static let neverUsedMinimum = 3

    private enum Tab { case features, permissions }

    private var hub: FeatureHubStrings { FeatureStrings.hub(l10n.language) }

    var body: some View {
        ScrollViewReader { proxy in
            content
                .onAppear {
                    refreshNeverUsed()
                    revealPendingFeatureTarget(using: proxy)
                }
                .onChange(of: router.requestID) { _, _ in revealPendingFeatureTarget(using: proxy) }
                .onChange(of: features.revision) { _, _ in refreshNeverUsed() }
                .onChange(of: experienceRaw) { _, _ in
                    revealedFeature = nil
                    selectedGroup = nil
                    refreshNeverUsed()
                    proxy.scrollTo("catalog", anchor: .top)
                }
                .onChange(of: catalogQuery) { _, query in
                    if !query.isEmpty { expandedGroups = Set(FeatureGroup.allCases) }
                }
                .onChange(of: selectedGroup) { _, group in
                    if let group { expandedGroups.insert(group) }
                }
        }
    }

    private var content: some View {
        // The lazy stack has to be the scroll view's own content (issue
        // #2270). Nested in a plain stack, it resized that stack each time a
        // card came into view: scrolling stalled for up to a second, and the
        // layout could keep redoing itself until Settings froze.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(hub.pageTitle).font(.title2.bold())
                    Text(tab == .features ? hub.intro : hub.permissionsIntro)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker(hub.pageTitle, selection: $tab) {
                    Text(hub.tabFeatures).tag(Tab.features)
                    Text(hub.tabPermissions).tag(Tab.permissions)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // The restart notice comes first, whichever tab is open:
                // uninstalling anything makes it impossible to miss.
                if features.needsRestartToUnload {
                    restartCard
                }
                if tab == .features {
                    catalogControls.id("catalog")
                    summaryCard
                    ForEach(FeatureGroup.allCases.filter { !members(in: $0).isEmpty }, id: \.self) { group in
                        groupCard(group)
                    }
                    if FeatureGroup.allCases.allSatisfy({ members(in: $0).isEmpty }) {
                        ContentUnavailableView.search(text: catalogQuery)
                    }
                    neverUsedCard
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hub.footerNote)
                        Text(hub.energyHelp)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    SettingsCard {
                        PermissionsPortalSections(hub: hub)
                    }
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(22)
        }

    }

    private var discovery: SettingsDiscoveryStrings { .localized(l10n.language) }
    private var experience: SettingsExperience { .sanitized(experienceRaw) }

    private func members(in group: FeatureGroup) -> [AppFeature] {
        guard selectedGroup == nil || selectedGroup == group else { return [] }
        let query = catalogQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = AppFeature.features(in: group).filter { feature in
            experience.shows(feature, revealing: revealedFeature)
                && (!includedOnly || feature.isAvailable)
                && (query.isEmpty || SettingsSearchSupport.matches(query: query,
                    title: feature.hubTitle(l10n.s, hub: hub),
                    keywords: [feature.hubDescription(hub), group.title(l10n.language, hub: hub)]))
        }
        let sorted = AppFeature.sorted(candidates) { $0.hubTitle(l10n.s, hub: hub) }
        if enabledFirst { return sorted.filter(\.isAvailable) + sorted.filter { !$0.isAvailable } }
        if group == .dynamicIsland {
            return sorted.filter { $0 == .notch } + sorted.filter { $0 != .notch }
        }
        return sorted
    }

    private var catalogControls: some View {
        SettingsCard {
            TextField(l10n.s.settingsSearchPlaceholder, text: $catalogQuery)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(discovery.text(.searchVisible))
            ViewThatFits(in: .horizontal) {
                HStack { categoryPicker; catalogOptions }
                VStack(alignment: .leading) { categoryPicker; catalogOptions }
            }
            let shown = FeatureGroup.allCases.reduce(0) { $0 + members(in: $1).count }
            Text(String(format: discovery.text(.shown), shown))
                .font(.caption).foregroundStyle(.secondary)
            let hidden = experience.hiddenFeatureCount(revealing: revealedFeature)
            if hidden > 0 {
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "eye.slash")
                        .font(.title3).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: discovery.text(.hidden), hidden))
                            .font(.callout.weight(.semibold))
                        Text(discovery.text(.filterHelp))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button(discovery.text(.showEverything)) { experienceRaw = SettingsExperience.expert.rawValue }
                        .buttonStyle(.link)
                }
            }

        }
    }

    private var categoryPicker: some View {
        Picker(discovery.text(.category), selection: $selectedGroup) {
            Text(discovery.text(.allCategories)).tag(Optional<FeatureGroup>.none)
            ForEach(FeatureGroup.allCases.filter { group in
                AppFeature.features(in: group).contains { experience.shows($0, revealing: revealedFeature) }
            }, id: \.self) { group in
                Text(group.title(l10n.language, hub: hub)).tag(Optional(group))
            }
        }.pickerStyle(.menu)
    }

    private var catalogOptions: some View {
        HStack(spacing: 12) {
            Toggle(discovery.text(.includedOnly), isOn: $includedOnly).toggleStyle(.checkbox)
            Toggle(discovery.text(.includedFirst), isOn: $enabledFirst).toggleStyle(.checkbox)
        }.font(.caption)
    }

    /// Consumes a pending Feature Hub target: switches off the Permissions
    /// tab if needed and scrolls the requested row into view. Retried once
    /// after the first run-loop turn, the same allowance
    /// `SettingsSectionFocusModifier` gives a freshly installed Form to
    /// register its row identities.
    private func revealPendingFeatureTarget(using proxy: ScrollViewProxy) {
        guard let request = router.pendingFeatureTarget else { return }
        router.consumeFeatureTarget(id: request.id)
        revealID = request.id
        revealedFeature = request.feature
        selectedGroup = nil
        includedOnly = false
        catalogQuery = ""
        if tab == .permissions { tab = .features }
        expandedGroups.insert(request.feature.group)
        DispatchQueue.main.async {
            guard self.revealID == request.id else { return }
            proxy.scrollTo(request.feature.group, anchor: .top)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard self.revealID == request.id else { return }
                reveal(request.feature, using: proxy)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    guard self.revealID == request.id else { return }
                    reveal(request.feature, using: proxy)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    guard self.revealID == request.id else { return }
                    clearHighlight()
                }
            }
        }
    }

    private func reveal(_ feature: AppFeature, using proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(feature, anchor: .center)
            highlightedFeature = feature
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(feature, anchor: .center)
                highlightedFeature = feature
            }
        }
    }

    private func clearHighlight() {
        if reduceMotion {
            highlightedFeature = nil
        } else {
            withAnimation(.easeOut(duration: 0.25)) {
                highlightedFeature = nil
            }
        }
    }

    private var restartCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor)
            Text(hub.restartNote)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button(hub.restartButton) {
                FeatureRuntime.shared.relaunchApp()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The tally as a bar, with the two bulk actions beside it.
    private var summaryCard: some View {
        SettingsCard {
            HStack(spacing: 12) {
                Text(String(format: hub.activeCountFormat,
                            features.availableCount, features.installableCount))
                    .font(.headline)
                Spacer(minLength: 12)
                Button(hub.installAllButton) {
                    FeatureRuntime.shared.setAllAvailable(true)
                }
                .disabled(features.availableCount == features.installableCount)
                Button(hub.uninstallAllButton) {
                    FeatureRuntime.shared.setAllAvailable(false)
                }
                .disabled(features.availableCount == 0)
            }
            InstalledShareBar(installed: features.availableCount, total: features.installableCount)
            HStack {
                Spacer(minLength: 12)
                Button(l10n.s.menuUndo) { features.undoLastFeatureChange() }
                    .disabled(features.undoCount == 0)
                Button(l10n.s.menuRedo) { features.redoLastFeatureChange() }
                    .disabled(features.redoCount == 0)
            }
        }
    }

    /// Installed switches that were never once turned on, offered as one
    /// batch. People come to this page to manage the app, so the offer waits
    /// here instead of interrupting anywhere else. Keep ends it for these
    /// features, and Undo puts back exactly what left.
    @ViewBuilder
    private var neverUsedCard: some View {
        if neverUsed.count >= Self.neverUsedMinimum {
            SettingsCard(title: hub.neverUsedTitle) {
                Text(String(format: hub.neverUsedMessageFormat,
                            neverUsed.map { $0.hubTitle(l10n.s, hub: hub) }.joined(separator: ", ")))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button(hub.neverUsedKeep, action: keepNeverUsed)
                    Button(hub.neverUsedUninstall, action: uninstallNeverUsed)
                }
            }
        }
    }

    private func refreshNeverUsed() {
        neverUsed = FeatureRuntime.shared.neverSwitchedOnFeatures()
            .filter { experience.shows($0, revealing: revealedFeature) }
    }

    private func uninstallNeverUsed() {
        // Read again at the click: a switch turned on in the panel since the
        // page appeared takes its feature out of the batch.
        let stillUnused = Set(FeatureRuntime.shared.neverSwitchedOnFeatures())
        let batch = neverUsed.filter(stillUnused.contains)
        guard !batch.isEmpty else {
            refreshNeverUsed()
            return
        }
        withAnimation(.easeOut(duration: 0.22)) {
            FeatureRuntime.shared.setAvailable(batch, false)
        }
    }

    private func keepNeverUsed() {
        FeatureRuntime.shared.keep(neverUsed)
        withAnimation(.easeOut(duration: 0.22)) {
            refreshNeverUsed()
        }
    }

    /// Every category uses the same disclosure, rows and sorting rules.
    /// Closing a group removes its feature rows until the user reopens it.
    private func groupCard(_ group: FeatureGroup) -> some View {
        let members = members(in: group)
        let installed = members.filter(\.isAvailable).count
        return SettingsCard {
            DisclosureGroup(isExpanded: Binding(
                get: { expandedGroups.contains(group) },
                set: { expanded in
                    if expanded { expandedGroups.insert(group) }
                    else { expandedGroups.remove(group) }
                }
            )) {
                if expandedGroups.contains(group) {
                    VStack(spacing: 0) {
                        ForEach(members, id: \.self) { feature in
                            FeatureHubRow(
                                feature: feature,
                                hub: hub,
                                isHighlighted: highlightedFeature == feature
                            )
                            .id(feature)
                            if feature != members.last {
                                Divider().padding(.leading, 8)
                            }
                        }
                    }
                    if group == .monitor,
                       !FeatureVisibilitySupport.monitorFeatures.contains(where: \.isAvailable) {
                        Text(hub.monitorAllOffNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } label: {
                groupHeader(group, installed: installed, total: members.count)
            }
        }
        .id(group)
    }

    private func groupHeader(_ group: FeatureGroup, installed: Int, total: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: group.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(groupTitle(group)).font(.headline)
            Spacer(minLength: 12)
            Text("\(installed)/\(total)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            InstalledShareBar(installed: installed, total: total)
                .controlSize(.small)
                .frame(width: 64)
        }
    }

    private func groupTitle(_ group: FeatureGroup) -> String {
        group.title(l10n.language, hub: hub)
    }
}

/// The installed share as the system's own bar, the one picture of "how
/// much of this is on" that needs no reading.
private struct InstalledShareBar: View {
    let installed: Int
    let total: Int

    var body: some View {
        ProgressView(value: Double(min(installed, total)), total: Double(max(total, 1)))
            .progressViewStyle(.linear)
            .tint(Color.accentColor)
    }
}

// MARK: - Feature row

/// Icon, name and one line about the feature; small icons for the
/// permissions it can use and what it keeps alive; and the install switch.
/// An installed feature with a page of its own opens it from the row.
private struct FeatureHubRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @State private var confirmingExtensions = false
    @State private var hovering = false
    @State private var preferenceRevision = 0
    let feature: AppFeature
    let hub: FeatureHubStrings
    var isHighlighted: Bool = false

    private var discovery: SettingsDiscoveryStrings { .localized(l10n.language) }
    private var installed: Bool { feature.isAvailable }

    private var opensSettings: Bool { installed && feature.hasNavigableSettingsDestination }

    /// Extensions still installed under this row's feature; only the Dynamic
    /// Island has any. They do nothing without it, so its uninstall asks
    /// whether they leave too.
    private var installedExtensions: [AppFeature] {
        feature == .notch ? AppFeature.dynamicIslandExtensions.filter(\.isAvailable) : []
    }

    /// Set only while this Mac cannot run the feature and it is not yet
    /// installed, so an install that predates the check keeps an ordinary
    /// row with its settings and the switch reachable.
    private var unsupportedReason: String? { feature.installBlockedReason }

    private var accessibilityTitle: String {
        let title = feature.hubTitle(l10n.s, hub: hub)
        if feature == .notch { return "\(title). \(hub.experimentalBadge)" }
        return feature.isBeta ? "\(title). \(l10n.s.betaFeatureWarning)" : title
    }

    /// The switch reads availability itself, so it only moves once the
    /// runtime has flipped; the Dynamic Island asks about its extensions
    /// before leaving, and the switch springs back if that is cancelled.
    private var installBinding: Binding<Bool> {
        Binding(get: { installed }, set: { wanted in
            if !wanted, !installedExtensions.isEmpty {
                confirmingExtensions = true
            } else {
                flip(to: wanted)
            }
        })
    }

    var body: some View {
        HStack(spacing: 12) {
            if opensSettings {
                Button {
                    SettingsRouter.shared.request(feature.settingsDestination,
                                                  sidebarFeature: feature)
                } label: {
                    rowContent(showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(accessibilityTitle). \(feature.hubDescription(hub)). \(statusLabel)")
                .accessibilityAddTraits(.isLink)
                .accessibilityRemoveTraits(.isButton)
            } else {
                rowContent(showsChevron: false)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(accessibilityTitle). \(feature.hubDescription(hub)). \(statusLabel)")
                    .opacity(unsupportedReason == nil ? 1 : 0.4)
                    .saturation(unsupportedReason == nil ? 1 : 0)
            }
            installSwitch
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(rowFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            preferenceRevision &+= 1
        }
        .alert(hub.notchUninstallTitle, isPresented: $confirmingExtensions) {
            Button(hub.notchUninstallWithExtensions) { flip(to: false, alongside: installedExtensions) }
            Button(hub.notchUninstallKeepExtensions) { flip(to: false) }
            Button(hub.presetConfirmCancel, role: .cancel) {}
        } message: {
            Text(String(format: hub.notchUninstallMessageFormat,
                        installedExtensions.map { $0.hubTitle(l10n.s, hub: hub) }
                            .joined(separator: ", ")))
        }
    }

    private var state: FeatureConfigurationState {
        _ = preferenceRevision
        return feature.configurationState(isAvailable: \.isAvailable,
                                          boolFor: UserDefaults.standard.bool(forKey:))
    }

    private var statusLabel: String {
        switch state {
        case .excluded: return discovery.text(.notIncluded)
        case .parentRequired: return discovery.text(.parentRequired)
        case .configuredOff: return discovery.text(.behaviorOff)
        case .configuredOn: return discovery.text(.behaviorOn)
        case .onDemand: return discovery.text(.onDemand)
        }
    }

    private var rowFill: Color {
        if isHighlighted { return Color.accentColor.opacity(0.10) }
        return hovering && opensSettings ? Color.primary.opacity(0.04) : Color.clear
    }

    private func rowContent(showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: feature.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(feature.hubTitle(l10n.s, hub: hub))
                        .foregroundStyle(installed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    if feature == .notch {
                        Text(hub.experimentalBadge.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .foregroundStyle(.orange)
                            .background(Capsule().fill(Color.orange.opacity(0.14)))
                            .accessibilityHidden(true)
                    }
                    if feature.isBeta {
                        Text(l10n.s.betaBadge)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                            .accessibilityHidden(true)
                    }
                }
                Text(feature.hubDescription(hub))
                    .font(.caption)
                    .foregroundStyle(installed ? Color.secondary : Color.secondary.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                Text(statusLabel).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var installSwitch: some View {
        let toggle = Toggle(SettingsDiscoveryStrings.localized(l10n.language).included, isOn: installBinding)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        if let reason = unsupportedReason {
            // .help() never fires on a disabled control, so the tooltip
            // has to sit on this wrapper. Flattening it loses the only
            // place the reason is shown.
            HStack(spacing: 0) {
                toggle.disabled(true)
            }
            .help(reason)
            .accessibilityLabel("\(accessibilityTitle). \(reason)")
        } else {
            VStack(alignment: .trailing, spacing: 5) {
                toggle
                    .accessibilityLabel("\(accessibilityTitle): \(discovery.included)")
                    .help(discovery.text(.includeHelp))
                Text(SettingsDiscoveryStrings.localized(l10n.language).included)
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                if state == .configuredOff {
                    Button(discovery.text(.turnOn)) { features.turnOn(feature) }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
        }
    }

    private func flip(to install: Bool, alongside companions: [AppFeature] = []) {
        withAnimation(.easeOut(duration: 0.22)) {
            FeatureRuntime.shared.setAvailable([feature] + companions, install)
        }
    }
}

// MARK: - Permissions portal

struct PermissionsPortalSections: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    let hub: FeatureHubStrings
    let visiblePermissions: [AppPermission]
    @State private var automation: [Permissions.AutomationTarget: Permissions.AutomationStatus] = [:]
    @State private var pollingDemandID = UUID()

    init(hub: FeatureHubStrings,
         visiblePermissions: [AppPermission] = AppPermission.allCases) {
        self.hub = hub
        self.visiblePermissions = visiblePermissions
    }

    var body: some View {
        ForEach(visiblePermissions, id: \.self) { permission in
            PermissionPortalRow(permission: permission,
                                hub: hub,
                                status: status(for: permission))
            if permission != visiblePermissions.last {
                Divider().padding(.leading, 42)
            }
        }
        .onAppear {
            // Statuses that only refresh at launch/activation get a fresh
            // read the moment the portal shows; automation is checked off the
            // main thread because the AE round trip can block briefly.
            permissions.refresh()
            if visiblePermissions.contains(.accessibility)
                || visiblePermissions.contains(.screenRecording) {
                permissions.setActivePermissionSurface(pollingDemandID, visible: true)
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let finder = Permissions.automationStatus(for: .finder)
                let terminal = Permissions.automationStatus(for: .terminal)
                DispatchQueue.main.async {
                    automation = [.finder: finder, .terminal: terminal]
                }
            }
        }
        .onDisappear {
            permissions.setActivePermissionSurface(pollingDemandID, visible: false)
        }
    }

    private func status(for permission: AppPermission) -> PermissionPortalRow.Status {
        switch permission {
        case .accessibility: return permissions.accessibility ? .granted : .missing
        case .screenRecording: return permissions.screenRecording ? .granted : .missing
        case .fullDiskAccess: return permissions.fullDiskAccess ? .granted : .missing
        case .filesAndFolders:
            guard AppFeature.cleaner.isAvailable,
                  WhatsAppDownloadSupport.isEnabled else {
                return .unknown
            }
            switch WhatsAppDownloadManager.shared.accessStatus {
            case .available: return .granted
            case .denied: return .missing
            case .unknown: return .unknown
            }
        case .notifications:
            switch permissions.notifications {
            case .granted: return .granted
            case .denied, .undetermined: return .missing
            case .unknown: return .unknown
            }
        case .automationFinder: return automationStatus(.finder)
        case .automationTerminal: return automationStatus(.terminal)
        case .automationPlayback: return .unknown
        case .audioCapture:
            // No public check exists for system audio capture; the mixer
            // reports a failed tap, which is the one readable signal.
            if AppFeature.mixer.isAvailable, AppVolumeMixer.shared.needsPermission {
                return .missing
            }
            return .unknown
        case .microphone:
            switch permissions.microphone {
            case .granted: return .granted
            case .denied, .undetermined: return .missing
            case .unknown: return .unknown
            }
        case .calendar:
            return permissions.calendarAccess == .fullAccess ? .granted : .missing
        case .camera:
            switch permissions.camera {
            case .granted: return .granted
            case .denied, .undetermined: return .missing
            case .unknown: return .unknown
            }
        case .appManagement:
            // macOS has no public preflight API for this permission. The
            // system records the app only after its first protected write.
            return .unknown
        }
    }

    private func automationStatus(_ target: Permissions.AutomationTarget) -> PermissionPortalRow.Status {
        switch automation[target] {
        case .granted: return .granted
        case .denied, .undetermined: return .missing
        case .notDeterminable, .none: return .unknown
        }
    }
}

private struct PermissionPortalRow: View {
    enum Status { case granted, missing, unknown }

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    let permission: AppPermission
    let hub: FeatureHubStrings
    let status: Status

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // The tile wears the status color, so a glance down the list
            // shows what is granted before any word is read.
            Image(systemName: permission.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 30, height: 30)
                .background(statusColor.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(permission.name(hub))
                        .fontWeight(.medium)
                    statusChip
                }
                Text(permission.explainer(hub))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(usedByLine)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if status == .granted, activeFeatures.isEmpty {
                    unusedCard
                }
                HStack(spacing: 8) {
                    if status != .granted, hasRequestFlow {
                        Button(hub.requestButton) { request() }
                    }
                    Button(hub.openSystemSettings) { openSystemSettings() }
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var activeFeatures: [AppFeature] {
        AppFeature.activeFeatures(using: permission).filter {
            permission != .notifications || $0 != .monitorPower || PowerSampler.hasInternalBattery
        }
    }

    private var usedByLine: String {
        let names = activeFeatures.map { $0.hubTitle(l10n.s, hub: hub) }
        guard !names.isEmpty else { return hub.usedByNone }
        return String(format: hub.usedByFormat, names.joined(separator: ", "))
    }

    private var statusChip: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(chipText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: return PanelMetricColor.green(for: colorScheme)
        case .missing: return PanelMetricColor.orange(for: colorScheme)
        case .unknown: return .secondary
        }
    }

    private var chipText: String {
        switch status {
        case .granted: return hub.statusGranted
        case .missing: return hub.statusMissing
        case .unknown: return hub.statusUnknown
        }
    }

    private var unusedCard: some View {
        Text(hub.unusedBanner)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
    }

    private var hasRequestFlow: Bool {
        switch permission {
        case .accessibility, .screenRecording, .fullDiskAccess: return true
        case .notifications: return Permissions.shared.notifications == .undetermined
        case .calendar: return Permissions.shared.calendarAccess == .notDetermined
            || Permissions.shared.calendarAccess == .writeOnly
        case .camera: return Permissions.shared.camera == .undetermined
        case .microphone: return Permissions.shared.microphone == .undetermined
        case .filesAndFolders, .automationFinder, .automationTerminal, .automationPlayback, .audioCapture,
             .appManagement: return false
        }
    }

    private func request() {
        switch permission {
        case .accessibility: Permissions.shared.requestAccessibility()
        case .screenRecording: Permissions.shared.requestScreenRecording()
        case .fullDiskAccess: Permissions.shared.requestFullDiskAccess()
        case .notifications:
            Notifier.requestPermission()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Permissions.shared.refresh()
            }
        case .calendar: Permissions.shared.requestCalendar()
        case .camera: Permissions.shared.requestCamera()
        case .microphone: Permissions.shared.requestMicrophone()
        case .filesAndFolders, .automationFinder, .automationTerminal, .automationPlayback, .audioCapture,
             .appManagement:
            break
        }
    }

    private func openSystemSettings() {
        switch permission {
        case .accessibility: Permissions.shared.openAccessibilitySettings()
        case .screenRecording: Permissions.shared.openScreenRecordingSettings()
        case .fullDiskAccess: Permissions.shared.openFullDiskAccessSettings()
        case .filesAndFolders: Permissions.shared.openFilesAndFoldersSettings()
        case .notifications: Permissions.shared.openNotificationSettings()
        case .automationFinder, .automationTerminal, .automationPlayback: Permissions.shared.openAutomationSettings()
        case .audioCapture: Permissions.shared.openAudioCaptureSettings()
        case .microphone: Permissions.shared.openMicrophoneSettings()
        case .calendar: Permissions.shared.openCalendarSettings()
        case .camera: Permissions.shared.openCameraSettings()
        case .appManagement: Permissions.shared.openAppManagementSettings()
        }
    }
}

// MARK: - Titles, descriptions and permission names

extension AppFeature {
    /// What an option that needs this feature says while it is uninstalled.
    func enableReason(_ l10n: L10n) -> String {
        FeatureStrings.notchEditor(l10n.language).enableFeature(hubTitle(l10n.s, hub: FeatureStrings.hub(l10n.language)))
    }

    /// Features, at this feature, for an option that needs it.
    func showInFeatures() {
        SettingsRouter.shared.request(FeatureSettingsDestination(.features), targetFeature: self)
    }

    /// Titles reuse the strings users already see across the app; only names
    /// with no clean existing form live in the hub strings.
    func hubTitle(_ s: Strings, hub: FeatureHubStrings) -> String {
        switch self {
        case .switcher: return s.switcherSection
        case .dockPreview: return s.dockPreviewName
        case .dockClick: return hub.titleDockClick
        case .windowMaximizer: return s.windowMaximizeName
        case .windowLayout: return FeatureStrings.windowLayout(L10n.shared.language).title
        case .autoQuit: return s.autoQuitName
        case .spacesOrder: return s.spacesOrderName
        case .quitWindowProtection: return FeatureStrings.quitProtection(L10n.shared.language).name
        case .scrollInverter: return s.invertMouseScroll
        case .scrollHorizontal: return s.scrollHorizontalName
        case .focusFollowsMouse: return s.focusFollowsMouseName
        case .smoothScroll: return s.smoothScrollName
        case .linearScroll: return s.linearScrollName
        case .mouseAcceleration: return s.mouseAccelerationName
        case .mouseNavigation: return hub.titleMouseNavigation
        case .mouseButtonShortcuts: return FeatureStrings.mouseButtons(L10n.shared.language).pageTitle
        case .middleClick: return s.middleClickSection
        case .keyboardDebounce: return s.keyDebounceName
        case .textSnippets: return FeatureStrings.snippets(L10n.shared.language).pageTitle
        case .superKey: return FeatureStrings.superKey(L10n.shared.language).pageTitle
        case .mouseClickDebounce:
            return FeatureStrings.mouseClickDebounce(L10n.shared.language).title
        case .clipboardHistory: return FeatureStrings.clipboard(L10n.shared.language).title
        case .pastePlain: return s.pastePlainName
        case .finderCutPaste: return s.cutPasteName
        case .finderRename: return FeatureStrings.finderRename(L10n.shared.language).hubTitle
        case .shelf: return s.shelfName
        case .urlCleaner: return s.urlCleanerName
        case .diskImageInstaller:
            return FeatureStrings.diskImageInstaller(L10n.shared.language).title
        case .mixer: return s.mixerSection
        case .soundOutputSwitcher: return s.soundOutputSwitcherTitle
        case .audioPriority: return hub.titleAudioPriority
        case .micMute: return s.micMuteName
        case .musicBlock: return hub.titleMusicBlock
        case .keepAwake: return s.keepAwakeTitle
        case .brightness: return FeatureStrings.brightness(L10n.shared.language).pageTitle
        case .extraBrightness: return s.extraBrightnessName
        case .bluetoothSleep: return FeatureStrings.bluetoothSleep(L10n.shared.language).pageTitle
        case .quickLauncher: return s.launcherName
        case .quickToggles: return FeatureStrings.quickToggles(L10n.shared.language).pageTitle
        case .colorPicker: return s.colorPickerName
        case .screenOCR: return s.ocrName
        case .screenshot: return FeatureStrings.screenshot(L10n.shared.language).pageTitle
        case .screenRecorder: return FeatureStrings.recorder(L10n.shared.language).pageTitle
        case .cameraPreview: return FeatureStrings.cameraPreview(L10n.shared.language).pageTitle
        case .wallpaper: return FeatureStrings.wallpaper(L10n.shared.language).pageTitle
        case .notchGestures: return FeatureStrings.notchGestures(L10n.shared.language).title
        case .notchTimer: return FeatureStrings.notchActivities(L10n.shared.language).timer
        case .notchAccessories: return FeatureStrings.notchActivities(L10n.shared.language).accessories
        case .notchNotifications: return FeatureStrings.notchNotifications(L10n.shared.language).title
        case .notchLyrics: return FeatureStrings.notchMusicExtras(L10n.shared.language).lyrics
        case .notchQueue: return FeatureStrings.notchMusicExtras(L10n.shared.language).queue
        case .notchLiveEqualizer: return FeatureStrings.notchMusicExtras(L10n.shared.language).liveEqualizer
        case .notchDownloads: return FeatureStrings.notchFiles(L10n.shared.language).downloadsTitle
        case .notchCalendar: return FeatureStrings.notchCalendar(L10n.shared.language).title
        case .notchAgents: return FeatureStrings.notchAgents(L10n.shared.language).title
        case .notchWatch: return FeatureStrings.notchWatch(L10n.shared.language).title
        case .notchMascot: return FeatureStrings.notchMascot(L10n.shared.language).title
        case .notch: return FeatureStrings.notch(L10n.shared.language).title
        case .radialMenu: return FeatureStrings.radialMenu(L10n.shared.language).pageTitle
        case .scratchpad: return FeatureStrings.scratchpad(L10n.shared.language).pageTitle
        case .commandBar: return FeatureStrings.commandBar(L10n.shared.language).pageTitle
        case .cleaningMode: return s.cleaningMenuItem
        case .mediaTools: return s.mediaName
        case .cleaner: return s.cleanerName
        case .uninstaller: return s.uninstallerName
        case .killProcess: return FeatureStrings.killProcess(L10n.shared.language).pageTitle
        case .portManager: return FeatureStrings.portManager(L10n.shared.language).title
        case .homebrew: return s.homebrewName
        case .appUpdates: return FeatureStrings.appUpdates(L10n.shared.language).pageTitle
        case .monitorCPU: return s.monitorShowCPU
        case .monitorGPU: return s.monitorShowGPU
        case .monitorMemory: return s.monitorShowMemory
        case .monitorNetwork: return s.monitorShowNetwork
        case .monitorDisk: return s.diskSection
        case .monitorPower: return s.powerSection
        case .connectedDevices: return FeatureStrings.connectedDevices(L10n.shared.language).title
        case .fanControl: return FeatureStrings.fanControl(L10n.shared.language).title
        }
    }

    func hubDescription(_ hub: FeatureHubStrings) -> String {
        switch self {
        case .switcher: return hub.descSwitcher
        case .dockPreview: return hub.descDockPreview
        case .dockClick: return hub.descDockClick
        case .windowMaximizer: return hub.descWindowMaximizer
        case .windowLayout: return hub.descWindowLayout
        case .autoQuit: return hub.descAutoQuit
        case .spacesOrder: return L10n.shared.s.spacesOrderCaption
        case .quitWindowProtection: return FeatureStrings.quitProtection(L10n.shared.language).description
        case .scrollInverter: return hub.descScrollInverter
        case .scrollHorizontal: return L10n.shared.s.scrollHorizontalCaption
        case .focusFollowsMouse: return L10n.shared.s.focusFollowsMouseCaption
        case .smoothScroll: return hub.descSmoothScroll
        case .linearScroll: return L10n.shared.s.linearScrollCaption
        case .mouseAcceleration: return L10n.shared.s.mouseAccelerationCaption
        case .mouseNavigation: return hub.descMouseNavigation
        case .mouseButtonShortcuts: return FeatureStrings.mouseButtons(L10n.shared.language).hubDescription
        case .middleClick: return hub.descMiddleClick
        case .keyboardDebounce: return hub.descKeyboardDebounce
        case .textSnippets: return FeatureStrings.snippets(L10n.shared.language).hubDescription
        case .superKey: return FeatureStrings.superKey(L10n.shared.language).hubDescription
        case .mouseClickDebounce:
            return FeatureStrings.mouseClickDebounce(L10n.shared.language).caption
        case .clipboardHistory: return hub.descClipboardHistory
        case .pastePlain: return hub.descPastePlain
        case .finderCutPaste: return hub.descFinderCutPaste
        case .finderRename: return FeatureStrings.finderRename(L10n.shared.language).hubDescription
        case .shelf: return hub.descShelf
        case .urlCleaner: return hub.descURLCleaner
        case .diskImageInstaller:
            return FeatureStrings.diskImageInstaller(L10n.shared.language).hubDescription
        case .mixer: return hub.descMixer
        case .soundOutputSwitcher: return hub.descSoundOutputSwitcher
        case .audioPriority: return hub.descAudioPriority
        case .micMute: return hub.descMicMute
        case .musicBlock: return hub.descMusicBlock
        case .keepAwake: return hub.descKeepAwake
        case .brightness: return FeatureStrings.brightness(L10n.shared.language).hubDescription
        case .extraBrightness: return hub.descExtraBrightness
        case .bluetoothSleep: return FeatureStrings.bluetoothSleep(L10n.shared.language).hubDescription
        case .quickLauncher: return hub.descQuickLauncher
        case .quickToggles: return FeatureStrings.quickToggles(L10n.shared.language).hubDescription
        case .colorPicker: return hub.descColorPicker
        case .screenOCR: return hub.descScreenOCR
        case .screenshot: return FeatureStrings.screenshot(L10n.shared.language).hubDescription
        case .screenRecorder: return FeatureStrings.recorder(L10n.shared.language).hubDescription
        case .cameraPreview: return FeatureStrings.cameraPreview(L10n.shared.language).hubDescription
        case .wallpaper: return FeatureStrings.wallpaper(L10n.shared.language).hubDescription
        case .notchGestures: return FeatureStrings.notchGestures(L10n.shared.language).description
        case .notchTimer: return FeatureStrings.notchActivities(L10n.shared.language).timerDescription
        case .notchAccessories: return FeatureStrings.notchActivities(L10n.shared.language).accessoryDescription
        case .notchNotifications: return FeatureStrings.notchNotifications(L10n.shared.language).description
        case .notchLyrics: return FeatureStrings.notchMusicExtras(L10n.shared.language).lyricsDescription
        case .notchQueue: return FeatureStrings.notchMusicExtras(L10n.shared.language).queueDescription
        case .notchLiveEqualizer: return FeatureStrings.notchMusicExtras(L10n.shared.language).liveEqualizerDescription
        case .notchDownloads: return FeatureStrings.notchFiles(L10n.shared.language).downloadsDescription
        case .notchCalendar: return FeatureStrings.notchCalendar(L10n.shared.language).description
        case .notchAgents: return FeatureStrings.notchAgents(L10n.shared.language).hubDescription
        case .notchWatch: return FeatureStrings.notchWatch(L10n.shared.language).description
        case .notchMascot: return FeatureStrings.notchMascot(L10n.shared.language).hubDescription
        case .notch: return FeatureStrings.notch(L10n.shared.language).description
        case .radialMenu: return FeatureStrings.radialMenu(L10n.shared.language).hubDescription
        case .scratchpad: return FeatureStrings.scratchpad(L10n.shared.language).hubDescription
        case .commandBar: return FeatureStrings.commandBar(L10n.shared.language).hubDescription
        case .cleaningMode: return hub.descCleaningMode
        case .mediaTools: return hub.descMediaTools
        case .cleaner:
            let description = hub.descCleaner
            guard WhatsAppDownloadSupport.isEnabled else {
                return description
            }
            return description + " · "
                + FeatureStrings.whatsAppDownloads(L10n.shared.language).hubDescription
        case .uninstaller: return hub.descUninstaller
        case .killProcess: return FeatureStrings.killProcess(L10n.shared.language).hubDescription
        case .portManager: return FeatureStrings.portManager(L10n.shared.language).hubDescription
        case .homebrew: return hub.descHomebrew
        case .appUpdates: return FeatureStrings.appUpdates(L10n.shared.language).hubDescription
        case .monitorCPU: return hub.descMonitorCPU
        case .monitorGPU: return hub.descMonitorGPU
        case .monitorMemory: return hub.descMonitorMemory
        case .monitorNetwork: return hub.descMonitorNetwork
        case .monitorDisk: return hub.descMonitorDisk
        case .monitorPower: return hub.descMonitorPower
        case .connectedDevices: return FeatureStrings.connectedDevices(L10n.shared.language).hubDescription
        case .fanControl: return FeatureStrings.fanControl(L10n.shared.language).hubDescription
        }
    }
}

extension AppPermission {
    func name(_ hub: FeatureHubStrings) -> String {
        switch self {
        case .accessibility: return hub.permAccessibility
        case .screenRecording: return hub.permScreenRecording
        case .fullDiskAccess: return hub.permFullDisk
        case .filesAndFolders: return hub.permFilesAndFolders
        case .notifications: return hub.permNotifications
        case .automationFinder: return hub.permAutomationFinder
        case .automationTerminal: return hub.permAutomationTerminal
        case .automationPlayback: return FeatureStrings.notchMusicExtras(L10n.shared.language).automationPermission
        case .audioCapture: return hub.permAudioCapture
        case .microphone: return FeatureStrings.recorder(L10n.shared.language).microphonePermissionName
        case .calendar: return FeatureStrings.notchCalendar(L10n.shared.language).title
        case .camera: return FeatureStrings.cameraPreview(L10n.shared.language).permName
        case .appManagement: return FeatureStrings.settingsCategories(L10n.shared.language).appManagement
        }
    }

    func explainer(_ hub: FeatureHubStrings) -> String {
        switch self {
        case .accessibility: return hub.explainAccessibility
        case .screenRecording: return hub.explainScreenRecording
        case .fullDiskAccess: return hub.explainFullDisk
        case .filesAndFolders: return hub.explainFilesAndFolders
        case .notifications: return hub.explainNotifications
        case .automationFinder: return hub.explainAutomationFinder
        case .automationTerminal: return hub.explainAutomationTerminal
        case .automationPlayback: return FeatureStrings.notchMusicExtras(L10n.shared.language).automationExplanation
        case .audioCapture: return hub.explainAudioCapture
        case .microphone:
            return FeatureStrings.recorder(L10n.shared.language).microphonePermissionExplain
        case .calendar: return FeatureStrings.notchCalendar(L10n.shared.language).permission
        case .camera: return FeatureStrings.cameraPreview(L10n.shared.language).permExplain
        case .appManagement: return hub.explainAppManagement
        }
    }
}
