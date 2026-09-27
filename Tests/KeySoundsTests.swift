// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum KeySoundsTests {
    static func run(_ suite: TestSuite) {
        keyGroups(suite)
        manifestFallbacks(suite)
        velocity(suite)
        preferences(suite)
        strings(suite)
        bundledPacks(suite)
    }

    private static func keyGroups(_ suite: TestSuite) {
        let cases: [(Int64, KeySoundGroup, String)] = [
            (49, .space, "space"), (36, .enter, "return"), (76, .enter, "keypad enter"),
            (51, .delete, "delete"), (117, .delete, "forward delete"), (123, .arrow, "left arrow"),
            (126, .arrow, "up arrow"), (55, .modifier, "command"), (57, .modifier, "caps lock"),
            (122, .function, "F1"), (53, .function, "escape"), (115, .function, "home"),
            (48, .other, "tab"), (0, .alpha, "A"), (29, .alpha, "0"),
        ]
        for (code, group, label) in cases {
            suite.expect(KeySoundGroup.group(forKeyCode: code) == group,
                         "\(label) plays the \(group.rawValue) sound")
        }
        suite.expect(KeySoundGroup.isModifier(keyCode: 56) && !KeySoundGroup.isModifier(keyCode: 49),
                     "only modifier key codes count as modifiers")
    }

    private static func manifestFallbacks(_ suite: TestSuite) {
        let json = """
        {"name":"T","sampleRate":48000,
         "groups":{"alpha":{"medium":["m.wav"],"hard":["h.wav"]},"other":{"soft":["o.wav"]}},
         "release":{"alpha":["r.wav"]}}
        """
        guard let manifest = try? JSONDecoder().decode(KeySoundPackManifest.self, from: Data(json.utf8)) else {
            suite.expect(false, "a pack.json manifest decodes")
            return
        }
        suite.expect(manifest.pressSamples(.alpha, .hard) == ["h.wav"], "an exact strength is used")
        suite.expect(manifest.pressSamples(.alpha, .slam) == ["h.wav"], "a missing strength uses the nearest one")
        suite.expect(manifest.pressSamples(.alpha, .soft) == ["m.wav"], "soft falls back upward when nothing is softer")
        suite.expect(manifest.pressSamples(.space, .soft) == ["o.wav"], "a missing key group borrows the other group")
        suite.expect(manifest.releaseSamples(.enter) == ["r.wav"], "a missing release group borrows alpha")
        let noRelease = try? JSONDecoder().decode(
            KeySoundPackManifest.self, from: Data(#"{"name":"N","groups":{"alpha":{"medium":["a.wav"]}}}"#.utf8))
        suite.expect(noRelease?.releaseSamples(.alpha).isEmpty == true, "packs without release sounds stay silent on key up")
    }

    private static func velocity(_ suite: TestSuite) {
        var classifier = KeyVelocityClassifier()
        for _ in 0..<60 { _ = classifier.classify(peak: 0.02, sensitivity: 1) }
        suite.expect(classifier.classify(peak: 0.0005, sensitivity: 1) == .medium,
                     "no measurable jolt (an external keyboard) plays the neutral sound")
        suite.expect(classifier.classify(peak: 0.006, sensitivity: 1) == .soft, "a light tap is soft")
        suite.expect(classifier.classify(peak: 0.02, sensitivity: 1) == .medium, "a typical hit is medium")
        suite.expect(classifier.classify(peak: 0.04, sensitivity: 1) == .hard, "twice the typical hit is hard")
        suite.expect(classifier.classify(peak: 0.08, sensitivity: 1) == .slam, "a much harder hit is a slam")
        suite.expect(classifier.classify(peak: 0.012, sensitivity: 2.5) > .soft,
                     "higher sensitivity promotes lighter hits")

        // A heavy typist and a light one both get the full range after learning.
        var light = KeyVelocityClassifier()
        for _ in 0..<60 { _ = light.classify(peak: 0.005, sensitivity: 1) }
        suite.expect(light.classify(peak: 0.005, sensitivity: 1) == .medium,
                     "the classifier adapts to a light typist's usual hit")
    }

    private static func preferences(_ suite: TestSuite) {
        let registered = Defaults.registeredDefaults
        for key in [DefaultsKey.keySoundsEnabled, DefaultsKey.keySoundsPack, DefaultsKey.keySoundsVolume,
                    DefaultsKey.keySoundsVelocityEnabled, DefaultsKey.keySoundsSensitivity,
                    DefaultsKey.keySoundsReleaseEnabled, DefaultsKey.keySoundsMuteModifiers,
                    DefaultsKey.keySoundsBuiltInSpeakersOnly, DefaultsKey.keySoundsShortcutEnabled,
                    DefaultsKey.keySoundsShortcut, DefaultsKey.panelControlKeySounds] {
            suite.expect(registered[key] != nil, "\(key) is registered, so settings backup includes it")
        }
        suite.expect(registered[DefaultsKey.keySoundsEnabled] as? Bool == false, "sounds start off")
        suite.expect(Defaults.sanitizedKeySoundsVolume(4) == 1 && Defaults.sanitizedKeySoundsVolume(-1) == 0.05,
                     "volume is clamped")
        suite.expect(Defaults.sanitizedKeySoundsVolume(.nan) == Defaults.defaultKeySoundsVolume,
                     "an invalid stored volume falls back to the default")
        suite.expect(Defaults.sanitizedKeySoundsSensitivity(9) == 2.5, "sensitivity is clamped")
        suite.expect(GlobalShortcutRole.keySounds.storageKey == DefaultsKey.keySoundsShortcut
                     && GlobalShortcutRole.keySounds.feature == .keySounds,
                     "the toggle shortcut takes part in shortcut conflict checks")
        suite.expect(GlobalShortcutRole.allCases.filter { $0 != .keySounds }.allSatisfy {
            $0.defaultShortcut != GlobalShortcut.keySoundsDefault
        }, "the default toggle shortcut does not collide with another default")
    }

    private static func strings(_ suite: TestSuite) {
        let english = FeatureStrings.keySounds(.enUS)
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.keySounds(language)
            let empty = Mirror(reflecting: strings).children.filter { ($0.value as? String)?.isEmpty ?? false }
            suite.expect(empty.isEmpty, "\(language.rawValue) key sound strings are complete")
            if language != .enUS {
                suite.expect(strings.enable != english.enable, "\(language.rawValue) key sound strings are translated")
            }
        }
    }

    /// Every bundled pack parses, and each sample it names exists.
    private static func bundledPacks(_ suite: TestSuite) {
        let root = URL(fileURLWithPath: "Resources/KeySoundPacks")
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let packs = KeySoundPackCatalog.available(in: [root])
        suite.expect(packs.contains { $0.id == Defaults.defaultKeySoundsPack }, "the default pack ships")
        for pack in packs {
            guard let manifest = KeySoundPackCatalog.load(pack.url) else { continue }
            let paths = KeySoundGroup.allCases.flatMap { group in
                KeySoundStrength.allCases.flatMap { manifest.pressSamples(group, $0) }
                    + manifest.releaseSamples(group)
            }
            let missing = Set(paths).filter {
                !FileManager.default.fileExists(atPath: pack.url.appendingPathComponent($0).path)
            }
            suite.expect(missing.isEmpty, "\(pack.id) has every sample it lists")
        }
    }
}
