// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Settings for the screenshot tool: its shortcuts, where and how it saves,
/// and how the capture screen behaves.
struct ScreenshotSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = ScreenshotService.shared
    @AppStorage(DefaultsKey.shotShortcutEnabled) private var shortcutEnabled = true
    @AppStorage(DefaultsKey.shotFullScreenShortcutEnabled) private var fullScreenShortcutEnabled = false
    @AppStorage(DefaultsKey.shotFolder) private var folder = ""
    @AppStorage(DefaultsKey.shotFileNamePattern) private var pattern = ShotFiles.defaultPattern
    @AppStorage(DefaultsKey.shotFormat) private var format = "png"
    @AppStorage(DefaultsKey.shotJPEGQuality) private var jpegQuality = 90
    @AppStorage(DefaultsKey.shotAutoCopy) private var autoCopy = false
    @AppStorage(DefaultsKey.shotNotify) private var notify = true
    @AppStorage(DefaultsKey.shotKeepSelection) private var keepSelection = false
    @AppStorage(DefaultsKey.shotCaptureCursor) private var captureCursor = false
    @AppStorage(DefaultsKey.shotMagnifier) private var magnifier = true
    @State private var patternDraft = ""
    @State private var systemShortcutsOn = true
    @FocusState private var patternFocused: Bool

    private var shot: ScreenshotFeatureStrings { FeatureStrings.screenshot(l10n.language) }
    private var text: ShotStrings { FeatureStrings.shot(l10n.language) }

    var body: some View {
        Form {
            Section {
                Button {
                    // The capture screen opens once this window's click has ended.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        ScreenshotService.shared.capture()
                    }
                } label: {
                    Label(shot.captureButton, systemImage: "camera.viewfinder")
                }
                Text(text.intro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !permissions.screenRecording {
                    PermissionRow(kind: .screenRecording)
                }
            } header: {
                Text(shot.pageTitle)
            }
            .settingsFormSectionAnchor(.screenshot)

            Section {
                Toggle(GlobalShortcutRole.screenshot.title(l10n.s), isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _, _ in service.syncWithPreferences() }
                ShortcutPreferenceRow(role: .screenshot, isEnabled: shortcutEnabled) {
                    service.syncWithPreferences()
                }
                if shortcutEnabled, service.shortcutRegistrationFailed {
                    unavailable
                }
                Toggle(GlobalShortcutRole.screenshotFullScreen.title(l10n.s), isOn: $fullScreenShortcutEnabled)
                    .onChange(of: fullScreenShortcutEnabled) { _, _ in service.syncWithPreferences() }
                ShortcutPreferenceRow(role: .screenshotFullScreen, isEnabled: fullScreenShortcutEnabled) {
                    service.syncWithPreferences()
                }
                if fullScreenShortcutEnabled, service.fullScreenShortcutRegistrationFailed {
                    unavailable
                }
                Text(text.fullScreenCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(l10n.s.shortcutsPageTitle)
            }

            Section {
                Text(systemShortcutsOn ? text.systemOn : text.systemOff)
                    .font(.caption)
                    .foregroundStyle(systemShortcutsOn ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(text.systemOpen) {
                    if let url = URL(string:
                        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } header: {
                Text(text.systemTitle)
            }

            Section {
                LabeledContent(shot.folderLabel) {
                    HStack(spacing: 6) {
                        Text(folder.isEmpty ? text.defaultFolder : (folder as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(shot.folderChoose) { chooseFolder() }
                        if !folder.isEmpty {
                            Button {
                                folder = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help(text.folderReset)
                            .accessibilityLabel(text.folderReset)
                        }
                    }
                }
                Text(text.folderCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(shot.fileNamePatternLabel, text: $patternDraft)
                    .focused($patternFocused)
                    .onSubmit { commitPattern() }
                    .onChange(of: patternFocused) { _, focused in
                        if !focused { commitPattern() }
                    }
                Text(String(format: text.exampleFormat, example) + "  ·  " + text.patternCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker(l10n.s.mediaFormat, selection: $format) {
                    Text("PNG").tag("png")
                    Text("JPEG").tag("jpg")
                    Text("BMP").tag("bmp")
                }
                .pickerStyle(.segmented)
                LabeledContent(text.jpegQuality) {
                    HStack(spacing: 8) {
                        Slider(value: jpegQualityBinding, in: 10...100, step: 5)
                            .frame(maxWidth: 220)
                            .accessibilityLabel(text.jpegQuality)
                        Text("\(jpegQuality)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                .disabled(format != "jpg")
            } header: {
                Text(text.saving)
            }

            Section {
                Toggle(text.autoCopy, isOn: $autoCopy)
                Toggle(text.notify, isOn: $notify)
                Toggle(text.keepSelection, isOn: $keepSelection)
                Toggle(shot.pointerToggle, isOn: $captureCursor)
                Toggle(text.magnifier, isOn: $magnifier)
            } header: {
                Text(text.behavior)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            patternDraft = pattern
            refreshSystemShortcuts()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSystemShortcuts()
        }
    }

    private var unavailable: some View {
        Text(l10n.s.shortcutUnavailable)
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private var jpegQualityBinding: Binding<Double> {
        Binding(get: { Double(jpegQuality) }, set: { jpegQuality = Int($0.rounded()) })
    }

    private var example: String {
        let ext = ShotFiles.fileExtension(format)
        return ShotFiles.name(pattern: patternDraft, time: Date(), fileExtension: ext) { _ in false } + ext
    }

    private func commitPattern() {
        let trimmed = patternDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        pattern = trimmed.isEmpty ? ShotFiles.defaultPattern : trimmed
        patternDraft = pattern
    }

    private func refreshSystemShortcuts() {
        systemShortcutsOn = !ShotSystemShortcut.enabled(in: GlobalShortcut.systemSymbolicHotKeys).isEmpty
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if !folder.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
        }
        if panel.runModal() == .OK, let url = panel.url {
            folder = url.path
        }
    }
}
