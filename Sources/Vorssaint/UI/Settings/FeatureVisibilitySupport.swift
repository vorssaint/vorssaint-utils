// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// The Settings pages. Lives here (without SwiftUI) so the visibility rules
/// below and the unit tests can reason about pages without pulling UI in.
enum SettingsPage: Hashable {
    case general, features, energy, monitor
    case mouse, switcher, keyDebounce, superKey, cutPaste, autoQuit, cleaner, uninstaller, urlCleaner, homebrew, appUpdates, media, clipboard, windowLayout, shelf, quickTools, textSnippets, screenshot, radialMenu, commandBar, killProcess
    case shortcuts, advanced, about, releaseNotes, support
}

/// Stable, non-localized identities for destinations inside shared Settings
/// pages. Raw values may be persisted or used by UI identifiers, so cases can
/// be added but should not be renamed.
enum SettingsSectionAnchor: String, CaseIterable, Hashable {
    case panelConfiguration
    case musicBlocking
    case keepAwake
    case brightness
    case extraBrightness
    case bluetoothSleep
    case scrollDirection
    case focusFollowsMouse
    case smoothScroll
    case mouseNavigation
    case mouseButtonShortcuts
    case middleClick
    case switcher
    case dock
    case dockClick
    case finderCutPaste
    case finderRename
    case clipboardHistory
    case pastePlain
    case quickLauncher
    case quickToggles
    case screenshot
    case screenRecorder
    case colorPicker
    case screenOCR
    case micMute
    case cameraPreview
    case scratchpad
    case soundOutputSwitcher
    case fanControl

    var page: SettingsPage {
        switch self {
        case .panelConfiguration, .musicBlocking: return .general
        case .keepAwake, .brightness, .extraBrightness, .bluetoothSleep: return .energy
        case .scrollDirection, .focusFollowsMouse, .smoothScroll, .mouseNavigation, .mouseButtonShortcuts,
             .middleClick:
            return .mouse
        case .switcher, .dock, .dockClick: return .switcher
        case .finderCutPaste, .finderRename: return .cutPaste
        case .clipboardHistory, .pastePlain: return .clipboard
        case .quickLauncher, .quickToggles, .micMute, .cameraPreview, .scratchpad:
            return .quickTools
        case .screenshot, .screenRecorder, .colorPicker, .screenOCR:
            return .screenshot
        case .soundOutputSwitcher: return .shortcuts
        case .fanControl: return .monitor
        }
    }
}

/// A feature's nearest configuration surface. The optional anchor distinguishes
/// a feature section on a shared page; nil means the page itself is the target.
struct FeatureSettingsDestination: Hashable {
    let page: SettingsPage
    let sectionAnchor: SettingsSectionAnchor?

    init(_ page: SettingsPage, sectionAnchor: SettingsSectionAnchor? = nil) {
        self.page = page
        self.sectionAnchor = sectionAnchor
    }

    var hasValidSectionAnchor: Bool {
        sectionAnchor == nil || sectionAnchor?.page == page
    }
}

struct SettingsDestinationRequest: Equatable {
    let id: UUID
    let destination: FeatureSettingsDestination
}

/// Selects a Settings destination and publishes a fresh request identity even
/// when callers ask for the same page and anchor repeatedly.
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()

    @Published var page: SettingsPage = .general
    @Published private(set) var destination = FeatureSettingsDestination(.general)
    @Published private(set) var requestID = UUID()
    @Published private(set) var pendingDestinationRequest: SettingsDestinationRequest?
    /// One-shot hint for the Cleaner page's tool switcher, so a panel surface
    /// can land directly on a specific tool. Consumed and cleared on arrival.
    @Published var cleanerTool: String?

    private init() {}

    func request(_ destination: FeatureSettingsDestination) {
        let requestID = UUID()
        self.destination = destination
        page = destination.page
        pendingDestinationRequest = SettingsDestinationRequest(id: requestID,
                                                               destination: destination)
        self.requestID = requestID
    }

    /// Clears only the request a view actually handled. A newer request that
    /// arrived while the destination page was being installed must survive.
    func consumeDestinationRequest(id: UUID) {
        guard pendingDestinationRequest?.id == id else { return }
        pendingDestinationRequest = nil
    }
}

extension AppFeature {
    /// The hub itself is the honest fallback for features without a separate
    /// configuration surface, but linking a row back to its current page would
    /// present a chevron that appears to do nothing.
    var hasNavigableSettingsDestination: Bool {
        settingsDestination.page != .features
    }

    /// Exhaustive by design: adding an AppFeature requires choosing its
    /// Settings destination before the project compiles.
    var settingsDestination: FeatureSettingsDestination {
        switch self {
        case .switcher: return FeatureSettingsDestination(.switcher, sectionAnchor: .switcher)
        case .dockPreview: return FeatureSettingsDestination(.switcher, sectionAnchor: .dock)
        case .dockClick: return FeatureSettingsDestination(.switcher, sectionAnchor: .dockClick)
        case .windowMaximizer:
            return FeatureSettingsDestination(.general, sectionAnchor: .panelConfiguration)
        case .windowLayout: return FeatureSettingsDestination(.windowLayout)
        case .autoQuit: return FeatureSettingsDestination(.autoQuit)

        case .scrollInverter:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .scrollDirection)
        case .focusFollowsMouse:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .focusFollowsMouse)
        case .smoothScroll:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .smoothScroll)
        case .mouseNavigation:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .mouseNavigation)
        case .mouseButtonShortcuts:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .mouseButtonShortcuts)
        case .middleClick:
            return FeatureSettingsDestination(.mouse, sectionAnchor: .middleClick)
        case .keyboardDebounce: return FeatureSettingsDestination(.keyDebounce)
        case .textSnippets: return FeatureSettingsDestination(.textSnippets)
        case .superKey: return FeatureSettingsDestination(.superKey)

        case .clipboardHistory:
            return FeatureSettingsDestination(.clipboard, sectionAnchor: .clipboardHistory)
        case .pastePlain:
            return FeatureSettingsDestination(.clipboard, sectionAnchor: .pastePlain)
        case .finderCutPaste:
            return FeatureSettingsDestination(.cutPaste, sectionAnchor: .finderCutPaste)
        case .finderRename:
            return FeatureSettingsDestination(.cutPaste, sectionAnchor: .finderRename)
        case .shelf: return FeatureSettingsDestination(.shelf)
        case .urlCleaner: return FeatureSettingsDestination(.urlCleaner)
        case .diskImageInstaller: return FeatureSettingsDestination(.features)

        case .mixer:
            return FeatureSettingsDestination(.general, sectionAnchor: .panelConfiguration)
        case .soundOutputSwitcher:
            return FeatureSettingsDestination(.shortcuts, sectionAnchor: .soundOutputSwitcher)
        case .micMute:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .micMute)
        case .musicBlock:
            return FeatureSettingsDestination(.general, sectionAnchor: .musicBlocking)

        case .keepAwake:
            return FeatureSettingsDestination(.energy, sectionAnchor: .keepAwake)
        case .brightness:
            return FeatureSettingsDestination(.energy, sectionAnchor: .brightness)
        case .extraBrightness:
            return FeatureSettingsDestination(.energy, sectionAnchor: .extraBrightness)
        case .bluetoothSleep:
            return FeatureSettingsDestination(.energy, sectionAnchor: .bluetoothSleep)

        case .quickLauncher:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .quickLauncher)
        case .quickToggles:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .quickToggles)
        case .colorPicker:
            return FeatureSettingsDestination(.screenshot, sectionAnchor: .colorPicker)
        case .screenOCR:
            return FeatureSettingsDestination(.screenshot, sectionAnchor: .screenOCR)
        case .cleaningMode:
            return FeatureSettingsDestination(.general, sectionAnchor: .panelConfiguration)
        case .mediaTools: return FeatureSettingsDestination(.media)
        case .cleaner: return FeatureSettingsDestination(.cleaner)
        case .uninstaller: return FeatureSettingsDestination(.uninstaller)
        case .killProcess: return FeatureSettingsDestination(.killProcess)
        case .homebrew: return FeatureSettingsDestination(.homebrew)
        case .appUpdates: return FeatureSettingsDestination(.appUpdates)
        case .screenshot:
            return FeatureSettingsDestination(.screenshot, sectionAnchor: .screenshot)
        case .cameraPreview:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .cameraPreview)
        case .radialMenu: return FeatureSettingsDestination(.radialMenu)
        case .scratchpad:
            return FeatureSettingsDestination(.quickTools, sectionAnchor: .scratchpad)
        case .commandBar: return FeatureSettingsDestination(.commandBar)
        case .screenRecorder:
            return FeatureSettingsDestination(.screenshot, sectionAnchor: .screenRecorder)

        case .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower:
            return FeatureSettingsDestination(.monitor)
        case .fanControl:
            return FeatureSettingsDestination(.monitor, sectionAnchor: .fanControl)
        }
    }
}

/// Which hub features keep each Settings page alive. A page with several
/// features only disappears when ALL of them are switched off in the hub.
enum FeatureVisibilitySupport {
    static let monitorFeatures: [AppFeature] = [
        .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
        .fanControl,
    ]

    /// Features gating a page; empty means the page is part of the app and
    /// always shows (General, Shortcuts, About and friends).
    static func features(for page: SettingsPage) -> [AppFeature] {
        switch page {
        case .energy: return [.keepAwake, .brightness, .extraBrightness, .bluetoothSleep]
        case .monitor: return monitorFeatures
        case .mouse: return [.scrollInverter, .focusFollowsMouse, .smoothScroll, .mouseNavigation, .mouseButtonShortcuts,
                             .middleClick]
        case .switcher: return [.switcher, .dockPreview, .dockClick]
        case .windowLayout: return [.windowLayout]
        case .autoQuit: return [.autoQuit]
        case .clipboard: return [.clipboardHistory, .pastePlain, .finderCutPaste]
        case .cutPaste: return [.finderCutPaste, .finderRename]
        case .shelf: return [.shelf]
        case .media: return [.mediaTools]
        case .quickTools: return [.quickLauncher, .quickToggles, .micMute,
                                  .cameraPreview, .scratchpad]
        case .urlCleaner: return [.urlCleaner]
        case .cleaner: return [.cleaner]
        case .homebrew: return [.homebrew]
        case .appUpdates: return [.appUpdates]
        case .uninstaller: return [.uninstaller]
        case .killProcess: return [.killProcess]
        case .keyDebounce: return [.keyboardDebounce]
        case .superKey: return [.superKey]
        case .textSnippets: return [.textSnippets]
        case .screenshot: return [.screenshot, .screenRecorder, .screenOCR, .colorPicker]
        case .radialMenu: return [.radialMenu]
        case .commandBar: return [.commandBar]
        case .general, .features, .shortcuts, .advanced, .about, .releaseNotes, .support:
            return []
        }
    }

    static func isPageVisible(_ page: SettingsPage,
                              isAvailable: (AppFeature) -> Bool) -> Bool {
        let gate = features(for: page)
        return gate.isEmpty || gate.contains(where: isAvailable)
    }
}
