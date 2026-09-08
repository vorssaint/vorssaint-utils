// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum MouseButtonTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Mouse button shortcuts (issue #282)

        expect(Defaults.registeredDefaults[DefaultsKey.mouseButtonShortcutsEnabled] as? Bool == false,
               "mouse button shortcuts ship off by default")
        expect((Defaults.registeredDefaults[DefaultsKey.mouseButtonShortcuts] as? [String: String])?.isEmpty == true,
               "the mapping dictionary registers empty so it travels with backups")
        expect(Defaults.registeredDefaults[DefaultsKey.panelControlMouseButtonShortcuts] as? Bool == true,
               "the mouse button shortcuts panel row ships visible like its siblings")
        expect(AppFeature.mouseButtonShortcuts.enabledKeys == [DefaultsKey.mouseButtonShortcutsEnabled,
                                                              DefaultsKey.mouseSpacesGestureEnabled]
                && AppFeature.mouseButtonShortcuts.permissions == [.accessibility]
                && AppFeature.mouseButtonShortcuts.group == .mouseKeyboard,
               "the hub knows the feature's switch, permission and group")

        expect(MouseButtonShortcutSupport.canMap(3) && MouseButtonShortcutSupport.canMap(31)
                && MouseButtonShortcutSupport.canMap(MouseButtonShortcutSupport.sideWheelLeftInput)
                && MouseButtonShortcutSupport.canMap(MouseButtonShortcutSupport.sideWheelRightInput)
                && !MouseButtonShortcutSupport.canMap(0) && !MouseButtonShortcutSupport.canMap(1)
                && !MouseButtonShortcutSupport.canMap(2) && !MouseButtonShortcutSupport.canMap(32)
                && !MouseButtonShortcutSupport.canMap(-3),
               "only extra buttons and both side-wheel directions can carry a shortcut")
        expect(MouseButtonShortcutSupport.backButtonNumber == MouseNavigationSupport.backButtonNumber
                && MouseButtonShortcutSupport.forwardButtonNumber == MouseNavigationSupport.forwardButtonNumber,
               "button shortcuts and mouse navigation agree on which button is which")
        let pressedExtraButtons = (1 << 3) | (1 << 31)
        expect(MouseButtonShortcutSupport.isPressed(3, pressedButtons: pressedExtraButtons)
                && MouseButtonShortcutSupport.isPressed(31, pressedButtons: pressedExtraButtons)
                && !MouseButtonShortcutSupport.isPressed(4, pressedButtons: pressedExtraButtons)
                && !MouseButtonShortcutSupport.isPressed(-1, pressedButtons: pressedExtraButtons)
                && !MouseButtonShortcutSupport.isPressed(Int64(Int.bitWidth),
                                                         pressedButtons: pressedExtraButtons),
               "tap recovery keeps custody only for extra buttons still physically held")

        let buttonCombo = GlobalShortcut(keyCode: 0, modifiers: [.command, .shift])
        let decodedButtons = MouseButtonShortcutSupport.decode([
            "3": buttonCombo.storageValue,
            "4": "command:11",
            String(MouseButtonShortcutSupport.sideWheelLeftInput): "command:11",
            "2": "command:11",
            "40": "command:11",
            "junk": "command:11",
            "5": "garbage",
            "6": ":48",
        ])
        expect(decodedButtons.count == 3 && decodedButtons[3] == buttonCombo && decodedButtons[4] != nil
                && decodedButtons[MouseButtonShortcutSupport.sideWheelLeftInput] != nil,
               "decoding keeps valid button and side-wheel mappings and drops everything else")
        expect(MouseButtonShortcutSupport.decode(MouseButtonShortcutSupport.encode(decodedButtons))
                == decodedButtons,
               "mappings round-trip through their stored form")
        expect(MouseButtonShortcutSupport.decode(nil).isEmpty,
               "no stored mappings decode to none")
        expect(MouseButtonShortcutSupport.sortedButtons([
            5: buttonCombo,
            MouseButtonShortcutSupport.sideWheelRightInput: buttonCombo,
            MouseButtonShortcutSupport.sideWheelLeftInput: buttonCombo,
            3: buttonCombo,
            12: buttonCombo,
        ]) == [MouseButtonShortcutSupport.sideWheelLeftInput,
               MouseButtonShortcutSupport.sideWheelRightInput, 3, 5, 12],
               "settings rows keep side-wheel directions together before numbered buttons")
        expect(MouseButtonShortcutSupport.sideWheelInput(isContinuous: false,
                                                         vertical: (0, 0, 0),
                                                         horizontal: (1, 0, 0))
                == MouseButtonShortcutSupport.sideWheelLeftInput
                && MouseButtonShortcutSupport.sideWheelInput(isContinuous: false,
                                                             vertical: (0, 0, 0),
                                                             horizontal: (0, -0.25, 0))
                == MouseButtonShortcutSupport.sideWheelRightInput
                && MouseButtonShortcutSupport.sideWheelInput(isContinuous: true,
                                                             vertical: (0, 0, 0),
                                                             horizontal: (0, 0, 3))
                == MouseButtonShortcutSupport.sideWheelLeftInput
                && MouseButtonShortcutSupport.sideWheelInput(isContinuous: true,
                                                             vertical: (0, 0, 0),
                                                             horizontal: (0, 0, 0)) == nil,
               "side-wheel directions follow AppKit's horizontal sign for discrete and continuous mice")
        expect(MouseButtonShortcutSupport.sideWheelInput(isContinuous: false,
                                                         vertical: (2, 2, 20),
                                                         horizontal: (1, 1, 10)) == nil
                && MouseButtonShortcutSupport.sideWheelInput(isContinuous: false,
                                                             vertical: (1, 1, 10),
                                                             horizontal: (1, 1, 10)) == nil
                && MouseButtonShortcutSupport.sideWheelInput(isContinuous: true,
                                                             vertical: (0, 0, 3),
                                                             horizontal: (0, 0, 4))
                == MouseButtonShortcutSupport.sideWheelLeftInput,
               "vertical and diagonal scrolling cannot leak into a side-wheel shortcut")

        var sideWheelGesture = MouseButtonShortcutSupport.SideWheelGestureGate()
        let wheelLeft = MouseButtonShortcutSupport.sideWheelLeftInput
        let wheelRight = MouseButtonShortcutSupport.sideWheelRightInput
        expect(sideWheelGesture.shouldFire(wheelLeft, at: 0)
                && !sideWheelGesture.shouldFire(wheelLeft, at: 10_000_000)
                && sideWheelGesture.shouldFire(wheelRight, at: 20_000_000)
                && !sideWheelGesture.shouldFire(wheelLeft, at: 30_000_000)
                && !sideWheelGesture.shouldFire(wheelRight, at: 40_000_000),
               "one wheel burst fires each deliberate direction exactly once")
        expect(sideWheelGesture.shouldFire(wheelLeft, at: 300_000_001),
               "a quiet gap arms the next side-wheel gesture")
        sideWheelGesture.reset()
        expect(sideWheelGesture.shouldFire(wheelRight, at: 1),
               "stopping the tap clears the side-wheel gesture state")

        expect(MouseButtonShortcutSupport.firesShortcut(for: 3, isAvailable: true, isEnabled: true,
                                                        mappings: [3: buttonCombo],
                                                        claimedByWheel: { _ in false }) == buttonCombo,
               "an available, enabled mapping fires its combination")
        expect(MouseButtonShortcutSupport.firesShortcut(for: 3, isAvailable: true, isEnabled: true,
                                                        mappings: [3: buttonCombo],
                                                        claimedByWheel: { $0 == 3 }) == nil,
               "the radial menu's summoner button never doubles as a shortcut")
        expect(MouseButtonShortcutSupport.firesShortcut(for: 3, isAvailable: false, isEnabled: true,
                                                        mappings: [3: buttonCombo],
                                                        claimedByWheel: { _ in false }) == nil
                && MouseButtonShortcutSupport.firesShortcut(for: 3, isAvailable: true, isEnabled: false,
                                                            mappings: [3: buttonCombo],
                                                            claimedByWheel: { _ in false }) == nil
                && MouseButtonShortcutSupport.firesShortcut(for: 4, isAvailable: true, isEnabled: true,
                                                            mappings: [3: buttonCombo],
                                                            claimedByWheel: { _ in false }) == nil,
               "hub-off, switch-off and unmapped buttons all stay inert")
        expect(!MouseButtonShortcutSupport.claimsButton(3) && !MouseButtonShortcutSupport.claimsButton(4),
               "with the feature off no button is claimed away from navigation")
        expect(MouseButtonShortcutSupport.buttonName(for: 3, strings: .enUS)
                == MouseButtonFeatureStrings.enUS.backButtonName
                && MouseButtonShortcutSupport.buttonName(for: 4, strings: .enUS)
                == MouseButtonFeatureStrings.enUS.forwardButtonName
                && MouseButtonShortcutSupport.buttonName(
                    for: MouseButtonShortcutSupport.sideWheelLeftInput, strings: .enUS) == "Side wheel left"
                && MouseButtonShortcutSupport.buttonName(
                    for: MouseButtonShortcutSupport.sideWheelRightInput, strings: .enUS) == "Side wheel right"
                && MouseButtonShortcutSupport.buttonName(for: 5, strings: .enUS) == "Button 6",
               "buttons and side-wheel directions have clear names")

        // MARK: Spaces and Mission Control drag (issue #1012)

        let spaceStep = MouseSpacesGestureSupport.spaceStep
        let overviewStep = MouseSpacesGestureSupport.overviewStep
        let spaceCooldown = MouseSpacesGestureSupport.spaceRepeatCooldown

        var dragRight = MouseSpacesGestureSupport.Tracker(origin: .zero)
        expect(dragRight.advance(to: CGPoint(x: spaceStep - 1, y: 0), now: 0) == nil
                && dragRight.advance(to: CGPoint(x: spaceStep, y: 0), now: 0.1) == .spaceRight,
               "one whole step to the right moves one Space to the right, and not a pixel sooner")
        var dragLeft = MouseSpacesGestureSupport.Tracker(origin: .zero)
        expect(dragLeft.advance(to: CGPoint(x: -spaceStep, y: 0), now: 0) == .spaceLeft,
               "the same step to the left moves the other way")
        var dragUp = MouseSpacesGestureSupport.Tracker(origin: .zero)
        expect(dragUp.advance(to: CGPoint(x: 0, y: -overviewStep + 1), now: 0) == nil
                && dragUp.advance(to: CGPoint(x: 0, y: -overviewStep), now: 0.1) == .missionControl,
               "dragging up opens Mission Control once the vertical step is behind it")
        var dragDown = MouseSpacesGestureSupport.Tracker(origin: .zero)
        expect(dragDown.advance(to: CGPoint(x: 0, y: overviewStep), now: 0) == .appExpose,
               "dragging down opens App Exposé, the way the trackpad swipe does")

        var nudge = MouseSpacesGestureSupport.Tracker(origin: .zero)
        let nudged = (1...12).compactMap {
            nudge.advance(to: CGPoint(x: CGFloat($0) * 5, y: CGFloat($0) * 3), now: Double($0) * 0.02)
        }
        expect(nudged.isEmpty && !nudge.didFire && nudge.axis == nil,
               "a drag that stays under both steps does nothing, so the press is still a plain click")

        var wildPointer = MouseSpacesGestureSupport.Tracker(origin: .zero)
        expect(wildPointer.advance(to: CGPoint(x: CGFloat.nan, y: CGFloat.infinity), now: 0) == nil
                && !wildPointer.didFire,
               "a pointer position that is not a number moves nothing")

        var heldDrag = MouseSpacesGestureSupport.Tracker(origin: .zero)
        expect(heldDrag.advance(to: CGPoint(x: spaceStep, y: 0), now: 0) == .spaceRight
                && heldDrag.advance(to: CGPoint(x: spaceStep * 2, y: 0), now: spaceCooldown / 2) == nil
                && heldDrag.advance(to: CGPoint(x: spaceStep * 2 + 1, y: 0),
                                    now: spaceCooldown + 0.01) == .spaceRight,
               "a held drag repeats one Space per step, never faster than the slide animation")

        var flick = MouseSpacesGestureSupport.Tracker(origin: .zero)
        _ = flick.advance(to: CGPoint(x: spaceStep, y: 0), now: 0)
        _ = flick.advance(to: CGPoint(x: spaceStep * 6, y: 0), now: spaceCooldown / 2)
        expect(flick.advance(to: CGPoint(x: spaceStep * 6, y: 0),
                             now: spaceCooldown + 0.01) == .spaceRight
                && flick.advance(to: CGPoint(x: spaceStep * 6, y: 0),
                                 now: spaceCooldown * 2 + 0.02) == nil,
               "a fast flick banks one further Space change, not a burst that outlives the hand")

        var diagonal = MouseSpacesGestureSupport.Tracker(origin: .zero)
        expect(diagonal.advance(to: CGPoint(x: spaceStep, y: 0), now: 0) == .spaceRight
                && diagonal.advance(to: CGPoint(x: spaceStep, y: -overviewStep * 3),
                                    now: spaceCooldown + 0.01) == nil
                && diagonal.axis == .horizontal,
               "a press that started switching Spaces never throws up Mission Control halfway through")

        var overviewPress = MouseSpacesGestureSupport.Tracker(origin: .zero)
        expect(overviewPress.advance(to: CGPoint(x: 0, y: -overviewStep), now: 0) == .missionControl
                && overviewPress.advance(to: CGPoint(x: 0, y: -overviewStep * 4), now: 1) == nil
                && overviewPress.didFire,
               "an overview is a toggle, so one press opens it exactly once")

        var bothAxes = MouseSpacesGestureSupport.Tracker(origin: .zero)
        expect(bothAxes.advance(to: CGPoint(x: spaceStep, y: overviewStep * 2), now: 0) == .appExpose,
               "a step past both thresholds is read as the axis that went furthest past its own")

        expect(MouseSpacesGestureSupport.resolved(.spaceRight, followsDrag: true) == .spaceLeft
                && MouseSpacesGestureSupport.resolved(.spaceLeft, followsDrag: true) == .spaceRight
                && MouseSpacesGestureSupport.resolved(.missionControl, followsDrag: true) == .missionControl
                && MouseSpacesGestureSupport.resolved(.appExpose, followsDrag: true) == .appExpose
                && MouseSpacesGestureSupport.resolved(.spaceRight, followsDrag: false) == .spaceRight
                && MouseSpacesGestureSupport.resolved(.spaceLeft, followsDrag: false) == .spaceLeft,
               "the Space can follow the hand instead of the pointer, and the overviews never swap")

        expect(MouseSpacesGestureSupport.canBind(3) && MouseSpacesGestureSupport.canBind(31)
                && !MouseSpacesGestureSupport.canBind(2) && !MouseSpacesGestureSupport.canBind(32)
                && !MouseSpacesGestureSupport.canBind(MouseButtonShortcutSupport.sideWheelLeftInput),
               "the drag lives on an extra button, never on a side-wheel tick there is no way to hold")

        expect(MouseSpacesGestureSupport.boundButton(isAvailable: true, isEnabled: true, button: 4,
                                                     hasShortcut: { _ in false },
                                                     claimedByWheel: { _ in false }) == 4,
               "an available, enabled and unclaimed button drives the drag")
        expect(MouseSpacesGestureSupport.boundButton(isAvailable: true, isEnabled: true, button: 4,
                                                     hasShortcut: { $0 == 4 },
                                                     claimedByWheel: { _ in false }) == nil
                && MouseSpacesGestureSupport.boundButton(isAvailable: true, isEnabled: true, button: 4,
                                                         hasShortcut: { _ in false },
                                                         claimedByWheel: { $0 == 4 }) == nil
                && MouseSpacesGestureSupport.boundButton(isAvailable: false, isEnabled: true, button: 4,
                                                         hasShortcut: { _ in false },
                                                         claimedByWheel: { _ in false }) == nil
                && MouseSpacesGestureSupport.boundButton(isAvailable: true, isEnabled: false, button: 4,
                                                         hasShortcut: { _ in false },
                                                         claimedByWheel: { _ in false }) == nil
                && MouseSpacesGestureSupport.boundButton(isAvailable: true, isEnabled: true, button: 0,
                                                         hasShortcut: { _ in false },
                                                         claimedByWheel: { _ in false }) == nil,
               "the drag never takes a button from a shortcut, from the wheel, or from a switched-off hub")
        expect(MouseButtonShortcutSupport.spacesGestureButton() == nil,
               "with nothing configured the drag claims no button away from navigation")

        let spacesServiceCode = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/MouseButtons/MouseButtonShortcutService.swift",
            encoding: .utf8)) ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(spacesServiceCode.contains("if button == spacesButton {")
                && spacesServiceCode.contains("return armSpacesGesture(event, button: button)"),
               "the bound button's press is held back by the tap that already receives its drags")
        expect(spacesServiceCode.contains("guard gesture.tracker.didFire else {")
                && spacesServiceCode.contains(
                    "replaySpacesPress(gesture.down, proxy: proxy, at: event.location)"),
               "a press that never fired goes back, so a tap on that button keeps its ordinary click")
        expect(spacesServiceCode.contains("SpaceWindowBridge.spaceShortcut(.left)")
                && spacesServiceCode.contains("SpaceWindowBridge.overviewShortcut(.missionControl)")
                && !spacesServiceCode.contains("DockSwipe"),
               "the drag asks with the system's own registered combinations, never a simulated gesture")

        let spaceBridgeCode = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Switcher/SpaceWindowBridge.swift",
            encoding: .utf8)) ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(spaceBridgeCode.contains("self == .left ? 79 : 81")
                && spaceBridgeCode.contains("self == .missionControl ? 32 : 33")
                && spaceBridgeCode.contains("CGSIsSymbolicHotKeyEnabled"),
               "the Space steps and the overviews keep their system symbolic hotkey ids")

        // The drag alone keeps the tap alive with the shortcut switch off, so
        // the down path must read that switch itself and hand the click back
        // whole: a mapping left behind is inert and its button is the app's.
        let spacesServiceLines = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/MouseButtons/MouseButtonShortcutService.swift",
            encoding: .utf8)) ?? "").components(separatedBy: "\n")

        let commandBarCatalogLines = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift",
            encoding: .utf8)) ?? "").components(separatedBy: "\n")
        for (constructor, eligibility) in [
            ("killProcessEntries", "false"),
            ("windowEntries", "false"),
            ("quitEntries", "app.bundleIdentifier != nil"),
        ] {
            let constructorCode = commandBarCatalogLines.firstIndex {
                isCodeLine($0) && $0.contains("static func \(constructor)(")
            }.map {
                commandBarCatalogLines[($0 + 1)...]
                    .prefix { !$0.contains("static func ") }
                    .filter(isCodeLine).joined(separator: "\n")
            } ?? ""
            expect(constructorCode.contains("countsUsage: \(eligibility)"),
                   "\(constructor) excludes recycled process and window IDs from learning")
        }
        let mouseButtonToggleCode = commandBarCatalogLines.firstIndex {
            isCodeLine($0) && $0.contains("if feature == .mouseButtonShortcuts {")
        }.map {
            commandBarCatalogLines[$0...].prefix(18).filter(isCodeLine).joined(separator: "\n")
        } ?? ""
        let mouseButtonToggleID = "toggle.\(AppFeature.mouseButtonShortcuts.rawValue)"
        expect(mouseButtonToggleCode.contains("DefaultsKey.mouseButtonShortcutsEnabled")
                && mouseButtonToggleCode.contains("feature.hubTitle(s, hub: hub)")
                && mouseButtonToggleCode.contains("id: \"\(mouseButtonToggleID)\""),
               "the Command Bar keeps the mouse-button shortcut row's key, title and stable id")
        expect(mouseButtonToggleCode.contains("FeatureStrings.mouseButtons(language)")
                && mouseButtonToggleCode.contains("DefaultsKey.mouseSpacesGestureEnabled")
                && mouseButtonToggleCode.contains("spacesEnableLabel")
                && mouseButtonToggleCode.contains("id: \"\(mouseButtonToggleID).spacesGesture\""),
               "the Command Bar exposes the Spaces gesture as its own localized toggle row")

        let restartAppCode = commandBarCatalogLines.firstIndex {
            isCodeLine($0) && $0.contains("id: \"action.restartApp\"")
        }.map {
            commandBarCatalogLines[$0...].prefix(8).filter(isCodeLine).joined(separator: "\n")
        } ?? ""
        expect(restartAppCode.contains("bar.restartAppFormat")
                && restartAppCode.contains("AppInfo.name")
                && restartAppCode.contains("FeatureRuntime.shared.relaunchApp()"),
               "the Command Bar exposes its own localized relaunch action")

        func appStorageProperty(_ key: String, in lines: [String]) -> String? {
            guard let line = lines.first(where: {
                isCodeLine($0) && $0.contains("@AppStorage(\(key))")
            }), let declaration = line.range(of: "private var ") else { return nil }
            return line[declaration.upperBound...].split(whereSeparator: { $0.isWhitespace || $0 == "=" }).first
                .map(String.init)
        }

        let mouseSettingsViewLines = ((try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/SettingsView.swift",
            encoding: .utf8)) ?? "").components(separatedBy: "\n")
        let menuPanelLines = ((try? String(
            contentsOfFile: "Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift",
            encoding: .utf8)) ?? "").components(separatedBy: "\n")
        let shortcutKey = "DefaultsKey.mouseButtonShortcutsEnabled"
        let spacesKey = "DefaultsKey.mouseSpacesGestureEnabled"
        let settingsShortcutProperty = appStorageProperty(shortcutKey, in: mouseSettingsViewLines) ?? ""
        let settingsSpacesProperty = appStorageProperty(spacesKey, in: mouseSettingsViewLines) ?? ""
        let settingsCode = mouseSettingsViewLines.filter(isCodeLine).joined()
            .filter { !$0.isWhitespace }
        expect(!settingsShortcutProperty.isEmpty && !settingsSpacesProperty.isEmpty
                && settingsCode.contains("(\(settingsShortcutProperty)||\(settingsSpacesProperty))"
                    + "&&AppFeature.mouseButtonShortcuts.isAvailable"),
               "the Mouse permission section treats either mouse-button switch as engaged")

        let panelShortcutProperty = appStorageProperty(shortcutKey, in: menuPanelLines) ?? ""
        let panelSpacesProperty = appStorageProperty(spacesKey, in: menuPanelLines) ?? ""
        let menuPanelCode = menuPanelLines.filter(isCodeLine).joined()
            .filter { !$0.isWhitespace }
        expect(!panelShortcutProperty.isEmpty && !panelSpacesProperty.isEmpty
                && menuPanelCode.contains("case.mouseButtonShortcuts:return\(panelShortcutProperty)"
                    + "||\(panelSpacesProperty)"),
               "the panel category count treats either mouse-button switch as engaged")
        // The defect this pins is not the operator, it is three arguments on
        // one row disagreeing: widening `needsAttention` alone leaves the row
        // asking for a grant while `permissionAction` returns nil and the
        // caption stays silent. So assert the three read ONE name, and that
        // the name is defined from both switches -- naming the expression is
        // what makes disagreeing impossible, and pinning the spelling of
        // `a || b` here would go red on a rename that broke nothing.
        let panelButtonRow = menuPanelLines.firstIndex {
            isCodeLine($0) && $0.contains("PanelToggleRow(title: buttonStrings.pageTitle,")
        }.map {
            menuPanelLines[$0...].prefix(24).filter(isCodeLine).joined().filter { !$0.isWhitespace }
        } ?? ""
        let engagedName = panelButtonRow.range(of: "needsAttention:").map {
            String(panelButtonRow[$0.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" })
        } ?? ""
        let engagedDefinition = menuPanelLines.first {
            isCodeLine($0) && !engagedName.isEmpty && $0.contains("let \(engagedName)")
        } ?? ""
        expect(!engagedName.isEmpty
                && panelButtonRow.contains("needsAccessibility:\(engagedName)")
                && panelButtonRow.contains("permissionAction:accessibilityPermissionAction(\(engagedName))")
                && panelButtonRow.contains("accessoryTitle:\(engagedName)?")
                && !panelShortcutProperty.isEmpty && !panelSpacesProperty.isEmpty
                && engagedDefinition.contains(panelShortcutProperty)
                && engagedDefinition.contains(panelSpacesProperty),
               "the panel mouse-button row's caption, attention state, grant button and "
                   + "Manage link all read one engaged flag built from both switches")

        // Per call site, not the last one seen: a second one added later must
        // read the switch too, and a file that lost the call entirely has to
        // fail rather than pass on an empty search.
        var shortcutCallSites = 0
        var callSitesMissingShortcutSwitch: [String] = []
        for (index, line) in spacesServiceLines.enumerated()
        where isCodeLine(line)
            && line.contains("guard let shortcut = MouseButtonShortcutSupport.firesShortcut(") {
            shortcutCallSites += 1
            let window = spacesServiceLines[index...].prefix(7)
            let readsSwitch = window.contains {
                isCodeLine($0) && $0.contains(
                    "isEnabled: UserDefaults.standard.bool(forKey: DefaultsKey.mouseButtonShortcutsEnabled)")
            }
            let passesPressOn = window.contains {
                isCodeLine($0) && $0.contains("else { return Unmanaged.passUnretained(event) }")
            }
            if !readsSwitch || !passesPressOn {
                callSitesMissingShortcutSwitch.append("MouseButtonShortcutService.swift:\(index + 1)")
            }
        }
        expect(shortcutCallSites > 0 && callSitesMissingShortcutSwitch.isEmpty,
               "a tap kept up for the drag alone never fires a mapping the shortcut switch turned "
                   + "off, and that button's click passes through whole: \(callSitesMissingShortcutSwitch)")
        expect(spacesServiceLines.contains {
            isCodeLine($0) && $0.contains(
                "let wanted = (enabled && !mappings.isEmpty) || isCapturing || spacesButton != nil")
        }, "a capture holds the tap up by itself: the press asked for may be the drag's, "
            + "whose switch is not the shortcut switch")

        let mouseSettingsLines = ((try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/MouseButtonSettings.swift",
            encoding: .utf8)) ?? "").components(separatedBy: "\n")
        // Matched as the whole line, indentation included: at Section-child
        // depth no outer `if enabled` can quietly re-gate the list behind the
        // shortcut switch alone.
        var exceptionsListCoversBothSwitches = false
        for (index, line) in mouseSettingsLines.enumerated()
        where line == "            if enabled || spacesEnabled {" {
            var cursor = index + 1
            while cursor < mouseSettingsLines.count, !isCodeLine(mouseSettingsLines[cursor]) {
                cursor += 1
            }
            exceptionsListCoversBothSwitches = cursor < mouseSettingsLines.count
                && mouseSettingsLines[cursor].contains("MouseExceptionsList(scope: .buttonShortcuts)")
        }
        expect(exceptionsListCoversBothSwitches,
               "the exception list the tap consults for the drag stays on screen while either switch is on")
        var spacesSwitchOffDropsBinding = false
        for (index, line) in mouseSettingsLines.enumerated()
        where isCodeLine(line) && line.contains(".onChange(of: spacesEnabled)") {
            let window = mouseSettingsLines[index...].prefix(12)
            let stop = window.firstIndex {
                $0.trimmingCharacters(in: .whitespaces) == "stopSpacesCapture()"
            }
            let clear = window.firstIndex {
                $0.trimmingCharacters(in: .whitespaces) == "spacesButton = 0"
            }
            if let stop, let clear, stop < clear { spacesSwitchOffDropsBinding = true }
        }
        expect(spacesSwitchOffDropsBinding,
               "the drag's own OFF branch drops its binding, so no hidden button ever refuses a shortcut")
        // The drag capture speaks its own strings: the shortcut capture's
        // prompt invites the side wheel the drag refuses, and its refusals
        // point at a list that is off screen with the shortcut switch off.
        var spacesPromptIsOwn = false
        for (index, line) in mouseSettingsLines.enumerated()
        where isCodeLine(line) && line.contains("private var spacesRow: some View {") {
            let window = mouseSettingsLines[index...].prefix(10)
            spacesPromptIsOwn = window.contains {
                isCodeLine($0) && $0.contains("Text(text.spacesCaptureWaiting)")
            } && !window.contains {
                isCodeLine($0) && $0.contains("text.captureWaiting")
            }
        }
        expect(spacesPromptIsOwn,
               "the drag capture's waiting prompt never invites the side wheel the drag refuses")
        var spacesRefusalsAreOwn = false
        for (index, line) in mouseSettingsLines.enumerated()
        where isCodeLine(line) && line.contains("private func handleSpacesCapture") {
            let window = mouseSettingsLines[index...].prefix(16)
            spacesRefusalsAreOwn = window.contains {
                isCodeLine($0) && $0.contains("text.spacesCaptureUnsupported")
            } && window.contains {
                isCodeLine($0) && $0.contains("text.spacesCaptureExists")
            } && !window.contains {
                isCodeLine($0) && ($0.contains("text.captureUnsupported") || $0.contains("text.captureExists"))
            }
        }
        expect(spacesRefusalsAreOwn,
               "the drag capture's refusals recommend only what the drag accepts and point at no list")
        // A button half-way through becoming a shortcut is still spoken for.
        // startSpacesCapture() calls stopCapture(), which clears `capturing`
        // and the feedback but leaves `pendingButton` and its row standing, so
        // without this clause the drag takes a button the shortcut flow is
        // still holding — and finishing that shortcut then drives the binding
        // to nil while the drag's row goes on naming the button.
        var spacesCaptureRefusesPending = false
        for (index, line) in mouseSettingsLines.enumerated()
        where isCodeLine(line) && line.contains("private func handleSpacesCapture") {
            let window = mouseSettingsLines[index...].prefix(16)
            spacesCaptureRefusesPending = window.contains {
                isCodeLine($0) && $0.contains("pendingButton == seen")
            }
        }
        expect(spacesCaptureRefusesPending,
               "the drag capture refuses a button that is mid-way through becoming a shortcut")

        // A synthesized press has to carry the same flags a finger produces,
        // or the system matches it against no shortcut of its own (issue #401).
        expect(GlobalShortcut(keyCode: Int64(kVK_ANSI_N), modifiers: [.command, .shift])
                .syntheticEventFlags == [.maskCommand, .maskShift],
               "an ordinary key goes out with its modifiers and nothing else")
        expect(GlobalShortcut(keyCode: Int64(kVK_RightArrow), modifiers: [.control, .command])
                .syntheticEventFlags == [.maskControl, .maskCommand, .maskSecondaryFn, .maskNumericPad],
               "an arrow goes out as a function key of the numeric pad, the way it arrives")
        expect(GlobalShortcut(keyCode: Int64(kVK_F13), modifiers: [.control, .option, .command])
                .syntheticEventFlags
                == [.maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn],
               "an F key goes out as a function key")
        expect(GlobalShortcut(keyCode: Int64(kVK_PageDown), modifiers: [.command])
                .syntheticEventFlags == [.maskCommand, .maskSecondaryFn]
                && GlobalShortcut(keyCode: Int64(kVK_ForwardDelete), modifiers: [.command])
                .syntheticEventFlags == [.maskCommand, .maskSecondaryFn],
               "the navigation block counts as function keys too")
        expect(GlobalShortcut(keyCode: Int64(kVK_ANSI_Keypad5), modifiers: [.control])
                .syntheticEventFlags == [.maskControl, .maskNumericPad],
               "a keypad key goes out as part of the keypad, without the function flag")
        expect(GlobalShortcut(keyCode: Int64(kVK_Delete), modifiers: [.command])
                .syntheticEventFlags == [.maskCommand]
                && GlobalShortcut(keyCode: Int64(kVK_Escape), modifiers: [.command])
                .syntheticEventFlags == [.maskCommand]
                && GlobalShortcut(keyCode: Int64(kVK_Return), modifiers: [.control, .option])
                .syntheticEventFlags == [.maskControl, .maskAlternate],
               "the keys beside them are ordinary and stay ordinary")
    }
}
