// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import EventKit

struct DockWidgetView: View {
    @ObservedObject var service: DockWidgetService
    let kind: DockWidgetService.Kind
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.headline).lineLimit(1)
                Spacer()
                Button { service.pinned.toggle() } label: { Image(systemName: service.pinned ? "pin.fill" : "pin") }
                    .help(service.pinned ? l10n.s.dockPreviewUnpinPanel : l10n.s.dockPreviewPinPanel)
                Button(action: service.dismiss) { Image(systemName: "xmark") }.help(l10n.s.dockPreviewClosePanel)
            }.buttonStyle(.plain)
            switch kind {
            case .folder(let url): DockFolderView(root: url)
            case .music: DockMusicWidgetView(service: service)
            case .calendar: DockCalendarWidgetView()
            }
        }.padding(12).background(HUDBackdrop(cornerRadius: DockPreviewLayout.radius))
            .clipShape(RoundedRectangle(cornerRadius: DockPreviewLayout.radius))
    }
    private var title: String {
        switch kind {
        case .folder(let url): return url.lastPathComponent
        case .music: return DockEnhancementStrings.text(.media)
        case .calendar: return DockEnhancementStrings.text(.calendar)
        }
    }
}

private struct DockFolderView: View {
    let root: URL
    @State private var directory: URL?
    @State private var entries: [DockFolderEntry] = []
    @State private var error: String?
    @State private var truncated = false
    @State private var order = DockOption.folderSort.string
    @State private var descending = DockOption.folderDescending.bool
    @AppStorage(DockOption.folderHiddenFiles.key) private var hidden = false
    @ObservedObject private var l10n = L10n.shared
    private var folder: URL { directory ?? root }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { directory = folder.deletingLastPathComponent() } label: { Image(systemName: "arrow.up") }
                    .disabled(folder.standardizedFileURL == root.standardizedFileURL)
                Button(folder.lastPathComponent) { NSWorkspace.shared.open(folder) }.lineLimit(1)
                Spacer()
                Picker(DockEnhancementStrings.text(.sort), selection: $order) {
                    Text(DockEnhancementStrings.text(.alphabetical)).tag("name")
                    Text(DockEnhancementStrings.text(.modified)).tag("modified")
                    Text(DockEnhancementStrings.text(.size)).tag("size")
                }.labelsHidden().frame(width: 125)
                Toggle(isOn: $descending) { Image(systemName: "arrow.down") }.toggleStyle(.button)
            }.buttonStyle(.borderless)
            if let error { Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            if entries.isEmpty, error == nil { Text(FeatureStrings.notchFiles(l10n.language).waiting).font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(DockFolderSupport.sorted(entries, by: order, descending: descending)) { entry in
                        Button {
                            if entry.directory { directory = entry.url } else { NSWorkspace.shared.open(entry.url) }
                        } label: {
                            HStack {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().frame(width: 24, height: 24)
                                Text(entry.name).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                if entry.directory { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                            }.padding(.vertical, 4).contentShape(Rectangle())
                        }.buttonStyle(.plain).contextMenu {
                            Button(l10n.s.dockPreviewOpenWindow) { NSWorkspace.shared.open(entry.url) }
                            Button { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) } label: { Image(systemName: "folder") }
                        }
                    }
                }
            }
            if truncated { Button("500+ · " + folder.lastPathComponent) { NSWorkspace.shared.open(folder) }.font(.caption) }
            Toggle(DockEnhancementStrings.text(.hiddenFiles), isOn: $hidden).font(.caption)
        }
        .task(id: folder.path + String(hidden)) { await read() }
        .onChange(of: order) { remember() }.onChange(of: descending) { remember() }
    }
    private func remember() {
        guard DockOption.folderRememberSort.bool else { return }
        var choices = UserDefaults.standard.dictionary(forKey: DockOption.folderSortChoices.key) as? [String: String] ?? [:]
        // Cap local history; paths are deliberately excluded from portable backups.
        if choices.count >= 200, choices[folder.path] == nil { choices.removeAll() }
        choices[folder.path] = order + (descending ? ":desc" : ":asc")
        UserDefaults.standard.set(choices, forKey: DockOption.folderSortChoices.key)
    }
    private func read() async {
        entries = []; error = nil; truncated = false
        if DockOption.folderRememberSort.bool,
           let choice = (UserDefaults.standard.dictionary(forKey: DockOption.folderSortChoices.key) as? [String: String])?[folder.path] {
            let parts = choice.split(separator: ":")
            order = String(parts.first ?? "name"); descending = parts.last == "desc"
        }
        let url = folder, includeHidden = hidden
        let result = await Task.detached(priority: .userInitiated) { () -> Result<(entries: [DockFolderEntry], truncated: Bool), Error> in
            do {
                let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .localizedNameKey]
                let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: includeHidden ? [] : [.skipsHiddenFiles])
                let entries = urls.prefix(500).compactMap { child -> DockFolderEntry? in
                    guard let value = try? child.resourceValues(forKeys: keys) else { return nil }
                    return DockFolderEntry(url: child, name: value.localizedName ?? child.lastPathComponent,
                        directory: value.isDirectory ?? false, modified: value.contentModificationDate ?? .distantPast, size: value.fileSize ?? 0)
                }
                return .success((entries, urls.count > 500))
            } catch { return .failure(error) }
        }.value
        guard !Task.isCancelled, folder == url else { return }
        switch result { case .success(let result): entries = result.entries; truncated = result.truncated; case .failure(let failure): error = failure.localizedDescription }
    }
}

private struct DockMusicWidgetView: View {
    @ObservedObject var service: DockWidgetService
    @ObservedObject private var music = NotchMusicService.shared
    @StateObject private var lyrics = NotchLyricsService(dockOwned: true)
    @AppStorage(DockOption.widgetLyrics.key) private var showsLyrics = false
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        VStack(spacing: 12) {
            if let playback = music.playback {
                HStack {
                    if let artwork = music.artwork { Image(nsImage: artwork).resizable().scaledToFit().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 8)) }
                    VStack(alignment: .leading) {
                        Text(playback.track.title ?? "").font(.headline).lineLimit(2)
                        Text(playback.track.artist ?? "").foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
                HStack(spacing: 24) {
                    Button { _ = music.send(.previous) } label: { Image(systemName: "backward.fill") }
                    Button { _ = music.send(.toggle) } label: { Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill") }
                    Button { _ = music.send(.next) } label: { Image(systemName: "forward.fill") }
                }.buttonStyle(.borderless)
                if !playback.canSendCommandsDirectly, music.automationAvailability?.access != .granted {
                    if music.automationAvailability?.access == .consent {
                        Button(FeatureStrings.notchMusicExtras(l10n.language).allowPlayback, action: music.requestAutomationAccess)
                            .disabled(music.requestingAutomation)
                    } else if music.automationAvailability?.access == .denied {
                        Button(l10n.s.permissionOpenSettings, action: Permissions.shared.openAutomationSettings)
                    }
                }
                if music.commandFailed { Text(FeatureStrings.notchMusicExtras(l10n.language).playbackFailed).font(.caption).foregroundStyle(.secondary) }
                if music.canSeek {
                    TimelineView(.periodic(from: .now, by: 1)) { time in
                        Slider(value: Binding(get: { playback.position(at: time.date) }, set: { music.seek(to: $0, in: playback.track, context: playback.commandContext) }), in: 0...max(1, playback.duration))
                    }
                }
                Toggle(DockEnhancementStrings.text(.lyrics), isOn: $showsLyrics)
                if showsLyrics { NotchLyricsView(playback: playback, service: lyrics) }
            } else { ProgressView() }
            Spacer(minLength: 0)
        }
        .onAppear { lyrics.dockPresentationWindow = service.presentationWindow; service.lyricSession = lyrics; update() }
        .onChange(of: music.playback) { update() }.onChange(of: showsLyrics) { update() }
        .onDisappear { lyrics.stop() }
    }
    private func update() { lyrics.update(playback: music.playback, visible: showsLyrics) }
}

private struct DockCalendarWidgetView: View {
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var day = Date()
    @State private var events: [NotchCalendarEvent] = []
    @State private var reader = NotchCalendarReader()
    @State private var revision = 0
    private var text: NotchCalendarStrings { FeatureStrings.notchCalendar(l10n.language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if permissions.calendarAccess != .fullAccess {
                Text(text.permission).font(.callout)
                Button(text.allow) { permissions.requestCalendar() }
                if permissions.calendarAccess == .denied { Button(text.settings) { permissions.openCalendarSettings() } }
            } else {
                HStack {
                    DatePicker(text.today, selection: $day, displayedComponents: .date).labelsHidden()
                    Button(text.today) { day = Date() }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if events.isEmpty { Text(text.empty).foregroundStyle(.secondary) }
                        ForEach(events) { event in
                            Button {
                                NSWorkspace.shared.open(URL(string: "ical://")!)
                            } label: {
                                HStack(alignment: .top) {
                                    Text(event.allDay ? text.allDay : event.start.formatted(date: .omitted, time: .shortened)).font(.caption).frame(width: 70)
                                    VStack(alignment: .leading) { Text(event.title.isEmpty ? text.untitled : event.title).lineLimit(2); Text(event.calendar).font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in revision += 1 }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in if permissions.calendarAccess == .fullAccess { revision += 1 } }
        .task(id: day.description + String(describing: permissions.calendarAccess) + String(revision)) {
            guard permissions.calendarAccess == .fullAccess, let interval = Calendar.current.dateInterval(of: .day, for: day) else { events = []; return }
            let result = await reader.read(interval: interval, excluded: NotchCalendarSupport.excludedCalendars())
            guard !Task.isCancelled else { return }
            events = result.filter { !Calendar.current.isDateInToday(day) || $0.end > Date() }.sorted { $0.start < $1.start }.prefix(100).map { $0 }
        }
    }
}
