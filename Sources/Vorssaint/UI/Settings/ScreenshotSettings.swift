// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct ScreenshotSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = ScreenshotService.shared
    @AppStorage(DefaultsKey.screenshotEnabled) private var enabled = true
    @AppStorage(DefaultsKey.screenshotShowThumbnail) private var showThumbnail = true
    @AppStorage(DefaultsKey.screenshotQuickCaptureMode) private var quickCaptureMode = 2
    @AppStorage(DefaultsKey.screenshotHideInstructions) private var hideInstructions = false
    @AppStorage(DefaultsKey.screenshotSaveAction) private var saveAction = 0
    @AppStorage(DefaultsKey.screenshotSaveDirectory) private var saveDirectory = Defaults.defaultScreenshotDirectoryPath

    var body: some View {
        Form {
            Section {
                Toggle("Enable Screenshot Capture", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        ScreenshotService.shared.syncWithPreferences()
                    }
                Text("Enable a global shortcut to capture a region on your screen and copy it to the clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if enabled {
                Section {
                    ShortcutPreferenceRow(role: .screenshot, isEnabled: true) {
                        ScreenshotService.shared.syncWithPreferences()
                    }
                    if service.hotkeyRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    
                    Toggle("Show Floating Thumbnail", isOn: $showThumbnail)
                    Text("Show a draggable preview in the bottom-right corner of the screen after taking a screenshot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Toggle("Hide capture instructions", isOn: $hideInstructions)
                    Text("Hide the text instructions displayed at the top of the screen during screen capture.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("Capture Behavior") {
                    Picker("Enter / Quick Capture:", selection: $quickCaptureMode) {
                        Text("Save to file").tag(0)
                        Text("Copy to clipboard").tag(1)
                        Text("Save + copy to clipboard").tag(2)
                        Text("Do nothing").tag(3)
                    }
                    .pickerStyle(.menu)
                    Text("Choose what action to perform automatically when you complete a screenshot selection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("Output Settings") {
                    Picker("Save action:", selection: $saveAction) {
                        Text("Save to default folder").tag(0)
                        Text("Ask where to save").tag(1)
                    }
                    .pickerStyle(.menu)
                    
                    HStack {
                        Text("Save folder:")
                        Spacer()
                        TextField("", text: $saveDirectory)
                            .disabled(true)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 150, maxWidth: .infinity)
                        Button("Browse…") {
                            browseFolder()
                        }
                    }
                }
                
                Section("Instructions") {
                    bullet("1", "Press the global shortcut to activate the capture crosshair.")
                    bullet("2", "Hover over any window to highlight its boundaries, then click to capture it instantly.")
                    bullet("3", "Click and drag to select any custom region on the screen.")
                    bullet("4", "On mouse release, the screenshot is processed according to your Quick Capture action.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func bullet(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            saveDirectory = url.path
        }
    }
}
