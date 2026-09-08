// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum SettingsSearchTests {
    static func run(expect: (Bool, String) -> Void) {
        expect(SettingsSearchSupport.matches(query: "", title: "Monitor"),
               "a blank settings search matches everything")
        expect(SettingsSearchSupport.matches(query: "moni", title: "Monitor"),
               "settings search is case-insensitive prefix-friendly")
        expect(SettingsSearchSupport.matches(query: "musica", title: "Música"),
               "settings search ignores accents")
        expect(!SettingsSearchSupport.matches(query: "shelf", title: "Monitor"),
               "settings search filters out non-matches")
        expect(SettingsSearchSupport.matches(query: "  switcher ", title: "Switcher"),
               "settings search trims surrounding whitespace")
        expect(SettingsSearchSupport.filteredIndices(query: "mo",
                                                     sections: [["Monitor", "Shelf"], ["Mouse"]])
                   == [[0], [0]],
               "settings search keeps matching rows per section")
        expect(SettingsSearchSupport.matches(query: "lid", title: "Energy",
                                             keywords: ["Keep going with the lid closed"]),
               "settings search finds a page by an option living inside it")
        expect(!SettingsSearchSupport.matches(query: "lid", title: "Energy", keywords: []),
               "without keywords the same query stays a miss")
        expect(SettingsSearchSupport.matches(
            query: "preview position",
            title: FeatureStrings.screenshot(.enUS).pageTitle,
            keywords: [FeatureStrings.screenshot(.enUS).previewPositionLabel]),
               "preview position is a searchable Screenshot keyword")
        expect(SettingsSearchSupport.matches(query: "hide",
                                             title: Strings.enUS.tabSwitcher,
                                             keywords: [Strings.enUS.dockClickHide]),
               "Dock hiding is findable through a localized Settings keyword")
        let captureSearchKeywords = SettingsSearchSupport.screenCaptureKeywords(
            Strings.enUS, language: .enUS)
        expect(SettingsSearchSupport.matches(
                    query: "screenshot",
                    title: FeatureStrings.screenshot(.enUS).screenCaptureTitle,
                    keywords: captureSearchKeywords)
                && SettingsSearchSupport.matches(
                    query: "screen recording",
                    title: FeatureStrings.screenshot(.enUS).screenCaptureTitle,
                    keywords: captureSearchKeywords)
                && SettingsSearchSupport.matches(
                    query: "line breaks",
                    title: FeatureStrings.screenshot(.enUS).screenCaptureTitle,
                    keywords: captureSearchKeywords),
               "Screen capture tools and their options find the one settings page")

        let settingsFeatureTitles: [AppFeature: String] = [
            .homebrew: "Homebrew",
            .cameraPreview: "Camera Preview",
            .screenRecorder: "Screen Recorder",
            .micMute: "Mic Mute",
            .diskImageInstaller: "Disk Image Installer",
        ]
        let featureSearchItems = SettingsSearchSupport.featureItems(language: .enUS) { feature in
            settingsFeatureTitles[feature] ?? feature.rawValue
        }
        let expectedFeatureSearchDestinations: [(AppFeature, FeatureSettingsDestination)] = [
            (.homebrew, FeatureSettingsDestination(.homebrew)),
            (.cameraPreview, FeatureSettingsDestination(.quickTools, sectionAnchor: .cameraPreview)),
            (.screenRecorder, FeatureSettingsDestination(.screenshot, sectionAnchor: .screenRecorder)),
            (.micMute, FeatureSettingsDestination(.quickTools, sectionAnchor: .micMute)),
            (.diskImageInstaller, FeatureSettingsDestination(.features)),
        ]
        for (feature, destination) in expectedFeatureSearchDestinations {
            let item = featureSearchItems.first { $0.id == .feature(feature) }
            expect(item?.destination == destination,
                   "\(settingsFeatureTitles[feature] ?? feature.rawValue) keeps its exact Settings destination")
            expect(item?.icon == feature.symbolName,
                   "\(settingsFeatureTitles[feature] ?? feature.rawValue) uses its feature symbol")
        }
        expect(featureSearchItems.count == AppFeature.allCases.count
                && Set(featureSearchItems.map(\.id)).count == AppFeature.allCases.count,
               "generated Settings feature results have one stable identity per feature")

        for language in AppLanguage.allCases {
            let pageTitle = FeatureStrings.clipboard(language).title
            let clipboardPage = SettingsSearchItem(
                id: .page(.clipboard), destination: FeatureSettingsDestination(.clipboard),
                title: pageTitle, icon: "doc.on.clipboard")
            let featureItems = SettingsSearchSupport.featureItems(language: language) {
                $0 == .clipboardHistory ? pageTitle : $0.rawValue
            }
            let items = SettingsSearchSupport.combinedItems(
                pageItems: [clipboardPage], featureItems: featureItems)
            let clipboardHistory = items.first { $0.id == .feature(.clipboardHistory) }
            expect(clipboardHistory?.title == FeatureStrings.commandBar(language).sourceClipboard
                    && clipboardHistory?.destination
                        == FeatureSettingsDestination(.clipboard, sectionAnchor: .clipboardHistory),
                   "\(language.rawValue) labels and routes Clipboard history as a section result")
            expect(items.contains { $0.id == .page(.clipboard) }
                    && clipboardPage.title != clipboardHistory?.title,
                   "\(language.rawValue) distinguishes Clipboard page and history search labels")
        }

        // MARK: Settings search structural deduplication
        let structuralPage = SettingsSearchItem(
            id: .page(.homebrew), destination: FeatureSettingsDestination(.homebrew),
            title: "Dedicated Packages Page", icon: "shippingbox", keywords: ["Formulae"])
        let structuralFeature = SettingsSearchItem(
            id: .feature(.homebrew), destination: FeatureSettingsDestination(.homebrew),
            title: "Generated Homebrew Feature", icon: "externaldrive", feature: .homebrew)
        let structurallyMerged = SettingsSearchSupport.combinedItems(
            pageItems: [structuralPage], featureItems: [structuralFeature])
        expect(structurallyMerged.map(\.id) == [.page(.homebrew)]
                && structurallyMerged.first?.title == "Dedicated Packages Page"
                && structurallyMerged.first?.icon == "shippingbox"
                && structurallyMerged.first?.keywords == ["Formulae"]
                && structurallyMerged.first?.feature == .homebrew,
               "differently titled Homebrew rows merge into the stable page row")

        let monitorPage = SettingsSearchItem(id: .page(.monitor),
                                             destination: FeatureSettingsDestination(.monitor),
                                             title: "Monitor", icon: "display")
        let monitorCPUFeature = SettingsSearchSupport.featureItems(language: .enUS) {
            $0 == .monitorCPU ? "Generated CPU Monitor" : $0.rawValue
        }.first { $0.id == .feature(.monitorCPU) }!
        let multiFeatureMerged = SettingsSearchSupport.combinedItems(
            pageItems: [monitorPage], featureItems: [monitorCPUFeature])
        expect(monitorPage.destination == monitorCPUFeature.destination
                && monitorCPUFeature.destination == AppFeature.monitorCPU.settingsDestination
                && monitorCPUFeature.destination.sectionAnchor == nil
                && multiFeatureMerged.map(\.id) == [.page(.monitor), .feature(.monitorCPU)],
               "the real shared Monitor destination does not merge a multi-feature page")

        let actionCoveredMappings: [(SettingsPage, AppFeature)] = [
            (.cleaner, .cleaner),
            (.uninstaller, .uninstaller),
            (.appUpdates, .appUpdates),
        ]
        let actionCoveredPages = actionCoveredMappings.map { page, feature in
            SettingsSearchItem(id: .page(page), destination: FeatureSettingsDestination(page),
                               title: "Dedicated \(feature.rawValue) Page", icon: "gearshape")
        }
        let actionCoveredFeatures = SettingsSearchSupport.featureItems(language: .enUS) {
            "Generated \($0.rawValue) Feature"
        }.filter { item in
            actionCoveredMappings.contains { _, feature in item.id == .feature(feature) }
        }
        let actionCoveredItems = SettingsSearchSupport.combinedItems(
            pageItems: actionCoveredPages, featureItems: actionCoveredFeatures)
        for (page, feature) in actionCoveredMappings {
            expect(actionCoveredItems.first { $0.id == .page(page) }?.feature == feature
                    && !actionCoveredItems.contains { $0.id == .feature(feature) },
                   "the differently titled \(feature.rawValue) rows keep only the page identity")
        }

        let dedicatedSettingsItems = [
            SettingsSearchItem(id: .page(.features),
                                destination: FeatureSettingsDestination(.features),
                                title: "Features", icon: "square.grid.2x2",
                                keywords: ["Homebrew", "Camera Preview"],
                                keywordFeatures: [.homebrew, .cameraPreview]),
            SettingsSearchItem(id: .page(.appUpdates),
                                destination: FeatureSettingsDestination(.appUpdates),
                                title: "App Updates", icon: "arrow.down.app",
                                keywords: ["Homebrew"]),
            SettingsSearchItem(id: .page(.quickTools),
                                destination: FeatureSettingsDestination(.quickTools),
                                title: "Quick Tools", icon: "wand.and.rays",
                                keywords: ["Camera Preview"]),
            SettingsSearchItem(id: .page(.homebrew),
                                destination: FeatureSettingsDestination(.homebrew),
                                title: "Homebrew", icon: "shippingbox"),
        ]
        let combinedSettingsItems = SettingsSearchSupport.combinedItems(
            pageItems: dedicatedSettingsItems,
            featureItems: featureSearchItems)
        expect(combinedSettingsItems.filter {
            $0.title == "Homebrew" && $0.destination == FeatureSettingsDestination(.homebrew)
        }.count == 1
                && combinedSettingsItems.contains { $0.id == .page(.homebrew) },
               "the explicit Homebrew page result replaces its equivalent generated result")
        expect(combinedSettingsItems.filter {
            $0.destination == FeatureSettingsDestination(.appUpdates)
        }.count == 1
                && combinedSettingsItems.contains { $0.id == .page(.appUpdates) },
               "a structurally one-to-one App Updates result is deduplicated to the page")
        expect(combinedSettingsItems.contains { $0.id == .feature(.diskImageInstaller) },
               "a differently named feature remains discoverable through its Features fallback")
        expect(combinedSettingsItems.first { $0.id == .page(.homebrew) }?.feature == .homebrew,
               "a deduplicated Homebrew page result keeps its feature identity")
        expect(combinedSettingsItems.first { $0.id == .page(.features) }?.feature == nil,
               "a generic page result that does not merge with a feature carries no feature identity")
        expect(combinedSettingsItems.first { $0.id == .feature(.diskImageInstaller) }?.feature
                == .diskImageInstaller,
               "a feature-only result carries its own feature identity")

        // MARK: Settings search routing

        let homebrewPageItem = combinedSettingsItems.first { $0.id == .page(.homebrew) }!
        let unavailableHomebrewRoute = SettingsSearchSupport.route(for: homebrewPageItem) { _ in false }
        expect(unavailableHomebrewRoute.destination == FeatureSettingsDestination(.features)
                && unavailableHomebrewRoute.targetFeature == .homebrew,
               "an unavailable Homebrew result preserves its identity and targets its Feature Hub row")
        let availableHomebrewRoute = SettingsSearchSupport.route(for: homebrewPageItem) { _ in true }
        expect(availableHomebrewRoute.destination == FeatureSettingsDestination(.homebrew)
                && availableHomebrewRoute.targetFeature == nil,
               "an available Homebrew result still opens its own dedicated page with no row to reveal")

        let cameraPreviewItem = featureSearchItems.first { $0.id == .feature(.cameraPreview) }!
        let unavailableCameraRoute = SettingsSearchSupport.route(for: cameraPreviewItem) { $0 != .cameraPreview }
        expect(unavailableCameraRoute.destination == FeatureSettingsDestination(.features)
                && unavailableCameraRoute.targetFeature == .cameraPreview,
               "an unavailable grouped feature targets its own row even while its shared page stays visible")
        let availableCameraRoute = SettingsSearchSupport.route(for: cameraPreviewItem) { _ in true }
        expect(availableCameraRoute.destination
                == FeatureSettingsDestination(.quickTools, sectionAnchor: .cameraPreview)
                && availableCameraRoute.targetFeature == nil,
               "an available grouped feature keeps opening its anchored section directly")

        let diskImageItem = featureSearchItems.first { $0.id == .feature(.diskImageInstaller) }!
        let diskImageRoute = SettingsSearchSupport.route(for: diskImageItem) { _ in true }
        expect(diskImageRoute.destination == FeatureSettingsDestination(.features)
                && diskImageRoute.targetFeature == .diskImageInstaller,
               "Disk Image Installer, whose own destination is Features, still targets its exact row")

        let genericFeaturesItem = SettingsSearchItem(id: .page(.features),
                                                     destination: FeatureSettingsDestination(.features),
                                                     title: "Features", icon: "square.grid.2x2")
        let genericFeaturesRoute = SettingsSearchSupport.route(for: genericFeaturesItem) { _ in true }
        expect(genericFeaturesRoute.destination == FeatureSettingsDestination(.features)
                && genericFeaturesRoute.targetFeature == nil,
               "a generic Features selection carries no feature target")

        let hiddenPageItem = SettingsSearchItem(id: .page(.shelf),
                                                destination: FeatureSettingsDestination(.shelf),
                                                title: "Shelf", icon: "tray.full")
        let hiddenPageRoute = SettingsSearchSupport.route(for: hiddenPageItem) { _ in false }
        expect(hiddenPageRoute.destination == FeatureSettingsDestination(.features)
                && hiddenPageRoute.targetFeature == nil,
               "a page result with no merged feature identity still falls back to Features generically")

        let homebrewMatches = SettingsSearchSupport.matchingItems(
            query: "  HOMEBREW ", items: combinedSettingsItems)
        expect(homebrewMatches.first?.destination == FeatureSettingsDestination(.homebrew)
                && homebrewMatches.map(\.id)
                    == [.page(.homebrew), .page(.features), .page(.appUpdates)],
               "an exact Homebrew title ranks before earlier generic keyword matches")
        let cameraPreviewMatches = SettingsSearchSupport.matchingItems(
            query: "Camera Preview", items: combinedSettingsItems)
        expect(cameraPreviewMatches.first?.destination
                == FeatureSettingsDestination(.quickTools, sectionAnchor: .cameraPreview)
                && cameraPreviewMatches.map(\.id)
                    == [.feature(.cameraPreview), .page(.features), .page(.quickTools)],
               "an exact Camera Preview feature ranks before its page containers")

        let keywordBeforePartialTitle = SettingsSearchItem(
            id: .page(.features), destination: FeatureSettingsDestination(.features),
            title: "Features", icon: "square.grid.2x2", keywords: ["Homebrew Packages"])
        let partialTitleAfterKeyword = SettingsSearchItem(
            id: .page(.appUpdates), destination: FeatureSettingsDestination(.appUpdates),
            title: "Homebrew Packages", icon: "arrow.down.app")
        let partialMatches = SettingsSearchSupport.matchingItems(
            query: "brew", items: [keywordBeforePartialTitle, partialTitleAfterKeyword])
        expect(partialMatches.map(\.id) == [.page(.appUpdates), .page(.features)],
               "partial title containment ranks before an earlier keyword-only match")

        let tiedTitleMatches = [
            SettingsSearchItem(id: .page(.quickTools),
                               destination: FeatureSettingsDestination(.quickTools),
                               title: "Camera Tools", icon: "wand.and.rays"),
            SettingsSearchItem(id: .feature(.cameraPreview),
                               destination: FeatureSettingsDestination(
                                 .quickTools, sectionAnchor: .cameraPreview),
                               title: "Camera Controls", icon: "web.camera"),
        ]
        expect(SettingsSearchSupport.matchingItems(query: "camera", items: tiedTitleMatches)
                .map(\.id) == tiedTitleMatches.map(\.id),
               "Settings search preserves source order between equal-rank matches")
        expect(SettingsSearchSupport.matchingItems(query: "  \n", items: tiedTitleMatches)
                .map(\.id) == tiedTitleMatches.map(\.id),
               "a blank Settings query preserves every item in source order")

        // MARK: Grouped Settings search suggestions
        let cameraGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "Camera Preview", items: combinedSettingsItems,
            isAvailable: { _ in true })
        expect(cameraGroups.map(\.id) == [.quickTools, .features]
                && cameraGroups.first?.pageItem.title == "Quick Tools",
               "an exact utility match puts its main Settings page first")
        expect(cameraGroups.first?.parentMatches == false
                && cameraGroups.first?.suggestions.map(\.title) == ["Camera Preview"]
                && cameraGroups.first?.suggestions.first?.item.destination
                    == FeatureSettingsDestination(.quickTools, sectionAnchor: .cameraPreview),
               "a grouped utility row retains its exact anchored destination")
        expect(cameraGroups.last?.suggestions.map(\.title) == ["Camera Preview"],
               "every other main page containing the query remains represented")
        let installedCameraHubRoute = cameraGroups.last?.suggestions.first.map {
            SettingsSearchSupport.route(for: $0, isAvailable: { _ in true })
        }
        expect(installedCameraHubRoute?.destination == FeatureSettingsDestination(.features)
                && installedCameraHubRoute?.targetFeature == .cameraPreview,
               "an installed utility's Features result reveals its exact uninstall row")

        let homebrewGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "Homebrew", items: combinedSettingsItems,
            isAvailable: { _ in true })
        expect(homebrewGroups.map(\.id) == [.homebrew, .features, .appUpdates]
                && homebrewGroups.first?.parentMatches == true
                && homebrewGroups.first?.suggestions.isEmpty == true,
               "a matching main page is shown once before grouped keyword matches")

        let settingPage = SettingsSearchItem(
            id: .page(.energy), destination: FeatureSettingsDestination(.energy),
            title: "Energy", icon: "bolt.fill",
            keywords: ["Keep awake", "Show countdown", "Show remaining duration"])
        let settingGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "show", items: [settingPage], isAvailable: { _ in true })
        expect(settingGroups.count == 1
                && settingGroups[0].id == .energy
                && !settingGroups[0].parentMatches
                && settingGroups[0].suggestions.map(\.title)
                    == ["Show countdown", "Show remaining duration"],
               "all matching setting labels are listed beneath their main page")
        expect(SettingsSearchSupport.groupedMatchingItems(
                    query: " \n ", items: [settingPage],
                    isAvailable: { _ in true }).isEmpty,
               "a blank query does not replace the normal Settings sidebar with groups")

        let availabilityPage = SettingsSearchItem(
            id: .page(.quickTools), destination: FeatureSettingsDestination(.quickTools),
            title: "Quick Tools", icon: "wand.and.rays",
            keywords: ["Camera Preview", "Open camera automatically", "Scratchpad Notes"],
            keywordFeatures: [.cameraPreview, .cameraPreview, .scratchpad])
        let availabilityHub = SettingsSearchItem(
            id: .page(.features), destination: FeatureSettingsDestination(.features),
            title: "Features", icon: "square.grid.2x2",
            keywords: ["Camera Preview", "scratchpad"],
            keywordFeatures: [.cameraPreview, .scratchpad])
        let availabilityFeatures = featureSearchItems.filter {
            $0.id == .feature(.cameraPreview) || $0.id == .feature(.scratchpad)
        }
        let availabilityItems = [availabilityHub, availabilityPage] + availabilityFeatures
        let onlyScratchpadAvailable: (AppFeature) -> Bool = { $0 == .scratchpad }
        let unavailableCameraGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "camera", items: availabilityItems,
            isAvailable: onlyScratchpadAvailable)
        let unavailableCameraSuggestion = unavailableCameraGroups.first?.suggestions.first
        let groupedUnavailableCameraRoute = unavailableCameraSuggestion.map {
            SettingsSearchSupport.route(for: $0.item, isAvailable: onlyScratchpadAvailable)
        }
        expect(unavailableCameraGroups.count == 1
                && unavailableCameraGroups[0].id == .features
                && unavailableCameraGroups[0].suggestions.map(\.title) == ["Camera Preview"]
                && groupedUnavailableCameraRoute?.destination == FeatureSettingsDestination(.features)
                && groupedUnavailableCameraRoute?.targetFeature == .cameraPreview,
               "an unavailable utility remains navigable through its exact Features row")
        expect(SettingsSearchSupport.groupedMatchingItems(
                    query: "automatically", items: availabilityItems,
                    isAvailable: onlyScratchpadAvailable).isEmpty,
               "setting fields owned by an unavailable utility stay out of suggestions")
        let availableCameraSetting = SettingsSearchSupport.groupedMatchingItems(
            query: "automatically", items: availabilityItems,
            isAvailable: { _ in true }).first?.suggestions.first
        let availableCameraSettingRoute = availableCameraSetting.map {
            SettingsSearchSupport.route(for: $0, isAvailable: { _ in true })
        }
        expect(availableCameraSetting?.title == "Open camera automatically"
                && availableCameraSettingRoute?.destination
                    == FeatureSettingsDestination(.quickTools, sectionAnchor: .cameraPreview)
                && availableCameraSettingRoute?.targetFeature == nil,
               "a feature-owned setting keyword opens its exact anchored section")
        let availableScratchpadGroups = SettingsSearchSupport.groupedMatchingItems(
            query: "scratchpad", items: availabilityItems,
            isAvailable: onlyScratchpadAvailable)
        expect(availableScratchpadGroups.first?.id == .quickTools
                && availableScratchpadGroups[0].suggestions.map(\.title)
                    == ["scratchpad", "Scratchpad Notes"]
                && availableScratchpadGroups[0].suggestions.first?.item.destination
                    == FeatureSettingsDestination(.quickTools, sectionAnchor: .scratchpad),
               "an installed utility remains searchable on a shared Settings page")
        expect(SettingsSearchSupport.groupedMatchingItems(
                    query: "Quick Tools", items: availabilityItems,
                    isAvailable: { _ in false }).isEmpty,
               "a main page with no installed utilities is not suggested")

        let freshSize = SettingsWindowSupport.initialContentSize(savedWidth: 0, savedHeight: 0,
                                                                 availableHeight: 1200)
        expect(freshSize.width == 772 && freshSize.height == 838,
               "settings window opens at the tall default when nothing is saved")
        let clampedSize = SettingsWindowSupport.initialContentSize(savedWidth: 0, savedHeight: 0,
                                                                   availableHeight: 700)
        expect(clampedSize.height == 700,
               "the tall default shrinks to what the screen fits")
        let tinyScreen = SettingsWindowSupport.initialContentSize(savedWidth: 0, savedHeight: 0,
                                                                  availableHeight: 400)
        expect(tinyScreen.height == 528,
               "the default never goes below the design height")
        let savedSize = SettingsWindowSupport.initialContentSize(savedWidth: 900, savedHeight: 950,
                                                                 availableHeight: 700)
        expect(savedSize.width == 900 && savedSize.height == 950,
               "a user-chosen size is restored as is")
        let bogusSaved = SettingsWindowSupport.initialContentSize(savedWidth: 300, savedHeight: 200,
                                                                  availableHeight: 1200)
        expect(bogusSaved.width == 772 && bogusSaved.height == 838,
               "a saved size below the minimum falls back to the default")
        expect(!SettingsWindowSupport.isValidContentSize(width: 300, height: 200),
               "sub-minimum sizes are rejected by isValidContentSize")
        expect(SettingsWindowSupport.isValidContentSize(width: 772, height: 528),
               "exact minimum size is valid")
        expect(SettingsWindowSupport.isValidContentSize(width: 1000, height: 800),
               "larger size is valid")
        let fullTourSize = CGSize(width: 600, height: 584)
        let tourSettingsSize = CGSize(width: 772, height: 750)
        let wideTourScreen = CGRect(x: -1600, y: 100, width: 1470, height: 900)
        let wideTourPlacement = SettingsWindowSupport.tourPlacement(
            settingsSize: tourSettingsSize, tourSize: fullTourSize, visibleFrame: wideTourScreen)
        expect(!wideTourPlacement.settings.intersects(wideTourPlacement.tour)
                && wideTourPlacement.settings.maxX < wideTourPlacement.tour.minX,
               "the complete tour fits beside Settings on a wide display")
        expect(wideTourScreen.contains(wideTourPlacement.settings)
                && wideTourScreen.contains(wideTourPlacement.tour),
               "tour placement respects external displays with offset coordinates")
        let smallTourScreen = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let smallTourPlacement = SettingsWindowSupport.tourPlacement(
            settingsSize: tourSettingsSize, tourSize: fullTourSize, visibleFrame: smallTourScreen)
        expect(smallTourScreen.contains(smallTourPlacement.settings)
                && smallTourScreen.contains(smallTourPlacement.tour)
                && smallTourPlacement.settings.size == tourSettingsSize
                && smallTourPlacement.tour.size == fullTourSize,
               "narrow displays keep the complete images and controls on screen without resizing")
        let tallTourPlacement = SettingsWindowSupport.tourPlacement(
            settingsSize: tourSettingsSize, tourSize: fullTourSize,
            visibleFrame: CGRect(x: 200, y: -1700, width: 1000, height: 1600))
        expect(!tallTourPlacement.settings.intersects(tallTourPlacement.tour)
                && tallTourPlacement.tour.minY > tallTourPlacement.settings.maxY,
               "portrait displays stack the tour above Settings when both fit")
        let oversizedTourPlacement = SettingsWindowSupport.tourPlacement(
            settingsSize: CGSize(width: 1600, height: 1000), tourSize: fullTourSize,
            visibleFrame: smallTourScreen)
        expect(smallTourScreen.contains(oversizedTourPlacement.tour)
                && oversizedTourPlacement.settings.maxY == smallTourScreen.maxY - 20,
               "an oversized Settings window cannot push the tour or its own title bar off screen")
        let preferredSettingsFrame = CGRect(x: -50, y: 100, width: 1000, height: 700)
        let overlappingPlacement = SettingsWindowSupport.panelPlacement(
            preferredFrame: preferredSettingsFrame,
            panelFrame: CGRect(x: 450, y: 500, width: 300, height: 300),
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 900))
        expect(overlappingPlacement.closesPanel
                && overlappingPlacement.frame == CGRect(x: 20, y: 100, width: 1000, height: 700),
               "failed avoidance closes the panel and clamps the preferred settings frame")
        let separatePlacement = SettingsWindowSupport.panelPlacement(
            preferredFrame: CGRect(x: 600, y: 100, width: 800, height: 700),
            panelFrame: CGRect(x: 1200, y: 500, width: 300, height: 300),
            visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 900))
        expect(!separatePlacement.closesPanel
                && separatePlacement.frame.maxX == 1172,
               "successful avoidance keeps the panel beside settings")
        let verticalPlacement = SettingsWindowSupport.panelPlacement(
            preferredFrame: CGRect(x: 100, y: 400, width: 1000, height: 300),
            panelFrame: CGRect(x: 450, y: 500, width: 300, height: 100),
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 900))
        expect(!verticalPlacement.closesPanel
                && verticalPlacement.frame.maxY == 472,
               "vertical avoidance moves settings below the panel with the standard gap")

    }
}
