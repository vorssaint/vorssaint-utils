// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import Foundation

enum RadialMenuTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Radial menu (issue #220)

        expect(RadialMenuGeometry.angle(dx: 0, dyUp: 1) == 0
                && abs(RadialMenuGeometry.angle(dx: 1, dyUp: 0) - .pi / 2) < 0.0001
                && abs(RadialMenuGeometry.angle(dx: 0, dyUp: -1) - .pi) < 0.0001
                && abs(RadialMenuGeometry.angle(dx: -1, dyUp: 0) - 3 * .pi / 2) < 0.0001,
               "wheel angles run clockwise from 12 o'clock")
        expect(RadialMenuGeometry.index(forAngle: 0, itemCount: 4) == 0
                && RadialMenuGeometry.index(forAngle: .pi / 2, itemCount: 4) == 1
                && RadialMenuGeometry.index(forAngle: .pi, itemCount: 4) == 2
                && RadialMenuGeometry.index(forAngle: 3 * .pi / 2, itemCount: 4) == 3,
               "each slice claims the arc around its own center")
        expect(RadialMenuGeometry.index(forAngle: 2 * .pi - 0.01, itemCount: 12) == 0
                && RadialMenuGeometry.index(forAngle: 2 * .pi - 0.3, itemCount: 12) == 11,
               "the top slice claims both sides of 12 o'clock and its left neighbor starts past it")
        expect(RadialMenuGeometry.index(forAngle: 1, itemCount: 0) == nil,
               "an empty wheel highlights nothing")
        expect(RadialMenuGeometry.highlightedIndex(dx: 10, dyUp: 0, deadZoneRadius: 40, itemCount: 4) == nil
                && RadialMenuGeometry.highlightedIndex(dx: 50, dyUp: 0, deadZoneRadius: 40, itemCount: 4) == 1,
               "the hub dead zone highlights nothing and past it the pointer picks a slice")
        let topUnit = RadialMenuGeometry.unitPosition(index: 0, itemCount: 6)
        let rightUnit = RadialMenuGeometry.unitPosition(index: 1, itemCount: 4)
        expect(abs(topUnit.dx) < 0.0001 && abs(topUnit.dyUp - 1) < 0.0001
                && abs(rightUnit.dx - 1) < 0.0001 && abs(rightUnit.dyUp) < 0.0001,
               "slice centers land on the unit circle from the top clockwise")

        let starter = RadialMenuSupport.starterItems
        expect(starter.count == 6 && RadialMenuSupport.sanitized(starter) == starter,
               "the starter wheel is already clean")
        expect(starter.allSatisfy { !$0.effectiveSymbolName.isEmpty },
               "every starter slice has a symbol to draw")
        expect(RadialMenuSupport.symbolNames.count >= 80
                && Set(RadialMenuSupport.symbolNames).count == RadialMenuSupport.symbolNames.count
                && RadialMenuSupport.symbolNames.contains("speaker.wave.2.fill")
                && RadialMenuSupport.symbolNames.contains("square.and.arrow.up"),
               "the radial editor offers a broad, duplicate-free built-in symbol catalog")
        expect(RadialMenuSupport.decode(nil) == starter,
               "a fresh install decodes to the starter wheel")
        expect(RadialMenuSupport.decode(RadialMenuSupport.encode([])) == [],
               "an emptied wheel stays empty instead of reseeding")

        let sampleWheel = [
            RadialMenuItem(kind: .app, name: "  Editor  ", payload: "/Applications/Editor.app"),
            RadialMenuItem(kind: .url, payload: "example.com/page"),
            RadialMenuItem(kind: .shortcut, payload: "control+option+command:49"),
            RadialMenuItem(kind: .submenu, name: "More", children: [
                RadialMenuItem(kind: .media, payload: "playPause"),
                RadialMenuItem(kind: .submenu, children: [RadialMenuItem(kind: .media, payload: "nextTrack")]),
            ]),
        ]
        let cleaned = RadialMenuSupport.sanitized(sampleWheel)
        expect(cleaned.count == 4 && cleaned[0].name == "Editor"
                && cleaned[1].payload == "https://example.com/page",
               "sanitizing trims names and completes bare links")
        expect(cleaned[3].children.count == 1 && cleaned[3].children[0].kind == .media,
               "submenus keep their actions but never nest another submenu")
        expect(RadialMenuSupport.decode(RadialMenuSupport.encode(cleaned)) == cleaned,
               "radial menu items round-trip through persistence")
        let fullSubmenu = [RadialMenuItem(kind: .submenu, name: "Pack", children: (0 ..< 5).map {
            RadialMenuItem(kind: .url, payload: "example.com/\($0)")
        })]
        expect(RadialMenuSupport.decode(RadialMenuSupport.encode(fullSubmenu)).first?.children.count == 5,
               "a submenu keeps every action through persistence, not just two")
        expect(RadialMenuSupport.sanitized([
            RadialMenuItem(kind: .app, payload: ""),
            RadialMenuItem(kind: .url, payload: "not a link"),
            RadialMenuItem(kind: .shortcut, payload: "garbage"),
            RadialMenuItem(kind: .tool, payload: "unknownTool"),
            RadialMenuItem(kind: .windowLayout, payload: "unknownLayout"),
            RadialMenuItem(kind: .media, payload: "unknownKey"),
        ]).isEmpty,
               "slices that cannot run are dropped instead of rendering dead")
        expect(RadialMenuSupport.sanitized((0 ..< 20).map {
            RadialMenuItem(kind: .url, payload: "example.com/\($0)")
        }).count == RadialMenuSupport.maxItemsPerWheel,
               "a wheel never holds more than 12 slices")
        let lossyJSON = """
        [{"kind":"media","payload":"playPause"},{"kind":"teleport","payload":"x"}]
        """
        expect(RadialMenuSupport.decode(Data(lossyJSON.utf8)).count == 1,
               "unknown kinds from newer versions drop just that slice")

        expect(RadialMenuSupport.normalizedURL("https://a.example/x") == "https://a.example/x"
                && RadialMenuSupport.normalizedURL("mailto:someone@example.com") == "mailto:someone@example.com"
                && RadialMenuSupport.normalizedURL("   ") == nil
                && RadialMenuSupport.normalizedURL("two words") == nil,
               "link normalization keeps schemes and rejects non-links")
        expect(RadialMenuSupport.normalizedURL("tel:5551234") == "tel:5551234"
                && RadialMenuSupport.normalizedURL("example.com:8080/x") == "https://example.com:8080/x"
                && RadialMenuSupport.normalizedURL("localhost:3000") == "https://localhost:3000",
               "digit-after-colon means a port only when the prefix looks like a host")
        expect(RadialMenuSupport.needsAccessibility([starter[3]]) == false
                && RadialMenuSupport.needsAccessibility(starter)
                && RadialMenuSupport.needsAccessibility([
                    RadialMenuItem(kind: .windowLayout, payload: WindowLayoutAction.leftThird.rawValue),
                ])
                && RadialMenuSupport.needsAccessibility([
                    RadialMenuItem(kind: .submenu, children: [RadialMenuItem(kind: .shortcut, payload: "command:8")]),
                ]),
               "keyboard and window actions need Accessibility, submenus included")
        let nowPlayingItem = RadialMenuItem(kind: .media, payload: RadialMenuMediaKey.nowPlaying.rawValue)
        expect(!RadialMenuSupport.needsAccessibility([nowPlayingItem])
                && RadialMenuSupport.containsNowPlaying([nowPlayingItem])
                && RadialMenuSupport.containsNowPlaying([
                    RadialMenuItem(kind: .submenu, children: [nowPlayingItem]),
                ]),
               "Now Playing is found inside wheels without claiming a key-posting permission")
        let radialLayout = RadialMenuItem(kind: .windowLayout,
                                          payload: WindowLayoutAction.leftThird.rawValue)
        expect(RadialMenuSupport.sanitized([radialLayout]) == [radialLayout]
                && radialLayout.windowLayoutAction == .leftThird
                && radialLayout.effectiveSymbolName == WindowLayoutAction.leftThird.symbolName
                && WindowLayoutAction.allCases.allSatisfy { !$0.symbolName.isEmpty }
                && RadialMenuSupport.usesWindowLayout([
                    RadialMenuItem(kind: .submenu, children: [radialLayout]),
                ]),
               "window-layout slices keep a valid placement and its automatic icon")
        expect(RadialMenuMediaKey.playPause.auxKeyType == 16
                && RadialMenuMediaKey.previousTrack.auxKeyType == 20
                && RadialMenuMediaKey.nextTrack.auxKeyType == 19
                && RadialMenuMediaKey.nowPlaying.auxKeyType == nil,
               "media slices post the aux codes of the physical keys")
        let nowPlayingInfo: [String: Any] = [
            RadialNowPlayingSupport.titleKey: " Midnight City ",
            RadialNowPlayingSupport.artistKey: "M83",
            RadialNowPlayingSupport.albumKey: "Hurry Up, We're Dreaming",
            RadialNowPlayingSupport.artworkDataKey: Data([1, 2, 3]),
            RadialNowPlayingSupport.playbackRateKey: 1.0,
        ]
        expect(RadialNowPlayingSupport.playbackIsActive(remoteIsPlaying: nil, info: nowPlayingInfo)
                && RadialNowPlayingSupport.playbackIsActive(remoteIsPlaying: true, info: [:])
                && !RadialNowPlayingSupport.playbackIsActive(remoteIsPlaying: false, info: nowPlayingInfo),
               "Now Playing accepts the remote state or a positive playback rate")
        let nowPlayingSnapshot = RadialNowPlayingSupport.snapshot(
            info: nowPlayingInfo,
            isPlaying: true,
            appBundleIdentifier: " com.apple.Music ",
            appPID: 42)
        expect(nowPlayingSnapshot?.title == "Midnight City"
                && nowPlayingSnapshot?.artist == "M83"
                && nowPlayingSnapshot?.album == "Hurry Up, We're Dreaming"
                && nowPlayingSnapshot?.artworkData == Data([1, 2, 3])
                && nowPlayingSnapshot?.appBundleIdentifier == "com.apple.Music"
                && nowPlayingSnapshot?.appPID == 42
                && nowPlayingSnapshot?.radialLabel == "Midnight City\nM83",
               "Now Playing metadata is sanitized into the radial label and floating card")
        expect(RadialNowPlayingSupport.snapshot(info: nowPlayingInfo,
                                                isPlaying: false,
                                                appBundleIdentifier: "com.apple.Music",
                                                appPID: 42) == nil
                && RadialNowPlayingSupport.snapshot(info: [:],
                                                    isPlaying: true,
                                                    appBundleIdentifier: nil,
                                                    appPID: 0) == nil,
               "paused or ownerless metadata degrades to Nothing Playing")
        let adapterLine = Data("""
            {"kMRMediaRemoteNowPlayingInfoTitle":"Midnight City","kMRMediaRemoteNowPlayingInfoArtist":"M83",\
            "kMRMediaRemoteNowPlayingInfoPlaybackRate":1,"artworkBase64":"AQID","pid":42,\
            "displayID":"com.apple.Music","isPlaying":true}
            """.utf8)
        let adapterReply = RadialNowPlayingSupport.adapterReply(from: adapterLine)
        expect(adapterReply?.info[RadialNowPlayingSupport.titleKey] as? String == "Midnight City"
                && adapterReply?.info[RadialNowPlayingSupport.artistKey] as? String == "M83"
                && adapterReply?.info[RadialNowPlayingSupport.artworkDataKey] as? Data == Data([1, 2, 3])
                && (adapterReply?.info[RadialNowPlayingSupport.playbackRateKey] as? NSNumber)?.doubleValue == 1
                && adapterReply?.pid == 42
                && adapterReply?.displayID == "com.apple.Music"
                && adapterReply?.isPlaying == true,
               "the Now Playing adapter line is read back into the MediaRemote keys the snapshot builder takes")
        let adapterPaused = RadialNowPlayingSupport.adapterReply(
            from: Data(#"{"kMRMediaRemoteNowPlayingInfoTitle":"Midnight City","isPlaying":false}"#.utf8))
        expect(adapterPaused?.pid == 0 && adapterPaused?.displayID == nil && adapterPaused?.isPlaying == false
                && RadialNowPlayingSupport.snapshot(
                    info: adapterPaused?.info ?? [:],
                    isPlaying: RadialNowPlayingSupport.playbackIsActive(remoteIsPlaying: adapterPaused?.isPlaying,
                                                                       info: adapterPaused?.info ?? [:]),
                    appBundleIdentifier: adapterPaused?.displayID,
                    appPID: adapterPaused?.pid ?? 0) == nil,
               "a paused adapter reply degrades to Nothing Playing through the same path as before")
        expect(RadialNowPlayingSupport.adapterReply(from: Data(#"{"error":"MRMediaRemoteGetNowPlayingInfo unavailable"}"#.utf8)) == nil
                && RadialNowPlayingSupport.adapterReply(from: Data("[1,2]".utf8)) == nil
                && RadialNowPlayingSupport.adapterReply(from: Data("perl: cannot load".utf8)) == nil
                && RadialNowPlayingSupport.adapterReply(from: Data(#"{"artworkBase64":"***"}"#.utf8))?
                    .info[RadialNowPlayingSupport.artworkDataKey] == nil,
               "an adapter error, a non-object, shell noise or bad base64 never become a snapshot")
        let adapterAfterWarning = RadialNowPlayingSupport.adapterReply(from: Data("""
            perl: warning: Setting locale failed.
            perl: warning: Falling back to the standard locale ("C").
            {"kMRMediaRemoteNowPlayingInfoTitle":"Midnight City","pid":42,"isPlaying":true}

            """.utf8))
        expect(adapterAfterWarning?.info[RadialNowPlayingSupport.titleKey] as? String == "Midnight City"
                && adapterAfterWarning?.pid == 42 && adapterAfterWarning?.isPlaying == true,
               "a perl warning on the shared stderr pipe ahead of the adapter's JSON line still parses")
        let nowPlayingBuildScript = (try? String(contentsOfFile: "build.sh", encoding: .utf8)) ?? ""
        expect(nowPlayingBuildScript.contains("Sources/NowPlayingAdapter/NowPlayingAdapter.swift")
                && nowPlayingBuildScript.contains("Resources/now-playing.pl")
                && nowPlayingBuildScript.contains("Contents/Frameworks/$NOW_PLAYING_ADAPTER"),
               "build.sh compiles the Now Playing adapter and stages the library and its perl loader")
        let radialQuickToggle = RadialMenuItem(kind: .quickToggle,
                                               payload: RadialMenuQuickToggle.darkMode.rawValue)
        expect(RadialMenuSupport.sanitized([radialQuickToggle]) == [radialQuickToggle]
                && radialQuickToggle.quickToggle == .darkMode
                && RadialMenuQuickToggle.allCases.allSatisfy { !$0.symbolName.isEmpty },
               "quick-toggle slices keep a valid action and automatic icon")
        expect(RadialMenuSupport.sanitized([
            RadialMenuItem(kind: .quickToggle, payload: "unknownAction"),
        ]).isEmpty,
               "unknown quick-toggle slices cannot leave a dead action on the wheel")
        expect(RadialMenuTool.allCases.allSatisfy { !$0.symbolName.isEmpty }
                && RadialMenuTool.screenshot.feature == .screenshot
                && RadialMenuTool.screenRecorder.feature == .screenRecorder
                && RadialMenuTool.clipboardHistory.feature == .clipboardHistory
                && RadialMenuTool.scratchpad.feature == .scratchpad
                && RadialMenuTool.shelf.feature == .shelf
                && RadialMenuTool.cleaner.feature == .cleaner
                && RadialMenuTool.uninstaller.feature == .uninstaller
                && RadialMenuTool.appUpdates.feature == .appUpdates
                && RadialMenuTool.cleaningMode.feature == .cleaningMode
                && RadialMenuTool.keepAwake.feature == .keepAwake,
               "every wheel tool maps to a real feature and symbol")
        let addedWheelTools: [RadialMenuTool] = [.screenRecorder, .cleaner, .uninstaller, .appUpdates]
        expect(addedWheelTools.allSatisfy {
            $0.isRunnable(isFeatureAvailable: { _ in true }, boolFor: { _ in false })
        }, "recording and maintenance tools are selectable when their hub features are available")
        expect(!RadialMenuTool.shelf.isRunnable(isFeatureAvailable: { _ in true },
                                                boolFor: { _ in false })
                && RadialMenuTool.shelf.isRunnable(isFeatureAvailable: { _ in true },
                                                   boolFor: { $0 == DefaultsKey.shelfEnabled })
                && !RadialMenuTool.shelf.isRunnable(isFeatureAvailable: { _ in false },
                                                    boolFor: { _ in true })
                && RadialMenuTool.cleaningMode.isRunnable(isFeatureAvailable: { _ in true },
                                                          boolFor: { _ in false }),
               "Shelf wheel slices follow the Shelf master switch without affecting on-demand tools")

        // MARK: Radial menu profiles

        let allColors = RadialMenuColor.allCases
        expect(allColors.count == 12
                && Set(allColors.map(\.rawValue)).count == 12
                && allColors.allSatisfy { $0.id == $0.rawValue },
               "twelve distinct radial menu accent colors")
        let enStrings = FeatureStrings.radialMenu(.enUS)
        expect(RadialMenuColor.accent.title(enStrings) == "Accent"
                && RadialMenuColor.blue.title(enStrings) == "Blue"
                && RadialMenuColor.purple.title(enStrings) == "Purple"
                && RadialMenuColor.pink.title(enStrings) == "Pink"
                && RadialMenuColor.red.title(enStrings) == "Red"
                && RadialMenuColor.orange.title(enStrings) == "Orange"
                && RadialMenuColor.yellow.title(enStrings) == "Yellow"
                && RadialMenuColor.green.title(enStrings) == "Green"
                && RadialMenuColor.mint.title(enStrings) == "Mint"
                && RadialMenuColor.cyan.title(enStrings) == "Cyan"
                && RadialMenuColor.indigo.title(enStrings) == "Indigo"
                && RadialMenuColor.graphite.title(enStrings) == "Graphite",
               "radial menu color titles localize properly")

        let allPresets = RadialMenuProfilePreset.allCases
        expect(allPresets.count == 6
                && Set(allPresets.map(\.rawValue)).count == 6
                && allPresets.allSatisfy { $0.id == $0.rawValue },
               "six distinct radial profile presets")
        expect(RadialMenuProfilePreset.general.makeItems().count == 6
                && RadialMenuProfilePreset.media.makeItems().count == 4
                && RadialMenuProfilePreset.tools.makeItems().count == 6
                && RadialMenuProfilePreset.windowLayout.makeItems().count == 5
                && RadialMenuProfilePreset.quickToggles.makeItems().count == 5
                && RadialMenuProfilePreset.blank.makeItems().isEmpty,
               "presets generate expected initial item layouts")

        let customProfile = RadialMenuProfile(
            id: UUID(),
            name: " Media Wheel ",
            color: .purple,
            shortcut: "control+command:49",
            mouseButton: RadialMenuMouseTrigger.back.rawValue,
            items: RadialMenuProfilePreset.media.makeItems()
        )
        expect(customProfile.displayName(enStrings) == " Media Wheel ",
               "profile custom name is displayed")
        let blankNamedProfile = RadialMenuProfile(name: "", color: .accent)
        expect(blankNamedProfile.displayName(enStrings) == enStrings.presetGeneral,
               "blank profile name falls back to General preset title")

        let encodedProfilesData = RadialMenuSupport.encodeProfiles([customProfile])
        let decodedProfiles = RadialMenuSupport.decodeProfiles(encodedProfilesData)
        expect(decodedProfiles.count == 1
                && decodedProfiles[0].id == customProfile.id
                && decodedProfiles[0].name == "Media Wheel"
                && decodedProfiles[0].color == .purple
                && decodedProfiles[0].shortcut == "control+command:49"
                && decodedProfiles[0].mouseButton == RadialMenuMouseTrigger.back.rawValue
                && decodedProfiles[0].items.count == 4,
               "profile encodes and decodes accurately with trimmed name")

        let renamedPresetProfile = RadialMenuProfilePreset.media.createProfile(name: "Renamed")
        let presetRoundTrip = RadialMenuSupport.decodeProfiles(
            RadialMenuSupport.encodeProfiles([renamedPresetProfile]))
        expect(renamedPresetProfile.preset == RadialMenuProfilePreset.media.rawValue
                && presetRoundTrip.first?.preset == RadialMenuProfilePreset.media.rawValue,
               "a wheel keeps the starter set it came from, whatever it is renamed to")
        let profileWithoutPreset = Data("""
        [{"id":"\(UUID().uuidString)","name":"Old Wheel","color":"accent",\
        "shortcut":"","mouseButton":"off","items":[]}]
        """.utf8)
        expect(RadialMenuSupport.decodeProfiles(profileWithoutPreset).first?.preset == nil,
               "a wheel saved before the starter set was recorded decodes without one")

        let dupID = UUID()
        let dups = [
            RadialMenuProfile(id: dupID, name: "First"),
            RadialMenuProfile(id: dupID, name: "Duplicate"),
            RadialMenuProfile(id: UUID(), name: "  Trim Me  ", shortcut: "invalidShortcutFormat"),
        ]
        let sanitizedDups = RadialMenuSupport.sanitizedProfiles(dups)
        expect(sanitizedDups.count == 2
                && sanitizedDups[0].name == "First"
                && sanitizedDups[1].name == "Trim Me"
                && sanitizedDups[1].shortcut.isEmpty,
               "sanitized profiles deduplicate IDs, trim names, and drop invalid shortcuts")

        let emptySanitized = RadialMenuSupport.sanitizedProfiles([])
        expect(emptySanitized.count == 1
                && emptySanitized[0].color == .accent
                && !emptySanitized[0].shortcut.isEmpty
                && emptySanitized[0].items.count == 6,
               "sanitizing empty profile list provides one default starter profile")

        let appOnlyProfile = RadialMenuProfile(
            mouseButton: RadialMenuMouseTrigger.off.rawValue,
            items: [RadialMenuItem(kind: .app, payload: "/Applications/Safari.app")]
        )
        expect(!RadialMenuSupport.needsAccessibility([appOnlyProfile]),
               "app-only profile without mouse button does not need Accessibility")
        let mouseProfile = RadialMenuProfile(
            mouseButton: RadialMenuMouseTrigger.forward.rawValue,
            items: [RadialMenuItem(kind: .app, payload: "/Applications/Safari.app")]
        )
        expect(RadialMenuSupport.needsAccessibility([mouseProfile]),
               "profile with mouse trigger needs Accessibility")
        let shortcutProfile = RadialMenuProfile(
            mouseButton: RadialMenuMouseTrigger.off.rawValue,
            items: [RadialMenuItem(kind: .shortcut, payload: "command:8")]
        )
        expect(RadialMenuSupport.needsAccessibility([shortcutProfile]),
               "profile with keyboard shortcut slice needs Accessibility")

        let profileTestDefaults = UserDefaults(suiteName: "com.vorssaint.tests.radialProfiles")!
        profileTestDefaults.removePersistentDomain(forName: "com.vorssaint.tests.radialProfiles")
        profileTestDefaults.set(true, forKey: AppFeature.radialMenu.availabilityKey)
        profileTestDefaults.set(true, forKey: DefaultsKey.radialMenuEnabled)

        let profileA = RadialMenuProfile(
            name: "Work",
            mouseButton: RadialMenuMouseTrigger.back.rawValue
        )
        let profileB = RadialMenuProfile(
            name: "Fun",
            mouseButton: RadialMenuMouseTrigger.button(4).rawValue
        )
        profileTestDefaults.set(RadialMenuSupport.encodeProfiles([profileA, profileB]), forKey: DefaultsKey.radialMenuProfiles)

        expect(RadialMenuSupport.claimsMouseButton(MouseButtonShortcutSupport.backButtonNumber, defaults: profileTestDefaults),
               "claims button 3 from profile A")
        expect(RadialMenuSupport.claimsMouseButton(4, defaults: profileTestDefaults),
               "claims button 4 from profile B")
        expect(!RadialMenuSupport.claimsMouseButton(5, defaults: profileTestDefaults),
               "does not claim unclaimed button 5")

        profileTestDefaults.set(false, forKey: DefaultsKey.radialMenuEnabled)
        expect(!RadialMenuSupport.claimsMouseButton(MouseButtonShortcutSupport.backButtonNumber, defaults: profileTestDefaults),
               "disabled radial menu never claims mouse buttons")
        profileTestDefaults.removePersistentDomain(forName: "com.vorssaint.tests.radialProfiles")

        let testImage = NSImage(size: NSSize(width: 16, height: 16))
        testImage.lockFocus()
        NSColor.red.set()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        testImage.unlockFocus()
        let samplePNG = RadialMenuFaviconFetcher.scaledPNGData(from: testImage, targetSize: 32)
        expect(samplePNG != nil && (samplePNG?.count ?? 0) > 0, "scaledPNGData produces valid PNG")
        expect(samplePNG.map { RadialMenuFaviconFetcher.sourceDimensionsAreSafe($0) } == true
               && !RadialMenuFaviconFetcher.sourceDimensionsAreSafe(Data("not an image".utf8)),
               "favicon decoding accepts bounded images and rejects invalid payloads")

        // The event taps read the cheap answer on every side-button event, so
        // it has to agree with the full decode, custom icons and all.
        let iconProfile = RadialMenuProfile(
            name: "Icons",
            mouseButton: RadialMenuMouseTrigger.button(6).rawValue,
            items: [RadialMenuItem(kind: .app,
                                   payload: "/Applications/Safari.app",
                                   customIconData: samplePNG)]
        )
        let iconProfilesData = RadialMenuSupport.encodeProfiles([iconProfile, profileA])
        let fullyDecodedButtons = RadialMenuSupport.decodeProfiles(iconProfilesData)
            .compactMap { RadialMenuMouseTrigger.sanitized($0.mouseButton).buttonNumber }
        expect(fullyDecodedButtons == [6, MouseButtonShortcutSupport.backButtonNumber]
                && RadialMenuSupport.claimedMouseButtons(iconProfilesData) == fullyDecodedButtons,
               "claimed mouse buttons read without the items match the full profile decode")

        let legacyButtonDefaults = UserDefaults(suiteName: "com.vorssaint.tests.radialLegacyButton")!
        legacyButtonDefaults.removePersistentDomain(forName: "com.vorssaint.tests.radialLegacyButton")
        legacyButtonDefaults.set(RadialMenuMouseTrigger.forward.rawValue,
                                 forKey: DefaultsKey.radialMenuMouseButton)
        expect(RadialMenuSupport.claimedMouseButtons(nil, defaults: legacyButtonDefaults)
                == [MouseButtonShortcutSupport.forwardButtonNumber]
                && RadialMenuSupport.claimedMouseButtons(Data("not profiles".utf8),
                                                         defaults: legacyButtonDefaults)
                == [MouseButtonShortcutSupport.forwardButtonNumber],
               "claimed mouse buttons fall back to the legacy button key like the full decode")
        legacyButtonDefaults.removePersistentDomain(forName: "com.vorssaint.tests.radialLegacyButton")

        var reorderItems = [
            RadialMenuItem(kind: .app, name: "A"),
            RadialMenuItem(kind: .app, name: "B"),
            RadialMenuItem(kind: .app, name: "C"),
        ]
        let itemToMove = reorderItems[0]
        let targetItem = reorderItems[2]
        if let from = reorderItems.firstIndex(where: { $0.id == itemToMove.id }),
           let to = reorderItems.firstIndex(where: { $0.id == targetItem.id }) {
            reorderItems.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        expect(reorderItems.map(\.name) == ["B", "C", "A"],
               "radial items can be reordered correctly by drag target")

        var swapItems = [
            RadialMenuItem(kind: .app, name: "A"),
            RadialMenuItem(kind: .app, name: "B"),
            RadialMenuItem(kind: .app, name: "C"),
            RadialMenuItem(kind: .app, name: "D"),
        ]
        let firstToSwap = swapItems[0]
        let secondToSwap = swapItems[2]
        if let from = swapItems.firstIndex(where: { $0.id == firstToSwap.id }),
           let to = swapItems.firstIndex(where: { $0.id == secondToSwap.id }) {
            swapItems.swapAt(from, to)
        }
        expect(swapItems.map(\.name) == ["C", "B", "A", "D"],
               "radial items can be swapped directly without displacing intermediate items")

        // The cheap read and the full decode can disagree on a corrupt blob,
        // so only one of them may decide whether the click is passed on: once
        // the button is claimed, nothing past that point hands an event back,
        // or the down and the up split.
        let radialServiceCode = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/RadialMenu/RadialMenuService.swift",
            encoding: .utf8)) ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let radialClaimedClick = radialServiceCode
            .components(separatedBy: "if type == .otherMouseDown {")
            .dropFirst().first?
            .components(separatedBy: "private func hotkeyPressed").first ?? ""
        expect(!radialClaimedClick.isEmpty && !radialClaimedClick.contains("passUnretained"),
               "a claimed side button keeps both halves of its click whatever the full decode says")

        // The tap is the only thing that ends a button-held wheel, so handing
        // it back on resign has to end the session too; a wheel left open
        // across the switch would come back in hold phase with no release
        // coming for it.
        let radialSessionResign = radialServiceCode
            .components(separatedBy: "SessionActivity.shared.onChange")
            .dropFirst().first?
            .components(separatedBy: "var sessionActive").first ?? ""
        expect(radialSessionResign.contains("endSession()"),
               "the radial menu ends its session when the mouse tap is handed back on resign")
        expect(RadialMenuFaviconFetcher.faviconURL(
            for: "https://example.com:8443/path?q=1#part")?.absoluteString
                == "https://example.com:8443/favicon.ico"
               && RadialMenuFaviconFetcher.faviconURL(for: "not a url") == nil,
               "favicon download stays on the website origin and preserves its port")

        let itemWithFavicon = RadialMenuItem(kind: .url, name: "Site", payload: "https://example.com", customIconData: samplePNG)
        let encodedFaviconData = RadialMenuSupport.encode([itemWithFavicon])
        let decodedFaviconItem = RadialMenuSupport.decode(encodedFaviconData).first
        expect(decodedFaviconItem?.customIconData == samplePNG,
               "customIconData survives encode and decode")

        let oversizedData = Data(repeating: 0xFF, count: 70_000)
        let itemWithOversizedIcon = RadialMenuItem(kind: .url, name: "Site", payload: "https://example.com", customIconData: oversizedData)
        let sanitizedOversized = RadialMenuSupport.sanitized([itemWithOversizedIcon]).first
        expect(sanitizedOversized?.customIconData == nil,
               "sanitized drops oversized customIconData")

        let invalidImageData = Data([0x00, 0x01, 0x02, 0x03])
        let itemWithInvalidIcon = RadialMenuItem(kind: .url, name: "Site", payload: "https://example.com", customIconData: invalidImageData)
        let sanitizedInvalid = RadialMenuSupport.sanitized([itemWithInvalidIcon]).first
        expect(sanitizedInvalid?.customIconData == nil,
               "sanitized drops corrupted customIconData that cannot form an NSImage")
    }

    static func runActivation(expect: (Bool, String) -> Void) {
        expect(Defaults.registeredDefaults[DefaultsKey.radialMenuEnabled] as? Bool == false,
               "the radial menu ships off by default")
        expect(Defaults.registeredDefaults[DefaultsKey.radialMenuShortcut] as? String
                == "control+option+command:49",
               "the default radial menu shortcut is control option command space")
        expect(Defaults.registeredDefaults[DefaultsKey.radialMenuAtPointer] as? Bool == true,
               "the radial menu opens at the pointer by default")
        expect(Defaults.registeredDefaults[DefaultsKey.radialMenuMouseButton] as? String == "off",
               "the side button trigger ships off")
        expect(Defaults.registeredDefaults[DefaultsKey.radialMenuActivationMode] as? String == "pressOrHold",
               "the radial menu preserves its adaptive gesture by default")
        expect(RadialMenuActivationMode.sanitized("press") == .press
                && RadialMenuActivationMode.sanitized("hold") == .hold
                && RadialMenuActivationMode.sanitized(nil) == .pressOrHold
                && RadialMenuActivationMode.sanitized("future-mode") == .pressOrHold,
               "the radial activation mode decodes known values and safely falls back")
        expect(!RadialMenuActivationMode.press.startsHeld(
                    requestedHold: true, hasHeldButton: false, shortcutHasModifiers: true)
                && RadialMenuActivationMode.hold.startsHeld(
                    requestedHold: true, hasHeldButton: false, shortcutHasModifiers: true)
                && RadialMenuActivationMode.pressOrHold.startsHeld(
                    requestedHold: false, hasHeldButton: true, shortcutHasModifiers: false)
                && !RadialMenuActivationMode.hold.startsHeld(
                    requestedHold: false, hasHeldButton: false, shortcutHasModifiers: true),
               "only hold-capable summons enter the held phase")
        expect(RadialMenuActivationMode.pressOrHold.releaseAction(hasSelection: false) == .stayOpen
                && RadialMenuActivationMode.hold.releaseAction(hasSelection: false) == .dismiss
                && RadialMenuActivationMode.hold.releaseAction(hasSelection: true) == .select,
               "release keeps the adaptive wheel, dismisses an empty strict hold, or selects its target")
        expect(RadialMenuSupport.shortcutIsStillHeld(modifiersHeld: true, superKeyHeld: false)
                && RadialMenuSupport.shortcutIsStillHeld(modifiersHeld: false, superKeyHeld: true)
                && !RadialMenuSupport.shortcutIsStillHeld(modifiersHeld: false, superKeyHeld: false),
               "the radial hold follows physical modifiers or the virtual super key")
        expect(RadialMenuMouseTrigger.sanitized("back") == .back
                && RadialMenuMouseTrigger.sanitized("forward").buttonNumber == 4
                && RadialMenuMouseTrigger.back.buttonNumber == 3
                && MouseButtonShortcutSupport.buttonRange.allSatisfy {
                    RadialMenuMouseTrigger.sanitized(
                        RadialMenuMouseTrigger.button($0).rawValue).buttonNumber == $0
                }
                && RadialMenuMouseTrigger.sanitized(nil) == .off
                && RadialMenuMouseTrigger.sanitized("teleport") == .off
                && RadialMenuMouseTrigger.sanitized("button:2") == .off
                && RadialMenuMouseTrigger.sanitized("button:32") == .off
                && RadialMenuMouseTrigger.off.buttonNumber == nil,
               "the mouse trigger round-trips every extra button and falls back to off")
        expect(RadialMenuMouseTrigger.back.buttonNumber == MouseNavigationSupport.backButtonNumber
                && RadialMenuMouseTrigger.forward.buttonNumber == MouseNavigationSupport.forwardButtonNumber,
               "the wheel and mouse navigation agree on which button is which")
        expect(!RadialMenuSupport.claimsMouseButton(3) && !RadialMenuSupport.claimsMouseButton(4),
               "with the feature off no side button is claimed away from navigation")
        expect(Defaults.registeredDefaults[DefaultsKey.panelControlRadialMenu] as? Bool == true,
               "the radial menu panel row ships visible like its siblings")
        expect(Defaults.registeredDefaults[DefaultsKey.radialMenuItems] == nil,
               "the items blob has no registered default so a fresh install detects the starter wheel")
        expect(GlobalShortcutRole.radialMenu.requiredEnableKeys == [DefaultsKey.radialMenuEnabled]
                && GlobalShortcutRole.radialMenu.feature == .radialMenu,
               "the radial menu shortcut role gates on the feature toggle")
    }
}
