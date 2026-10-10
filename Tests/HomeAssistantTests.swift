// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Combine

enum HomeAssistantTests {
    static func run(_ suite: TestSuite) {
        modelContracts(suite)
        colorContracts(suite)
        pageContracts(suite)
        let finished = Completion()
        let task = Task { @MainActor in
            await clientContracts(suite)
            await serviceContracts(suite)
            finished.finish()
        }
        let deadline = Date().addingTimeInterval(20)
        while !finished.done, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        suite.expect(finished.done, "Home Assistant async contracts complete without hanging")
        if !finished.done { task.cancel() }
    }
    private final class Completion: @unchecked Sendable {
        let lock = NSLock()
        private var value = false
        var done: Bool { lock.withLock { value } }
        func finish() { lock.withLock { value = true } }
    }
    static func entity(_ id: String = "light.desk", state: String = "off",
                       attributes: [String: HomeAssistantValue] = [:]) -> HomeAssistantEntity {
        HomeAssistantEntity(entityID: id, state: state, attributes: attributes)
    }
    static func value(_ entity: HomeAssistantEntity) -> HomeAssistantValue {
        .object(["entity_id": .string(entity.id), "state": .string(entity.state), "attributes": .object(entity.attributes)])
    }
    private static func modelContracts(_ suite: TestSuite) {
        for invalid in ["", "file:///tmp/test", "ftp://example.com", "https://user:secret@example.com", "https://example.com/lovelace",
                        "https://example.com?token=secret", "https://example.com#token"] {
            suite.expect((try? HomeAssistantConfiguration(invalid)) == nil, "reject ambiguous or credential-bearing address")
        }
        suite.expect((try? HomeAssistantConfiguration(" HTTPS://EXAMPLE.COM:443/ "))?.webSocketURL.absoluteString == "wss://example.com/api/websocket",
                     "canonical HTTPS address maps to a secure socket")
        suite.expect((try? HomeAssistantConfiguration("http://homeassistant.local:8123"))?.webSocketURL.absoluteString == "ws://homeassistant.local:8123/api/websocket",
                     "LAN and VPN HTTP addresses retain their port")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: "Resources/Info.plist")),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            let ats = plist["NSAppTransportSecurity"] as? [String: Any]
            suite.expect(ats?["NSAllowsLocalNetworking"] as? Bool == true && ats?["NSAllowsArbitraryLoads"] == nil,
                         "local HTTP support does not disable transport protection globally")
            suite.expect((plist["NSLocalNetworkUsageDescription"] as? String)?.isEmpty == false,
                         "the bundle explains its local network access")
        } else { suite.expect(false, "network privacy configuration is readable") }
        for language in AppLanguage.allCases where language != .enUS {
            let path = "Resources/\(language.rawValue).lproj/InfoPlist.strings"
            let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            suite.expect(source.contains("NSLocalNetworkUsageDescription"),
                         "local network prompt is localized for \(language.rawValue)")
        }
        let light = entity(attributes: ["supported_color_modes": .array([.string("brightness")])])
        suite.expect((try? HomeAssistantAction.make("turn_on", entity: light, data: ["brightness": .number(128)])) != nil,
                     "dimmable lights accept brightness")
        suite.expect((try? HomeAssistantAction.make("turn_on", entity: entity(), data: ["brightness": .number(128)])) == nil,
                     "on-off lights do not offer unsupported brightness")
        for number in [-1.0, 256, Double.infinity] {
            suite.expect((try? HomeAssistantAction.make("turn_on", entity: light, data: ["brightness": .number(number)])) == nil,
                         "invalid brightness is refused before network access")
        }
        suite.expect((try? HomeAssistantAction.make("turn_on", entity: entity(state: "unavailable"))) == nil,
                     "unavailable entities cannot be controlled")
        for (id, attributes) in [("lock.front", [String: HomeAssistantValue]()),
                                 ("cover.garage", ["device_class": .string("garage")]),
                                 ("camera.front", [:]), ("media_player.tv", [:])] {
            suite.expect(!entity(id, attributes: attributes).eligible, "out-of-scope entity is excluded")
        }
        let cover = entity("cover.blind", state: "open", attributes: ["supported_features": .number(3)])
        suite.expect((try? HomeAssistantAction.make("close_cover", entity: cover)) != nil
                     && (try? HomeAssistantAction.make("stop_cover", entity: cover)) == nil
                     && (try? HomeAssistantAction.make("set_cover_position", entity: cover, data: ["position": .number(50)])) == nil,
                     "cover controls honor independent capability bits")
        let climate = entity("climate.office", state: "heat_cool", attributes: ["supported_features": .number(2),
            "min_temp": .number(10), "max_temp": .number(30), "hvac_modes": .array([.string("off"), .string("heat_cool")])])
        suite.expect((try? HomeAssistantAction.make("set_temperature", entity: climate,
                     data: ["target_temp_low": .number(18), "target_temp_high": .number(24)])) != nil,
                     "range thermostats accept both bounds")
        suite.expect((try? HomeAssistantAction.make("set_temperature", entity: climate,
                     data: ["target_temp_low": .number(24), "target_temp_high": .number(18)])) == nil
                     && (try? HomeAssistantAction.make("set_hvac_mode", entity: climate, data: ["hvac_mode": .string("cool")])) == nil,
                     "invalid ranges and unsupported climate modes are refused")
        let incompleteClimate = entity("climate.incomplete", state: "heat", attributes: ["supported_features": .number(1)])
        suite.expect((try? HomeAssistantAction.make("set_temperature", entity: incompleteClimate,
                     data: ["temperature": .number(20)])) == nil,
                     "missing thermostat bounds do not invent a temperature scale")
        suite.expect(HomeAssistantPresentation.columns(0) == 2 && HomeAssistantPresentation.columns(3) == 2,
                     "missing and invalid grid preferences fall back to two columns")
        for count in [2, 4, 6, 8] {
            suite.expect(HomeAssistantPresentation.columns(count) == count, "requested grid density is preserved")
        }
        suite.expect(HomeAssistantPresentation.customName("  Desk\nLight  ") == "Desk Light"
                     && HomeAssistantPresentation.customName("  \n ") == nil,
                     "aliases trim whitespace and empty aliases restore server names")
        suite.expect(HomeAssistantPresentation.customName(String(repeating: "x", count: 100))?.count == 80,
                     "very long aliases have a bounded persisted length")
        suite.expect(entity(state: "on").primaryService == "turn_off" && entity().primaryService == "turn_on"
                     && entity("switch.plug", state: "on").primaryService == "turn_off",
                     "single-click light and switch actions use the current server state")
        suite.expect(entity("scene.evening").primaryService == "turn_on" && entity("script.evening").primaryService == "turn_on"
                     && entity("sensor.temperature", state: "22").primaryService == nil
                     && entity(state: "unavailable").primaryService == nil,
                     "run actions are distinct from read-only and unavailable entities")
        let half = entity(state: "on", attributes: ["brightness": .number(128)])
        suite.expect(abs(half.brightnessPercent - 50.196) < 0.01 && entity(attributes: ["brightness": .number(128)]).brightnessPercent == 0,
                     "brightness fill follows the reported state and 0–255 scale")
        suite.expect(entity(state: "on", attributes: ["brightness": .number(999)]).brightnessPercent == 100
                     && entity(state: "on", attributes: ["brightness": .number(-20)]).brightnessPercent == 0,
                     "malformed device brightness never draws outside its card")
        let zero = try? HomeAssistantAction.brightness(0, entity: light)
        let one = try? HomeAssistantAction.brightness(1, entity: light)
        let full = try? HomeAssistantAction.brightness(100, entity: light)
        suite.expect(zero?.service == "turn_off" && zero?.data.isEmpty == true
                     && one?.data["brightness"]?.number == 3 && full?.data["brightness"]?.number == 255,
                     "dimmer endpoints switch off or map percentages to native brightness")
        suite.expect((try? HomeAssistantAction.brightness(0.01, entity: light))?.data["brightness"]?.number == 1,
                     "a positive dimmer value never accidentally switches off")
        for percent in [-1.0, 101, .nan, .infinity] {
            suite.expect((try? HomeAssistantAction.brightness(percent, entity: light)) == nil,
                         "invalid dimmer input is refused")
        }
        suite.expect((try? HomeAssistantAction.brightness(50, entity: entity())) == nil
                     && (try? HomeAssistantAction.brightness(50, entity: entity("switch.fake", attributes: light.attributes))) == nil,
                     "brightness controls cannot target unsupported devices")
        let strings = HomeAssistantStrings.localized(.es)
        let temperatureReading = HomeAssistantPresentation.reading(entity("sensor.temperature", state: "22.40000",
            attributes: ["unit_of_measurement": .string("°C")]), text: strings, temperatureUnit: "", locale: Locale(identifier: "es"))
        suite.expect(temperatureReading.value == "22,4" && temperatureReading.unit == "°C",
                     "sensor readings localize numbers and retain separate units")
        let climateReading = HomeAssistantPresentation.reading(entity("climate.office", state: "heat",
            attributes: ["current_temperature": .number(21.5)]), text: strings, temperatureUnit: "°F", locale: Locale(identifier: "en-US"))
        suite.expect(climateReading.value == "21.5" && climateReading.unit == "°F",
                     "thermostat cards display current temperature with the server unit")
        let unavailableReading = HomeAssistantPresentation.reading(entity("sensor.temperature", state: "unavailable",
            attributes: ["unit_of_measurement": .string("°C")]), text: strings, temperatureUnit: "", locale: .current)
        suite.expect(unavailableReading.value == strings[.unavailable] && unavailableReading.unit.isEmpty,
                     "unavailable readings do not imply a numerical measurement")
        suite.expect(!entity(attributes: ["supported_color_modes": .array([.string("onoff")]), "brightness": .number(128)]).hasBrightness
                     && !entity(attributes: ["supported_color_modes": .array([.string("unknown")])]).hasBrightness,
                     "brightness attributes alone never enable dimmers for on-off lights")
        suite.expect(HomeAssistantPresentation.sensorIDs(["sensor.power", "sensor.power", "lock.front", "sensor.current", "sensor.energy"],
                     excluding: "switch.plug") == ["sensor.power", "sensor.current"],
                     "extra readings accept two distinct sensors in the user's order")
        suite.expect(HomeAssistantPresentation.sensorIDs(["sensor.self", "sensor.", "sensor.bad name", "binary_sensor.motion"],
                     excluding: "sensor.self") == ["binary_sensor.motion"],
                     "sensor associations reject malformed identifiers and self references")
        let oneRow = NotchHomeAssistantLayout(count: 2, columns: 2)
        let twoRows = NotchHomeAssistantLayout(count: 4, columns: 2)
        let threeRows = NotchHomeAssistantLayout(count: 5, columns: 2)
        for count in [0, 2, 4, 5, 40] {
            let single = NotchHomeAssistantLayout(count: count, columns: 2, pageCount: 1)
            let multiple = NotchHomeAssistantLayout(count: count, columns: 2, pageCount: 3)
            suite.expect(single.navigationHeight == 0 && multiple.navigationHeight == 36
                         && abs(multiple.contentHeight - single.contentHeight - 36) < 0.01
                         && multiple.cardHeight == single.cardHeight && multiple.visibleRows == single.visibleRows,
                         "one page omits navigation space without changing cards or the row viewport")
        }
        suite.expect(oneRow.cardHeight == NotchLayout.sectionTileHeight && oneRow.rows == 1 && twoRows.rows == 2,
                     "Home cards use the same standard height as Explore")
        suite.expect(oneRow.contentHeight < twoRows.contentHeight && twoRows.contentHeight < threeRows.contentHeight
                     && threeRows.rows == 3 && threeRows.cardHeight == twoRows.cardHeight
                     && twoRows.cardHeight == oneRow.cardHeight,
                     "window height follows occupied rows while every row retains the Explore card height")
        suite.expect(NotchHomeAssistantLayout(count: 4, columns: 4).contentHeight == oneRow.contentHeight
                     && NotchHomeAssistantLayout(count: 0, columns: 8).rows == 0,
                     "column changes and an empty favorite list change the grid's actual height")
        for columns in HomeAssistantPresentation.columnOptions {
            let capped = NotchHomeAssistantLayout(count: columns * 3, columns: columns)
            suite.expect(capped.slots(in: 2, fillLastRow: true) == columns
                         && capped.slots(in: -1, fillLastRow: true) == 0 && capped.slots(in: 3, fillLastRow: true) == 0,
                         "filling a complete last row preserves its columns and rejects nonexistent rows")
            for remaining in 1..<columns {
                let partial = NotchHomeAssistantLayout(count: columns * 3 + remaining, columns: columns)
                suite.expect(partial.slots(in: 3, fillLastRow: true) == remaining
                             && partial.slots(in: 3, fillLastRow: false) == columns
                             && partial.slots(in: 2, fillLastRow: true) == columns
                             && partial.visibleRows == 3 && partial.cardHeight == capped.cardHeight,
                             "an incomplete scrolling row exposes only its cards when filling, keeping earlier rows and card height")
            }
            for count in [columns * 3 + 1, columns * 4, columns * 20] {
                let overflow = NotchHomeAssistantLayout(count: count, columns: columns)
                suite.expect(overflow.rows > 3 && overflow.visibleRows == 3
                             && overflow.contentHeight == capped.contentHeight && overflow.cardHeight == capped.cardHeight,
                             "rows beyond the third scroll without resizing the window or shrinking cards at \(columns) columns")
            }
        }
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        for layout: NotchSize in [.compact, .spacious, .custom] {
            let geometry = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 210, layout: layout, customHeight: 260)
            for count in [0, 1, 4, 5, 8, 40] {
                let size = geometry.expandedSize(module: .homeAssistant, homeAssistantCount: count, homeAssistantColumns: 2)
                let planned = NotchHomeAssistantLayout(count: count, columns: 2).contentHeight
                let expected = count == 0 ? min(geometry.contentBudget, planned) : planned
                suite.expect(abs(geometry.contentSize(for: size).height - expected) < 0.01
                             && screen.contains(geometry.frame(for: size)),
                             "Home fits occupied rows at every preset and bounds its empty message by the chosen budget")
                let pagedSize = geometry.expandedSize(module: .homeAssistant, homeAssistantCount: count,
                                                     homeAssistantColumns: 2, homeAssistantPageCount: 2)
                let pagedHeight = NotchHomeAssistantLayout(count: count, columns: 2, pageCount: 2).contentHeight
                suite.expect(abs(geometry.contentSize(for: pagedSize).height
                                 - (count == 0 ? min(geometry.contentBudget, pagedHeight) : pagedHeight)) < 0.01,
                             "window geometry reserves navigation only when multiple pages exist")
            }
        }
        let short = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 800, height: 300), safeAreaTop: 0, cameraWidth: 0, layout: .compact)
        suite.expect(short.screen.contains(short.frame(for: short.expandedSize(module: .homeAssistant, homeAssistantCount: 40))),
                     "many rows stay inside a short display and leave scrolling available")
        let action = try! HomeAssistantAction.make("turn_on", entity: light)
        suite.expect(!action.confirmed(by: light) && action.confirmed(by: entity(state: "on")),
                     "an acknowledgement cannot stand in for the actual state")
        var store = HomeAssistantStateStore()
        store.change(id: "light.desk", value: value(entity(state: "on")))
        store.change(id: "sensor.removed", value: .null)
        store.snapshot([entity(), entity("sensor.removed", state: "20")])
        suite.expect(store.entities["light.desk"]?.state == "on" && store.entities["sensor.removed"] == nil,
                     "events and deletions during initial loading win over the snapshot")
        for language in AppLanguage.allCases {
            suite.expect(HomeAssistantStrings.localized(language)[.home] == "Home Assistant",
                         "every locale names the integration explicitly rather than Home or HomeKit")
            let strings = HomeAssistantStrings.localized(language)
            suite.expect(strings.values.count == HomeAssistantText.allCases.count && strings.values.allSatisfy { !$0.isEmpty },
                         "every Home Assistant string is present in \(language.rawValue)")
        }
        suite.expect(!AppFeature.notchHomeAssistant.installedByDefault
                     && !AppFeature.dynamicIslandInitialExtensions.contains(.notchHomeAssistant)
                     && AppFeature.notchHomeAssistant.permissions.isEmpty,
                     "Home Assistant stays opt-in and needs no unrelated macOS permission")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchHomeAssistantURL)
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchHomeAssistantFavorites)
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchHomeAssistantColumns)
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchHomeAssistantNames)
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchHomeAssistantSensors)
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchHomeAssistantPages)
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchHomeAssistantActivePage)
                     && !SettingsBackupSupport.exportKeys().contains("notchHomeAssistantToken"),
                     "portable configuration includes favorites but no token")
    }

    private static func colorContracts(_ suite: TestSuite) {
        let rgb = HomeAssistantRGB(red: 32, green: 128, blue: 255)
        for mode in ["rgb", "rgbw", "rgbww", "hs", "xy"] {
            let lamp = entity(state: "on", attributes: ["supported_color_modes": .array([.string(mode)]),
                "color_mode": .string(mode), "rgb_color": rgb.value, "brightness": .number(128)])
            let action = try? HomeAssistantAction.color(rgb, entity: lamp)
            suite.expect(lamp.hasColor && lamp.rgbColor == rgb && action?.data == ["rgb_color": rgb.value]
                         && action?.service == "turn_on" && action?.confirmed(by: lamp) == true,
                         "color-capable lights use HA's converted RGB and send one RGB parameter without changing brightness")
        }
        for mode in ["onoff", "brightness", "color_temp", "white", "unknown"] {
            let lamp = entity(attributes: ["supported_color_modes": .array([.string(mode)]), "rgb_color": rgb.value])
            suite.expect(!lamp.hasColor && lamp.rgbColor == nil && (try? HomeAssistantAction.color(rgb, entity: lamp)) == nil,
                         "reported color attributes cannot enable a selector on an unsupported lamp")
        }
        let lamp = entity(attributes: ["supported_color_modes": .array([.string("rgb")])])
        let on = entity(state: "on", attributes: lamp.attributes)
        let action = try? HomeAssistantAction.color(rgb, entity: lamp)
        suite.expect(action?.confirmed(by: lamp) == false && action?.confirmed(by: on) == true,
                     "applying a color to an off lamp waits for on state without requiring exact color reproduction in its gamut")
        let whiteMode = entity(state: "on", attributes: ["supported_color_modes": .array([.string("rgb"), .string("color_temp")]),
            "color_mode": .string("color_temp"), "rgb_color": rgb.value])
        suite.expect(whiteMode.hasColor && whiteMode.rgbColor == nil, "white mode does not reuse stale RGB attributes")
        let red = HomeAssistantRGB(red: 255, green: 0, blue: 0)
        let representations: [(String, String, HomeAssistantValue)] = [
            ("hs", "hs_color", .array([.number(0), .number(100)])),
            ("xy", "xy_color", .array([.number(0.701), .number(0.299)])),
            ("rgbw", "rgbw_color", .array([.number(255), .number(0), .number(0), .number(0)])),
            ("rgbww", "rgbww_color", .array([.number(255), .number(0), .number(0), .number(0), .number(0)]))]
        for (mode, key, value) in representations {
            let light = entity(state: "on", attributes: ["supported_color_modes": .array([.string(mode)]),
                "color_mode": .string(mode), key: value, "rgb_color": .array([.number(255), .number(255), .number(255)])])
            let reported = light.rgbColor
            suite.expect(reported?.red == 255 && (reported?.green ?? 255) < 10 && (reported?.blue ?? 255) < 10,
                         "a red native color in \(mode) overrides a stale white converted RGB attribute")
        }
        suite.expect(HomeAssistantRGB.hs(.array([.number(360), .number(100)])) == red
                     && HomeAssistantRGB.hs(.array([.number(120), .number(100)])) == .init(red: 0, green: 255, blue: 0)
                     && HomeAssistantRGB.hs(.array([.number(240), .number(100)])) == .init(red: 0, green: 0, blue: 255)
                     && HomeAssistantRGB.hs(.array([.number(60), .number(0)])) == .init(red: 255, green: 255, blue: 255),
                     "HS conversion handles hue wrap, primary colors and unsaturated white")
        suite.expect(HomeAssistantRGB.reported(.array([.number(254.7), .number(0.2), .number(0)])) == red
                     && HomeAssistantRGB.hs(.array([.number(0), .number(101)])) == nil
                     && HomeAssistantRGB.xy(.array([.number(0.5), .number(0)])) == nil
                     && HomeAssistantRGB.xy(.array([.number(0.8), .number(0.8)])) == nil,
                     "display colors tolerate fractional RGB and reject invalid HS and XY coordinates")
        let incomplete = entity(state: "on", attributes: ["supported_color_modes": .array([.string("hs")]),
            "hs_color": .array([.number(0), .number(100)])])
        suite.expect(incomplete.rgbColor == red,
                     "a lamp missing color_mode and converted RGB still displays a valid reported HS color")
        for bad: HomeAssistantValue in [.array([]), .array([.number(0), .number(0)]),
            .array([.number(0), .number(0), .number(0), .number(255)]),
            .array([.number(-1), .number(0), .number(0)]), .array([.number(256), .number(0), .number(0)]),
            .array([.number(1.5), .number(0), .number(0)]), .array([.number(.infinity), .number(0), .number(0)]),
            .array([.string("255"), .number(0), .number(0)])] {
            suite.expect(HomeAssistantRGB(bad) == nil
                         && (try? HomeAssistantAction.make("turn_on", entity: lamp, data: ["rgb_color": bad])) == nil,
                         "malformed colors are refused before network access")
        }
        suite.expect((try? HomeAssistantAction.make("turn_off", entity: lamp, data: ["rgb_color": rgb.value])) == nil
                     && (try? HomeAssistantAction.make("turn_on", entity: lamp,
                         data: ["rgb_color": rgb.value, "brightness": .number(128)])) == nil
                     && (try? HomeAssistantAction.color(rgb, entity: entity("switch.fake", attributes: lamp.attributes))) == nil
                     && (try? HomeAssistantAction.color(rgb, entity: entity(state: "unavailable", attributes: lamp.attributes))) == nil,
                     "color actions reject off services, mixed parameters, non-lights and unavailable devices")
    }

    private static func pageContracts(_ suite: TestSuite) {
        let name = "vorss.tests.home-pages.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["light.desk", "light.desk", "sensor.temperature", "lock.front"], forKey: DefaultsKey.notchHomeAssistantFavorites)
        let initial = HomeAssistantPages.load(in: defaults)
        suite.expect(initial.count == 1 && initial[0].entities == ["light.desk", "sensor.temperature"],
                     "the previous flat selection migrates into one page without losing valid entities")
        suite.expect(initial[0].columns == nil && !initial[0].fillLastRow && initial[0].effectiveColumns(default: 6) == 6,
                     "existing pages inherit the global columns and keep empty slots until filling is enabled")
        let second = HomeAssistantPage(id: "upstairs", title: "Upstairs", entities: ["light.desk"], columns: 4, fillLastRow: true)
        defaults.set((initial + [second]).map(\.dictionary), forKey: DefaultsKey.notchHomeAssistantPages)
        defaults.set(second.id, forKey: DefaultsKey.notchHomeAssistantActivePage)
        suite.expect(HomeAssistantPages.selected(in: defaults) == second
                     && HomeAssistantPages.allEntityIDs(initial + [second]) == ["light.desk", "sensor.temperature"],
                     "pages share entities while retaining independent order and the active page")
        suite.expect(HomeAssistantPages.destination(initial[0].id, offset: 1, pages: initial + [second]) == second.id
                     && HomeAssistantPages.destination(second.id, offset: 1, pages: initial + [second]) == nil
                     && HomeAssistantPages.destination(initial[0].id, offset: Int.min, pages: initial) == nil,
                     "page navigation stops at boundaries and rejects invalid offsets")
        let payload = SettingsBackupSupport.payload(appVersion: "test") { defaults.object(forKey: $0) }
        let json = try! JSONSerialization.data(withJSONObject: payload)
        let decoded = try! JSONSerialization.jsonObject(with: json) as! [String: Any]
        let restored = SettingsBackupSupport.sanitizedSettings(from: decoded)
        suite.expect((restored?[DefaultsKey.notchHomeAssistantPages] as? [[String: Any]])?.count == 2
                     && restored?[DefaultsKey.notchHomeAssistantActivePage] as? String == second.id,
                     "JSON backups preserve named pages and the selected page")
        let importedName = "vorss.tests.home-pages-import.\(UUID().uuidString)"
        let imported = UserDefaults(suiteName: importedName)!
        defer { imported.removePersistentDomain(forName: importedName) }
        imported.set(restored?[DefaultsKey.notchHomeAssistantPages], forKey: DefaultsKey.notchHomeAssistantPages)
        imported.set(second.id, forKey: DefaultsKey.notchHomeAssistantActivePage)
        suite.expect(HomeAssistantPages.selected(in: imported) == second
                     && HomeAssistantPages.load(in: imported)[0].columns == nil,
                     "JSON backup restore retains custom columns and filling while keeping inherited pages inherited")
        let legacy = SettingsBackupSupport.sanitizedSettings(from: [SettingsBackupSupport.formatVersionKey: 1,
            SettingsBackupSupport.settingsKey: [DefaultsKey.notchHomeAssistantFavorites: ["switch.plug"]]])
        suite.expect((legacy?[DefaultsKey.notchHomeAssistantPages] as? [[String: Any]])?.isEmpty == true,
                     "restoring an old backup replaces existing pages with the restored flat selection")
        defaults.set([["id": "valid", "title": " Room\nA ", "entities": ["switch.plug", "switch.plug", "bad"],
                       "columns": 3, "fillLastRow": "invalid"],
                      ["id": "valid", "title": "Duplicate", "entities": []]], forKey: DefaultsKey.notchHomeAssistantPages)
        defaults.set("missing", forKey: DefaultsKey.notchHomeAssistantActivePage)
        suite.expect(HomeAssistantPages.load(in: defaults) == [.init(id: "valid", title: "Room A", entities: ["switch.plug"])]
                     && HomeAssistantPages.selected(in: defaults).id == "valid",
                     "malformed page selections are normalized and a missing active page falls back safely")
        var swipe = HomeAssistantPageSwipe()
        func feed(_ x: Double, _ y: Double = 0, began: Bool = false, ended: Bool = false, momentum: Bool = false,
                  precise: Bool = true, time: Double = 1) -> HomeAssistantPageSwipe.Result {
            swipe.handle(x: x, y: y, timestamp: time, precise: precise, began: began, ended: ended, momentum: momentum)
        }
        suite.expect(feed(-5, began: true) == .passThrough && feed(-15) == .consume && feed(-25) == .change(1),
                     "a left swipe accumulates into the next page")
        suite.expect(feed(-100) == .consume && feed(-100, momentum: true) == .consume
                     && feed(0, ended: true) == .consume && feed(-100, momentum: true) == .consume,
                     "a continued swipe and its momentum never skip multiple pages")
        suite.expect(feed(45, began: true) == .change(-1), "a new right swipe selects the previous page")
        suite.expect(feed(2, -20, began: true) == .passThrough && feed(-100, -10) == .passThrough && swipe.isVertical,
                     "vertical scrolling stays vertical even when the fingers later drift sideways")
        suite.expect(feed(-100, precise: false) == .passThrough && feed(-100) == .passThrough,
                     "a wheel and a gesture whose beginning was outside the gallery cannot change pages")
        suite.expect(feed(.nan, began: true) == .passThrough && feed(-45, began: true) == .change(1),
                     "invalid input resets cleanly without blocking the next swipe")
    }

    private static func clientContracts(_ suite: TestSuite) async {
        let transport = Transport()
        let client = HomeAssistantClient(transport: transport, timeout: 200_000_000)
        do {
            let events = try await client.connect(token: "test-token")
            var iterator = events.makeAsyncIterator()
            guard case .changed? = try await iterator.next(), case .snapshot(let entities)? = try await iterator.next() else {
                suite.expect(false, "subscription streams the event and initial snapshot"); await client.close(); return
            }
            suite.expect(entities.first?.state == "off", "initial snapshot is decoded without transforming server data")
            let action = try HomeAssistantAction.make("turn_on", entity: entity())
            transport.reject = true
            do { try await client.perform(action); suite.expect(false, "rejection must throw") }
            catch { suite.expect(error as? HomeAssistantFailure == .rejected, "server rejection is surfaced without raw credential-bearing messages") }
            transport.reject = false; transport.silent = true
            do { try await client.perform(action); suite.expect(false, "silent command must time out") }
            catch { suite.expect(error as? HomeAssistantFailure == .timeout, "unanswered actions time out") }
            suite.expect(transport.calls("call_service") == 2, "rejected and timed-out commands are each sent once")
            let waiting = Task { try await client.perform(action) }
            try? await Task.sleep(nanoseconds: 10_000_000)
            await client.close()
            do { try await waiting.value; suite.expect(false, "closing must cancel in-flight requests") }
            catch { suite.expect(true, "closing resumes in-flight continuations") }
            suite.expect(transport.isClosed, "closing terminates transport and pending reads")
        } catch { suite.expect(false, "valid client handshake succeeds: \(error)"); await client.close() }
        let invalid = Transport(invalidAuth: true)
        let unauthorized = HomeAssistantClient(transport: invalid)
        do { _ = try await unauthorized.connect(token: "bad"); suite.expect(false, "invalid credentials must fail") }
        catch { suite.expect(error as? HomeAssistantFailure == .credentials && invalid.calls("get_states") == 0,
                             "authentication failure stops before reading any entities") }
    }

    @MainActor private static func serviceContracts(_ suite: TestSuite) async {
        let name = "vorss.tests.home-assistant.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: AppFeature.notch.availabilityKey)
        defaults.set(true, forKey: AppFeature.notchHomeAssistant.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: DefaultsKey.notchHomeAssistantEnabled)
        let vault = Vault()
        let transport = Transport()
        let service = HomeAssistantService(defaults: defaults, credentials: vault, makeTransport: { _ in transport }, observesSleep: false)
        service.configure(url: "https://ha.example", token: "private-test-token")
        suite.expect(transport.calls("auth") == 0, "configuration alone does not start background work")
        suite.expect(vault.tokens["https://ha.example"] == "private-test-token"
                     && !defaults.dictionaryRepresentation().values.contains { ($0 as? String)?.contains("private-test-token") == true },
                     "tokens only enter the credential store")
        let first = UUID(), second = UUID()
        service.setVisible(true, surface: first)
        for _ in 0..<100 where service.connection != .connected { try? await Task.sleep(nanoseconds: 10_000_000) }
        suite.expect(service.connection == .connected && service.entities["light.desk"]?.state == "on" && service.temperatureUnit == "°C",
                     "visible service connects and merges early events")
        service.setFavorite("light.desk", selected: true)
        service.setFavorite("light.desk", selected: true)
        suite.expect(service.favorites == ["light.desk"], "favorite identities stay unique")
        service.setSensors(["sensor.plug_power", "sensor.plug_power", "lock.front", "sensor.plug_current"], for: "light.desk")
        let readings = service.cardReadings("light.desk", text: .localized(.enUS), locale: Locale(identifier: "en-US"))
        suite.expect(readings.map(\.id) == ["sensor.plug_power", "sensor.plug_current"]
                     && readings.first?.value == "58.4" && readings.first?.unit == "W",
                     "a control card exposes explicitly selected sensor values and units")
        await islandContracts(suite, service: service, transport: transport)
        transport.emit(entity("sensor.plug_power", state: "64.8", attributes: ["unit_of_measurement": .string("W")]))
        for _ in 0..<100 where service.entities["sensor.plug_power"]?.state != "64.8" { try? await Task.sleep(nanoseconds: 10_000_000) }
        suite.expect(service.cardReadings("light.desk", text: .localized(.enUS), locale: Locale(identifier: "en-US")).first?.value == "64.8"
                     && transport.calls("get_states") == 1,
                     "associated sensor changes arrive live without polling the server")
        transport.emit(entity("sensor.plug_power", state: "unavailable", attributes: ["unit_of_measurement": .string("W")]))
        for _ in 0..<100 where service.entities["sensor.plug_power"]?.state != "unavailable" { try? await Task.sleep(nanoseconds: 10_000_000) }
        let missingReading = service.cardReadings("light.desk", text: .localized(.enUS), locale: Locale(identifier: "en-US")).first
        suite.expect(missingReading?.value == HomeAssistantStrings.localized(.enUS)[.unavailable] && missingReading?.unit.isEmpty == true
                     && service.entities["light.desk"]?.available == true,
                     "an unavailable auxiliary sensor does not disable the device's own action")
        service.setName("Consumption", for: "sensor.plug_current")
        suite.expect(service.cardReadings("light.desk", text: .localized(.enUS), locale: Locale(identifier: "en-US")).last?.name == "Consumption"
                     && service.sensors["light.desk"]?.last == "sensor.plug_current",
                     "renaming an associated sensor changes its caption without changing identity")
        service.setName("", for: "sensor.plug_current")
        suite.expect(service.cardReadings("light.desk", text: .localized(.enUS), locale: Locale(identifier: "en-US")).last?.name
                     == service.entities["sensor.plug_current"]?.name,
                     "restoring a sensor caption uses Home Assistant's original name")
        service.setName("  Living room  ", for: "light.desk")
        service.setColumns(8)
        suite.expect(service.displayName("light.desk") == "Living room" && service.favorites == ["light.desk"]
                     && service.entities["light.desk"]?.id == "light.desk",
                     "renaming changes presentation without changing server identity or favorite order")
        let restored = HomeAssistantService(defaults: defaults, credentials: vault, makeTransport: { _ in Transport() }, observesSleep: false)
        suite.expect(restored.names["light.desk"] == "Living room" && restored.columns == 8
                     && restored.sensors["light.desk"] == ["sensor.plug_power", "sensor.plug_current"],
                     "aliases, extra sensors and density survive service recreation")
        service.setName(" ", for: "light.desk")
        suite.expect(service.names["light.desk"] == nil && service.displayName("light.desk") == service.entities["light.desk"]?.name,
                     "clearing an alias restores the server's friendly name")
        service.setName("Lamp", for: "light.desk")
        defaults.set(5, forKey: DefaultsKey.notchHomeAssistantColumns)
        defaults.set(["sensor.valid": " Room ", "sensor.invalid": 5, "sensor.empty": " "], forKey: DefaultsKey.notchHomeAssistantNames)
        restored.syncWithPreferences()
        suite.expect(restored.columns == 2 && restored.names == ["sensor.valid": "Room"],
                     "imported malformed preferences are normalized without affecting device control")
        service.setColumns(8)
        service.setName("Lamp", for: "light.desk")
        service.perform("turn_off", entityID: "light.desk")
        service.perform("turn_off", entityID: "light.desk")
        for _ in 0..<100 where service.pending.contains("light.desk") { try? await Task.sleep(nanoseconds: 10_000_000) }
        suite.expect(transport.calls("call_service") == 1 && service.entities["light.desk"]?.state == "off" && service.pending.isEmpty,
                     "duplicate clicks are ignored while server-confirmed actions complete")
        transport.emitsChanges = false
        service.perform("turn_off", entityID: "light.desk")
        for _ in 0..<100 where service.pending.contains("light.desk") { try? await Task.sleep(nanoseconds: 10_000_000) }
        suite.expect(service.pending.isEmpty && service.failure == nil,
                     "an acknowledged idempotent action completes even when HA emits no new state event")
        transport.emitsChanges = true
        let rgbAttributes: [String: HomeAssistantValue] = ["supported_color_modes": .array([.string("rgb")]),
            "color_mode": .string("rgb"), "rgb_color": HomeAssistantRGB(red: 255, green: 0, blue: 0).value]
        transport.emit(entity("light.rgb", attributes: rgbAttributes))
        for _ in 0..<100 where service.entities["light.rgb"] == nil { try? await Task.sleep(nanoseconds: 10_000_000) }
        let colorCalls = transport.calls("call_service")
        service.setColor(HomeAssistantRGB(red: 0, green: 0, blue: 255), entityID: "light.rgb")
        service.setColor(HomeAssistantRGB(red: 0, green: 255, blue: 0), entityID: "light.rgb")
        for _ in 0..<100 where service.pending.contains("light.rgb") { try? await Task.sleep(nanoseconds: 10_000_000) }
        suite.expect(transport.calls("call_service") == colorCalls + 1 && service.pending.isEmpty && service.failure == nil
                     && service.entities["light.rgb"]?.state == "on"
                     && service.entities["light.rgb"]?.rgbColor == HomeAssistantRGB(red: 0, green: 0, blue: 255),
                     "color controls send once, suppress pending duplicates and render the server-confirmed color")
        let originalPage = service.activePageID
        let newPage = service.addPage()
        service.renamePage(newPage, title: " Bedroom ")
        service.setEntity("light.desk", selected: true, pageID: newPage)
        service.setEntity("sensor.plug_current", selected: true, pageID: newPage)
        suite.expect(service.visibleEntityIDs == ["light.desk", "sensor.plug_current"] && service.pages.last?.title == "Bedroom",
                     "a named page has an independent entity selection")
        service.setPageColumns(4, pageID: newPage)
        service.setPageFillLastRow(true, pageID: newPage)
        suite.expect(service.effectiveColumns == 4 && service.activePage?.fillLastRow == true && service.columns == 8,
                     "per-page layout overrides do not alter the global column preference")
        service.setColumns(6)
        suite.expect(service.effectiveColumns == 4, "a global column change does not replace a page's override")
        service.setPageColumns(nil, pageID: newPage)
        suite.expect(service.effectiveColumns == 6 && service.activePage?.fillLastRow == true,
                     "disabling custom columns immediately restores inheritance and retains row filling")
        service.setPageColumns(3, pageID: newPage)
        suite.expect(service.activePage?.columns == nil && service.effectiveColumns == 6,
                     "invalid custom column values safely fall back to the global setting")
        service.setColumns(8)
        service.setPageColumns(4, pageID: newPage)
        service.selectPage(originalPage)
        suite.expect(service.visibleEntityIDs == ["light.desk"] && service.favorites.contains("sensor.plug_current")
                     && service.effectiveColumns == 8 && service.activePage?.fillLastRow == false,
                     "switching pages preserves entities assigned to other pages")
        service.advancePage(by: 1)
        let pagesRestored = HomeAssistantService(defaults: defaults, credentials: vault, observesSleep: false)
        suite.expect(pagesRestored.pages == service.pages && pagesRestored.activePageID == newPage,
                     "named pages and the active selection survive service recreation")
        service.movePage(newPage, by: -1)
        suite.expect(service.pages.first?.id == newPage && service.activePageID == newPage,
                     "reordering pages preserves the active page identity")
        let callsBeforeTransfers = transport.calls("call_service")
        service.transferEntity("sensor.plug_current", from: newPage, to: originalPage, duplicate: true)
        service.transferEntity("sensor.plug_current", from: newPage, to: originalPage, duplicate: true)
        suite.expect(service.pages.first?.entities == ["light.desk", "sensor.plug_current"]
                     && service.pages.last?.entities == ["light.desk", "sensor.plug_current"],
                     "duplicating appends to the destination, keeps the source and never duplicates a card within a page")
        service.transferEntity("sensor.plug_current", from: originalPage, to: newPage, duplicate: false)
        suite.expect(service.pages.last?.entities == ["light.desk"] && service.pages.first?.entities.count == 2,
                     "moving to a page that already contains the entity removes only its source assignment")
        service.transferEntity("light.desk", from: originalPage, to: newPage, duplicate: false)
        service.transferEntity("light.desk", from: newPage, to: originalPage, duplicate: false)
        suite.expect(service.pages.first?.entities == ["sensor.plug_current"] && service.pages.last?.entities == ["light.desk"]
                     && service.names["light.desk"] == "Lamp"
                     && service.sensors["light.desk"] == ["sensor.plug_power", "sensor.plug_current"],
                     "moving between pages preserves aliases and associated readings")
        let beforeInvalidTransfers = service.pages
        service.transferEntity("light.desk", from: originalPage, to: originalPage, duplicate: false)
        service.transferEntity("light.desk", from: originalPage, to: "missing", duplicate: false)
        service.transferEntity("light.desk", from: newPage, to: originalPage, duplicate: false)
        suite.expect(service.pages == beforeInvalidTransfers && service.activePageID == newPage
                     && transport.calls("call_service") == callsBeforeTransfers,
                     "invalid transfers are ignored, page selection stays unchanged and rearranging cards sends no device actions")
        let transfersRestored = HomeAssistantService(defaults: defaults, credentials: vault, observesSleep: false)
        suite.expect(transfersRestored.pages == service.pages,
                     "moved and duplicated assignments survive service recreation")
        service.removePage(newPage)
        service.removePage(originalPage)
        suite.expect(service.pages.count == 1 && service.activePageID == originalPage && service.visibleEntityIDs == ["light.desk"],
                     "deleting a page retains other assignments and cannot remove the final page")
        service.setVisible(true, surface: second)
        service.setVisible(false, surface: first)
        suite.expect(service.connection == .connected, "one remaining visible surface keeps the connection")
        service.setVisible(false, surface: second)
        try? await Task.sleep(nanoseconds: 10_000_000)
        suite.expect(transport.isClosed && service.connection == .offline, "closing the last surface stops network work")
        let offlineCalls = transport.calls("call_service")
        service.setColor(HomeAssistantRGB(red: 255, green: 0, blue: 0), entityID: "light.rgb")
        suite.expect(transport.calls("call_service") == offlineCalls, "an offline color selection cannot send a device command")
        service.configure(url: "https://ha.example", token: "")
        suite.expect(service.names["light.desk"] == "Lamp" && service.columns == 8,
                     "retesting the same server preserves aliases and density")
        service.configure(url: "https://another.example", token: "new-token")
        suite.expect(service.favorites.isEmpty && service.entities.isEmpty && service.names.isEmpty && service.sensors.isEmpty && service.columns == 8,
                     "changing servers clears device aliases and selections while preserving density")
        service.setName("Another lamp", for: "light.desk")
        service.forgetConnection()
        suite.expect(service.server.isEmpty && vault.tokens["https://another.example"] == nil && service.names.isEmpty,
                     "forgetting removes the selected server's credential and local aliases")
        service.stop()

        let transports = Transports()
        let lifecycle = HomeAssistantService(defaults: defaults, credentials: vault,
            makeTransport: { _ in transports.make() }, observesSleep: false)
        lifecycle.configure(url: "https://ha.example", token: "local-test-token")
        lifecycle.setVisible(true, surface: first)
        for _ in 0..<100 where lifecycle.connection != .connected { try? await Task.sleep(nanoseconds: 10_000_000) }
        lifecycle.setSleeping(true)
        try? await Task.sleep(nanoseconds: 20_000_000)
        suite.expect(transports.values.first?.isClosed == true && lifecycle.connection == .offline,
                     "sleep suspends the visible connection")
        lifecycle.setSleeping(false)
        for _ in 0..<100 where lifecycle.connection != .connected { try? await Task.sleep(nanoseconds: 10_000_000) }
        suite.expect(transports.values.count == 2 && lifecycle.connection == .connected,
                     "wake creates a fresh authenticated connection and reloads states")
        transports.values.last?.close()
        for _ in 0..<200 {
            if transports.values.count == 3 && lifecycle.connection == .connected { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        suite.expect(transports.values.count == 3 && lifecycle.connection == .connected,
                     "network loss reconnects while a surface remains visible")
        suite.expect(transports.values.reduce(0) { $0 + $1.calls("call_service") } == 0,
                     "reconnection never replays commands")
        defaults.set(false, forKey: AppFeature.notchHomeAssistant.availabilityKey)
        lifecycle.syncWithPreferences()
        try? await Task.sleep(nanoseconds: 20_000_000)
        suite.expect(transports.values.last?.isClosed == true && lifecycle.connection == .offline,
                     "uninstalling the feature tears down its visible connection")
        lifecycle.stop()
    }
    @MainActor private static func islandContracts(_ suite: TestSuite, service: HomeAssistantService, transport: Transport) async {
        let model = HomeAssistantIslandModel(service: service)
        let original = model.state
        var updates = 0
        let subscription = model.$state.dropFirst().sink { _ in updates += 1 }
        defer { subscription.cancel() }
        for index in 0..<50 {
            transport.emit(entity("sensor.unselected", state: String(index)))
            transport.emit(entity(state: "on"))
        }
        transport.emit(entity("sensor.unselected", state: "done"))
        for _ in 0..<100 where service.entities["sensor.unselected"]?.state != "done" {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        try? await Task.sleep(nanoseconds: 60_000_000)
        suite.expect(service.entities["sensor.unselected"]?.state == "done"
                     && model.state == original && updates == 0,
                     "unselected sensors remain searchable without redrawing the island during scroll")
        suite.expect(model.state.entities["sensor.plug_power"] != nil && model.state.entities["sensor.unselected"] == nil,
                     "the island retains associated readings while excluding unrelated server entities")
        var notifications = 0
        let changes = service.objectWillChange.sink { notifications += 1 }
        for _ in 0..<50 { transport.emit(entity(state: "on")) }
        transport.emit(entity("sensor.unselected", state: "processed"))
        for _ in 0..<100 where service.entities["sensor.unselected"]?.state != "processed" {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        changes.cancel()
        suite.expect(notifications == 1, "duplicate server states do not issue redundant UI notifications")
        for index in 0..<100 {
            transport.emit(entity("sensor.plug_power", state: String(index), attributes: ["unit_of_measurement": .string("W")]))
        }
        for _ in 0..<100 where model.state.entities["sensor.plug_power"]?.state != "99" {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        suite.expect(model.state.entities["sensor.plug_power"]?.state == "99" && updates > 0 && updates < 100
                     && model.state.cardReadings("light.desk", text: .localized(.enUS), locale: Locale(identifier: "en-US")).first?.value == "99",
                     "bursts coalesce visual updates while preserving the latest associated sensor reading")
        service.setName("Amperage", for: "sensor.plug_current")
        service.setColumns(4)
        for _ in 0..<100 where model.state.columns != 4 || model.state.displayName("sensor.plug_current") != "Amperage" {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        suite.expect(model.state.columns == 4 && model.state.displayName("sensor.plug_current") == "Amperage",
                     "the island projection follows density changes and sensor aliases")
        service.setPageColumns(2, pageID: service.activePageID)
        service.setPageFillLastRow(true, pageID: service.activePageID)
        for _ in 0..<100 where model.state.columns != 2 || !model.state.fillLastRow {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        suite.expect(model.state.columns == 2 && model.state.fillLastRow && service.columns == 4,
                     "the island projection follows per-page columns and last-row filling instead of the global columns")
        service.setPageColumns(nil, pageID: service.activePageID)
        service.setPageFillLastRow(false, pageID: service.activePageID)
        for _ in 0..<100 where model.state.columns != 4 || model.state.fillLastRow {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        suite.expect(model.state.columns == 4 && !model.state.fillLastRow,
                     "removing a page override updates the island back to the global layout")
        service.setName("", for: "sensor.plug_current")
        service.setColumns(2)
    }

    private final class Transports {
        var values: [Transport] = []
        func make() -> Transport {
            let transport = Transport(); values.append(transport); return transport
        }
    }

    private final class Vault: HomeAssistantCredentialStore {
        var tokens: [String: String] = [:]
        func read(server: String) throws -> String? { tokens[server] }
        func save(_ token: String, server: String) throws { tokens[server] = token }
        func remove(server: String) throws { tokens.removeValue(forKey: server) }
    }

    final class Transport: HomeAssistantTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var messages: [String] = []
        private var waiter: CheckedContinuation<String, Error>?
        private var sent: [[String: HomeAssistantValue]] = []
        private var closed = false
        private var rejecting = false
        private var silentActions = false
        private var serviceChanges = true
        let invalidAuth: Bool
        var emitsChanges: Bool { get { lock.withLock { serviceChanges } } set { lock.withLock { serviceChanges = newValue } } }
        var reject: Bool { get { lock.withLock { rejecting } } set { lock.withLock { rejecting = newValue } } }
        var silent: Bool { get { lock.withLock { silentActions } } set { lock.withLock { silentActions = newValue } } }
        var isClosed: Bool { lock.withLock { closed } }
        init(invalidAuth: Bool = false) {
            self.invalidAuth = invalidAuth
            push(["type": .string("auth_required")])
        }
        func calls(_ type: String) -> Int { lock.withLock { sent.filter { $0["type"]?.string == type }.count } }
        func send(_ text: String) async throws {
            let message = try JSONDecoder().decode([String: HomeAssistantValue].self, from: Data(text.utf8))
            lock.withLock { sent.append(message) }
            let type = message["type"]?.string
            if type == "auth" { push(["type": .string(invalidAuth ? "auth_invalid" : "auth_ok")]); return }
            if type == "call_service", silent { return }
            var response: [String: HomeAssistantValue] = ["id": message["id"]!, "type": .string("result"), "success": .bool(true), "result": .null]
            if type == "get_config" {
                response["result"] = .object(["unit_system": .object(["temperature": .string("°C")])])
            } else if type == "get_states" {
                change(entity(state: "on"))
                response["result"] = .array([value(entity()), value(entity("sensor.plug_power", state: "58.4",
                    attributes: ["friendly_name": .string("Power"), "unit_of_measurement": .string("W")])),
                    value(entity("sensor.plug_current", state: "0.2", attributes: ["unit_of_measurement": .string("A")]))])
            } else if type == "call_service" {
                response["success"] = .bool(!reject)
                if !reject, emitsChanges {
                    if let rgb = message["service_data"]?.object?["rgb_color"] {
                        let id = message["target"]?.object?["entity_id"]?.string ?? "light.rgb"
                        change(entity(id, state: "on", attributes: ["supported_color_modes": .array([.string("rgb")]),
                            "color_mode": .string("rgb"), "rgb_color": rgb]))
                    } else { change(entity(state: message["service"]?.string == "turn_off" ? "off" : "on")) }
                }
            }
            push(response)
        }
        func emit(_ entity: HomeAssistantEntity) { change(entity) }
        private func change(_ entity: HomeAssistantEntity) {
            push(["type": .string("event"), "event": .object(["data": .object([
                "entity_id": .string(entity.id), "new_state": value(entity)])])])
        }
        private func push(_ message: [String: HomeAssistantValue]) {
            let text = String(decoding: try! JSONEncoder().encode(message), as: UTF8.self)
            let continuation = lock.withLock { () -> CheckedContinuation<String, Error>? in
                guard !closed else { return nil }
                if let waiter { self.waiter = nil; return waiter }
                messages.append(text); return nil
            }
            continuation?.resume(returning: text)
        }
        func receive() async throws -> String {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    if closed { continuation.resume(throwing: HomeAssistantFailure.network) }
                    else if !messages.isEmpty { continuation.resume(returning: messages.removeFirst()) }
                    else { waiter = continuation }
                }
            }
        }
        func close() {
            let continuation = lock.withLock { () -> CheckedContinuation<String, Error>? in
                closed = true
                let value = waiter; waiter = nil
                return value
            }
            continuation?.resume(throwing: HomeAssistantFailure.network)
        }
    }
}
