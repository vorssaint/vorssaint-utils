// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Everything about converting files, as sections of the Shelf page: whether
/// the island offers it, where results go, quality, which formats show, the
/// drag keys, the engines with a self-test, and the recent results. The layout
/// follows the Windows Convert app's settings: General, Triggers, Wheels
/// (here, formats), Output, Engines and Recent.
struct ConvertSettingsSections: View {
    @AppStorage(DefaultsKey.convertEnabled) private var enabled = true
    @AppStorage(DefaultsKey.convertOutputLocation) private var location = OutputLocation.besideOriginal.rawValue
    @AppStorage(DefaultsKey.convertRevealInFinder) private var reveal = false
    @AppStorage(DefaultsKey.convertJPEGQuality) private var quality = 0.9
    @AppStorage(DefaultsKey.convertHiddenFormats) private var hiddenRaw = ""
    @AppStorage(DefaultsKey.convertKeyConvert) private var keyConvert = true
    @AppStorage(DefaultsKey.convertKeyTools) private var keyTools = true
    @AppStorage(DefaultsKey.convertKeyActions) private var keyActions = true
    @AppStorage(DefaultsKey.convertFFmpegPath) private var ffmpegPath = ""
    @State private var recents = ConvertRecents.all()
    @State private var testing = false
    @State private var testLines: [String] = []
    @State private var health: FFmpeg.Health?

    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        Group {
            Section("Convert") {
                Toggle("Offer “Convert here” when dragging files to the island", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in ConvertDragMonitor.shared.sync() }
                Text("Drag a file to the island and drop it on Convert here to pick a format and its options. Everything runs on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if enabled {
                Section("Drag keys") {
                    Toggle("Hold ⇧ Shift while dragging to convert", isOn: $keyConvert)
                        .onChange(of: keyConvert) { _, _ in ConvertDragMonitor.shared.sync() }
                    Toggle("Hold ⌘ Command (or ⌥ Option + ⇧ Shift) for tools", isOn: $keyTools)
                        .onChange(of: keyTools) { _, _ in ConvertDragMonitor.shared.sync() }
                    Toggle("Hold ⌃ Control for file actions", isOn: $keyActions)
                        .onChange(of: keyActions) { _, _ in ConvertDragMonitor.shared.sync() }
                    Text("The island opens on the matching page while you drag, so you can drop straight onto a format.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Output") {
                    Picker("Save results", selection: $location) {
                        ForEach(OutputLocation.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Toggle("Show the result in Finder", isOn: $reveal)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Default image quality")
                            Spacer()
                            Text("\(Int(quality * 100))%").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $quality, in: 0.2...1)
                    }
                    Text("Your originals are never changed. A name already taken becomes “name 2”.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Formats") {
                    ForEach(FormatCategory.allCases, id: \.self) { category in
                        DisclosureGroup {
                            ForEach(FileFormat.allCases.filter { $0.category == category }) { format in
                                Toggle(format.displayName, isOn: Binding(
                                    get: { !hidden.contains(format.rawValue) },
                                    set: { setShown(format, $0) }))
                            }
                        } label: {
                            Label(category.title, systemImage: category.symbol)
                        }
                    }
                    Text("A format switched off is not offered as a target. Reading it stays possible.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Engines") {
                    engineRow
                    HStack {
                        TextField("ffmpeg path (blank for automatic)", text: $ffmpegPath).textFieldStyle(.roundedBorder)
                        Button("Choose…") { chooseFFmpeg() }
                    }
                    Button {
                        runSelfTest()
                    } label: {
                        Label(testing ? "Testing…" : "Test every converter", systemImage: "checkmark.seal")
                    }
                    .disabled(testing)
                    if !testLines.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(testLines.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(line.hasPrefix("FAIL") ? .red : line.hasPrefix("SKIP") ? .orange : .secondary)
                            }
                        }
                    }
                }
                Section("Recent") {
                    if recents.isEmpty {
                        Text("Nothing converted yet.").font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(recents.prefix(10)) { entry in
                            HStack {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.path)).resizable().frame(width: 18, height: 18)
                                Text(URL(fileURLWithPath: entry.path).lastPathComponent).lineLimit(1)
                                Spacer()
                                Text(entry.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                                Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)]) } label: {
                                    Image(systemName: "magnifyingglass")
                                }.buttonStyle(.plain).help("Show in Finder")
                            }
                        }
                        Button("Clear") { ConvertRecents.clear() }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .convertRecentsChanged)) { _ in recents = ConvertRecents.all() }
        .task { health = await FFmpeg.checkHealth() }
    }

    @ViewBuilder private var engineRow: some View {
        switch health {
        case .ready(let path, let version)?:
            Label("ffmpeg \(version) ready — \(path)", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
        case .broken(let path, let reason)?:
            Label("ffmpeg at \(path) does not run: \(reason)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
        case .missing?:
            Label("ffmpeg not found. Video and some audio formats need it.", systemImage: "xmark.circle").foregroundStyle(.orange).font(.callout)
        case nil:
            Label("Checking ffmpeg…", systemImage: "hourglass").font(.callout)
        }
    }

    private func setShown(_ format: FileFormat, _ shown: Bool) {
        var set = hidden
        if shown { set.remove(format.rawValue) } else { set.insert(format.rawValue) }
        hiddenRaw = set.sorted().joined(separator: ",")
    }

    private func chooseFFmpeg() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        if panel.runModal() == .OK, let url = panel.url {
            ffmpegPath = url.path
            Task { health = await FFmpeg.checkHealth() }
        }
    }

    private func runSelfTest() {
        testing = true
        testLines = []
        Task { @MainActor in
            let lines = await ConvertSelfTest.runForSettings()
            testLines = lines
            testing = false
        }
    }
}
