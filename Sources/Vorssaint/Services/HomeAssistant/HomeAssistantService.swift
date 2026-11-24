// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Security
import LocalAuthentication

protocol HomeAssistantCredentialStore {
    func read(server: String) throws -> String?
    func save(_ token: String, server: String) throws
    func remove(server: String) throws
}

/// The island observes only its cards and associated readings, not the full
/// server. Settings retain access to every entity for selection and search.
struct HomeAssistantIslandState: Equatable {
    let pages: [HomeAssistantPage]
    let activePageID: String
    let favorites: [String]
    let columns: Int
    let fillLastRow: Bool
    let entities: [String: HomeAssistantEntity]
    let names: [String: String]
    let sensors: [String: [String]]
    let pending: Set<String>
    let connection: HomeAssistantConnection
    let failure: HomeAssistantFailure?
    let temperatureUnit: String
    let server: String

    init(service: HomeAssistantService) {
        pages = service.pages
        activePageID = service.activePageID
        favorites = service.visibleEntityIDs
        columns = service.effectiveColumns
        fillLastRow = service.activePage?.fillLastRow ?? false
        sensors = favorites.reduce(into: [:]) { $0[$1] = service.sensors[$1] }
        let ids = Set(favorites + sensors.values.flatMap { $0 })
        entities = ids.reduce(into: [:]) { $0[$1] = service.entities[$1] }
        names = ids.reduce(into: [:]) { $0[$1] = service.names[$1] }
        pending = service.pending.intersection(favorites)
        connection = service.connection
        failure = service.failure
        temperatureUnit = service.temperatureUnit
        server = service.server
    }
    func displayName(_ id: String) -> String { names[id] ?? entities[id]?.name ?? id }
    func cardReadings(_ owner: String, text: HomeAssistantStrings, locale: Locale) -> [HomeAssistantCardReading] {
        (sensors[owner] ?? []).map { id in
            let reading = entities[id].map { HomeAssistantPresentation.reading($0, text: text, temperatureUnit: temperatureUnit, locale: locale) }
            return HomeAssistantCardReading(id: id, name: displayName(id), value: reading?.value ?? text[.unavailable], unit: reading?.unit ?? "")
        }
    }
}

final class HomeAssistantIslandModel: ObservableObject {
    @Published private(set) var state: HomeAssistantIslandState
    private var subscription: AnyCancellable?

    init(service: HomeAssistantService) {
        state = HomeAssistantIslandState(service: service)
        // @Published sends before storing. Read after the mutation, at most
        // once per frame, without delaying network events or action confirmation.
        subscription = service.objectWillChange.receive(on: DispatchQueue.main)
            .throttle(for: .milliseconds(16), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self, weak service] _ in
                guard let self, let service else { return }
                let next = HomeAssistantIslandState(service: service)
                if next != self.state { self.state = next }
            }
    }
}

struct HomeAssistantKeychain: HomeAssistantCredentialStore {
    static var serviceName: String {
        #if VORSSAINT_DEVELOPMENT
        return "com.vorssaint.utils.dev.home-assistant"
        #else
        return "com.vorssaint.utils.home-assistant"
        #endif
    }
    private func query(_ server: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.serviceName,
         kSecAttrAccount as String: server, kSecAttrSynchronizable as String: false]
    }
    func read(server: String) throws -> String? {
        var query = query(server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { throw HomeAssistantFailure.keychain }
        return token
    }
    func save(_ token: String, server: String) throws {
        let data = Data(token.utf8)
        let existing = query(server)
        let status = SecItemUpdate(existing as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = existing
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw HomeAssistantFailure.keychain }
        } else if status != errSecSuccess { throw HomeAssistantFailure.keychain }
    }
    func remove(server: String) throws {
        let status = SecItemDelete(query(server) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw HomeAssistantFailure.keychain }
    }
}

enum HomeAssistantConnection: Equatable {
    case unconfigured, connecting, connected, offline
}

/// Main-thread service, like the other feature runtimes. Network message handling lives in the client actor.
final class HomeAssistantService: ObservableObject {
    private(set) static var current: HomeAssistantService?
    static var shared: HomeAssistantService {
        if let current { return current }
        let service = HomeAssistantService()
        current = service
        return service
    }
    @Published private(set) var connection: HomeAssistantConnection = .unconfigured
    // Keep one state dictionary: publishing a copy on each sensor event forces
    // a copy of the entire server on the next mutation.
    var entities: [String: HomeAssistantEntity] { store.entities }
    @Published private(set) var temperatureUnit = ""
    @Published private(set) var favorites: [String] = []
    @Published private(set) var pages: [HomeAssistantPage] = []
    @Published private(set) var activePageID = HomeAssistantPages.initialID
    @Published private(set) var columns = 2
    @Published private(set) var names: [String: String] = [:]
    @Published private(set) var sensors: [String: [String]] = [:]
    @Published private(set) var pending: Set<String> = []
    @Published private(set) var failure: HomeAssistantFailure?
    private let defaults: UserDefaults
    private let credentials: any HomeAssistantCredentialStore
    private let makeTransport: (URL) -> any HomeAssistantTransport
    private var surfaces: Set<UUID> = []
    private var task: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var commandTasks: [String: Task<Void, Never>] = [:]
    private var client: HomeAssistantClient?
    private var generation = UUID()
    private var store = HomeAssistantStateStore()
    private var confirmations: [String: HomeAssistantAction] = [:]
    private var observers: [NSObjectProtocol] = []
    private var sleeping = false
    private var activeServer: String?
    private var authenticationFailureServer: String?

    init(defaults: UserDefaults = .standard, credentials: any HomeAssistantCredentialStore = HomeAssistantKeychain(),
         makeTransport: @escaping (URL) -> any HomeAssistantTransport = { HomeAssistantWebSocket(url: $0) },
         observesSleep: Bool = true) {
        self.defaults = defaults; self.credentials = credentials; self.makeTransport = makeTransport
        reloadPreferences()
        if observesSleep {
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.setSleeping(true)
            })
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.setSleeping(false)
            })
        }
    }
    deinit { observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) } }

    var server: String { defaults.string(forKey: DefaultsKey.notchHomeAssistantURL) ?? "" }
    var activePage: HomeAssistantPage? { pages.first { $0.id == activePageID } }
    var visibleEntityIDs: [String] { activePage?.entities ?? [] }
    var effectiveColumns: Int { activePage?.effectiveColumns(default: columns) ?? columns }
    func pageTitle(_ page: HomeAssistantPage, text: HomeAssistantStrings) -> String {
        page.title.isEmpty ? text[.page] + " " + String((pages.firstIndex { $0.id == page.id } ?? 0) + 1) : page.title
    }
    var dashboardURL: URL? { try? HomeAssistantConfiguration(server).baseURL }
    var enabled: Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchHomeAssistant.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchHomeAssistantEnabled)
            && NotchSupport.modules(in: defaults).contains(.homeAssistant)
    }
    func setSleeping(_ sleeping: Bool) {
        self.sleeping = sleeping
        syncWithPreferences()
    }
    func setVisible(_ visible: Bool, surface: UUID) {
        if visible { surfaces.insert(surface) } else { surfaces.remove(surface) }
        syncWithPreferences()
    }
    private func reloadPreferences() {
        let loaded = HomeAssistantPages.load(in: defaults)
        if loaded != pages { pages = loaded }
        let selected = defaults.string(forKey: DefaultsKey.notchHomeAssistantActivePage) ?? ""
        let active = loaded.contains { $0.id == selected } ? selected : loaded[0].id
        if active != activePageID { activePageID = active }
        favorites = HomeAssistantPages.allEntityIDs(loaded)
        // Migrate the original flat selection once, preserving names and sensors.
        if (defaults.array(forKey: DefaultsKey.notchHomeAssistantPages) ?? []).isEmpty { persistPages() }
        columns = HomeAssistantPresentation.columns(defaults.integer(forKey: DefaultsKey.notchHomeAssistantColumns))
        names = (defaults.dictionary(forKey: DefaultsKey.notchHomeAssistantNames) ?? [:]).reduce(into: [:]) { result, pair in
            if let name = pair.value as? String, let normalized = HomeAssistantPresentation.customName(name) {
                result[pair.key] = normalized
            }
        }
        sensors = (defaults.dictionary(forKey: DefaultsKey.notchHomeAssistantSensors) ?? [:]).reduce(into: [:]) { result, pair in
            if let values = pair.value as? [String] {
                let ids = HomeAssistantPresentation.sensorIDs(values, excluding: pair.key)
                if !ids.isEmpty { result[pair.key] = ids }
            }
        }
    }
    func setSensors(_ ids: [String], for owner: String) {
        guard favorites.contains(owner) else { return }
        let ids = HomeAssistantPresentation.sensorIDs(ids, excluding: owner)
        sensors[owner] = ids.isEmpty ? nil : ids
        defaults.set(sensors, forKey: DefaultsKey.notchHomeAssistantSensors)
    }
    func cardReadings(_ owner: String, text: HomeAssistantStrings, locale: Locale) -> [HomeAssistantCardReading] {
        (sensors[owner] ?? []).map { id in
            let reading = entities[id].map { HomeAssistantPresentation.reading($0, text: text, temperatureUnit: temperatureUnit, locale: locale) }
            return HomeAssistantCardReading(id: id, name: displayName(id), value: reading?.value ?? text[.unavailable], unit: reading?.unit ?? "")
        }
    }
    func setColumns(_ value: Int) {
        columns = HomeAssistantPresentation.columns(value)
        defaults.set(columns, forKey: DefaultsKey.notchHomeAssistantColumns)
    }
    func displayName(_ id: String) -> String { names[id] ?? entities[id]?.name ?? id }
    func setName(_ name: String, for id: String) {
        names[id] = HomeAssistantPresentation.customName(name)
        defaults.set(names, forKey: DefaultsKey.notchHomeAssistantNames)
    }
    private func clearEntityPreferences() {
        sensors = [:]
        defaults.set([String: [String]](), forKey: DefaultsKey.notchHomeAssistantSensors)
        names = [:]
        defaults.set([String: String](), forKey: DefaultsKey.notchHomeAssistantNames)
    }
    func setBrightness(_ percent: Double, entityID: String) {
        guard let entity = entities[entityID], let action = try? HomeAssistantAction.brightness(percent, entity: entity) else { return }
        perform(action.service, entityID: entityID, data: action.data)
    }
    func setColor(_ rgb: HomeAssistantRGB, entityID: String) {
        guard let entity = entities[entityID], let action = try? HomeAssistantAction.color(rgb, entity: entity) else { return }
        perform(action.service, entityID: entityID, data: action.data)
    }
    func setFavorite(_ id: String, selected: Bool) {
        setEntity(id, selected: selected, pageID: activePageID)
    }
    func moveFavorite(_ id: String, by offset: Int) {
        guard let page = pages.firstIndex(where: { $0.id == activePageID }),
              let index = pages[page].entities.firstIndex(of: id),
              (offset > 0 ? offset <= pages[page].entities.count - 1 - index : offset >= -index) else { return }
        pages[page].entities.swapAt(index, index + offset)
        persistPages()
    }
    private func persistPages() {
        favorites = HomeAssistantPages.allEntityIDs(pages)
        defaults.set(pages.map(\.dictionary), forKey: DefaultsKey.notchHomeAssistantPages)
        defaults.set(activePageID, forKey: DefaultsKey.notchHomeAssistantActivePage)
        defaults.set(favorites, forKey: DefaultsKey.notchHomeAssistantFavorites)
    }
    private func resetPages() {
        pages = [HomeAssistantPage(id: HomeAssistantPages.initialID, title: "", entities: [])]
        activePageID = pages[0].id
        persistPages()
    }
    @discardableResult func addPage() -> String {
        let page = HomeAssistantPage(id: UUID().uuidString, title: "", entities: [])
        pages.append(page); activePageID = page.id; persistPages()
        return page.id
    }
    func renamePage(_ id: String, title: String) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        let normalized = HomeAssistantPresentation.customName(title) ?? ""
        guard pages[index].title != normalized else { return }
        pages[index].title = normalized; persistPages()
    }
    func setPageColumns(_ value: Int?, pageID: String) {
        guard let index = pages.firstIndex(where: { $0.id == pageID }) else { return }
        let normalized = value.flatMap { HomeAssistantPresentation.columnOptions.contains($0) ? $0 : nil }
        guard pages[index].columns != normalized else { return }
        pages[index].columns = normalized
        persistPages()
    }
    func setPageFillLastRow(_ value: Bool, pageID: String) {
        guard let index = pages.firstIndex(where: { $0.id == pageID }), pages[index].fillLastRow != value else { return }
        pages[index].fillLastRow = value
        persistPages()
    }
    func removePage(_ id: String) {
        guard pages.count > 1, let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages.remove(at: index)
        if activePageID == id { activePageID = pages[min(index, pages.count - 1)].id }
        persistPages()
    }
    func movePage(_ id: String, by offset: Int) {
        guard let target = HomeAssistantPages.destination(id, offset: offset, pages: pages),
              let from = pages.firstIndex(where: { $0.id == id }), let to = pages.firstIndex(where: { $0.id == target }) else { return }
        pages.swapAt(from, to); persistPages()
    }
    func selectPage(_ id: String) {
        guard id != activePageID, pages.contains(where: { $0.id == id }) else { return }
        activePageID = id
        defaults.set(id, forKey: DefaultsKey.notchHomeAssistantActivePage)
    }
    func advancePage(by offset: Int) {
        if let id = HomeAssistantPages.destination(activePageID, offset: offset, pages: pages) { selectPage(id) }
    }
    func setEntity(_ id: String, selected: Bool, pageID: String) {
        guard let page = pages.firstIndex(where: { $0.id == pageID }) else { return }
        if selected {
            guard entities[id]?.eligible == true, !pages[page].entities.contains(id) else { return }
            pages[page].entities.append(id)
        } else { pages[page].entities.removeAll { $0 == id } }
        persistPages()
    }
    func transferEntity(_ id: String, from sourceID: String, to destinationID: String, duplicate: Bool) {
        guard sourceID != destinationID,
              let source = pages.firstIndex(where: { $0.id == sourceID }),
              let destination = pages.firstIndex(where: { $0.id == destinationID }),
              pages[source].entities.contains(id) else { return }
        var updated = pages
        if !updated[destination].entities.contains(id) { updated[destination].entities.append(id) }
        if !duplicate { updated[source].entities.removeAll { $0 == id } }
        guard updated != pages else { return }
        pages = updated
        persistPages()
    }
    func configure(url: String, token: String) {
        do {
            let configuration = try HomeAssistantConfiguration(url)
            let normalized = configuration.baseURL.absoluteString
            let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty || normalized == server else { throw HomeAssistantFailure.credentials }
            if !token.isEmpty { try credentials.save(token, server: normalized) }
            else if try credentials.read(server: normalized) == nil { throw HomeAssistantFailure.credentials }
            stop()
            if normalized != server {
                clearEntityPreferences()
                resetPages()
                temperatureUnit = ""; store = HomeAssistantStateStore()
            }
            defaults.set(normalized, forKey: DefaultsKey.notchHomeAssistantURL)
            failure = nil; authenticationFailureServer = nil
            syncWithPreferences()
        } catch { failure = error as? HomeAssistantFailure ?? .keychain }
    }
    func forgetConnection() {
        do {
            try credentials.remove(server: server)
            stop()
            clearEntityPreferences()
            defaults.set("", forKey: DefaultsKey.notchHomeAssistantURL)
            resetPages()
            store = HomeAssistantStateStore(); temperatureUnit = ""; favorites = []; failure = nil; authenticationFailureServer = nil; connection = .unconfigured
        } catch { failure = .keychain }
    }
    func retry() { stop(); failure = nil; authenticationFailureServer = nil; syncWithPreferences() }
    func syncWithPreferences() {
        reloadPreferences()
        guard enabled, !surfaces.isEmpty, !sleeping else { stop(); return }
        if activeServer != server, task != nil { stop(); temperatureUnit = ""; store = HomeAssistantStateStore() }
        guard task == nil, authenticationFailureServer != server else { return }
        guard let configuration = try? HomeAssistantConfiguration(server) else { connection = .unconfigured; return }
        let token: String
        do {
            guard let saved = try credentials.read(server: configuration.baseURL.absoluteString), !saved.isEmpty else {
                connection = .unconfigured; return
            }
            token = saved
        } catch { failure = .keychain; connection = .offline; return }
        activeServer = server
        let current = generation
        task = Task { @MainActor [weak self] in
            var delay: UInt64 = 1
            while !Task.isCancelled {
                guard let self, self.generation == current else { return }
                self.connection = .connecting
                self.store.beginSnapshot()
                let client = HomeAssistantClient(transport: self.makeTransport(configuration.webSocketURL))
                self.client = client
                do {
                    let events = try await client.connect(token: token)
                    guard !Task.isCancelled, self.generation == current else { await client.close(); return }
                    let temperatureUnit = await client.temperatureUnit
                    guard !Task.isCancelled, self.generation == current else { await client.close(); return }
                    self.temperatureUnit = temperatureUnit
                    for try await event in events {
                        guard !Task.isCancelled, self.generation == current else { break }
                        switch event {
                        case .snapshot(let values):
                            self.store.snapshot(values)
                            let newlyConnected = self.connection != .connected
                            if newlyConnected { self.failure = nil }
                            self.connection = .connected; delay = 1
                            self.refreshTask = nil
                        case .changed(let id, let value):
                            let previous = self.store.entities[id]
                            self.store.change(id: id, value: value)
                            guard previous != self.store.entities[id] else { continue }
                        }
                        self.objectWillChange.send()
                        for (id, action) in self.confirmations where self.entities[id].map(action.confirmed) == true {
                            self.confirmations.removeValue(forKey: id)
                        }
                    }
                    await client.close()
                } catch {
                    await client.close()
                    guard !Task.isCancelled, self.generation == current else { return }
                    self.connection = .offline
                    self.failure = error as? HomeAssistantFailure ?? .network
                    self.clearCommands()
                    if self.failure == .credentials {
                        self.authenticationFailureServer = self.server
                        self.task = nil; return
                    }
                }
                guard !Task.isCancelled, self.generation == current else { return }
                do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) } catch { return }
                delay = min(30, delay * 2)
            }
        }
    }
    private func clearCommands() {
        commandTasks.values.forEach { $0.cancel() }; commandTasks.removeAll()
        pending.removeAll(); confirmations.removeAll()
    }
    func stop() {
        generation = UUID()
        task?.cancel(); task = nil
        refreshTask?.cancel(); refreshTask = nil
        if let client { Task { await client.close() } }
        client = nil; activeServer = nil
        clearCommands()
        connection = server.isEmpty ? .unconfigured : .offline
    }
    private func refreshStates() {
        guard refreshTask == nil, let client, connection == .connected else { return }
        store.beginSnapshot()
        let current = generation
        refreshTask = Task { @MainActor [weak self] in
            do { try await client.refresh() }
            catch {
                guard let self, self.generation == current else { return }
                self.refreshTask = nil
                // A failed refresh cannot make the previous state authoritative.
                await client.close(error: HomeAssistantFailure.network)
            }
        }
    }
    func perform(_ service: String, entityID: String, data: [String: HomeAssistantValue] = [:]) {
        guard enabled, connection == .connected, !pending.contains(entityID),
              let entity = entities[entityID], let client else { return }
        let action: HomeAssistantAction
        do { action = try .make(service, entity: entity, data: data) }
        catch { failure = .unsupported; return }
        pending.insert(entityID); failure = nil
        confirmations[entityID] = action
        let current = generation
        commandTasks[entityID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.generation == current {
                    self.pending.remove(entityID); self.confirmations.removeValue(forKey: entityID)
                    self.commandTasks.removeValue(forKey: entityID)
                }
            }
            do {
                let deadline = Date().addingTimeInterval(10)
                try await client.perform(action)
                guard !Task.isCancelled, self.generation == current else { return }
                if self.entities[entityID].map(action.confirmed) == true {
                    self.confirmations.removeValue(forKey: entityID)
                }
                while !action.expected.isEmpty, self.confirmations[entityID] != nil {
                    guard !Task.isCancelled, self.generation == current else { return }
                    if Date() >= deadline { throw HomeAssistantFailure.timeout }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
            } catch {
                guard !Task.isCancelled, self.generation == current else { return }
                self.failure = error as? HomeAssistantFailure ?? .network
                if self.failure == .timeout { self.refreshStates() }
            }
        }
    }
}
