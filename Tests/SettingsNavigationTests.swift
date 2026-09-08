// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

enum SettingsNavigationTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Settings page visibility

        let allFeatures = Set(AppFeature.allCases)
        expect(pageVisible(.mouse, available: allFeatures), "mouse page shows with everything available")
        expect(pageVisible(.mouse, available: [.middleClick]),
               "one remaining mouse feature keeps the mouse page")
        expect(pageVisible(.mouse, available: [.mouseAcceleration]),
               "mouse acceleration alone keeps the mouse page")
        expect(pageVisible(.mouse, available: [.mouseClickDebounce]),
               "mouse click debounce alone keeps its Settings page reachable")
        expect(!pageVisible(.mouse, available: []),
               "the mouse page hides only with all eight mouse features off")
        expect(!pageVisible(.energy, available: allFeatures.subtracting([.keepAwake, .brightness,
                                                                         .extraBrightness,
                                                                         .bluetoothSleep])),
               "energy hides when all four of its features are off")
        expect(pageVisible(.energy, available: [.extraBrightness]), "XDR alone keeps the energy page")
        expect(pageVisible(.energy, available: [.brightness]),
               "brightness control alone keeps the energy page")
        expect(!pageVisible(.monitor, available: allFeatures.subtracting(Set(FeatureVisibilitySupport.monitorFeatures))),
               "monitor page hides with every metric off")
        expect(pageVisible(.monitor, available: [.monitorNetwork]), "one metric keeps the monitor page")
        expect(pageVisible(.general, available: []) && pageVisible(.about, available: [])
                && pageVisible(.shortcuts, available: []),
               "app pages never hide")
        expect(!pageVisible(.shelf, available: allFeatures.subtracting([.shelf])),
               "single-feature pages follow their feature")
        expect(pageVisible(.cutPaste, available: [.finderRename])
                && pageVisible(.cutPaste, available: [.finderCutPaste])
                && !pageVisible(.cutPaste, available: []),
               "either Finder shortcut keeps their shared page visible")
        expect(!pageVisible(.cleaner,
                            available: allFeatures.subtracting([.cleaner])),
               "cleaner settings, including WhatsApp downloads, follow the cleaner module")
        expect(pageVisible(.quickTools, available: [.quickToggles]),
               "the quick toggles alone keep the quick tools page")
        expect(pageVisible(.clipboard, available: [.finderCutPaste]),
               "the image paste option keeps the Clipboard page available")
        expect(AppFeature.allCases.allSatisfy { feature in
            let destination = feature.settingsDestination
            let gate = FeatureVisibilitySupport.features(for: destination.page)
            return gate.isEmpty || gate.contains(feature)
        }, "every feature destination is either always visible or gated by that feature")
        expect(AppFeature.allCases.allSatisfy { $0.settingsDestination.hasValidSectionAnchor },
               "every feature anchor belongs to its destination page")
        expect(Set(AppFeature.allCases.compactMap(\.settingsDestination.sectionAnchor))
                == Set(SettingsSectionAnchor.allCases),
               "every declared Settings section anchor is used by a feature destination")
        expect(AppFeature.windowMaximizer.settingsDestination
                == FeatureSettingsDestination(.general, sectionAnchor: .panelConfiguration)
                && AppFeature.mixer.settingsDestination
                == FeatureSettingsDestination(.general, sectionAnchor: .panelConfiguration),
               "panel-oriented features land on General panel configuration")
        expect(AppFeature.cleaningMode.settingsDestination
                == FeatureSettingsDestination(.quickTools, sectionAnchor: .cleaningMode),
               "cleaning mode lands on Quick Tools cleaning mode section")
        expect(AppFeature.musicBlock.settingsDestination
                == FeatureSettingsDestination(.general, sectionAnchor: .musicBlocking)
                && AppFeature.soundOutputSwitcher.settingsDestination
                == FeatureSettingsDestination(.shortcuts, sectionAnchor: .soundOutputSwitcher)
                && AppFeature.diskImageInstaller.settingsDestination
                == FeatureSettingsDestination(.features),
               "features without dedicated pages use explicit nearest Settings destinations")
        expect(!AppFeature.diskImageInstaller.hasNavigableSettingsDestination
                && AppFeature.allCases.filter { $0 != .diskImageInstaller }
                    .allSatisfy(\.hasNavigableSettingsDestination),
               "a feature without a separate configuration surface does not show a dead-end link")
        expect(AppFeature.monitorCPU.settingsDestination == FeatureSettingsDestination(.monitor)
                && AppFeature.fanControl.settingsDestination
                == FeatureSettingsDestination(.monitor, sectionAnchor: .fanControl),
               "shared monitor destinations distinguish the dedicated fan controls")
        let settingsRouter = SettingsRouter.shared
        var settingsRequestCount = 0
        var settingsRequestsPublishedReady = true
        let settingsRequestObservation = settingsRouter.$requestID
            .dropFirst()
            .sink { requestID in
                settingsRequestCount += 1
                settingsRequestsPublishedReady =
                    settingsRequestsPublishedReady
                    && settingsRouter.pendingDestinationRequest?.id == requestID
            }
        let repeatedDestination = FeatureSettingsDestination(.mouse, sectionAnchor: .middleClick)
        settingsRouter.request(repeatedDestination)
        let firstSettingsRequestID = settingsRouter.requestID
        settingsRouter.request(repeatedDestination)
        expect(settingsRouter.destination == repeatedDestination
                && settingsRouter.page == repeatedDestination.page,
               "a Settings destination request selects its page and preserves its anchor")
        expect(settingsRequestCount == 2 && settingsRouter.requestID != firstSettingsRequestID,
               "repeated requests for the same Settings destination remain observable")
        expect(settingsRequestsPublishedReady,
               "a Settings request is ready to consume when its request identity is published")
        let repeatedSettingsRequestID = settingsRouter.requestID
        settingsRouter.consumeDestinationRequest(id: firstSettingsRequestID)
        expect(settingsRouter.pendingDestinationRequest?.id == repeatedSettingsRequestID,
               "consuming an older Settings request cannot clear a newer request")
        settingsRouter.consumeDestinationRequest(id: repeatedSettingsRequestID)
        expect(settingsRouter.pendingDestinationRequest == nil,
               "a handled Settings destination request is cleared")

        let featuresDestination = FeatureSettingsDestination(.features)
        settingsRouter.request(featuresDestination, targetFeature: .homebrew)
        let firstFeatureTargetRequestID = settingsRouter.requestID
        expect(settingsRouter.pendingFeatureTarget?.id == firstFeatureTargetRequestID
                && settingsRouter.pendingFeatureTarget?.feature == .homebrew,
               "requesting Features with a target feature publishes a matching feature-target request")
        settingsRouter.request(featuresDestination, targetFeature: .homebrew)
        let secondFeatureTargetRequestID = settingsRouter.requestID
        expect(secondFeatureTargetRequestID != firstFeatureTargetRequestID
                && settingsRouter.pendingFeatureTarget?.id == secondFeatureTargetRequestID,
               "repeated requests for the same target feature remain observable")
        settingsRouter.consumeFeatureTarget(id: firstFeatureTargetRequestID)
        expect(settingsRouter.pendingFeatureTarget?.id == secondFeatureTargetRequestID,
               "consuming an older feature-target request cannot clear a newer target")
        settingsRouter.consumeFeatureTarget(id: secondFeatureTargetRequestID)
        expect(settingsRouter.pendingFeatureTarget == nil,
               "a handled feature-target request is cleared")
        settingsRouter.request(featuresDestination, targetFeature: .diskImageInstaller)
        expect(settingsRouter.pendingFeatureTarget?.feature == .diskImageInstaller,
               "requesting a different target feature is observable")
        settingsRouter.request(repeatedDestination)
        expect(settingsRouter.pendingFeatureTarget == nil,
               "a later generic request clears any unconsumed feature target so it cannot leak into unrelated navigation")

        settingsRouter.cleanerTool = "tool-id"
        settingsRouter.request(FeatureSettingsDestination(.cleaner))
        expect(settingsRouter.page == .cleaner && settingsRouter.cleanerTool == "tool-id",
               "requesting Cleaner Settings preserves its one-shot tool hint")
        settingsRouter.consumeDestinationRequest(id: settingsRouter.requestID)
        settingsRouter.cleanerTool = nil
        settingsRouter.page = .general
        withExtendedLifetime(settingsRequestObservation) {}

    }
}
