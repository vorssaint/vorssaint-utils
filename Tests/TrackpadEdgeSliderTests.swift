// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TrackpadEdgeSliderTests {
    static func run(_ suite: TestSuite) {
        typealias Support = TrackpadEdgeSliderSupport
        typealias Engine = TrackpadEdgeSliderEngine
        typealias Config = TrackpadEdgeSliderConfig
        let stepTravel = Support.stepTravel
        let defaultZone = Config().zone

        // MARK: Edge zones

        suite.expect(Support.edge(atX: 0.02, zone: defaultZone) == .left
                && Support.edge(atX: defaultZone, zone: defaultZone) == .left
                && Support.edge(atX: 0.98, zone: defaultZone) == .right
                && Support.edge(atX: 1 - defaultZone, zone: defaultZone) == .right,
               "the outer slice of the pad on each side is an edge")
        suite.expect(Support.edge(atX: 0.5, zone: defaultZone) == nil
                && Support.edge(atX: defaultZone + 0.01, zone: defaultZone) == nil
                && Support.edge(atX: 1 - defaultZone - 0.01, zone: defaultZone) == nil,
               "the rest of the pad is not an edge")
        suite.expect(Support.edge(atX: 0.2, zone: 0.25) == .left
                && Support.edge(atX: 0.8, zone: 0.25) == .right
                && Support.edge(atX: 0.2, zone: defaultZone) == nil,
               "a wider edge reaches further into the pad")

        // MARK: Engine helpers

        /// An engine whose pad was empty, so a finger landing now can start a slide.
        func readyEngine(_ config: Config = Config()) -> Engine {
            var engine = Engine()
            engine.config = config
            _ = engine.update(fingerCount: 0, position: nil, typedRecently: false)
            return engine
        }
        func touch(_ engine: inout Engine, x: Float, y: Float,
                   typedRecently: Bool = false) -> TrackpadEdgeSliderOutput {
            engine.update(fingerCount: 1, position: (x, y), typedRecently: typedRecently)
        }
        /// Lands on an edge and moves far enough up to commit a slide.
        func committedSlide(x: Float = 0.95, config: Config = Config()) -> (Engine, y: Float) {
            var engine = readyEngine(config)
            _ = touch(&engine, x: x, y: 0.40)
            let y = 0.40 + Support.commitTravel + 0.001
            _ = touch(&engine, x: x, y: y)
            return (engine, y)
        }

        // MARK: Starting a slide

        var engine = readyEngine()
        let landing = touch(&engine, x: 0.95, y: 0.50)
        suite.expect(landing.target == .volume && landing.steps == 0 && landing.holdsPointer,
               "a finger landing on the right edge holds the pointer and changes nothing yet")
        engine = readyEngine()
        suite.expect(touch(&engine, x: 0.04, y: 0.50).target == .brightness,
               "the left edge adjusts brightness by default")

        var swapped = Config()
        swapped.left = .volume
        swapped.right = .brightness
        engine = readyEngine(swapped)
        suite.expect(touch(&engine, x: 0.04, y: 0.50).target == .volume,
               "an edge can be given volume")
        engine = readyEngine(swapped)
        suite.expect(touch(&engine, x: 0.95, y: 0.50).target == .brightness,
               "an edge can be given brightness")

        var leftOff = Config()
        leftOff.left = .off
        engine = readyEngine(leftOff)
        suite.expect(touch(&engine, x: 0.04, y: 0.50) == .idle
                && touch(&engine, x: 0.04, y: 0.70) == .idle,
               "an edge set to Off leaves the touch alone and keeps the pointer free")
        engine = readyEngine(leftOff)
        suite.expect(touch(&engine, x: 0.95, y: 0.50).target == .volume,
               "the other edge keeps working when one is off")

        engine = readyEngine()
        _ = touch(&engine, x: 0.95, y: 0.50)
        let belowCommit = touch(&engine, x: 0.95, y: 0.50 + Support.commitTravel / 2)
        suite.expect(belowCommit.steps == 0 && belowCommit.holdsPointer,
               "a small movement keeps waiting instead of changing a level")

        // MARK: Steps

        var (slide, lastY) = committedSlide()
        let up = touch(&slide, x: 0.95, y: lastY + stepTravel * 3 + stepTravel * 0.4)
        suite.expect(up.steps == 3 && up.target == .volume && up.holdsPointer,
               "sliding up sends one raising step per step of travel")
        lastY += stepTravel * 3 + stepTravel * 0.4
        // 0.4 of a step was left over, so 2.6 steps down is 2.2 and sends two.
        let down = touch(&slide, x: 0.95, y: lastY - stepTravel * 2.6)
        suite.expect(down.steps == -2 && down.target == .volume,
               "sliding down sends lowering steps, counting the travel left over from before")

        // Movement below one step is never lost: it adds up across frames.
        (slide, lastY) = committedSlide()
        var accumulated = 0
        for _ in 0..<10 {
            lastY += stepTravel / 4
            accumulated += touch(&slide, x: 0.95, y: lastY).steps
        }
        suite.expect(accumulated == 2,
               "slow movement adds up to whole steps instead of being dropped")

        // The commit point is where counting starts: the dead zone never jumps a level.
        (slide, lastY) = committedSlide()
        suite.expect(touch(&slide, x: 0.95, y: lastY).steps == 0,
               "the first frame after committing has not moved a level")

        // A late frame cannot turn into a burst.
        (slide, lastY) = committedSlide()
        suite.expect(touch(&slide, x: 0.95, y: lastY + 0.5).steps == Support.maxStepsPerFrame,
               "one frame changes at most \(Support.maxStepsPerFrame) steps")

        // The finger may drift inward once the slide has started.
        (slide, lastY) = committedSlide()
        let drifting = touch(&slide, x: 0.55, y: lastY + stepTravel * 2.2)
        suite.expect(drifting.steps == 2 && drifting.holdsPointer,
               "a committed slide survives the finger drifting off the edge")

        // MARK: Sensitivity, direction and width

        var fast = Config()
        fast.sensitivity = 2
        (slide, lastY) = committedSlide(config: fast)
        suite.expect(touch(&slide, x: 0.95, y: lastY + stepTravel * 2.2).steps == 4,
               "double sensitivity covers the same range in half the travel")

        var slow = Config()
        slow.sensitivity = 0.5
        (slide, lastY) = committedSlide(config: slow)
        suite.expect(touch(&slide, x: 0.95, y: lastY + stepTravel * 2.2).steps == 1,
               "half sensitivity needs twice the travel for each step")

        var reversed = Config()
        reversed.reversed = true
        (slide, lastY) = committedSlide(config: reversed)
        let reversedUp = touch(&slide, x: 0.95, y: lastY + stepTravel * 3.2)
        suite.expect(reversedUp.steps == -3 && reversedUp.target == .volume,
               "a reversed edge lowers the level when sliding up")
        // 0.2 of a step was left over, so 2.6 steps down is 2.4 and sends two.
        let reversedDown = touch(&slide, x: 0.95, y: lastY + stepTravel * 3.2 - stepTravel * 2.6)
        suite.expect(reversedDown.steps == 2,
               "a reversed edge raises the level when sliding down")

        var wide = Config()
        wide.zone = 0.25
        engine = readyEngine(wide)
        suite.expect(touch(&engine, x: 0.80, y: 0.50).holdsPointer,
               "a touch in a widened edge starts a slide")
        engine = readyEngine()
        suite.expect(touch(&engine, x: 0.80, y: 0.50) == .idle,
               "the same touch is ordinary with the default width")
        engine = readyEngine(wide)
        _ = touch(&engine, x: 0.80, y: 0.50)
        suite.expect(touch(&engine, x: 1 - wide.zone - Support.zoneExitMargin + 0.005, y: 0.51).holdsPointer
                && touch(&engine, x: 1 - wide.zone - Support.zoneExitMargin - 0.02, y: 0.52) == .idle,
               "how far a touch may drift before it counts as pointing follows the edge width")

        // MARK: Haptics

        (slide, lastY) = committedSlide()
        var ticks = 0
        for _ in 0..<5 {
            lastY += stepTravel * 1.2
            ticks += touch(&slide, x: 0.95, y: lastY).haptic ? 1 : 0
        }
        // 5 frames add up to 6 steps, and a system key step is 4: one tick, not two.
        suite.expect(ticks == 1,
               "a light tick comes once for every step of the system keys")
        (slide, lastY) = committedSlide()
        suite.expect(touch(&slide, x: 0.95, y: lastY + stepTravel * 3.2).haptic == false
                && touch(&slide, x: 0.95, y: lastY + stepTravel * 5.4).haptic,
               "steps below a notch add up across frames before they tick")
        (slide, lastY) = committedSlide()
        suite.expect(touch(&slide, x: 0.95, y: lastY + stepTravel * 8.2).haptic,
               "a fast slide still ticks")

        var quiet = Config()
        quiet.haptics = false
        (slide, lastY) = committedSlide(config: quiet)
        suite.expect(touch(&slide, x: 0.95, y: lastY + stepTravel * 8.2).haptic == false,
               "turning haptics off silences the tick")

        // MARK: Touches that must stay ordinary

        engine = readyEngine()
        suite.expect(touch(&engine, x: 0.50, y: 0.50) == .idle
                && touch(&engine, x: 0.95, y: 0.50) == .idle,
               "a touch that starts mid-pad never becomes a slide, even after it reaches the edge")
        suite.expect(engine.update(fingerCount: 0, position: nil, typedRecently: false) == .idle
                && touch(&engine, x: 0.95, y: 0.50).holdsPointer,
               "the next touch on an empty pad can start a slide again")

        engine = readyEngine()
        _ = touch(&engine, x: 0.95, y: 0.50)
        let second = engine.update(fingerCount: 2, position: nil, typedRecently: false)
        suite.expect(second == .idle,
               "a second finger ends the slide and releases the pointer")
        suite.expect(touch(&engine, x: 0.95, y: 0.60) == .idle,
               "the finger left after a second one lifts does not restart the slide")

        engine = readyEngine()
        _ = engine.update(fingerCount: 2, position: nil, typedRecently: false)
        suite.expect(touch(&engine, x: 0.95, y: 0.50) == .idle,
               "one finger remaining from a two-finger gesture is not an edge touch")

        engine = readyEngine()
        suite.expect(touch(&engine, x: 0.95, y: 0.50, typedRecently: true) == .idle
                && touch(&engine, x: 0.95, y: 0.70) == .idle,
               "a contact right after typing is ignored for the whole touch")

        engine = readyEngine()
        _ = touch(&engine, x: 0.95, y: 0.50)
        let pointing = touch(&engine, x: 0.95 - defaultZone - 0.1, y: 0.51)
        suite.expect(pointing == .idle
                && touch(&engine, x: 0.95, y: 0.80) == .idle,
               "a touch that heads inward before sliding is pointing and stays free")

        (slide, lastY) = committedSlide()
        slide.cancel()
        suite.expect(touch(&slide, x: 0.95, y: lastY + 0.1) == .idle,
               "a physical click ends the slide")
        suite.expect(slide.update(fingerCount: 0, position: nil, typedRecently: false) == .idle
                && touch(&slide, x: 0.95, y: 0.5).holdsPointer,
               "a slide can start again once the click's touch is over")

        engine = readyEngine()
        suite.expect(engine.update(fingerCount: 1, position: nil, typedRecently: false) == .idle
                && touch(&engine, x: 0.95, y: 0.5) == .idle,
               "a finger whose position cannot be read blocks the touch")

        var restarted = Engine()
        suite.expect(touch(&restarted, x: 0.95, y: 0.5) == .idle,
               "a finger already on the pad when the feature starts is not a slide")
        (slide, lastY) = committedSlide()
        slide.reset()
        suite.expect(touch(&slide, x: 0.95, y: lastY + 0.2) == .idle,
               "resetting the engine drops a slide in progress")

        // MARK: Keys

        suite.expect(Support.keyCode(for: .volume, raising: true) == 0
                && Support.keyCode(for: .volume, raising: false) == 1
                && Support.keyCode(for: .brightness, raising: true) == 2
                && Support.keyCode(for: .brightness, raising: false) == 3,
               "steps press the system volume and brightness keys")
        suite.expect(Support.fineStepsPerRange == 64
                && abs(Support.stepTravel * Float(Support.fineStepsPerRange) - Support.fullRangeTravel) < 0.0001
                && Support.fineStepsPerRange / Support.fineStepsPerNotch == 16,
               "a slide across three quarters of the pad covers the whole range in sixteen notches")

        // MARK: Saved choices

        suite.expect(Defaults.sanitizedTrackpadEdgeSliderWidth(6) == 6
                && Defaults.sanitizedTrackpadEdgeSliderWidth(25) == 25
                && Defaults.sanitizedTrackpadEdgeSliderWidth(5) == Defaults.defaultTrackpadEdgeSliderWidth
                && Defaults.sanitizedTrackpadEdgeSliderWidth(0) == Defaults.defaultTrackpadEdgeSliderWidth
                && Defaults.sanitizedTrackpadEdgeSliderWidth(26) == Defaults.defaultTrackpadEdgeSliderWidth,
               "edge width accepts 6 to 25 percent and falls back to the default outside it")
        suite.expect(Defaults.sanitizedTrackpadEdgeSliderSensitivity(50) == 50
                && Defaults.sanitizedTrackpadEdgeSliderSensitivity(200) == 200
                && Defaults.sanitizedTrackpadEdgeSliderSensitivity(49)
                    == Defaults.defaultTrackpadEdgeSliderSensitivity
                && Defaults.sanitizedTrackpadEdgeSliderSensitivity(201)
                    == Defaults.defaultTrackpadEdgeSliderSensitivity,
               "sensitivity accepts 50 to 200 percent and falls back to the default outside it")
        suite.expect(TrackpadEdgeSliderAction.sanitized("volume", fallback: .brightness) == .volume
                && TrackpadEdgeSliderAction.sanitized("off", fallback: .brightness) == .off
                && TrackpadEdgeSliderAction.sanitized("sideways", fallback: .brightness) == .brightness
                && TrackpadEdgeSliderAction.sanitized(nil, fallback: .volume) == .volume,
               "an unknown saved edge action falls back to that edge's own default")
        suite.expect(TrackpadEdgeSliderAction.off.target == nil
                && TrackpadEdgeSliderAction.brightness.target == .brightness
                && TrackpadEdgeSliderAction.volume.target == .volume,
               "every edge action knows what it adjusts")

        let domain = "com.vorssaint.tests.trackpadEdgeSliders"
        if let saved = UserDefaults(suiteName: domain) {
            saved.removePersistentDomain(forName: domain)
            // Not register(defaults:): the registration domain is shared by
            // every UserDefaults in the process and would leak into other tests.
            for key in [DefaultsKey.trackpadEdgeSlidersLeft, DefaultsKey.trackpadEdgeSlidersRight,
                        DefaultsKey.trackpadEdgeSlidersWidth, DefaultsKey.trackpadEdgeSlidersSensitivity,
                        DefaultsKey.trackpadEdgeSlidersHaptics, DefaultsKey.trackpadEdgeSlidersReversed] {
                saved.set(Defaults.registeredDefaults[key], forKey: key)
            }
            suite.expect(Config(defaults: saved) == Config(),
                   "the registered defaults give the built-in choices")
            saved.set("volume", forKey: DefaultsKey.trackpadEdgeSlidersLeft)
            saved.set("off", forKey: DefaultsKey.trackpadEdgeSlidersRight)
            saved.set(20, forKey: DefaultsKey.trackpadEdgeSlidersWidth)
            saved.set(150, forKey: DefaultsKey.trackpadEdgeSlidersSensitivity)
            saved.set(false, forKey: DefaultsKey.trackpadEdgeSlidersHaptics)
            saved.set(true, forKey: DefaultsKey.trackpadEdgeSlidersReversed)
            let read = Config(defaults: saved)
            suite.expect(read.left == .volume && read.right == .off
                    && abs(read.zone - 0.20) < 0.0001 && abs(read.sensitivity - 1.5) < 0.0001
                    && !read.haptics && read.reversed,
                   "saved choices are what the engine runs with")
            saved.set(500, forKey: DefaultsKey.trackpadEdgeSlidersWidth)
            saved.set(0, forKey: DefaultsKey.trackpadEdgeSlidersSensitivity)
            let repaired = Config(defaults: saved)
            suite.expect(abs(repaired.zone - Config().zone) < 0.0001
                    && abs(repaired.sensitivity - Config().sensitivity) < 0.0001,
                   "a damaged width or sensitivity cannot disable the gesture or make it unusable")
            saved.removePersistentDomain(forName: domain)
        }

        // MARK: Feature wiring

        let feature = AppFeature.trackpadEdgeSliders
        suite.expect(feature.group == .mouseKeyboard
                && feature.enabledKeys == [DefaultsKey.trackpadEdgeSlidersEnabled]
                && feature.permissions == [.accessibility]
                && !feature.installedByDefault,
               "edge sliders are an opt-in mouse feature that needs only Accessibility")
        let registered = Defaults.registeredDefaults
        suite.expect(registered[DefaultsKey.trackpadEdgeSlidersEnabled] as? Bool == false
                && registered[DefaultsKey.trackpadEdgeSlidersLeft] as? String == "brightness"
                && registered[DefaultsKey.trackpadEdgeSlidersRight] as? String == "volume"
                && registered[DefaultsKey.trackpadEdgeSlidersWidth] as? Int
                    == Defaults.defaultTrackpadEdgeSliderWidth
                && registered[DefaultsKey.trackpadEdgeSlidersSensitivity] as? Int
                    == Defaults.defaultTrackpadEdgeSliderSensitivity
                && registered[DefaultsKey.trackpadEdgeSlidersHaptics] as? Bool == true
                && registered[DefaultsKey.trackpadEdgeSlidersReversed] as? Bool == false,
               "edge sliders start off, left brightness and right volume, with a light tick")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [
            DefaultsKey.trackpadEdgeSlidersEnabled, DefaultsKey.trackpadEdgeSlidersLeft,
            DefaultsKey.trackpadEdgeSlidersRight, DefaultsKey.trackpadEdgeSlidersWidth,
            DefaultsKey.trackpadEdgeSlidersSensitivity, DefaultsKey.trackpadEdgeSlidersHaptics,
            DefaultsKey.trackpadEdgeSlidersReversed,
        ]), "settings backup carries every edge slider choice")

        let runtimeSource = (try? String(contentsOfFile: "Sources/Vorssaint/App/FeatureRuntime.swift",
                                         encoding: .utf8)) ?? ""
        suite.expect(runtimeSource.contains(
            ".trackpadEdgeSliders: { MiddleClickService.shared.syncWithPreferences() }"
        ), "the Features hub owns the edge sliders runtime lifecycle")

        let serviceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/MiddleClick/MiddleClickService.swift",
            encoding: .utf8)) ?? ""
        let serviceCode = serviceSource.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(serviceCode.contains("featureWanted: enabled || radialMenuTap > 0 || edgeSliders"),
               "the trackpad service runs when only edge sliders are on")
        suite.expect(serviceCode.contains("edgeSlidersOn }"),
               "a disabled tap is kept alive for edge sliders alone")
        suite.expect(serviceCode.contains("edgeEngine.config = TrackpadEdgeSliderConfig(defaults: defaults)"),
               "the saved edge slider choices reach the engine whenever preferences change")
        let stopCode = serviceCode.components(separatedBy: "private func stop()")
            .dropFirst().first?.components(separatedBy: "private func restartMultitouch").first ?? ""
        suite.expect(stopCode.contains("resetEdgeSlidersLocked()"),
               "stopping the service drops an edge touch in progress")
        let frameCode = serviceCode.components(separatedBy: "fileprivate func contactFrame")
            .dropFirst().first?.components(separatedBy: "private func trackTapLocked").first ?? ""
        suite.expect(frameCode.contains("if edgeSlidersOn")
                && frameCode.contains("CGWarpMouseCursorPosition")
                && frameCode.contains("edgeOutput.haptic"),
               "contact frames only read edge positions while the feature is on")

        // MARK: Strings

        let english = FeatureStrings.trackpadEdgeSliders(.enUS)
        for language in AppLanguage.allCases {
            let text = FeatureStrings.trackpadEdgeSliders(language)
            let all = [text.title, text.caption, text.leftLabel, text.rightLabel, text.actionOff,
                       text.actionBrightness, text.actionVolume, text.widthLabel, text.sensitivityLabel,
                       text.hapticsLabel, text.reverseLabel]
            suite.expect(all.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                         "edge slider strings exist for \(language.rawValue)")
            suite.expect(Set([text.actionOff, text.actionBrightness, text.actionVolume]).count == 3
                    && text.label(for: .off) == text.actionOff
                    && text.label(for: .brightness) == text.actionBrightness
                    && text.label(for: .volume) == text.actionVolume,
                         "edge actions read differently from each other in \(language.rawValue)")
            if language != .enUS {
                suite.expect(text.title != english.title && text.widthLabel != english.widthLabel,
                             "edge slider labels are translated for \(language.rawValue)")
            }
        }
    }
}
