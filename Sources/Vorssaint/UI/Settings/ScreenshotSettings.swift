// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Settings for the screenshot shortcut, capture, save and export behavior.
struct ScreenshotSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = ScreenshotService.shared
    @AppStorage(DefaultsKey.screenshotShortcutEnabled) private var shortcutEnabled = false
    @AppStorage(DefaultsKey.screenshotFreeze) private var freeze = true
    @AppStorage(DefaultsKey.screenshotSaveFolder) private var saveFolder = ""
    @AppStorage(DefaultsKey.screenshotSaveSubfolder) private var saveSubfolder = ""
    @AppStorage(DefaultsKey.screenshotFileNamePattern) private var fileNamePattern = ""
    @AppStorage(DefaultsKey.screenshotFileNumberStart) private var numberStart = 1
    @AppStorage(DefaultsKey.screenshotFileNumberNext) private var nextNumber = 1
    @AppStorage(DefaultsKey.screenshotIncludePointer) private var includePointer = false
    @AppStorage(DefaultsKey.screenshotShowLastRegion) private var showLastRegion = true
    @AppStorage(DefaultsKey.screenshotDownscale) private var downscale = false
    @AppStorage(DefaultsKey.screenshotDelay) private var delay = 0
    @AppStorage(DefaultsKey.screenshotDefaultAction) private var defaultActionRaw = ""
    @AppStorage(DefaultsKey.screenshotToolOrder) private var toolOrderRaw =
        ScreenshotSupport.Tool.defaultOrderStorage
    @AppStorage(DefaultsKey.screenshotToolShortcutsEnabled) private var toolShortcutsEnabled = true
    @AppStorage(DefaultsKey.screenshotCopyToClipboard) private var copyToClipboard = false

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    var body: some View {
        Form {
            Section {
                Button {
                    ScreenshotService.shared.capture()
                } label: {
                    Label(strings.captureButton, systemImage: "camera.viewfinder")
                }
                Text(strings.panelCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(l10n.s.quickToolShortcutToggle, isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _, _ in
                        ScreenshotService.shared.syncWithPreferences()
                    }
                ShortcutPreferenceRow(role: .screenshot,
                                      isEnabled: shortcutEnabled) {
                    ScreenshotService.shared.syncWithPreferences()
                }
                if shortcutEnabled, service.shortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if !permissions.screenRecording {
                    PermissionRow(kind: .screenRecording)
                }
            } header: {
                Text(strings.pageTitle)
            }

            Section {
                Toggle(strings.freezeToggle, isOn: $freeze)
                Text(strings.freezeCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(strings.delayLabel, selection: $delay) {
                    ForEach(ScreenshotSupport.allowedDelays, id: \.self) { seconds in
                        if seconds == 0 {
                            Text(strings.delayOff).tag(0)
                        } else {
                            Text(String(format: strings.delaySecondsFormat, seconds)).tag(seconds)
                        }
                    }
                }
                .pickerStyle(.segmented)
                Toggle(strings.pointerToggle, isOn: $includePointer)
                Toggle(strings.lastRegionToggle, isOn: $showLastRegion)
                defaultActionRow
            }

            Section {
                Toggle(strings.autoCopyToggle, isOn: $copyToClipboard)
                Text(strings.autoCopyCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                folderRow
                subfolderRow
                fileNameRow
                Toggle(strings.downscaleToggle, isOn: $downscale)
                Text(strings.downscaleCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ScreenshotToolOrderControls(orderRaw: $toolOrderRaw,
                                            shortcutsEnabled: $toolShortcutsEnabled,
                                            showsTitle: false)
            } header: {
                Text(strings.toolShortcutsTitle)
            }
        }
        .formStyle(.grouped)
    }

    private var defaultActionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(strings.defaultActionLabel, selection: $defaultActionRaw) {
                Text(strings.defaultActionNone).tag(ScreenshotDefaultAction.none.rawValue)
                Text(strings.saveButton).tag(ScreenshotDefaultAction.save.rawValue)
                Text(strings.defaultActionSaveAndCopy).tag(ScreenshotDefaultAction.saveAndCopy.rawValue)
                Text(strings.copyButton).tag(ScreenshotDefaultAction.copy.rawValue)
                Text(strings.editButton).tag(ScreenshotDefaultAction.edit.rawValue)
            }
            Text(strings.defaultActionCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var folderRow: some View {
        HStack {
            Text(strings.folderLabel)
            Spacer()
            Text(currentFolderName)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if !saveFolder.isEmpty {
                Button {
                    saveFolder = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .screenshotSafeHelp(l10n.s.shortcutReset)
            }
            Button(strings.folderChoose) {
                chooseFolder()
            }
        }
    }

    private var subfolderRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(strings.subfolderLabel)
                    .lineLimit(1)
                TextField("", text: $saveSubfolder)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 150)
                if !saveSubfolder.isEmpty {
                    Text(ScreenshotSupport.expandSaveSubfolder(saveSubfolder, date: Date()))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(strings.subfolderCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var fileNameRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(strings.fileNamePatternLabel)
                    .lineLimit(1)
                TextField("", text: $fileNamePattern)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 150)
                Text(fileNamePreview)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(strings.fileNamePatternCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            if ScreenshotSupport.fileNamePatternUsesNumber(fileNamePattern) {
                HStack {
                    Text(strings.fileNumberStartLabel)
                        .lineLimit(1)
                    TextField("", value: $numberStart, formatter: Self.numberFieldFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Stepper("", value: $numberStart, in: 0...999_999)
                        .labelsHidden()
                    Button(strings.fileNumberResetButton) {
                        nextNumber = numberStart
                    }
                    Spacer()
                    Text(String(format: strings.fileNumberNextFormat, nextNumber))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: numberStart) { _, newValue in
                    nextNumber = newValue
                }
            }
        }
    }

    private static let numberFieldFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        formatter.maximum = 999_999
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    private var fileNamePreview: String {
        let trimmed = fileNamePattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ScreenshotSupport.fileName(prefix: strings.fileNamePrefix, date: Date())
        }
        return ScreenshotSupport.expandFileNamePattern(trimmed, date: Date(), number: nextNumber) + ".png"
    }

    private var currentFolderName: String {
        let manager = FileManager.default
        if !saveFolder.isEmpty {
            let expanded = (saveFolder as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
                return manager.displayName(atPath: expanded)
            }
        }
        let desktop = manager.urls(for: .desktopDirectory, in: .userDomainMask).first
        return desktop.map { manager.displayName(atPath: $0.path) } ?? "Desktop"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            saveFolder = url.path
        }
    }
}
