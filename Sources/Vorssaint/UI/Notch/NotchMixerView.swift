// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The mixer as a desk: the output fader on the left, one fader per app
/// running sideways, pinned ones first. Every row action of the panel's list
/// is here: the app's menu pins, moves and routes it, Command-drag reorders,
/// a click on a level types a new one. A tab at the end turns the desk into
/// the options: where sound effects and the microphone go, the switches the
/// panel keeps under Options, and the hidden rows.
struct NotchMixerView: View {
    let size: CGSize
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.mixerAppArrangement) private var arrangementValue = ""
    @AppStorage(DefaultsKey.mixerHideInactiveApps) private var hideInactiveApps = false
    @State private var showingOptions = false
    @State private var editingVolumeID: String?
    @State private var draggingAppID: String?
    @State private var dropTarget: MixerAppDropTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let masterWidth: CGFloat = 108
    private static let columnWidth: CGFloat = 72
    private static let tabWidth: CGFloat = 28

    private var arrangement: MixerAppArrangement { MixerAppArrangement(rawValue: arrangementValue) }

    /// The same order and the same hidden rows as the panel's list.
    private var apps: [MixerApp] {
        arrangement.ordered(mixer.apps, identity: { $0.persistenceID }).filter { app in
            MixerRoutingSupport.shouldShowApp(isPlaying: app.isPlaying, volume: app.volume,
                                              selectedOutputDeviceUID: app.selectedOutputDeviceUID,
                                              hideInactiveApps: hideInactiveApps)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showingOptions {
                NotchMixerOptions(editingVolumeID: $editingVolumeID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NotchMasterFader(editingVolumeID: $editingVolumeID).frame(width: Self.masterWidth)
                Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
                    .accessibilityHidden(true)
                desk.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack {
                NotchIconButton(symbol: showingOptions ? "xmark" : "slider.horizontal.3",
                                title: showingOptions ? l10n.s.menuClose : l10n.s.keepAwakeOptions,
                                selected: showingOptions) {
                    editingVolumeID = nil
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { showingOptions.toggle() }
                }
                Spacer(minLength: 0)
            }
            .frame(width: Self.tabWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var desk: some View {
        if !AppVolumeMixer.isSupported {
            NotchEmptyView(symbol: "slider.vertical.3", message: l10n.s.mixerUnavailable)
        } else if mixer.needsPermission {
            permission
        } else if apps.isEmpty {
            NotchEmptyView(symbol: "slider.vertical.3", message: l10n.s.mixerEmpty)
        } else {
            let apps = apps
            let ids = apps.compactMap(\.persistenceID)
            NotchRail(items: apps, rows: 1, itemWidth: Self.columnWidth,
                      width: size.width - Self.masterWidth - Self.tabWidth - 31) { app in
                NotchAppFader(app: app, height: size.height, editingVolumeID: $editingVolumeID,
                              isPinned: arrangement.isPinned(app.persistenceID),
                              togglePin: { updateArrangement { $0.togglePin(app.persistenceID ?? "") } },
                              moveBack: moveAction(for: app, offset: -1, ids: ids),
                              moveForward: moveAction(for: app, offset: 1, ids: ids))
                    .modifier(MixerAppReorderModifier(
                        id: app.persistenceID,
                        icon: ResponsibleProcess.icon(for: app.ownerPid, pointSize: 32),
                        draggingID: $draggingAppID,
                        target: $dropTarget,
                        dragChanged: { NotchService.shared.fileDragChanged($0, internalDrag: true) },
                        canMove: { source, target in
                            ids.contains(source) && ids.contains(target)
                                && arrangement.isPinned(source) == arrangement.isPinned(target)
                        },
                        move: { source, target, after in
                            updateArrangement { $0.move(source, to: target, after: after, visibleIDs: ids) }
                        },
                        sideways: true))
                    .help(FeatureStrings.mixer(l10n.language).arrange)
            }
        }
    }

    private func updateArrangement(_ change: (inout MixerAppArrangement) -> Void) {
        var updated = arrangement
        change(&updated)
        arrangementValue = updated.rawValue
    }

    private func moveAction(for app: MixerApp, offset: Int, ids: [String]) -> (() -> Void)? {
        guard let id = app.persistenceID,
              arrangement.neighbor(of: id, offset: offset, visibleIDs: ids) != nil else { return nil }
        return { updateArrangement { $0.move(id, offset: offset, visibleIDs: ids) } }
    }

    private var permission: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.badge.exclamationmark").font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.s.mixerPermissionBody).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(l10n.s.permissionOpenSettings) { Permissions.shared.openAudioCaptureSettings() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.horizontal, 8)
    }
}

/// A level that reads as text and, clicked, takes a typed one: the same
/// editor as the panel's rows, so the two agree on what a "150" means.
private struct NotchEditablePercent: View {
    let percent: Int
    let maximum: Int
    let editorID: String
    @Binding var editingID: String?
    let label: String
    var tint: Color = .secondary
    var boosting = false
    var width: CGFloat = 40
    let commit: (Double) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        EditableVolumePercent(currentPercent: percent, maximumPercent: maximum, width: width,
                              editorID: editorID, editingID: $editingID, accessibilityLabel: label) {
            HStack(spacing: 1) {
                if boosting {
                    Image(systemName: "bolt.fill").font(.system(size: 7, weight: .bold)).foregroundStyle(tint)
                }
                Text("\(percent)%")
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: percent)
            }
        } onCommit: { commit($0) }
        .frame(height: 18)
    }
}

/// The system output: its device, level and mute, in the same column shape
/// as the apps beside it.
private struct NotchMasterFader: View {
    @Binding var editingVolumeID: String?
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var level: Double? { mixer.systemOutputVolume.map { mixer.systemOutputMuted == true ? 0 : $0 } }
    private var muted: Bool { mixer.systemOutputMuted == true }

    var body: some View {
        VStack(spacing: 4) {
            Button {
                if let muted = mixer.systemOutputMuted { mixer.requestOutputAdjustment(muted: !muted) }
            } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(muted ? Color.red : Color.white)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: muted)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 14))
            .disabled(mixer.systemOutputMuted == nil)
            .accessibilityLabel(muted ? l10n.s.actionUnmute : l10n.s.actionMute)
            NotchOutputDeviceMenu(width: 100, lines: 2)
            if let level {
                NotchLevelSlider(value: Binding(get: { level }, set: { mixer.requestOutputAdjustment(volume: $0) }),
                                 label: l10n.s.mixerSystemOutputTitle, vertical: true)
                    .frame(width: 24)
                    .frame(maxHeight: .infinity)
                NotchEditablePercent(percent: Int((level * 100).rounded()), maximum: 100,
                                     editorID: "notch-system-output", editingID: $editingVolumeID,
                                     label: l10n.s.mixerSystemOutputTitle) {
                    mixer.requestOutputAdjustment(volume: $0)
                }
            } else {
                Text(l10n.s.mixerOutputUnavailable).font(.system(size: 10)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct NotchOutputDeviceMenu: View {
    var width: CGFloat = 150
    var lines = 1
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var l10n = L10n.shared
    private var deviceName: String {
        mixer.outputDevices.first(where: { $0.uid == mixer.currentOutputDeviceUID })?.name ?? l10n.s.mixerOutputUnavailable
    }

    var body: some View {
        NotchDeviceMenu(title: l10n.s.mixerSystemOutputTitle, current: mixer.outputSwitchError ?? deviceName,
                        width: width, lines: lines, alignment: lines > 1 ? .center : .trailing,
                        items: mixer.outputDevices.filter(\.canBeDefaultOutput).map { device in
                            NotchMenuItem(title: device.name, checked: device.uid == mixer.currentOutputDeviceUID) {
                                _ = mixer.setUniversalOutputDeviceUID(device.uid)
                            }
                        })
    }
}

/// Everything the desk leaves out, in one list that scrolls down: where the
/// output, sound effects and the microphone go, the microphone's level, and
/// the panel's options under them.
private struct NotchMixerOptions: View {
    @Binding var editingVolumeID: String?
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var input = AudioInputDeviceManager.shared
    @ObservedObject private var micMute = MicMuteService.shared
    @ObservedObject private var l10n = L10n.shared
    private var outputDevices: [MixerOutputDevice] { mixer.outputDevices.filter(\.canBeDefaultOutput) }
    private var soundEffectsDevices: [MixerOutputDevice] { mixer.outputDevices.filter(\.canBeDefaultSystemOutput) }
    private var soundEffectsName: String {
        mixer.outputDevices.first(where: { $0.uid == mixer.currentSystemSoundOutputDeviceUID })?.name ?? l10n.s.mixerOutputUnavailable
    }
    private var microphoneName: String {
        guard let uid = input.preferredInputDeviceUID else { return l10n.s.mixerOutputDefault }
        return input.inputDevices.first(where: { $0.uid == uid })?.name ?? l10n.s.mixerInputUnavailable
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    row(l10n.s.mixerSystemOutputTitle, symbol: "speaker.wave.2") { NotchOutputDeviceMenu(width: 200) }
                    if outputDevices.isEmpty {
                        message(l10n.s.mixerSystemOutputNoDevices, systemImage: "speaker.slash")
                    }
                    if let error = mixer.outputSwitchError {
                        message(String(format: l10n.s.mixerSystemOutputErrorFormat, error),
                                systemImage: "exclamationmark.triangle")
                    }
                    row(l10n.s.mixerSoundEffectsOutputTitle, symbol: "bell") {
                        NotchDeviceMenu(title: l10n.s.mixerSoundEffectsOutputTitle, current: soundEffectsName,
                                        width: 200, lines: 1, alignment: .trailing,
                                        items: soundEffectsDevices.map { device in
                                            NotchMenuItem(title: device.name,
                                                          checked: device.uid == mixer.currentSystemSoundOutputDeviceUID) {
                                                _ = mixer.setSystemSoundOutputDeviceUID(device.uid)
                                            }
                                        })
                    }
                    if soundEffectsDevices.isEmpty {
                        message(l10n.s.mixerSystemOutputNoDevices, systemImage: "bell.slash")
                    }
                    microphone
                }
                Divider().overlay(.white.opacity(0.12))
                MixerOptionsControls()
            }
            .padding(.trailing, 4)
            .padding(.bottom, 4)
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var microphone: some View {
        row(l10n.s.mixerInputTitle, symbol: micMute.isMuted ? "mic.slash" : "mic") {
            NotchDeviceMenu(title: l10n.s.mixerInputTooltip, current: microphoneName, width: 200, lines: 1, alignment: .trailing,
                            items: [NotchMenuItem(title: l10n.s.mixerOutputDefault, checked: input.preferredInputDeviceUID == nil) {
                                input.setPreferredInputDeviceUID(nil)
                            }] + input.inputDevices.map { device in
                                NotchMenuItem(title: device.name, checked: device.uid == input.preferredInputDeviceUID) {
                                    input.setPreferredInputDeviceUID(device.uid)
                                }
                            } + (input.preferredUnavailable && input.preferredInputDeviceUID != nil
                                 ? [NotchMenuItem(title: l10n.s.mixerInputUnavailable, checked: true)] : []))
        }
        if let volume = input.inputVolume {
            HStack(spacing: 8) {
                Button(action: micMute.toggle) {
                    Image(systemName: micMute.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(micMute.isMuted ? Color.red : Color.white)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: 6))
                .accessibilityLabel(micMute.isMuted ? l10n.s.micUnmuteName : l10n.s.micMuteName)
                NotchLevelSlider(value: Binding(get: { volume }, set: { input.setInputVolume($0) }),
                                 label: l10n.s.mixerInputTitle)
                    .frame(height: 22)
                    .disabled(micMute.isMuted)
                NotchEditablePercent(percent: Int((volume * 100).rounded()), maximum: 100,
                                     editorID: "notch-microphone-input", editingID: $editingVolumeID,
                                     label: l10n.s.mixerInputTitle) {
                    input.setInputVolume($0)
                }
                .disabled(micMute.isMuted)
            }
            .frame(height: 22)
        }
        if input.inputDevices.isEmpty {
            message(l10n.s.mixerInputNoDevices, systemImage: "mic.slash")
        } else if input.preferredUnavailable {
            message(l10n.s.mixerInputFallback, systemImage: "mic.badge.xmark")
        } else if let lastError = input.lastError {
            message(String(format: l10n.s.mixerInputErrorFormat, lastError), systemImage: "exclamationmark.triangle")
        }
    }

    private func row<Menu: View>(_ title: String, symbol: String, @ViewBuilder menu: () -> Menu) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).frame(width: 18)
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            menu()
        }
        .frame(height: 22)
    }

    private func message(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One app: icon, name, fader and level. The track ticks at unity, and the
/// fader turns amber in the boost range the way the panel's slider does.
/// The panel row's menu, output picker and context menu fold into the
/// column's own menu, with the route shown as a badge on the icon.
private struct NotchAppFader: View {
    let app: MixerApp
    let height: CGFloat
    @Binding var editingVolumeID: String?
    let isPinned: Bool
    let togglePin: () -> Void
    let moveBack: (() -> Void)?
    let moveForward: (() -> Void)?
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var l10n = L10n.shared
    private var strings: MixerFeatureStrings { FeatureStrings.mixer(l10n.language) }
    private var percent: Int { Int((app.volume * 100).rounded()) }
    private var boosting: Bool { percent > 100 }
    private var muted: Bool { app.volume <= 0.001 }
    private var routed: Bool { !app.isBypassed && app.selectedOutputDeviceUID != nil }
    private var routeDescription: String {
        if app.outputDeviceUnavailable { return l10n.s.mixerOutputFallback }
        return mixer.outputDevices.first(where: { $0.uid == app.selectedOutputDeviceUID })?.name
            ?? l10n.s.mixerOutputUnavailable
    }

    var body: some View {
        VStack(spacing: 4) {
            icon
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .overlay(alignment: .topTrailing) {
                    if app.persistenceID != nil || !app.isBypassed { actionsMenu }
                }
            HStack(spacing: 3) {
                if isPinned {
                    Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.secondary)
                        .accessibilityLabel(strings.pinFirst)
                }
                Text(app.name)
                    .font(.system(size: 10, weight: .medium)).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 14)
            if app.isBypassed {
                // Zoom and pro audio apps manage their own sound: listed so
                // their absence never reads as a bug, never tapped.
                Text(l10n.s.mixerBypassedCaption)
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NotchLevelSlider(value: Binding(get: { app.volume }, set: { mixer.setVolume($0, for: app) }),
                                 label: app.name, range: 0...AppVolumeMixer.maxVolume,
                                 tint: boosting ? .orange : .white, vertical: true, marker: 1)
                    .frame(width: 24)
                    .frame(maxHeight: .infinity)
                HStack(spacing: 0) {
                    NotchEditablePercent(percent: percent, maximum: Int(AppVolumeMixer.maxVolume * 100),
                                         editorID: "notch-app:\(app.id)", editingID: $editingVolumeID,
                                         label: app.name, tint: boosting ? .orange : .secondary, boosting: boosting) {
                        mixer.setVolume($0, for: app)
                    }
                    // Back to unity, in the same spot the panel's row keeps it;
                    // the spot stays reserved so the row never shifts.
                    Button { mixer.setVolume(1, for: app) } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(boosting ? Color.orange : Color.secondary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(NotchButtonStyle(cornerRadius: 5))
                    .opacity(percent == 100 ? 0 : 1)
                    .disabled(percent == 100)
                    .help(l10n.s.mixerResetTooltip)
                    .accessibilityLabel(l10n.s.mixerResetTooltip)
                    Button { mixer.toggleMute(app) } label: {
                        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(muted ? Color.red : Color.secondary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(NotchButtonStyle(cornerRadius: 5))
                    .accessibilityLabel(muted ? l10n.s.actionUnmute : l10n.s.actionMute)
                }
                .frame(height: 18)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .contextMenu { actions }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.name)
        .accessibilityValue("\(percent)%")
        .accessibilityAction(named: Text(strings.moveLeft)) { moveBack?() }
        .accessibilityAction(named: Text(strings.moveRight)) { moveForward?() }
    }

    private var icon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(nsImage: ResponsibleProcess.icon(for: app.ownerPid, pointSize: 32))
                .resizable()
                .frame(width: 28, height: 28)
            if app.isPlaying {
                Circle().fill(.green).frame(width: 7, height: 7)
                    .overlay(Circle().stroke(.black, lineWidth: 1.2))
                    .offset(x: 1, y: 1)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottomLeading) {
            // An app sent to its own device wears the route on its icon; the
            // panel's row shows the picker itself, which the column has no
            // room for.
            if routed {
                Image(systemName: app.outputDeviceUnavailable ? "exclamationmark.triangle.fill" : "arrow.triangle.branch")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(app.outputDeviceUnavailable ? Color.orange : Color.white)
                    .frame(width: 12, height: 12)
                    .background(.black, in: Circle())
                    .offset(x: -2, y: 1)
                    .help(routeDescription)
                    .accessibilityLabel(routeDescription)
            }
        }
    }

    private var actionsMenu: some View {
        Menu { actions } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(strings.actions)
        .accessibilityLabel("\(strings.actions): \(app.name)")
    }

    @ViewBuilder private var actions: some View {
        if app.persistenceID != nil {
            Button(action: togglePin) {
                Label(isPinned ? strings.unpin : strings.pinFirst, systemImage: isPinned ? "pin.slash" : "pin")
            }
            Button { moveBack?() } label: { Label(strings.moveLeft, systemImage: "arrow.left") }
                .disabled(moveBack == nil)
            Button { moveForward?() } label: { Label(strings.moveRight, systemImage: "arrow.right") }
                .disabled(moveForward == nil)
        }
        if !app.isBypassed {
            if app.persistenceID != nil { Divider() }
            Picker(l10n.s.mixerOutputTooltip, selection: outputSelection) {
                Text(l10n.s.mixerOutputDefault).tag(MixerRoutingSupport.systemDefaultSelectionID)
                ForEach(mixer.outputDevices) { device in
                    Text(device.isDefault ? "\(device.name) (\(l10n.s.mixerOutputCurrent))" : device.name).tag(device.uid)
                }
                if let selected = app.selectedOutputDeviceUID, app.outputDeviceUnavailable {
                    Text(l10n.s.mixerOutputUnavailable).tag(selected)
                }
            }
            .pickerStyle(.menu)
            Divider()
            Button(l10n.s.mixerResetTooltip) { mixer.setVolume(1, for: app) }
                .disabled(percent == 100)
        }
        if app.persistenceID != nil {
            Divider()
            Button(l10n.s.mixerHideFromList) { mixer.hideFromList(app) }
        }
    }

    private var outputSelection: Binding<String> {
        Binding(
            get: { app.selectedOutputDeviceUID ?? MixerRoutingSupport.systemDefaultSelectionID },
            set: { selection in
                mixer.setOutputDeviceUID(selection == MixerRoutingSupport.systemDefaultSelectionID ? nil : selection,
                                         for: app)
            }
        )
    }
}
