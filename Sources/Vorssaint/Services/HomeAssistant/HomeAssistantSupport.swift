// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Preserve arbitrary HA attributes without assuming every integration has the same shape.
indirect enum HomeAssistantValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), array([Self]), object([String: Self]), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode([Self].self) { self = .array(v) }
        else { self = .object(try value.decode([String: Self].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let v): try value.encode(v)
        case .number(let v): try value.encode(v)
        case .bool(let v): try value.encode(v)
        case .array(let v): try value.encode(v)
        case .object(let v): try value.encode(v)
        case .null: try value.encodeNil()
        }
    }

    var string: String? { if case .string(let v) = self { return v }; return nil }
    var number: Double? { if case .number(let v) = self, v.isFinite { return v }; return nil }
    var object: [String: Self]? { if case .object(let v) = self { return v }; return nil }
    var array: [Self]? { if case .array(let v) = self { return v }; return nil }
}

struct HomeAssistantEntity: Codable, Identifiable, Equatable, Sendable {
    let entityID: String
    let state: String
    let attributes: [String: HomeAssistantValue]
    enum CodingKeys: String, CodingKey { case entityID = "entity_id", state, attributes }
    var id: String { entityID }
    var domain: String { String(entityID.prefix { $0 != "." }) }
    var name: String { attributes["friendly_name"]?.string ?? entityID }
    var available: Bool { state != "unavailable" && state != "unknown" }
    var features: Int {
        guard let value = attributes["supported_features"]?.number, value >= 0, value < Double(Int.max) else { return 0 }
        return Int(value)
    }
    func supports(_ bit: Int) -> Bool { features & bit != 0 }
    var modes: [String] { attributes["hvac_modes"]?.array?.compactMap(\.string) ?? [] }
    var hasBrightness: Bool {
        guard domain == "light" else { return false }
        let modes = attributes["supported_color_modes"]?.array?.compactMap(\.string) ?? []
        return modes.contains { ["brightness", "color_temp", "hs", "xy", "rgb", "rgbw", "rgbww", "white"].contains($0) }
    }
    var hasColor: Bool {
        domain == "light" && (attributes["supported_color_modes"]?.array?.compactMap(\.string) ?? [])
            .contains { ["rgb", "rgbw", "rgbww", "hs", "xy"].contains($0) }
    }
    var rgbColor: HomeAssistantRGB? {
        guard hasColor else { return nil }
        let mode = attributes["color_mode"]?.string ?? ""
        guard !["color_temp", "white"].contains(mode) else { return nil }
        // Prefer the active native representation. Some integrations omit or
        // leave a stale converted RGB attribute when changing color modes.
        let native: HomeAssistantRGB?
        switch mode {
        case "hs": native = HomeAssistantRGB.hs(attributes["hs_color"])
        case "xy": native = HomeAssistantRGB.xy(attributes["xy_color"])
        case "rgbw": native = HomeAssistantRGB.whiteChannels(attributes["rgbw_color"], count: 4, attributes: attributes)
        case "rgbww": native = HomeAssistantRGB.whiteChannels(attributes["rgbww_color"], count: 5, attributes: attributes)
        default: native = HomeAssistantRGB.reported(attributes["rgb_color"])
        }
        return native ?? HomeAssistantRGB.reported(attributes["rgb_color"])
            ?? HomeAssistantRGB.hs(attributes["hs_color"])
            ?? HomeAssistantRGB.xy(attributes["xy_color"])
            ?? HomeAssistantRGB.whiteChannels(attributes["rgbw_color"], count: 4, attributes: attributes)
            ?? HomeAssistantRGB.whiteChannels(attributes["rgbww_color"], count: 5, attributes: attributes)
    }
    var isSensor: Bool { domain == "sensor" || domain == "binary_sensor" }
    var temperatureRange: ClosedRange<Double>? {
        guard let minimum = attributes["min_temp"]?.number, let maximum = attributes["max_temp"]?.number,
              (maximum - minimum).isFinite, maximum - minimum >= 0.1 else { return nil }
        return minimum...maximum
    }
    var eligible: Bool {
        guard ["light", "switch", "sensor", "binary_sensor", "scene", "script", "climate", "cover"].contains(domain) else { return false }
        return domain != "cover" || !["garage", "gate", "door"].contains(attributes["device_class"]?.string ?? "")
    }
    var symbol: String {
        switch domain {
        case "light": return "lightbulb"
        case "switch": return "powerplug"
        case "climate": return "thermometer"
        case "cover": return "window.shade.closed"
        case "scene": return "sparkles"
        case "script": return "play.circle"
        case "binary_sensor": return "sensor"
        default: return "gauge.with.dots.needle.50percent"
        }
    }
    var reading: String {
        state + (attributes["unit_of_measurement"]?.string.map { " " + $0 } ?? "")
    }
    var primaryService: String? {
        guard eligible, available else { return nil }
        switch domain {
        case "light", "switch": return state == "on" ? "turn_off" : "turn_on"
        case "scene", "script": return "turn_on"
        default: return nil
        }
    }
    var brightnessPercent: Double {
        guard domain == "light", state == "on" else { return 0 }
        return min(100, max(0, (attributes["brightness"]?.number ?? 255) / 255 * 100))
    }
}

struct HomeAssistantRGB: Equatable, Sendable {
    let red: Int
    let green: Int
    let blue: Int
    init(red: Int, green: Int, blue: Int) {
        self.red = min(255, max(0, red))
        self.green = min(255, max(0, green))
        self.blue = min(255, max(0, blue))
    }
    init?(_ value: HomeAssistantValue?) {
        guard let channels = value?.array, channels.count == 3 else { return nil }
        let numbers = channels.compactMap(\.number)
        guard numbers.count == 3, numbers.allSatisfy({ (0...255).contains($0) && $0 == $0.rounded() }) else { return nil }
        self.init(red: Int(numbers[0]), green: Int(numbers[1]), blue: Int(numbers[2]))
    }
    var value: HomeAssistantValue { .array([.number(Double(red)), .number(Double(green)), .number(Double(blue))]) }
    private static func components(_ value: HomeAssistantValue?, count: Int, range: ClosedRange<Double>) -> [Double]? {
        guard let values = value?.array, values.count == count else { return nil }
        let numbers = values.compactMap(\.number)
        return numbers.count == count && numbers.allSatisfy(range.contains) ? numbers : nil
    }
    static func reported(_ value: HomeAssistantValue?) -> Self? {
        guard let channels = components(value, count: 3, range: 0...255) else { return nil }
        return Self(red: Int(channels[0].rounded()), green: Int(channels[1].rounded()), blue: Int(channels[2].rounded()))
    }
    static func hs(_ value: HomeAssistantValue?) -> Self? {
        guard let pair = components(value, count: 2, range: 0...360), pair[1] <= 100 else { return nil }
        let sector = pair[0].truncatingRemainder(dividingBy: 360) / 60
        let saturation = pair[1] / 100
        let low = 1 - saturation
        let falling = 1 - saturation * (sector - floor(sector))
        let rising = 1 - saturation * (1 - sector + floor(sector))
        let channels: [Double]
        switch Int(sector) {
        case 0: channels = [1, rising, low]
        case 1: channels = [falling, 1, low]
        case 2: channels = [low, 1, rising]
        case 3: channels = [low, falling, 1]
        case 4: channels = [rising, low, 1]
        default: channels = [1, low, falling]
        }
        return Self(red: Int((channels[0] * 255).rounded()), green: Int((channels[1] * 255).rounded()), blue: Int((channels[2] * 255).rounded()))
    }
    static func xy(_ value: HomeAssistantValue?) -> Self? {
        guard let pair = components(value, count: 2, range: 0...1), pair[1] > 0,
              pair[0] + pair[1] <= 1.000001 else { return nil }
        let x = pair[0] / pair[1], z = (1 - pair[0] - pair[1]) / pair[1]
        // HA's Wide RGB D65 matrix, followed by inverse gamma and gamut scaling.
        let linear = [1.656492 * x - 0.354851 - 0.255038 * z,
                      -0.707196 * x + 1.655397 + 0.036152 * z,
                      0.051713 * x - 0.121364 + 1.011530 * z]
        guard linear.allSatisfy(\.isFinite) else { return nil }
        let gamma = linear.map { max(0, $0 <= 0.0031308 ? 12.92 * $0 : 1.055 * pow($0, 1 / 2.4) - 0.055) }
        let scale = max(1, gamma.max() ?? 1)
        return Self(red: Int(gamma[0] / scale * 255), green: Int(gamma[1] / scale * 255), blue: Int(gamma[2] / scale * 255))
    }
    static func whiteChannels(_ value: HomeAssistantValue?, count: Int, attributes: [String: HomeAssistantValue]) -> Self? {
        guard [4, 5].contains(count), let channels = components(value, count: count, range: 0...255) else { return nil }
        let white: [Double]
        if count == 4 { white = [channels[3], channels[3], channels[3]] }
        else {
            let cold = channels[3], warm = channels[4]
            let minimum = attributes["min_color_temp_kelvin"]?.number ?? 2000
            let maximum = attributes["max_color_temp_kelvin"]?.number ?? 6500
            guard minimum > 0, maximum >= minimum else { return nil }
            let ratio = cold + warm == 0 ? 0.5 : warm / (cold + warm)
            let kelvin = min(40000, max(1000, 1 / ((1 - ratio) / maximum + ratio / minimum)))
            let temperature = kelvin / 100
            let red = temperature <= 66 ? 255 : 329.698727446 * pow(temperature - 60, -0.1332047592)
            let green = temperature <= 66 ? 99.4708025861 * log(temperature) - 161.1195681661
                : 288.1221695283 * pow(temperature - 60, -0.0755148492)
            let blue = temperature >= 66 ? 255 : temperature <= 19 ? 0 : 138.5177312231 * log(temperature - 10) - 305.0447927307
            white = [red, green, blue].map { min(255, max(0, $0)) * max(cold, warm) / 255 }
        }
        let mixed = (0..<3).map { channels[$0] + white[$0] }
        let factor = (mixed.max() ?? 0) == 0 ? 0 : (channels.max() ?? 0) / mixed.max()!
        return Self(red: Int((mixed[0] * factor).rounded()), green: Int((mixed[1] * factor).rounded()), blue: Int((mixed[2] * factor).rounded()))
    }
}

struct HomeAssistantCardReading: Identifiable, Equatable {
    let id: String
    let name: String
    let value: String
    let unit: String
    var description: String { name + ": " + [value, unit].filter { !$0.isEmpty }.joined(separator: " ") }
}

struct HomeAssistantPage: Identifiable, Equatable {
    let id: String
    var title: String
    var entities: [String]
    var columns: Int? = nil
    var fillLastRow = false
    func effectiveColumns(default value: Int) -> Int { HomeAssistantPresentation.columns(columns ?? value) }
    var dictionary: [String: Any] {
        var result: [String: Any] = ["id": id, "title": title, "entities": entities, "fillLastRow": fillLastRow]
        if let columns { result["columns"] = columns }
        return result
    }
}

enum HomeAssistantPages {
    static let initialID = "home-assistant-default"
    static func entityIDs(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter {
            $0.range(of: "^(light|switch|sensor|binary_sensor|scene|script|climate|cover)\\.[a-z0-9_]+$", options: .regularExpression) != nil
                && seen.insert($0).inserted
        }
    }
    static func load(in defaults: UserDefaults) -> [HomeAssistantPage] {
        var seen: Set<String> = []
        let pages = (defaults.array(forKey: DefaultsKey.notchHomeAssistantPages) ?? []).compactMap { raw -> HomeAssistantPage? in
            guard let raw = raw as? [String: Any], let id = raw["id"] as? String, !id.isEmpty, id.count <= 80,
                  let title = raw["title"] as? String, let entities = raw["entities"] as? [String],
                  seen.insert(id).inserted else { return nil }
            let columns = (raw["columns"] as? Int).flatMap { HomeAssistantPresentation.columnOptions.contains($0) ? $0 : nil }
            return HomeAssistantPage(id: id, title: HomeAssistantPresentation.customName(title) ?? "", entities: entityIDs(entities),
                                     columns: columns, fillLastRow: raw["fillLastRow"] as? Bool ?? false)
        }
        return pages.isEmpty ? [HomeAssistantPage(id: initialID, title: "", entities:
            entityIDs(defaults.stringArray(forKey: DefaultsKey.notchHomeAssistantFavorites) ?? []))] : pages
    }
    static func allEntityIDs(_ pages: [HomeAssistantPage]) -> [String] { entityIDs(pages.flatMap(\.entities)) }
    static func selected(in defaults: UserDefaults) -> HomeAssistantPage {
        let pages = load(in: defaults)
        return pages.first { $0.id == defaults.string(forKey: DefaultsKey.notchHomeAssistantActivePage) } ?? pages[0]
    }
    static func destination(_ id: String, offset: Int, pages: [HomeAssistantPage]) -> String? {
        guard let index = pages.firstIndex(where: { $0.id == id }),
              (offset > 0 ? offset <= pages.count - 1 - index : offset >= -index) else { return nil }
        return pages[index + offset].id
    }
}

/// Locks the axis once per physical gesture. A vertical scroll never becomes
/// page navigation, and momentum cannot skip further pages after a swipe.
struct HomeAssistantPageSwipe {
    enum Result: Equatable { case passThrough, consume, change(Int) }
    private enum Axis { case horizontal, vertical }
    private var axis: Axis?
    private var x = 0.0
    private var y = 0.0
    private var fired = false
    private var started = false
    private var timestamp: TimeInterval?
    var isVertical: Bool { axis == .vertical }

    mutating func handle(x dx: Double, y dy: Double, timestamp time: TimeInterval,
                         precise: Bool, began: Bool, ended: Bool, momentum: Bool, hasPhase: Bool = true) -> Result {
        guard precise, dx.isFinite, dy.isFinite, time.isFinite else { self = Self(); return .passThrough }
        if began || timestamp.map({ time < $0 || time - $0 > 0.35 }) == true { self = Self() }
        timestamp = time
        if began { started = true }
        if hasPhase && !started { return .passThrough }
        if momentum { return axis == .horizontal ? .consume : .passThrough }
        if ended {
            // Keep the axis for momentum; the next beginning clears it.
            fired = true
            return axis == .horizontal ? .consume : .passThrough
        }
        x += dx; y += dy
        if axis == nil {
            if abs(y) >= 8, abs(y) >= abs(x) * 1.5 { axis = .vertical }
            else if abs(x) >= 8, abs(x) >= abs(y) * 1.5 { axis = .horizontal }
        }
        guard axis == .horizontal else { return .passThrough }
        guard !fired, abs(x) >= 40 else { return .consume }
        fired = true
        return .change(x < 0 ? 1 : -1)
    }
}

/// Presentation preferences and readings shared by settings and the island.
enum HomeAssistantPresentation {
    static let columnOptions = [2, 4, 6, 8]
    static func sensorIDs(_ values: [String], excluding owner: String) -> [String] {
        var seen: Set<String> = []
        return Array(values.filter {
            $0 != owner && $0.range(of: "^(sensor|binary_sensor)\\.[a-z0-9_]+$", options: .regularExpression) != nil
                && seen.insert($0).inserted
        }.prefix(2))
    }
    static func columns(_ value: Int) -> Int { columnOptions.contains(value) ? value : 2 }
    static func customName(_ value: String) -> String? {
        let name = value.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : String(name.prefix(80))
    }
    static func reading(_ entity: HomeAssistantEntity, text: HomeAssistantStrings,
                        temperatureUnit: String, locale: Locale) -> (value: String, unit: String) {
        guard entity.available else { return (text.state(entity.state), "") }
        if entity.domain == "climate", let current = entity.attributes["current_temperature"]?.number {
            return (number(current, locale: locale), temperatureUnit)
        }
        if let value = Double(entity.state), value.isFinite {
            return (number(value, locale: locale), entity.attributes["unit_of_measurement"]?.string ?? "")
        }
        if ["scene", "script"].contains(entity.domain) { return (text[.run], "") }
        return (text.state(entity.state), entity.attributes["unit_of_measurement"]?.string ?? "")
    }
    private static func number(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }
}

enum HomeAssistantFailure: Error, Equatable {
    case invalidURL, credentials, network, protocolError, rejected, timeout, keychain, unsupported
}

struct HomeAssistantConfiguration: Equatable, Sendable {
    let baseURL: URL
    init(_ input: String) throws {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path == "" || parts.path == "/"
        else { throw HomeAssistantFailure.invalidURL }
        parts.scheme = scheme
        parts.host = host.lowercased()
        parts.path = ""
        if (scheme == "https" && parts.port == 443) || (scheme == "http" && parts.port == 80) { parts.port = nil }
        guard let url = parts.url else { throw HomeAssistantFailure.invalidURL }
        baseURL = url
    }
    var webSocketURL: URL {
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        parts.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        parts.path = "/api/websocket"
        return parts.url!
    }
}

struct HomeAssistantAction: Equatable, Sendable {
    let domain: String
    let service: String
    let entityID: String
    let data: [String: HomeAssistantValue]
    /// State/attribute values the server must confirm. Scenes and scripts have no target state.
    let expected: [String: HomeAssistantValue]

    static func brightness(_ percent: Double, entity: HomeAssistantEntity) throws -> Self {
        guard entity.domain == "light", entity.hasBrightness, percent.isFinite, (0...100).contains(percent)
        else { throw HomeAssistantFailure.unsupported }
        if percent == 0 { return try make("turn_off", entity: entity) }
        return try make("turn_on", entity: entity, data: ["brightness": .number(max(1, (percent / 100 * 255).rounded()))])
    }
    static func color(_ rgb: HomeAssistantRGB, entity: HomeAssistantEntity) throws -> Self {
        try make("turn_on", entity: entity, data: ["rgb_color": rgb.value])
    }

    static func make(_ service: String, entity: HomeAssistantEntity,
                     data: [String: HomeAssistantValue] = [:]) throws -> Self {
        guard entity.eligible, entity.available else { throw HomeAssistantFailure.unsupported }
        let allowed: Bool
        var expected: [String: HomeAssistantValue] = [:]
        switch (entity.domain, service) {
        case ("light", "turn_on"), ("light", "turn_off"), ("switch", "turn_on"), ("switch", "turn_off"):
            allowed = data.isEmpty || (entity.domain == "light" && service == "turn_on" && entity.hasBrightness
                && data.count == 1 && data["brightness"]?.number.map { (1...255).contains($0) } == true)
                || (entity.domain == "light" && service == "turn_on" && entity.hasColor
                    && data.count == 1 && HomeAssistantRGB(data["rgb_color"]) != nil)
            expected["state"] = .string(service == "turn_off" ? "off" : "on")
            // HA may convert RGB into the lamp's gamut. Confirm on/off state;
            // render the actual color from subsequent server events.
            if let brightness = data["brightness"] { expected["brightness"] = brightness }
        case ("scene", "turn_on"), ("script", "turn_on"):
            allowed = data.isEmpty
        case ("cover", "open_cover"), ("cover", "close_cover"), ("cover", "stop_cover"):
            allowed = data.isEmpty && entity.supports(service == "open_cover" ? 1 : service == "close_cover" ? 2 : 8)
            // Covers may take minutes to move; acknowledge the command, display real movement events.
        case ("cover", "set_cover_position"):
            allowed = entity.supports(4) && data.count == 1 && data["position"]?.number.map { (0...100).contains($0) } == true
        case ("climate", "set_hvac_mode"):
            allowed = data.count == 1 && data["hvac_mode"]?.string.map { entity.modes.contains($0) } == true
            expected["state"] = data["hvac_mode"]
        case ("climate", "set_temperature"):
            guard let range = entity.temperatureRange else { throw HomeAssistantFailure.unsupported }
            if entity.state == "heat_cool", entity.supports(2) {
                allowed = data.count == 2 && data["target_temp_low"]?.number.map { range.contains($0) } == true
                    && data["target_temp_high"]?.number.map { range.contains($0) } == true
                    && data["target_temp_low"]!.number! <= data["target_temp_high"]!.number!
            } else {
                allowed = entity.supports(1) && data.count == 1 && data["temperature"]?.number.map { range.contains($0) } == true
            }
            expected = data
        default: allowed = false
        }
        guard allowed else { throw HomeAssistantFailure.unsupported }
        return Self(domain: entity.domain, service: service, entityID: entity.id, data: data, expected: expected)
    }

    func confirmed(by entity: HomeAssistantEntity) -> Bool {
        !expected.isEmpty && expected.allSatisfy { key, value in
            let actual = key == "state" ? HomeAssistantValue.string(entity.state) : entity.attributes[key]
            if let a = actual?.number, let b = value.number { return abs(a - b) <= (key == "brightness" ? 1 : 0.05) }
            return actual == value
        }
    }
    var message: [String: HomeAssistantValue] {
        ["type": .string("call_service"), "domain": .string(domain), "service": .string(service),
         "target": .object(["entity_id": .string(entityID)]), "service_data": .object(data)]
    }
}

/// Pure synchronization logic: events arriving during a snapshot take precedence over that snapshot.
struct HomeAssistantStateStore {
    private(set) var entities: [String: HomeAssistantEntity] = [:]
    private var changes: [String: HomeAssistantValue] = [:]
    private var loading = true
    mutating func beginSnapshot() { loading = true; changes.removeAll() }
    mutating func change(id: String, value: HomeAssistantValue) {
        if loading { changes[id] = value }
        apply(id: id, value: value)
    }
    mutating func snapshot(_ values: [HomeAssistantEntity]) {
        entities = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for (id, value) in changes { apply(id: id, value: value) }
        changes.removeAll(); loading = false
    }
    private mutating func apply(id: String, value: HomeAssistantValue) {
        if value == .null { entities.removeValue(forKey: id); return }
        guard let data = try? JSONEncoder().encode(value),
              let entity = try? JSONDecoder().decode(HomeAssistantEntity.self, from: data), entity.id == id else { return }
        entities[id] = entity
    }
}
