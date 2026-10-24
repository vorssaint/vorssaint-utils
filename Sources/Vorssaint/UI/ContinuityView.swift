// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import SwiftUI
import ApplicationServices

@MainActor struct ContinuityCard: View {
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(FeatureStrings.continuity(l10n.language).title)
            VStack(alignment: .leading, spacing: 10) {
                ContinuityControls()
                ContinuityOptions()
            }
            .panelCard()
        }
    }
}

@MainActor struct ContinuityControls: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var workflow = ContinuityService.shared.workflow
    @AppStorage(DefaultsKey.continuityHotspot) private var hotspot = ""
    private var strings: ContinuityStrings { FeatureStrings.continuity(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if workflow.busy {
                    ProgressView().controlSize(.small)
                    Text(status).font(.caption)
                    Spacer()
                    Button(strings.cancel) { ContinuityService.shared.cancel() }
                        .keyboardShortcut(.cancelAction)
                } else if workflow.phase == .failed(.brightness) {
                    Text(status).font(.caption)
                    Spacer()
                    Button(strings.restore) { ContinuityService.shared.cancel() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button { ContinuityService.shared.start() } label: {
                        Label(strings.start, systemImage: "iphone.and.arrow.forward")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(hotspot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("continuity-start")
                    if case .failed = workflow.phase {
                        Button(strings.cancel) { ContinuityService.shared.cancel() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if hotspot.isEmpty { Text(strings.setup).font(.caption).foregroundStyle(.secondary) }
            if case .failed(let error) = workflow.phase {
                Text(strings.message(for: error)).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var status: String {
        switch workflow.phase {
        case .connecting: return strings.connecting
        case .quitting: return strings.quitting
        case .countdown(let seconds): return String(format: strings.countdown, seconds)
        case .active: return strings.active
        default: return strings.title
        }
    }
}

@MainActor struct ContinuityOptions: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var workflow = ContinuityService.shared.workflow
    @AppStorage(DefaultsKey.continuityHotspot) private var hotspot = ""
    @AppStorage(DefaultsKey.continuityDuration) private var duration = 60
    @State private var apps = UserDefaults.standard.stringArray(forKey: DefaultsKey.continuityQuitApps) ?? []
    @ObservedObject private var service = ContinuityService.shared
    private var strings: ContinuityStrings { FeatureStrings.continuity(l10n.language) }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Picker(l10n.s.keepAwakeTitle, selection: $duration) {
                    ForEach(DurationPicker.choices, id: \.self) { minutes in
                        Text(DurationPicker.shortTitle(for: minutes, l10n.s, l10n.language)).tag(minutes)
                    }
                }
                Picker(strings.hotspot, selection: $hotspot) {
                    Text(strings.chooseHotspot).tag("")
                    ForEach(Array(Set(service.hotspots + (hotspot.isEmpty ? [] : [hotspot]))).sorted(), id: \.self) {
                        Text($0).tag($0)
                    }
                }
                Button(strings.discover) { service.discover() }
                    .disabled(service.discovering)
                if service.discovering { ProgressView().controlSize(.small) }
                if let failure = service.discoveryFailure {
                    Text(strings.message(for: failure)).font(.caption).foregroundStyle(.orange)
                }
                if service.discoveryFailure == .permission {
                    Button(l10n.s.permissionRequest) {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                    }
                }
                AppBundleList(title: strings.apps, caption: strings.appsCaption,
                              addTitle: strings.addApp, removeLabel: strings.removeApp,
                              bundleIDs: apps, reachesEveryApp: true,
                              onAdd: { save(apps + [$0]) },
                              onRemove: { id in save(apps.filter { $0 != id }) })
                Text(strings.help).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
            .disabled(workflow.busy)
        } label: {
            Text(l10n.s.keepAwakeOptions)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .onAppear { duration = Defaults.sanitizedDefaultDuration(duration) }
    }

    private func save(_ ids: [String]) {
        apps = Defaults.sanitizedBundleIdentifierList(ids).filter(ContinuityService.canQuit)
        UserDefaults.standard.set(apps, forKey: DefaultsKey.continuityQuitApps)
    }


}

extension ContinuityStrings {
    func message(for failure: ContinuityFailure) -> String {
        switch failure {
        case .permission: return permission
        case .unavailable: return unavailable
        case .connection: return connectionFailed
        case .quit: return quitFailed
        case .brightness: return brightnessFailed
        }
    }
}
