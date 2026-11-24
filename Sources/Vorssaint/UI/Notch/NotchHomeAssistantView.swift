// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import AppKit

struct NotchHomeAssistantSettingsControls: View {
    @ObservedObject private var service = HomeAssistantService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchHomeAssistantEnabled) private var enabled = false
    @Environment(\.notchSettingsPreview) private var preview
    @State private var surface = UUID()
    @State private var url = ""
    @State private var token = ""
    @State private var search = ""
    private var text: HomeAssistantStrings { .localized(l10n.language) }
    private static let logo: NSImage? = Bundle.main.url(forResource: "home-assistant-logo", withExtension: "png", subdirectory: "Images")
        .flatMap { NSImage(contentsOf: $0) }
    private var matches: [HomeAssistantEntity] {
        service.entities.values.filter {
            $0.eligible && (search.isEmpty || service.displayName($0.id).localizedCaseInsensitiveContains(search) || $0.name.localizedCaseInsensitiveContains(search)
                || $0.id.localizedCaseInsensitiveContains(search))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let logo = Self.logo {
                    Image(nsImage: logo).resizable().scaledToFit().frame(width: 40, height: 40).accessibilityHidden(true)
                }
                Toggle("Home Assistant", isOn: $enabled).font(.headline)
            }
            Text(text[.description]).font(.caption).foregroundStyle(.secondary)
            if enabled {
                SettingsCard(title: text[.connectionSettings]) {
                    TextField(text[.url], text: $url).textFieldStyle(.roundedBorder)
                    SecureField(text[.token], text: $token).textFieldStyle(.roundedBorder)
                    Text(text[.tokenHint]).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(text[.connect]) {
                            service.configure(url: url, token: token)
                            token = ""
                        }
                        .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || preview)
                        Button(text[.forget]) { service.forgetConnection(); url = ""; token = "" }
                            .disabled(service.server.isEmpty || preview)
                    }
                    HomeAssistantStatusView()
                }
                SettingsCard(title: text[.pages]) {
                    Picker(text[.defaultColumns], selection: Binding(get: { service.columns }, set: { service.setColumns($0) })) {
                        ForEach(HomeAssistantPresentation.columnOptions, id: \.self) { count in
                            Text(String(count)).tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(text[.pagesHint]).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Picker(text[.page], selection: Binding(get: { service.activePageID }, set: { service.selectPage($0) })) {
                            ForEach(service.pages) { page in Text(service.pageTitle(page, text: text)).tag(page.id) }
                        }
                        Button { service.addPage(); search = "" } label: { Label(text[.createPage], systemImage: "plus") }
                    }
                    if let page = service.pages.first(where: { $0.id == service.activePageID }) {
                        HStack {
                            HomeAssistantPageNameField(page: page).id(page.id)
                            Button { service.movePage(page.id, by: -1) } label: { Image(systemName: "chevron.up") }
                                .help(text[.up]).accessibilityLabel(text[.up]).disabled(service.pages.first?.id == page.id)
                            Button { service.movePage(page.id, by: 1) } label: { Image(systemName: "chevron.down") }
                                .help(text[.down]).accessibilityLabel(text[.down]).disabled(service.pages.last?.id == page.id)
                            Button { service.removePage(page.id) } label: { Image(systemName: "trash") }
                                .help(text[.deletePage]).accessibilityLabel(text[.deletePage]).disabled(service.pages.count <= 1)
                        }
                        Toggle(text[.customColumns], isOn: Binding(get: { page.columns != nil }, set: {
                            service.setPageColumns($0 ? service.columns : nil, pageID: page.id)
                        })).toggleStyle(.checkbox)
                        if page.columns != nil {
                            Picker(text[.entitiesPerRow], selection: Binding(get: { page.effectiveColumns(default: service.columns) }, set: {
                                service.setPageColumns($0, pageID: page.id)
                            })) {
                                ForEach(HomeAssistantPresentation.columnOptions, id: \.self) { count in
                                    Text(String(count)).tag(count)
                                }
                            }.pickerStyle(.segmented)
                        }
                        Toggle(text[.fillLastRow], isOn: Binding(get: { page.fillLastRow }, set: {
                            service.setPageFillLastRow($0, pageID: page.id)
                        })).toggleStyle(.checkbox)
                        Text(text[.fillLastRowHint]).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(text[.visibleEntities]).font(.subheadline.weight(.semibold))
                    if !service.visibleEntityIDs.isEmpty {
                        ForEach(service.visibleEntityIDs, id: \.self) { id in entityRow(id) }
                    }
                    Divider()
                    Text(text[.addEntities]).font(.subheadline.weight(.semibold))
                    TextField(text[.search], text: $search).textFieldStyle(.roundedBorder)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(matches) { entity in
                                Toggle(isOn: Binding(get: { service.visibleEntityIDs.contains(entity.id) },
                                                     set: { service.setFavorite(entity.id, selected: $0) })) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Label(service.displayName(entity.id), systemImage: entity.symbol)
                                        Text(entity.id).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
            }
        }
        .disabled(!AppFeature.notchHomeAssistant.isAvailable || preview)
        .onAppear { url = service.server; if !preview { service.setVisible(true, surface: surface) } }
        .onDisappear { if !preview { service.setVisible(false, surface: surface) }; token = "" }
        .onChange(of: service.server) { url = service.server }
        .onChange(of: enabled) {
            service.syncWithPreferences()
            NotchService.shared.syncWithPreferences()
        }
    }
    private func entityRow(_ id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HomeAssistantNameField(id: id)
                Spacer(minLength: 4)
                Button { service.moveFavorite(id, by: -1) } label: { Image(systemName: "chevron.up") }
                    .help(text[.up]).accessibilityLabel(text[.up]).disabled(service.visibleEntityIDs.first == id)
                Button { service.moveFavorite(id, by: 1) } label: { Image(systemName: "chevron.down") }
                    .help(text[.down]).accessibilityLabel(text[.down]).disabled(service.visibleEntityIDs.last == id)
                entityPageMenu(id)
                Button { service.setFavorite(id, selected: false) } label: { Image(systemName: "minus.circle") }
                    .help(l10n.s.actionRemove).accessibilityLabel(l10n.s.actionRemove)
            }
            HomeAssistantExtraInfoSettings(id: id)
        }
        .padding(10).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private func entityPageMenu(_ id: String) -> some View {
        let sourceID = service.activePageID
        let destinations = service.pages.filter { $0.id != sourceID }
        return Menu {
            Menu(text[.moveEntity]) {
                ForEach(destinations) { page in
                    Button(service.pageTitle(page, text: text)) {
                        service.transferEntity(id, from: sourceID, to: page.id, duplicate: false)
                    }
                }
            }
            Menu(text[.duplicateEntity]) {
                ForEach(destinations) { page in
                    Button(service.pageTitle(page, text: text)) {
                        service.transferEntity(id, from: sourceID, to: page.id, duplicate: true)
                    }.disabled(page.entities.contains(id))
                }
            }
        } label: { Image(systemName: "ellipsis") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(text[.entityOptions]).accessibilityLabel(text[.entityOptions])
        .disabled(destinations.isEmpty)
    }

}

private struct HomeAssistantPageNameField: View {
    let page: HomeAssistantPage
    @ObservedObject private var service = HomeAssistantService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var draft = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField(HomeAssistantStrings.localized(l10n.language)[.pageTitle], text: $draft)
            .textFieldStyle(.roundedBorder).focused($focused)
            .onAppear { draft = page.title }
            .onChange(of: draft) { service.renamePage(page.id, title: draft) }
            .onChange(of: page.title) { if !focused { draft = page.title } }
    }
}

private struct HomeAssistantStatusView: View {
    @ObservedObject private var service = HomeAssistantService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: HomeAssistantStrings { .localized(l10n.language) }
    var body: some View {
        HomeAssistantConnectionStatus(connection: service.connection, failure: service.failure, text: text)
    }
}

private struct HomeAssistantConnectionStatus: View {
    let connection: HomeAssistantConnection
    let failure: HomeAssistantFailure?
    let text: HomeAssistantStrings
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if connection == .connecting { ProgressView().controlSize(.small) }
                else { Circle().fill(connection == .connected ? Color.green : Color.orange).frame(width: 5, height: 5) }
                Text(text.status(connection)).font(.caption).foregroundStyle(.secondary)
            }
            if let failure {
                Text(text.error(failure)).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct NotchHomeAssistantView: View {
    let size: CGSize
    @StateObject private var model = HomeAssistantIslandModel(service: HomeAssistantService.shared)
    @StateObject private var paging = HomeAssistantPagingSession()
    private var service: HomeAssistantService { .shared }
    private var state: HomeAssistantIslandState { model.state }
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchSettingsPreview) private var preview
    @State private var surface = UUID()
    @State private var selected: String?
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: HomeAssistantStrings { .localized(l10n.language) }
    private var grid: NotchHomeAssistantLayout { .init(count: state.favorites.count, columns: state.columns, pageCount: state.pages.count) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HomeAssistantConnectionStatus(connection: state.connection, failure: state.failure, text: text)
                Spacer(minLength: 4)
                if let url = service.dashboardURL {
                    Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.forward.app") }
                        .help(text[.dashboard]).accessibilityLabel(text[.dashboard]).disabled(preview)
                }
                Button { NotchService.shared.openSettings(showing: .homeAssistant) } label: { Image(systemName: "gearshape") }
                    .help(text[.setup]).accessibilityLabel(text[.setup]).disabled(preview)
            }
            if selected == nil && state.pages.count > 1 { pageNavigation }
            if let selected {
                Button { self.selected = nil } label: { Label(l10n.s.actionBack, systemImage: "chevron.left") }
                ScrollView {
                    if let entity = state.entities[selected], entity.eligible {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(state.displayName(entity.id), systemImage: entity.symbol).font(.headline)
                            Text(reading(entity)).foregroundStyle(.secondary)
                            HomeAssistantEntityControls(entity: entity)
                                .disabled(state.connection != .connected || !entity.available || state.pending.contains(entity.id) || preview)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else { Text(text[.unsupported]) }
                }
            } else {
                NotchHomeAssistantGallery(ids: state.favorites, columns: state.columns, fillLastRow: state.fillLastRow, layout: grid,
                                          availableHeight: max(0, size.height - NotchHomeAssistantLayout.toolbarHeight - grid.navigationHeight),
                                          pageID: state.activePageID, preview: preview, empty: text[.empty], session: paging,
                                          changePage: changePage, tile: tile)
                    .id(state.activePageID)
                    .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                    .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0), value: state.activePageID)
            }
        }
        .buttonStyle(.borderless)
        .frame(width: size.width, height: size.height, alignment: .top)
        .onChange(of: state.server) { selected = nil }
        .onChange(of: state.activePageID) { selected = nil; paging.rows = NotchSectionScroll() }
        .onChange(of: selected) {
            if !preview {
                NotchService.shared.setPageLayer(.homeAssistant, close: selected == nil ? nil : { selected = nil })
            }
        }
        .onAppear { if !preview { service.setVisible(true, surface: surface) } }
        .onDisappear {
            if !preview {
                service.setVisible(false, surface: surface)
                NotchService.shared.setPageLayer(.homeAssistant, close: nil)
            }
        }
    }
    private var pageNavigation: some View {
        let index = state.pages.firstIndex { $0.id == state.activePageID } ?? 0
        let page = state.pages.first { $0.id == state.activePageID }
        return HStack(spacing: 8) {
            Button { changePage(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(index == 0).help(text[.previousPage]).accessibilityLabel(text[.previousPage])
            Text(page.map { service.pageTitle($0, text: text) } ?? text[.page])
                .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(page?.title ?? "")
            Text("\(index + 1)/\(state.pages.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Button { changePage(1) } label: { Image(systemName: "chevron.right") }
                .disabled(index >= state.pages.count - 1).help(text[.nextPage]).accessibilityLabel(text[.nextPage])
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 8, lifts: false))
        .disabled(preview)
        .frame(height: 26)
    }
    private func changePage(_ offset: Int) {
        guard !preview else { return }
        forward = offset > 0
        service.advancePage(by: offset)
    }
    private func reading(_ entity: HomeAssistantEntity) -> String {
        let reading = HomeAssistantPresentation.reading(entity, text: text, temperatureUnit: state.temperatureUnit,
                                                       locale: Locale(identifier: l10n.language.rawValue))
        return [reading.value, reading.unit].filter { !$0.isEmpty }.joined(separator: " ")
    }
    private func tile(_ id: String, columns: Int) -> some View {
        let pageID = state.activePageID
        return NotchHomeAssistantEntityTile(entity: state.entities[id], name: state.displayName(id), columns: columns,
                                    connected: state.connection == .connected && !preview,
                                    pending: state.pending.contains(id), text: text, height: grid.cardHeight,
                                    readings: state.cardReadings(id, text: text, locale: Locale(identifier: l10n.language.rawValue)),
                                    locale: Locale(identifier: l10n.language.rawValue), temperatureUnit: state.temperatureUnit,
                                    activate: {
                                        guard service.activePageID == pageID else { return }
                                        if let action = service.entities[id]?.primaryService { service.perform(action, entityID: id) }
                                    }, details: { if service.activePageID == pageID { selected = id } },
                                    setBrightness: { if service.activePageID == pageID { service.setBrightness($0, entityID: id) } },
                                    setColor: { if service.activePageID == pageID { service.setColor($0, entityID: id) } })
            .equatable()
    }
}

/// Sensors are separate HA entities; associate them explicitly rather than guessing from names.
private struct HomeAssistantExtraInfoSettings: View {
    let id: String
    @ObservedObject private var service = HomeAssistantService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var search = ""
    @State private var renaming: String?
    private var text: HomeAssistantStrings { .localized(l10n.language) }
    private var selected: [String] { service.sensors[id] ?? [] }
    private var matches: [HomeAssistantEntity] {
        service.entities.values.filter {
            $0.isSensor && $0.id != id && (search.isEmpty || selected.contains($0.id)
                || service.displayName($0.id).localizedCaseInsensitiveContains(search) || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        DisclosureGroup(text[.extraInfo]) {
            VStack(alignment: .leading, spacing: 8) {
                Text(text[.liveHint]).font(.caption).foregroundStyle(.secondary)
                TextField(text[.search], text: $search).textFieldStyle(.roundedBorder)
                sensorPicker(0, label: .firstSensor)
                if !selected.isEmpty { sensorPicker(1, label: .secondSensor) }
            }.padding(.top, 6)
        }.font(.caption)
        .popover(isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            if let sensor = renaming { HomeAssistantSensorNameEditor(id: sensor, close: { renaming = nil }) }
        }
        .onChange(of: selected) { if let sensor = renaming, !selected.contains(sensor) { renaming = nil } }
        .onChange(of: service.server) { renaming = nil }
    }
    private func sensorPicker(_ index: Int, label: HomeAssistantText) -> some View {
        HStack(spacing: 6) {
            Picker(text[label], selection: Binding(get: { selected.indices.contains(index) ? selected[index] : "" }, set: { value in
                var ids = selected
                if ids.indices.contains(index) {
                    if value.isEmpty { ids.remove(at: index) } else { ids[index] = value }
                } else if !value.isEmpty { ids.append(value) }
                service.setSensors(ids, for: id)
            })) {
                Text(text[.none]).tag("")
                ForEach(matches) { sensor in
                    Text(service.displayName(sensor.id) + " · " + sensor.id).tag(sensor.id)
                }
                ForEach(selected.filter { service.entities[$0] == nil }, id: \.self) { missing in
                    Text(service.displayName(missing) + " · " + text[.unavailable]).tag(missing)
                }
            }
            Button {
                if selected.indices.contains(index) { renaming = selected[index] }
            } label: { Image(systemName: "pencil") }
            .buttonStyle(.borderless).disabled(!selected.indices.contains(index))
            .help(text[.rename]).accessibilityLabel(text[.rename] + ": " + (selected.indices.contains(index) ? service.displayName(selected[index]) : text[label]))
        }
    }
}

private struct HomeAssistantSensorNameEditor: View {
    let id: String
    let close: () -> Void
    @ObservedObject private var service = HomeAssistantService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var draft = ""
    @FocusState private var focused: Bool
    private var text: HomeAssistantStrings { .localized(l10n.language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text[.rename]).font(.headline)
            TextField(text[.customName], text: $draft, prompt: Text(service.entities[id]?.name ?? id))
                .textFieldStyle(.roundedBorder).focused($focused).onSubmit(close)
            Text(id).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(text[.originalName]) { draft = "" }
                Spacer()
                Button(text[.close], action: close)
            }
        }
        .padding(16).frame(width: 300)
        .onAppear { draft = service.names[id] ?? ""; focused = true }
        .onChange(of: draft) { service.setName(draft, for: id) }
    }
}

/// Keep the draft separate so trimming stored aliases does not interrupt typing spaces.
private struct HomeAssistantNameField: View {
    let id: String
    @ObservedObject private var service = HomeAssistantService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var draft = ""
    @FocusState private var focused: Bool
    private var text: HomeAssistantStrings { .localized(l10n.language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField(text[.customName], text: $draft, prompt: Text(service.entities[id]?.name ?? id))
                .textFieldStyle(.roundedBorder).focused($focused)
                .accessibilityLabel(text[.customName] + ": " + id)
            Text(id).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .onAppear { draft = service.names[id] ?? "" }
        .onChange(of: draft) { if focused { service.setName(draft, for: id) } }
        .onChange(of: focused) { if !focused { draft = service.names[id] ?? "" } }
        .onChange(of: service.names) { if !focused { draft = service.names[id] ?? "" } }
        .onChange(of: service.server) { focused = false; draft = service.names[id] ?? "" }
    }
}

private struct HomeAssistantEntityControls: View {
    let entity: HomeAssistantEntity
    @ObservedObject private var service = HomeAssistantService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var brightness = 50.0
    @State private var position = 50.0
    @State private var temperature = 20.0
    @State private var low = 18.0
    @State private var high = 24.0
    @State private var editing = false
    private var text: HomeAssistantStrings { .localized(l10n.language) }
    private var temperatureRange: ClosedRange<Double> {
        entity.temperatureRange ?? 7...35
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch entity.domain {
            case "light", "switch":
                HStack {
                    action(.on, "turn_on"); action(.off, "turn_off")
                }
                if entity.domain == "light", entity.hasBrightness {
                    slider(.brightness, value: $brightness, range: 0...100, step: 1) {
                        service.setBrightness(brightness, entityID: entity.id)
                    }
                }
            case "scene", "script": action(.run, "turn_on")
            case "cover":
                HStack {
                    if entity.supports(1) { action(.open, "open_cover") }
                    if entity.supports(2) { action(.close, "close_cover") }
                    if entity.supports(8) { action(.stop, "stop_cover") }
                }
                if entity.supports(4) {
                    slider(.position, value: $position, range: 0...100, step: 1) {
                        service.perform("set_cover_position", entityID: entity.id, data: ["position": .number(position.rounded())])
                    }
                }
            case "climate":
                if let current = entity.attributes["current_temperature"]?.number {
                    Text(text[.temperature] + ": " + current.formatted() + " " + service.temperatureUnit)
                }
                if !entity.modes.isEmpty {
                    Menu(text[.mode] + ": " + text.state(entity.state)) {
                        ForEach(entity.modes, id: \.self) { mode in
                            Button(text.state(mode)) { service.perform("set_hvac_mode", entityID: entity.id, data: ["hvac_mode": .string(mode)]) }
                        }
                    }
                }
                if entity.state == "heat_cool", entity.supports(2), entity.temperatureRange != nil {
                    slider(.low, value: $low, range: temperatureRange, step: temperatureStep, commit: setRange)
                    slider(.high, value: $high, range: temperatureRange, step: temperatureStep, commit: setRange)
                } else if entity.supports(1), entity.temperatureRange != nil {
                    slider(.temperature, value: $temperature, range: temperatureRange, step: temperatureStep) {
                        service.perform("set_temperature", entityID: entity.id, data: ["temperature": .number(temperature)])
                    }
                }
            default: EmptyView()
            }
        }
        .onAppear(perform: readValues)
        .onChange(of: entity) { if !editing, !service.pending.contains(entity.id) { readValues() } }
        .onChange(of: service.pending) { if !editing, !service.pending.contains(entity.id) { readValues() } }
    }
    private var temperatureStep: Double {
        min(temperatureRange.upperBound - temperatureRange.lowerBound,
            max(0.1, entity.attributes["target_temp_step"]?.number ?? 0.5))
    }
    private func setRange() {
        if low > high { high = low }
        service.perform("set_temperature", entityID: entity.id,
                        data: ["target_temp_low": .number(low), "target_temp_high": .number(high)])
    }
    private func readValues() {
        brightness = entity.brightnessPercent
        position = min(100, max(0, entity.attributes["current_position"]?.number ?? 50))
        func bounded(_ key: String, _ fallback: Double) -> Double {
            min(temperatureRange.upperBound, max(temperatureRange.lowerBound, entity.attributes[key]?.number ?? fallback))
        }
        temperature = bounded("temperature", 20)
        low = bounded("target_temp_low", 18); high = bounded("target_temp_high", 24)
    }
    private func action(_ label: HomeAssistantText, _ name: String) -> some View {
        Button(text[label]) { service.perform(name, entityID: entity.id) }
    }
    private func slider(_ label: HomeAssistantText, value: Binding<Double>, range: ClosedRange<Double>,
                        step: Double, commit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text[label] + ": " + value.wrappedValue.formatted() + (label == .brightness ? "%" : "")).font(.caption)
            Slider(value: value, in: range, step: step) { active in
                editing = active
                if !active { commit() }
            }.accessibilityLabel(text[label])
        }
    }
}
