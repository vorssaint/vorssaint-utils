// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Based on Textream by Fatih Kadir Akın (MIT License)

import AppKit
import CoreImage.CIFilterBuiltins
import Speech
import SwiftUI

// MARK: - Haptic Feedback Performer

private func triggerHaptic() {
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
}

private struct TeleprompterPreviewSettingsSnapshot: Equatable {
    let values: [String]

    @MainActor
    init(_ service: TeleprompterService) {
        values = [
            service.fontFamily.rawValue, service.fontSize.rawValue,
            service.highlightColor.rawValue, service.cueColor.rawValue, service.cueBrightness.rawValue,
            service.guidanceMode.rawValue,
            service.readingPosition.rawValue, String(service.showParagraphDividers),
            String(service.showLastSpokenWords), String(service.windowWidth), String(service.windowHeight),
            String(service.showElapsedTime),
            String(service.autoNextPage), service.externalDisplayMode.rawValue,
            service.externalMirrorAxis.rawValue
        ]
    }
}

// MARK: - Inline Info / Tooltip Badge

struct InfoTip: View {
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowing, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(.system(size: 11))
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle) {
                        isShowing = false
                        action()
                    }
                    .font(.system(size: 11, weight: .medium))
                }
            }
            .frame(width: 250, alignment: .leading)
            .padding(12)
        }
    }
}

// MARK: - Circular Color Pickers (Radial Menu Style)

struct TeleprompterHighlightColorPicker: View {
    @Binding var selection: TeleprompterHighlightColorPreset
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 7) {
            ForEach(TeleprompterHighlightColorPreset.allCases) { item in
                Button {
                    selection = item
                    triggerHaptic()
                } label: {
                    ZStack {
                        Circle()
                            .fill(item.color)
                            .frame(width: 16, height: 16)
                        if selection == item {
                            Circle()
                                .strokeBorder(Color.white.opacity(colorScheme == .light ? 0.9 : 0.8), lineWidth: 2)
                                .frame(width: 12, height: 12)
                            Circle()
                                .strokeBorder(item.color, lineWidth: 1.5)
                                .frame(width: 20, height: 20)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(item.label)
                .accessibilityLabel(item.label)
            }
        }
    }
}

struct TeleprompterCueColorPicker: View {
    @Binding var selection: TeleprompterCueColorPreset
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 7) {
            ForEach(TeleprompterCueColorPreset.allCases) { item in
                Button {
                    selection = item
                    triggerHaptic()
                } label: {
                    ZStack {
                        Circle()
                            .fill(item.color)
                            .frame(width: 16, height: 16)
                        if selection == item {
                            Circle()
                                .strokeBorder(Color.white.opacity(colorScheme == .light ? 0.9 : 0.8), lineWidth: 2)
                                .frame(width: 12, height: 12)
                            Circle()
                                .strokeBorder(item.color, lineWidth: 1.5)
                                .frame(width: 20, height: 20)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(item.label)
                .accessibilityLabel(item.label)
            }
        }
    }
}

// MARK: - Inline Waveform for Dictation

struct TeleprompterWaveformView: View {
    let levels: [CGFloat]
    var color: Color = .red
    var isActive: Bool = false

    private let barCount = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive)) { timeline in
            let samples = Array(levels.suffix(barCount))
            let paddedSamples = Array(repeating: CGFloat.zero, count: barCount - samples.count) + samples
            let warmingUp = isActive && levels.count < 6
            let phase = timeline.date.timeIntervalSinceReferenceDate * 6

            HStack(alignment: .center, spacing: 1.5) {
                ForEach(0..<barCount, id: \.self) { index in
                    let animatedLevel = 0.12 + (sin(phase + Double(index) * 0.72) + 1) * 0.22
                    let level = warmingUp ? CGFloat(animatedLevel) : paddedSamples[index]
                    let normalized = pow(min(1, max(0, level)), 0.6)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(0.9))
                        .frame(width: 2, height: max(3.5, normalized * 16))
                }
            }
            .frame(height: 16)
            .animation(.easeOut(duration: 0.08), value: levels)
        }
    }
}

// MARK: - Native Page Action Menu with SF Symbol Icons

struct PageActionMenuButton: NSViewRepresentable {
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let canDelete: Bool
    let canDuplicate: Bool

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Page Actions")
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.onEdit = onEdit
        context.coordinator.onDuplicate = onDuplicate
        context.coordinator.onDelete = onDelete
        context.coordinator.canDelete = canDelete
        context.coordinator.canDuplicate = canDuplicate
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onEdit: onEdit, onDuplicate: onDuplicate, onDelete: onDelete,
                    canDelete: canDelete, canDuplicate: canDuplicate)
    }

    final class Coordinator: NSObject {
        var onEdit: () -> Void
        var onDuplicate: () -> Void
        var onDelete: () -> Void
        var canDelete: Bool
        var canDuplicate: Bool

        init(onEdit: @escaping () -> Void, onDuplicate: @escaping () -> Void, onDelete: @escaping () -> Void,
             canDelete: Bool, canDuplicate: Bool) {
            self.onEdit = onEdit
            self.onDuplicate = onDuplicate
            self.onDelete = onDelete
            self.canDelete = canDelete
            self.canDuplicate = canDuplicate
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()

            let editItem = NSMenuItem(title: "Edit Page...", action: #selector(editAction), keyEquivalent: "")
            editItem.target = self
            if let img = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Edit") {
                img.isTemplate = true
                editItem.image = img
            }
            menu.addItem(editItem)

            let dupItem = NSMenuItem(title: "Duplicate Page", action: #selector(duplicateAction), keyEquivalent: "")
            dupItem.target = self
            if let img = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Duplicate") {
                img.isTemplate = true
                dupItem.image = img
            }
            dupItem.isEnabled = canDuplicate
            menu.addItem(dupItem)

            menu.addItem(NSMenuItem.separator())

            let delItem = NSMenuItem(title: "Delete Page", action: #selector(deleteAction), keyEquivalent: "")
            delItem.target = self
            if let img = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete") {
                img.isTemplate = true
                delItem.image = img
            }
            delItem.isEnabled = canDelete
            menu.addItem(delItem)

            let location = NSPoint(x: 0, y: sender.bounds.height + 4)
            menu.popUp(positioning: nil, at: location, in: sender)
        }

        @objc func editAction() { onEdit() }
        @objc func duplicateAction() { onDuplicate() }
        @objc func deleteAction() { onDelete() }
    }
}

// MARK: - Teleprompter Settings View

struct TeleprompterSettings: View {
    @ObservedObject private var service = TeleprompterService.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var dictation = TeleprompterService.shared.dictationManager

    @AppStorage(DefaultsKey.teleprompterEnabled) private var teleprompterEnabled = true
    @AppStorage(DefaultsKey.teleprompterShortcutEnabled) private var teleprompterShortcutEnabled = true
    @AppStorage(DefaultsKey.teleprompterShortcut) private var teleprompterShortcutRaw =
        GlobalShortcut.teleprompterDefault.storageValue

    @State private var inputDevices: [AudioInputDevice] = AudioInputDevice.allInputDevices()
    @State private var editingPageIndex: Int? = nil
    @State private var pageToDelete: Int? = nil
    @State private var confirmingReset = false
    @State private var showingImportError = false
    @State private var importErrorMessage: String? = nil
    @State private var importAlertTitle = "Import Failed"
    @State private var lastPreviewSettings: TeleprompterPreviewSettingsSnapshot?
    @State private var previewRefreshTask: Task<Void, Never>?
    @State private var isEditingScrollSpeed = false
    @State private var lastScrollSpeedHapticStep: Int?

    private var strings: TeleprompterStrings {
        FeatureStrings.teleprompter(l10n.language)
    }

    private var pagesList: [String] {
        if service.pages.isEmpty {
            return [service.text]
        }
        return service.pages
    }

    private func closeAppearancePreviewIfActive() {
        if !service.isRunning && service.isPreviewingInNotch {
            service.closeNotchPreview()
        }
    }

    var body: some View {
        Form {
            // MARK: - 1. Master Section
            Section {
                Toggle(isOn: $teleprompterEnabled) {
                    HStack(spacing: 4) {
                        Text("Enable the Teleprompter")
                        InfoTip(text: strings.hubDescription)
                    }
                }

                HStack {
                    Text("Global Shortcut")
                    Spacer()
                    ShortcutRecorderButton(
                        shortcut: GlobalShortcut(storageValue: teleprompterShortcutRaw) ?? .teleprompterDefault,
                        isEnabled: teleprompterEnabled && teleprompterShortcutEnabled,
                        waitingTitle: l10n.s.shortcutPressKeys,
                        invalidAction: { },
                        captureAction: { saved in
                            teleprompterShortcutRaw = saved.storageValue
                            service.syncWithPreferences()
                        }
                    )
                    .frame(width: 108)
                    .disabled(!teleprompterEnabled || !teleprompterShortcutEnabled)

                    Toggle("", isOn: $teleprompterShortcutEnabled)
                        .labelsHidden()
                        .onChange(of: teleprompterShortcutEnabled) { _, _ in
                            service.syncWithPreferences()
                        }
                        .disabled(!teleprompterEnabled)
                }

            } header: {
                Text(strings.title)
            }

            .settingsSectionAnchor(.teleprompter, cornerRadius: 16)

            // MARK: - 2. Script Studio & Notes Section
            Section {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        ForEach(pagesList.indices, id: \.self) { idx in
                            pageRow(index: idx)
                            if idx < pagesList.count - 1 {
                                Divider()
                                    .padding(.leading, 8)
                            }
                        }
                    }
                    // Keep the overlay scrollbar clear of the trailing page
                    // action buttons and their circular hit targets.
                    .padding(.vertical, 2)
                    .padding(.trailing, 16)
                }
                .frame(height: min(CGFloat(pagesList.count) * 36, 252))

                Toggle("Auto Next Page", isOn: $service.autoNextPage)
                    .onChange(of: service.autoNextPage) { _, _ in service.savePreferences() }
                    .padding(.top, 4)

                HStack(spacing: 10) {
                    Button {
                        addNewPage()
                    } label: {
                        Label("Add Page", systemImage: "plus")
                    }

                    Button {
                        chooseAndImportPPTX()
                    } label: {
                        Label("Import .pptx...", systemImage: "doc.badge.plus")
                    }

                    Spacer(minLength: 0)

                    Button {
                        if service.isPreviewingInNotch {
                            service.closeNotchPreview()
                        } else {
                            lastPreviewSettings = TeleprompterPreviewSettingsSnapshot(service)
                            service.previewInNotch(autoCloseAfter: 4)
                        }
                    } label: {
                        Label(service.isPreviewingInNotch ? "Close Preview" : "Preview",
                              systemImage: service.isPreviewingInNotch ? "xmark" : "eye")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!NotchSupport.isEnabled() || service.isRunning)
                    .help("Preview the teleprompter in the notch.")

                    Button {
                        service.openPrompter()
                        triggerHaptic()
                    } label: {
                        Label("Open Prompter", systemImage: "rectangle.topthird.inset.filled")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!NotchSupport.isEnabled())
                    .help(NotchSupport.isEnabled()
                          ? "Open the teleprompter in the notch. Start reading from its ready state."
                          : "Enable the notch in Notch settings to use the teleprompter.")
                }
                .padding(.top, 4)
            } header: {
                Text("Script Studio & Notes")
            }
            .disabled(!teleprompterEnabled)

            // MARK: - 3. Appearance Section
            Section {
                Picker("Font Family", selection: $service.fontFamily) {
                    ForEach(TeleprompterFontFamilyPreset.allCases) { family in
                        Text(family.label).tag(family)
                    }
                }
                .onChange(of: service.fontFamily) { _, _ in service.savePreferences() }

                Picker("Font Size", selection: $service.fontSize) {
                    ForEach(TeleprompterFontSizePreset.allCases) { size in
                        Text("\(size.label) (\(Int(size.pointSize)) pt)").tag(size)
                    }
                }
                .onChange(of: service.fontSize) { _, _ in service.savePreferences() }

                HStack {
                    Text("Highlight Color")
                    Spacer()
                    TeleprompterHighlightColorPicker(selection: $service.highlightColor)
                        .onChange(of: service.highlightColor) { _, _ in service.savePreferences() }
                }

                HStack {
                    Text("Cue Color")
                    Spacer()
                    TeleprompterCueColorPicker(selection: $service.cueColor)
                        .onChange(of: service.cueColor) { _, _ in service.savePreferences() }
                }

                Picker("Cue Brightness", selection: $service.cueBrightness) {
                    ForEach(TeleprompterCueBrightness.allCases) { bright in
                        Text(bright.label).tag(bright)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: service.cueBrightness) { _, _ in
                    triggerHaptic()
                    service.savePreferences()
                }

                HStack {
                    HStack(spacing: 4) {
                        Text("Reading Position")
                        InfoTip(text: "Anchor position of the active reading line within the notch.")
                    }
                    Spacer()
                    Picker("", selection: $service.readingPosition) {
                        ForEach(TeleprompterReadingPosition.allCases) { pos in
                            Text(pos.label).tag(pos)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: service.readingPosition) { _, _ in
                        triggerHaptic()
                        service.savePreferences()
                    }
                }

                HStack(spacing: 12) {
                    Text("Notch Width")
                        .frame(width: 110, alignment: .leading)
                    Slider(value: $service.windowWidth,
                           in: TeleprompterService.notchWindowWidthRange, step: 20, onEditingChanged: { editing in
                        if !editing { service.savePreferences() }
                    })
                        .help("\(Int(TeleprompterService.notchWindowWidthRange.lowerBound))–\(Int(TeleprompterService.notchWindowWidthRange.upperBound)) points.")
                    Text("\(Int(service.windowWidth)) pt")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }

                HStack(spacing: 12) {
                    Text("Notch Height")
                        .frame(width: 110, alignment: .leading)
                    Slider(value: $service.windowHeight,
                           in: TeleprompterService.notchWindowHeightRange, step: 20, onEditingChanged: { editing in
                        if !editing { service.savePreferences() }
                    })
                        .help("\(Int(TeleprompterService.notchWindowHeightRange.lowerBound))–\(Int(TeleprompterService.notchWindowHeightRange.upperBound)) points.")
                    Text("\(Int(service.windowHeight)) pt")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }

                Toggle("Show paragraph dividers", isOn: $service.showParagraphDividers)
                    .onChange(of: service.showParagraphDividers) { _, _ in service.savePreferences() }

                Toggle("Show last spoken word", isOn: $service.showLastSpokenWords)
                    .onChange(of: service.showLastSpokenWords) { _, _ in service.savePreferences() }

                Toggle("Show elapsed time", isOn: $service.showElapsedTime)
                    .onChange(of: service.showElapsedTime) { _, _ in service.savePreferences() }

            } header: {
                Text("Appearance")
            }
            .disabled(!teleprompterEnabled)
            .simultaneousGesture(TapGesture().onEnded { closeAppearancePreviewIfActive() })

            // MARK: - 4. Guidance Section
            Section {
                HStack {
                    HStack(spacing: 4) {
                        Text("Tracking Mode")
                        InfoTip(text: "Word Tracking highlights words as you speak; Classic auto-scrolls at steady pace; Voice-Activated pauses on silence.")
                    }
                    Spacer()
                    Picker("", selection: $service.guidanceMode) {
                        ForEach(GuidanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: service.guidanceMode) { _, _ in
                        triggerHaptic()
                        service.savePreferences()
                    }
                }

                if service.guidanceMode != .wordTracking {
                    HStack(spacing: 12) {
                        Text("Scroll Speed")
                            .frame(width: 110, alignment: .leading)
                        Slider(value: $service.scrollSpeed, in: TeleprompterService.scrollSpeedRange, step: 0.05,
                               onEditingChanged: { editing in
                            isEditingScrollSpeed = editing
                            if editing {
                                lastScrollSpeedHapticStep = Int((service.scrollSpeed * 4).rounded())
                            } else {
                                lastScrollSpeedHapticStep = nil
                            }
                            if !editing {
                                service.savePreferences()
                            }
                        })
                        Text(String(format: "%.1fx", locale: l10n.language.formattingLocale(), service.scrollSpeed))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }

                Picker("Speech Language", selection: $service.speechLocale) {
                    ForEach(SpeechLocaleSupport.supportedLocales, id: \.identifier) { loc in
                        Text(Locale.current.localizedString(forIdentifier: loc.identifier) ?? loc.identifier)
                            .tag(loc.identifier)
                    }
                }
                .onChange(of: service.speechLocale) { _, _ in service.savePreferences() }

                Picker("Microphone", selection: $service.selectedMicUID) {
                    Text("System Default").tag("")
                    ForEach(inputDevices) { dev in
                        Text(dev.name).tag(dev.uid)
                    }
                }
                .onChange(of: service.selectedMicUID) { _, _ in service.savePreferences() }
            } header: {
                Text("Guidance")
            }
            .disabled(!teleprompterEnabled)
            .simultaneousGesture(TapGesture().onEnded { closeAppearancePreviewIfActive() })

            // MARK: - 5. Controls Section
            Section {
                Toggle(isOn: $service.keepScreenAwake) {
                    HStack(spacing: 4) {
                        Text("Keep screen awake while teleprompter is active")
                        InfoTip(text: "Prevents the display from sleeping during an active teleprompter session.")
                    }
                }
                .onChange(of: service.keepScreenAwake) { _, _ in service.savePreferences() }

                Toggle(isOn: $service.hideFromScreenSharing) {
                    HStack(spacing: 4) {
                        Text(strings.hideFromScreenSharing)
                        let notchEditor = FeatureStrings.notchEditor(l10n.language)
                        InfoTip(text: strings.hideFromScreenSharingDesc,
                                actionTitle: "\(notchEditor.behavior) · \(notchEditor.privacy)") {
                            let router = SettingsRouter.shared
                            router.request(FeatureSettingsDestination(.notch))
                            router.notchPrivacySettingsRequested = true
                        }
                    }
                }
                .onChange(of: service.hideFromScreenSharing) { _, _ in service.savePreferences() }

                Toggle("Focus Notch", isOn: $service.focusNotchMode)
                    .onChange(of: service.focusNotchMode) { _, _ in service.savePreferences() }
            } header: {
                Text("Controls")
            }
            .disabled(!teleprompterEnabled)
            .simultaneousGesture(TapGesture().onEnded { closeAppearancePreviewIfActive() })

            // MARK: - 7. External Display Section
            Section {
                Picker("Mode", selection: $service.externalDisplayMode) {
                    ForEach(ExternalDisplayMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: service.externalDisplayMode) { _, _ in
                    triggerHaptic()
                    service.savePreferences()
                }

                if service.externalDisplayMode != .off {
                    let externalScreens = NSScreen.screens.filter { $0 != NSScreen.main }
                    if externalScreens.isEmpty {
                        Text("No external display detected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Target Screen", selection: $service.externalScreenID) {
                            ForEach(externalScreens, id: \.displayID) { scr in
                                Text(scr.localizedName).tag(scr.displayID)
                            }
                        }
                        .onChange(of: service.externalScreenID) { _, _ in service.savePreferences() }
                    }

                    if service.externalDisplayMode == .mirror {
                        HStack {
                            HStack(spacing: 4) {
                                Text("Mirror Axis")
                                InfoTip(text: "Invert text orientation for reflective beam splitter glass rigs.")
                            }
                            Spacer()
                            Picker("", selection: $service.externalMirrorAxis) {
                                ForEach(ExternalMirrorAxis.allCases) { axis in
                                    Text(axis.label).tag(axis)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 220)
                            .onChange(of: service.externalMirrorAxis) { _, _ in
                                triggerHaptic()
                                service.savePreferences()
                            }
                        }
                    }
                }
            } header: {
                Text("External Display")
            }
            .disabled(!teleprompterEnabled)
            .simultaneousGesture(TapGesture().onEnded { closeAppearancePreviewIfActive() })

            // MARK: - 8. Remote Control Section
            Section {
                Toggle(isOn: $service.remoteServerEnabled) {
                    HStack(spacing: 4) {
                        Text("Enable Browser Remote")
                        InfoTip(text: "Control scroll speed, play/pause, and pagination wirelessly from any mobile or desktop browser on your local network.")
                    }
                }
                .onChange(of: service.remoteServerEnabled) { _, on in
                    service.savePreferences()
                    if on {
                        service.remoteServer.start()
                    } else {
                        service.remoteServer.stop()
                    }
                }

                if service.remoteServerEnabled {
                    remoteViewerDetails
                }
            } header: {
                Text("Remote Control")
            }
            .disabled(!teleprompterEnabled)
            .simultaneousGesture(TapGesture().onEnded { closeAppearancePreviewIfActive() })

            // MARK: - 9. Director Studio Section
            Section {
                Toggle(isOn: $service.directorServerEnabled) {
                    HStack(spacing: 4) {
                        Text("Enable Director Server")
                        InfoTip(text: "Live studio production server for live multi-client script editing and prompting.")
                    }
                }
                .onChange(of: service.directorServerEnabled) { _, on in
                    service.savePreferences()
                    if on {
                        service.directorServer.start()
                    } else {
                        service.directorServer.stop()
                    }
                }

                if service.directorServerEnabled {
                    directorStudioDetails
                }
            } header: {
                Text("Director Studio")
            }
            .disabled(!teleprompterEnabled)
            .simultaneousGesture(TapGesture().onEnded { closeAppearancePreviewIfActive() })

            // MARK: - 10. Reset Section
            Section {
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        confirmingReset = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("Reset Teleprompter Settings")
                        }
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .confirmationDialog(
                    "Reset Teleprompter Settings?",
                    isPresented: $confirmingReset,
                    titleVisibility: .visible
                ) {
                    Button("Reset to Defaults", role: .destructive) {
                        service.resetSettings()
                        triggerHaptic()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will reset all appearance, guidance, reading, display, and server settings to their defaults. Your scripts and pages will not be deleted.")
                }
            } header: {
                Text("Reset")
            }
            .disabled(!teleprompterEnabled)
            .simultaneousGesture(TapGesture().onEnded { closeAppearancePreviewIfActive() })
        }
        .formStyle(.grouped)
        .onAppear {
            lastPreviewSettings = TeleprompterPreviewSettingsSnapshot(service)
            inputDevices = AudioInputDevice.allInputDevices()
            openRequestedNewPageIfNeeded()
            openRequestedEditPageIfNeeded()
        }
        .onDisappear {
            previewRefreshTask?.cancel()
            previewRefreshTask = nil
            closeAppearancePreviewIfActive()
        }
        .onChange(of: TeleprompterPreviewSettingsSnapshot(service)) { _, snapshot in
            guard snapshot != lastPreviewSettings else { return }
            lastPreviewSettings = snapshot
            guard !service.isRunning, NotchSupport.isEnabled() else { return }
            previewRefreshTask?.cancel()
            previewRefreshTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 80_000_000)
                } catch {
                    return
                }
                guard !Task.isCancelled, !service.isRunning else { return }
                service.previewInNotch(autoCloseAfter: 4)
            }
        }
        .onChange(of: service.scrollSpeed) { _, speed in
            if isEditingScrollSpeed {
                let step = Int((speed * 4).rounded())
                if step != lastScrollSpeedHapticStep {
                    lastScrollSpeedHapticStep = step
                    triggerHaptic()
                }
            }
            guard !service.isRunning, NotchSupport.isEnabled() else { return }
            previewRefreshTask?.cancel()
            previewRefreshTask = Task { @MainActor in
                service.previewInNotch(autoCloseAfter: 4)
            }
        }
        .onChange(of: service.pendingAddPageInSettings) { _, requested in
            if requested { openRequestedNewPageIfNeeded() }
        }
        .onChange(of: service.pendingEditPageIndexInSettings) { _, index in
            if index != nil { openRequestedEditPageIfNeeded() }
        }
        .confirmationDialog(
            "Delete Page \((pageToDelete ?? 0) + 1)?",
            isPresented: Binding(
                get: { pageToDelete != nil },
                set: { if !$0 { pageToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Page", role: .destructive) {
                if let idx = pageToDelete {
                    deletePage(at: idx)
                    triggerHaptic()
                }
                pageToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pageToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete this page? This action cannot be undone.")
        }
        .alert(importAlertTitle, isPresented: $showingImportError) {
            Button("OK") { }
        } message: {
            Text(importErrorMessage ?? "Could not extract presenter notes.")
        }
    }

    // MARK: - Page Row Component

    private func pageRow(index: Int) -> some View {
        let pageContent = (index < pagesList.count) ? pagesList[index] : ""
        let snippet = previewSnippet(pageContent)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Page \(index + 1)")
                    .font(.system(size: 13, weight: .medium))
                Text(snippet.isEmpty ? "Empty page" : snippet)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            PageActionMenuButton(
                onEdit: { openPageEditor(index: index) },
                onDuplicate: { duplicatePage(at: index) },
                onDelete: { pageToDelete = index },
                canDelete: pagesList.count > 1,
                canDuplicate: true
            )
            .frame(width: 18, height: 18)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            openPageEditor(index: index)
        }
    }

    private func previewSnippet(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count > 65 {
            return clean.prefix(65) + "..."
        }
        return clean
    }

    // MARK: - Page Actions

    private func openPageEditor(index: Int) {
        if service.pages.isEmpty {
            service.pages = [service.text]
        }
        guard index < service.pages.count else { return }
        editingPageIndex = index
        let pageText = service.pages[index]

        PageEditorWindowController.shared.show(
            pageIndex: index,
            initialText: pageText,
            service: service,
            dictation: dictation,
            onCancel: {
                closePageEditor(save: false)
            },
            onDone: { newText in
                closePageEditor(save: true, newText: newText)
            }
        )
    }

    private func closePageEditor(save: Bool, newText: String? = nil) {
        if save, let idx = editingPageIndex, let newText = newText, idx < service.pages.count {
            service.pages[idx] = newText
            service.savePreferences()
        }
        editingPageIndex = nil
    }

    private func addNewPage() {
        service.addPage()
        let newIdx = max(0, service.pages.count - 1)
        editingPageIndex = newIdx
        let pageText = service.pages[newIdx]
        triggerHaptic()

        PageEditorWindowController.shared.show(
            pageIndex: newIdx,
            initialText: pageText,
            service: service,
            dictation: dictation,
            onCancel: {
                if newIdx < service.pages.count && service.pages[newIdx].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && service.pages.count > 1 {
                    service.removePage(at: newIdx)
                }
                closePageEditor(save: false)
            },
            onDone: { newText in
                closePageEditor(save: true, newText: newText)
            }
        )
    }

    private func openRequestedNewPageIfNeeded() {
        guard service.pendingAddPageInSettings else { return }
        service.pendingAddPageInSettings = false
        // Let Settings become the key window before presenting its page editor sheet.
        DispatchQueue.main.async {
            addNewPage()
        }
    }

    private func openRequestedEditPageIfNeeded() {
        guard let index = service.pendingEditPageIndexInSettings else { return }
        service.pendingEditPageIndexInSettings = nil
        // Present from the Settings window after it becomes key, as for Add Page.
        DispatchQueue.main.async {
            openPageEditor(index: index)
        }
    }

    private func duplicatePage(at index: Int) {
        guard index < pagesList.count else { return }
        if service.pages.isEmpty {
            service.pages = [service.text]
        }
        let copy = service.pages[index]
        service.pages.insert(copy, at: index + 1)
        service.savePreferences()
        triggerHaptic()
    }

    private func deletePage(at index: Int) {
        service.removePage(at: index)
    }

    // MARK: - Remote Details

    @ViewBuilder
    private var remoteViewerDetails: some View {
        let ip = TeleprompterServer.localIPAddress() ?? "localhost"
        let urlStr = "http://\(ip):\(service.remoteServer.httpPort)"

        VStack(alignment: .leading, spacing: 8) {
            Text("Connect from any device on your local network:")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(urlStr)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(urlStr, forType: .string)
                    triggerHaptic()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let qr = generateQRCode(from: urlStr) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .padding(6)
                    .background(Color.white)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var directorStudioDetails: some View {
        let ip = TeleprompterServer.localIPAddress() ?? "localhost"
        let urlStr = "http://\(ip):\(service.directorServer.httpPort)"

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(urlStr)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(urlStr, forType: .string)
                    triggerHaptic()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(service.directorServer.connectedClients > 0 ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text("\(service.directorServer.connectedClients) connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let qr = generateQRCode(from: urlStr) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 110, height: 110)
                    .padding(6)
                    .background(Color.white)
                    .cornerRadius(8)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - PPTX Import & QR Generation

    private func chooseAndImportPPTX() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "pptx")].compactMap { $0 }

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try service.importPPTX(url: url)
                triggerHaptic()
            } catch {
                importAlertTitle = "Import Failed"
                importErrorMessage = error.localizedDescription
                showingImportError = true
            }
        }
    }

    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 120, height: 120))
    }
}

// MARK: - Dedicated Page Editor Window Controller (Modal Sheet)

@MainActor
final class PageEditorWindowController: NSObject, ObservableObject {
    static let shared = PageEditorWindowController()

    private var currentSheet: NSWindow?
    private var isDismissing: Bool = false
    private var isExpanded: Bool = false
    @Published private(set) var isShowing = false

    func toggleZoom() {
        guard let panel = currentSheet else { return }
        let normalSize = NSSize(width: 660, height: 520)
        let expandedSize = NSSize(width: 900, height: 750)

        let targetSize = isExpanded ? normalSize : expandedSize
        var frame = panel.frame
        let dw = targetSize.width - frame.size.width
        let dh = targetSize.height - frame.size.height
        frame.origin.x -= dw / 2
        frame.origin.y -= dh / 2
        frame.size = targetSize

        panel.setFrame(frame, display: true, animate: true)
        isExpanded.toggle()
    }

    func show(
        pageIndex: Int,
        initialText: String,
        service: TeleprompterService,
        dictation: DictationManager,
        onCancel: @escaping () -> Void,
        onDone: @escaping (String) -> Void
    ) {
        guard !isDismissing else { return }
        isExpanded = false

        // Never attach an editor sheet to the notch prompter.
        // Doing so stacks interactive notch controls under the dialog and can
        // make clicks intended for the editor activate those controls.
        let parentWindow = NSApp.windows.first(where: {
            $0.isVisible && !$0.isMiniaturized && !($0 is NSPanel) && $0.level == .normal
        })

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 520),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.minSize = NSSize(width: 540, height: 400)
        panel.maxSize = NSSize(width: 920, height: 820)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let contentView = PageEditorDialog(
            pageIndex: pageIndex,
            initialText: initialText,
            service: service,
            dictation: dictation,
            onCancel: { [weak self, weak parentWindow, weak panel] in
                guard let self = self, !self.isDismissing else { return }
                self.isDismissing = true
                if let panel = panel, let parentWindow = parentWindow, parentWindow.sheets.contains(panel) {
                    parentWindow.endSheet(panel)
                } else {
                    panel?.orderOut(nil)
                }
                self.currentSheet = nil
                self.isShowing = false
                self.isDismissing = false
                onCancel()
            },
            onDone: { [weak self, weak parentWindow, weak panel] newText in
                guard let self = self, !self.isDismissing else { return }
                self.isDismissing = true
                if let panel = panel, let parentWindow = parentWindow, parentWindow.sheets.contains(panel) {
                    parentWindow.endSheet(panel)
                } else {
                    panel?.orderOut(nil)
                }
                self.currentSheet = nil
                self.isShowing = false
                self.isDismissing = false
                onDone(newText)
            }
        )
        .ignoresSafeArea()

        panel.contentView = NSHostingView(rootView: contentView)
        self.currentSheet = panel
        self.isShowing = true

        if let parent = parentWindow {
            parent.beginSheet(panel)
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Dedicated Page Editor Dialog (macOS Component Action Dialog)

struct PageEditorDialog: View {
    let pageIndex: Int
    private let initialText: String
    @State private var text: String
    @ObservedObject var service: TeleprompterService
    @ObservedObject var dictation: DictationManager
    var onCancel: () -> Void
    var onDone: (String) -> Void

    @State private var caretPosition: Int? = nil
    @State private var editorCaretPosition: Int = 0
    @State private var cueToInsert: String? = nil
    @State private var dictationHighlightRange: NSRange? = nil
    @State private var highlightClearTimer: Timer?
    @State private var isHoveringControls: Bool = false
    @State private var showingUnsavedAlert: Bool = false

    @State private var segmentStart: Int = 0
    @State private var segmentLength: Int = 0
    @State private var segmentNeedsSeparator: Bool = false
    @State private var spokenSkipOffset: Int = 0
    @State private var lastRawSpokenLength: Int = 0

    init(
        pageIndex: Int,
        initialText: String,
        service: TeleprompterService,
        dictation: DictationManager,
        onCancel: @escaping () -> Void,
        onDone: @escaping (String) -> Void
    ) {
        self.pageIndex = pageIndex
        self.initialText = initialText
        self._text = State(initialValue: initialText)
        self.service = service
        self.dictation = dictation
        self.onCancel = onCancel
        self.onDone = onDone
    }

    private var wordsCount: Int {
        splitTextIntoWords(text).count
    }

    private var estimatedReadingTimeText: String {
        let words = wordsCount
        guard words > 0 else { return "0s" }
        let seconds = Int(Double(words) / 130.0 * 60.0)
        let mins = seconds / 60
        let remSecs = seconds % 60
        return mins > 0 ? "~\(mins)m \(remSecs)s" : "~\(remSecs)s"
    }

    private func attemptClose() {
        if text != initialText {
            showingUnsavedAlert = true
        } else {
            if dictation.isRecording {
                stopDictation()
            }
            onCancel()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Header Row: Window Buttons, Centered Title, Cue & Dictate on Right
            ZStack {
                // Centered Page Title (page number only)
                Text("Page \(pageIndex + 1)")
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 12) {
                    // macOS traffic lights style dots
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.38, blue: 0.35))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(Color.black.opacity(0.55))
                                    .opacity(isHoveringControls ? 1 : 0)
                            )
                            .onTapGesture {
                                attemptClose()
                            }
                            .help("Close & Discard")

                        // Yellow minimize button is disabled for modal dialogs
                        Circle()
                            .fill(Color(red: 1.0, green: 0.76, blue: 0.2).opacity(0.35))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Image(systemName: "minus")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(Color.black.opacity(0.25))
                                    .opacity(isHoveringControls ? 1 : 0)
                            )
                            .help("Disabled")

                        Circle()
                            .fill(Color(red: 0.2, green: 0.8, blue: 0.35))
                            .frame(width: 12, height: 12)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundStyle(Color.black.opacity(0.55))
                                    .opacity(isHoveringControls ? 1 : 0)
                            )
                            .onTapGesture {
                                PageEditorWindowController.shared.toggleZoom()
                            }
                            .help("Toggle Zoom")
                    }
                    .onHover { isHoveringControls = $0 }

                    Spacer()

                    // Top Right: Cue Menu & Dictate Button
                    HStack(spacing: 8) {
                        Menu {
                            Button("[PAUSE]") { insertCue("PAUSE") }
                            Button("[LOOK AT CAMERA]") { insertCue("LOOK AT CAMERA") }
                            Button("[SPEED UP]") { insertCue("SPEED UP") }
                            Button("[SLOW DOWN]") { insertCue("SLOW DOWN") }
                            Button("[SMILE]") { insertCue("SMILE") }
                            Button("[TAKE A BREATH]") { insertCue("TAKE A BREATH") }
                        } label: {
                            Label("Cue", systemImage: "sparkles")
                        }
                        .menuStyle(.borderedButton)
                        .controlSize(.small)

                        if dictation.isStarting {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Starting Dictation…")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                TeleprompterWaveformView(levels: dictation.audioLevels, color: .red, isActive: true)
                                    .frame(width: 56, height: 16)
                                Button {
                                    stopDictation()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Cancel Dictation")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                        } else if dictation.isRecording {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)

                                Text("Listening")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.red)

                                TeleprompterWaveformView(levels: dictation.audioLevels, color: .red, isActive: true)
                                    .frame(width: 56, height: 16)

                                Button {
                                    stopDictation()
                                    triggerHaptic()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Stop Dictation")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
                            )
                        } else {
                            Button {
                                startDictation()
                                triggerHaptic()
                            } label: {
                                Label("Dictate", systemImage: "mic.fill")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // MARK: - Text Area with Native Vertical Scrollbar
            HighlightingTextEditor(
                text: $text,
                font: service.fontFamily.nsFont(ofSize: service.fontSize.pointSize),
                highlightRange: dictationHighlightRange,
                cueColor: service.cueColor.nsColor,
                cueAlpha: service.cueBrightness.alpha,
                caretPosition: $caretPosition,
                editorCaretPosition: $editorCaretPosition,
                cueToInsert: $cueToInsert
            )
            .padding(12)
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            // MARK: - Bottom Bar: Words, Characters, Reading Time on Left; Cancel & Done on Right
            HStack(spacing: 16) {
                HStack(spacing: 14) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.word.spacing")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("\(wordsCount) words")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "character")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("\(text.count) characters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("\(estimatedReadingTimeText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button("Cancel") {
                        attemptClose()
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Done") {
                        if dictation.isRecording {
                            stopDictation()
                        }
                        onDone(text)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 540, idealWidth: 660, maxWidth: 920, minHeight: 400, idealHeight: 520, maxHeight: 820)
        .alert("Unsaved Changes", isPresented: $showingUnsavedAlert) {
            Button("Discard Changes", role: .destructive) {
                if dictation.isRecording {
                    stopDictation()
                }
                onCancel()
            }
            Button("Keep Editing", role: .cancel) { }
            Button("Save & Close") {
                if dictation.isRecording {
                    stopDictation()
                }
                onDone(text)
            }
        } message: {
            Text("You have unsaved changes in Page \(pageIndex + 1). Do you want to discard them?")
        }
    }

    private func insertCue(_ cue: String) {
        let tag = "[\(cue)]"
        let source = text as NSString
        // The Cue menu takes focus from NSTextView, so its last reported caret
        // can be stale. Append cues to the script in order instead of inserting
        // them into an earlier word when a second cue is chosen.
        let caret = source.length
        let needsLeadingSpace = caret > 0 && source.character(at: caret - 1) != 0x20 && source.character(at: caret - 1) != 0x0A
        let toInsert = (needsLeadingSpace ? " " : "") + tag + " "
        let updated = source.mutableCopy() as! NSMutableString
        updated.insert(toInsert, at: caret)
        text = updated as String

        let newCaret = caret + (toInsert as NSString).length
        editorCaretPosition = newCaret
        caretPosition = newCaret
        if dictation.isRecording {
            // Re-anchor the live transcript after the inserted cue. Otherwise
            // subsequent partial results replace text at the previous segment
            // start and appear before or overwrite the cue.
            dictation.restartCurrentSegment()
        }
        triggerHaptic()
    }

    private func toggleDictation() {
        if dictation.isRecording {
            stopDictation()
        } else {
            startDictation()
        }
        triggerHaptic()
    }

    private func startDictation() {
        lastRawSpokenLength = 0
        spokenSkipOffset = 0
        beginNewSegment()

        dictation.onNewSegment = {
            lastRawSpokenLength = 0
            spokenSkipOffset = 0
            beginNewSegment()
        }

        dictation.onTextUpdate = { spokenText in
            lastRawSpokenLength = spokenText.count

            let effectiveText: String
            if spokenSkipOffset < spokenText.count {
                effectiveText = String(spokenText.suffix(spokenText.count - spokenSkipOffset))
            } else {
                effectiveText = ""
            }
            guard !effectiveText.isEmpty else { return }

            let source = text as NSString
            let safeStart = min(segmentStart, source.length)
            let safeLen = min(segmentLength, source.length - safeStart)
            let updated = source.mutableCopy() as! NSMutableString
            updated.replaceCharacters(in: NSRange(location: safeStart, length: safeLen), with: "")

            let sep = segmentNeedsSeparator ? " " : ""
            let newSegment = sep + effectiveText
            let insertIndex = min(segmentStart, updated.length)
            updated.insert(newSegment, at: insertIndex)
            text = updated as String

            let prevLen = segmentLength
            segmentLength = (newSegment as NSString).length

            let newChars = segmentLength - prevLen
            if newChars > 0 {
                let highlightStart = segmentStart + prevLen
                dictationHighlightRange = NSRange(location: highlightStart, length: newChars)
            }

            let newCaret = min(segmentStart + segmentLength, (text as NSString).length)
            caretPosition = newCaret
            editorCaretPosition = newCaret

            highlightClearTimer?.invalidate()
            highlightClearTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                MainActor.assumeIsolated {
                    dictationHighlightRange = nil
                }
            }
        }

        dictation.start()
    }

    private func stopDictation() {
        highlightClearTimer?.invalidate()
        highlightClearTimer = nil
        dictationHighlightRange = nil
        dictation.stop()
    }

    private func beginNewSegment() {
        let source = text as NSString
        let caret = min(editorCaretPosition, source.length)
        spokenSkipOffset = lastRawSpokenLength
        let charBefore = caret > 0 ? source.character(at: caret - 1) : 0x0A
        segmentNeedsSeparator = !(charBefore == 0x20 || charBefore == 0x0A || caret == 0)
        segmentStart = caret
        segmentLength = 0
    }
}
