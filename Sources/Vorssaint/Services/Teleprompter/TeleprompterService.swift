// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Based on Textream by Fatih Kadir Akın (MIT License)

import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt
import SwiftUI

@MainActor
final class TeleprompterPreviewPlayback: ObservableObject {
    @Published var wordProgress: Double = 0
    @Published var pageIndex = 0
    @Published var isSpeaking = false
    @Published var isPaused = false
}

@MainActor
final class TeleprompterService: ObservableObject {
    static let shared = TeleprompterService()
    static let scrollSpeedRange = 0.25...3.0
    static let notchWindowWidthRange = 420.0...1000.0
    static let notchWindowHeightRange = 220.0...640.0

    @Published var isRunning: Bool = false {
        didSet { UserDefaults.standard.set(isRunning, forKey: DefaultsKey.teleprompterIsRunning) }
    }
    /// Shows a sample through the real notch prompter UI without starting a session.
    @Published private(set) var isPreviewingInNotch = false
    let previewPlayback = TeleprompterPreviewPlayback()
    @Published var isPaused: Bool = false
    @Published var text: String = "Welcome to Vorssaint Teleprompter.\n\nRead your script naturally while on camera. Words highlight in real time as you speak, powered by 100% on-device speech recognition."
    @Published var pages: [String] = []
    @Published var currentPageIndex: Int = 0
    @Published var readPages: Set<Int> = []
    @Published var pendingAddPageInSettings = false
    @Published var pendingEditPageIndexInSettings: Int?

    @Published var guidanceMode: GuidanceMode = .wordTracking {
        didSet {
            guard oldValue != guidanceMode, isRunning else { return }
            autoScrollTimer?.invalidate()
            autoScrollTimer = nil
            speechRecognizer.stop()
            if isPaused {
                restartSpeechOnResume = guidanceMode != .classic
                return
            }
            if guidanceMode == .classic {
                startAutoScrollTimer()
            } else {
                speechRecognizer.start(with: currentScript)
                startAutoScrollTimerIfNeeded()
            }
        }
    }
    @Published var scrollSpeed: Double = 2.5 {
        didSet {
            let bounded = Self.clampedScrollSpeed(scrollSpeed)
            if bounded != scrollSpeed { scrollSpeed = bounded }
        }
    }
    @Published var fontSize: TeleprompterFontSizePreset = .sm
    @Published var fontFamily: TeleprompterFontFamilyPreset = .sans
    @Published var highlightColor: TeleprompterHighlightColorPreset = .yellow
    @Published var cueColor: TeleprompterCueColorPreset = .yellow
    @Published var cueBrightness: TeleprompterCueBrightness = .medium
    @Published var windowWidth: Double = 560.0 {
        didSet {
            let range = Self.notchWindowWidthRange
            let bounded = min(range.upperBound, max(range.lowerBound, windowWidth))
            if bounded != windowWidth { windowWidth = bounded }
            if bounded != oldValue { updateNotchSurfaceSize() }
        }
    }
    @Published var windowHeight: Double = 280.0 {
        didSet {
            let range = Self.notchWindowHeightRange
            let bounded = min(range.upperBound, max(range.lowerBound, windowHeight))
            if bounded != windowHeight { windowHeight = bounded }
            if bounded != oldValue { updateNotchSurfaceSize() }
        }
    }
    @Published var readingPosition: TeleprompterReadingPosition = .centered
    @Published var showParagraphDividers: Bool = false
    @Published var showLastSpokenWords: Bool = true
    @Published var keepScreenAwake: Bool = true
    @Published var hideFromScreenSharing: Bool = true {
        didSet {
            guard oldValue != hideFromScreenSharing else { return }
            externalDisplayController.updateScreenCaptureVisibility(
                isHidden: isRunning && hideFromScreenSharing)
        }
    }
    @Published var focusNotchMode: Bool = true
    @Published var showElapsedTime: Bool = true
    @Published var autoNextPage: Bool = false
    @Published var speechLocale: String = "en-US"
    @Published var selectedMicUID: String = ""
    @Published var remoteServerEnabled: Bool = false
    @Published var timerWordProgress: Double = 0

    // Director and External Display
    @Published var directorServerEnabled: Bool = false
    @Published var externalDisplayMode: ExternalDisplayMode = .off
    @Published var externalMirrorAxis: ExternalMirrorAxis = .horizontal
    @Published var externalScreenID: UInt32 = 0

    let speechRecognizer = SpeechRecognizer()
    let remoteServer = TeleprompterServer()
    let directorServer = DirectorServer()
    let dictationManager = DictationManager()
    let externalDisplayController = ExternalDisplayController()

    private var autoScrollTimer: Timer?
    private var words: [String] = []
    private var cancellables = Set<AnyCancellable>()
    private let hotkey = QuickToolHotkey(id: 90)
    private var sleepAssertionID: IOPMAssertionID = 0
    private var elapsedTimer: Timer?
    private var notchPreviewIdleTask: Task<Void, Never>?
    private var previewProgressTimer: Timer?
    private var previewLastTickTime: TimeInterval?
    private var previewVoiceCycleTime: TimeInterval = 0
    private var restartSpeechOnResume = false

    static let previewPages = [
        "A quick brown fox jumps over the quiet fence, then follows the winding path toward the river. [PAUSE] The morning light catches every leaf as the breeze moves softly through the trees.",
        "Take a slow breath, look toward the camera, and let the next idea arrive naturally. [LOOK AT CAMERA] Speak clearly, keep a comfortable pace, and leave a little space between each thought.",
        "When the story reaches its final point, pause for a moment before continuing. A steady rhythm makes every sentence easier to follow. [SMILE]"
    ]
    static let previewScript = previewPages.joined(separator: "\n\n")
    var previewCurrentScript: String { Self.previewPages[previewPlayback.pageIndex] }

    @Published var sessionStartTime: Date? = nil
    @Published var elapsedSeconds: Int = 0

    var formattedElapsedTime: String {
        let mins = elapsedSeconds / 60
        let secs = elapsedSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    static func clampedScrollSpeed(_ speed: Double) -> Double {
        speed.isFinite ? min(scrollSpeedRange.upperBound, max(scrollSpeedRange.lowerBound, speed)) : 2.5
    }

    var currentScript: String {
        get {
            if !pages.isEmpty && currentPageIndex < pages.count {
                return pages[currentPageIndex]
            }
            return text
        }
        set {
            if pages.isEmpty {
                text = newValue
            } else if currentPageIndex < pages.count {
                pages[currentPageIndex] = newValue
            }
            savePreferences()
        }
    }

    var currentWords: [String] {
        splitTextIntoWords(currentScript)
    }

    var totalWordCount: Int {
        currentWords.count
    }

    var activeWordIndex: Int {
        let charCount = speechRecognizer.recognizedCharCount
        var cumulative = 0
        for (index, word) in currentWords.enumerated() {
            cumulative += word.count + 1
            if cumulative > charCount {
                return index
            }
        }
        return max(0, currentWords.count - 1)
    }

    private init() {
        UserDefaults.standard.set(false, forKey: DefaultsKey.teleprompterIsRunning)
        loadPreferences()
        setupObservers()
        syncWithPreferences()
    }

    func syncWithPreferences() {
        loadPreferences()

        let shortcut = GlobalShortcut.saved(for: DefaultsKey.teleprompterShortcut, fallback: .teleprompterDefault)
        let isEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.teleprompterEnabled)
        let shortcutEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.teleprompterShortcutEnabled)
        hotkey.onPress = { [weak self] in
            self?.toggle()
        }
        hotkey.sync(enabled: isEnabled && shortcutEnabled, shortcut: shortcut, storageKey: DefaultsKey.teleprompterShortcut)

        if remoteServerEnabled && !remoteServer.isRunning {
            remoteServer.start()
        } else if !remoteServerEnabled && remoteServer.isRunning {
            remoteServer.stop()
        }

        if directorServerEnabled && !directorServer.isRunning {
            directorServer.start()
        } else if !directorServerEnabled && directorServer.isRunning {
            directorServer.stop()
        }
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        if let savedText = defaults.string(forKey: DefaultsKey.teleprompterScriptText), !savedText.isEmpty {
            text = savedText
        }
        if let savedPages = defaults.stringArray(forKey: DefaultsKey.teleprompterPages), !savedPages.isEmpty {
            pages = savedPages
        }
        currentPageIndex = max(0, min(pages.isEmpty ? 0 : pages.count - 1, defaults.integer(forKey: DefaultsKey.teleprompterCurrentPageIndex)))

        if let modeStr = defaults.string(forKey: DefaultsKey.teleprompterGuidanceMode),
           let mode = GuidanceMode(rawValue: modeStr) {
            guidanceMode = mode
        }
        let speed = defaults.double(forKey: DefaultsKey.teleprompterScrollSpeed)
        if speed > 0 {
            scrollSpeed = speed
        }
        if let sizeStr = defaults.string(forKey: DefaultsKey.teleprompterFontSize),
           let size = TeleprompterFontSizePreset(rawValue: sizeStr) {
            fontSize = size
        }
        if let fontStr = defaults.string(forKey: DefaultsKey.teleprompterFontFamily),
           let family = TeleprompterFontFamilyPreset(rawValue: fontStr) {
            fontFamily = family
        }
        if let colorStr = defaults.string(forKey: DefaultsKey.teleprompterHighlightColor),
           let color = TeleprompterHighlightColorPreset(rawValue: colorStr) {
            highlightColor = color
        }
        if let cueStr = defaults.string(forKey: DefaultsKey.teleprompterCueColor),
           let cc = TeleprompterCueColorPreset(rawValue: cueStr) {
            cueColor = cc
        }
        if let brightStr = defaults.string(forKey: DefaultsKey.teleprompterCueBrightness),
           let cb = TeleprompterCueBrightness(rawValue: brightStr) {
            cueBrightness = cb
        }
        let w = defaults.double(forKey: DefaultsKey.teleprompterWidth)
        if w > 0 {
            let range = Self.notchWindowWidthRange
            windowWidth = min(range.upperBound, max(range.lowerBound, w))
        }
        let h = defaults.double(forKey: DefaultsKey.teleprompterHeight)
        if h > 0 {
            let range = Self.notchWindowHeightRange
            windowHeight = min(range.upperBound, max(range.lowerBound, h))
        }
        if let posStr = defaults.string(forKey: DefaultsKey.teleprompterReadingPosition),
           let rp = TeleprompterReadingPosition(rawValue: posStr) {
            readingPosition = rp
        }
        showParagraphDividers = defaults.bool(forKey: DefaultsKey.teleprompterShowParagraphDividers)
        if defaults.object(forKey: DefaultsKey.teleprompterShowLastSpokenWords) != nil {
            showLastSpokenWords = defaults.bool(forKey: DefaultsKey.teleprompterShowLastSpokenWords)
        }
        if defaults.object(forKey: DefaultsKey.teleprompterKeepScreenAwake) != nil {
            keepScreenAwake = defaults.bool(forKey: DefaultsKey.teleprompterKeepScreenAwake)
        }
        if defaults.object(forKey: DefaultsKey.teleprompterHideFromScreenSharing) != nil {
            hideFromScreenSharing = defaults.bool(forKey: DefaultsKey.teleprompterHideFromScreenSharing)
        }
        if defaults.object(forKey: DefaultsKey.teleprompterFocusNotch) != nil {
            focusNotchMode = defaults.bool(forKey: DefaultsKey.teleprompterFocusNotch)
        }
        if defaults.object(forKey: DefaultsKey.teleprompterShowElapsedTime) != nil {
            showElapsedTime = defaults.bool(forKey: DefaultsKey.teleprompterShowElapsedTime)
        }
        autoNextPage = defaults.bool(forKey: DefaultsKey.teleprompterAutoNextPage)
        if let locale = defaults.string(forKey: DefaultsKey.teleprompterSpeechLanguage), !locale.isEmpty {
            speechLocale = locale
        } else {
            speechLocale = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        }
        if let mic = defaults.string(forKey: DefaultsKey.teleprompterSelectedMicUID) {
            selectedMicUID = mic
        }
        remoteServerEnabled = defaults.bool(forKey: DefaultsKey.teleprompterRemoteServerEnabled)
        directorServerEnabled = defaults.bool(forKey: DefaultsKey.teleprompterDirectorServerEnabled)

        if let extModeStr = defaults.string(forKey: DefaultsKey.teleprompterExternalDisplayMode),
           let em = ExternalDisplayMode(rawValue: extModeStr) {
            externalDisplayMode = em
        }
        if let mirrorAxisStr = defaults.string(forKey: DefaultsKey.teleprompterExternalDisplayMirrorAxis),
           let ma = ExternalMirrorAxis(rawValue: mirrorAxisStr) {
            externalMirrorAxis = ma
        }
        externalScreenID = UInt32(defaults.integer(forKey: DefaultsKey.teleprompterExternalScreenID))
        loadPlacementProfile(for: "notch")
    }

    func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(text, forKey: DefaultsKey.teleprompterScriptText)
        if !pages.isEmpty {
            defaults.set(pages, forKey: DefaultsKey.teleprompterPages)
        }
        defaults.set(currentPageIndex, forKey: DefaultsKey.teleprompterCurrentPageIndex)
        defaults.set(guidanceMode.rawValue, forKey: DefaultsKey.teleprompterGuidanceMode)
        defaults.set(scrollSpeed, forKey: DefaultsKey.teleprompterScrollSpeed)
        defaults.set(fontSize.rawValue, forKey: DefaultsKey.teleprompterFontSize)
        defaults.set(fontFamily.rawValue, forKey: DefaultsKey.teleprompterFontFamily)
        defaults.set(highlightColor.rawValue, forKey: DefaultsKey.teleprompterHighlightColor)
        defaults.set(cueColor.rawValue, forKey: DefaultsKey.teleprompterCueColor)
        defaults.set(cueBrightness.rawValue, forKey: DefaultsKey.teleprompterCueBrightness)
        defaults.set(windowWidth, forKey: DefaultsKey.teleprompterWidth)
        defaults.set(windowHeight, forKey: DefaultsKey.teleprompterHeight)
        defaults.set(readingPosition.rawValue, forKey: DefaultsKey.teleprompterReadingPosition)
        defaults.set(showParagraphDividers, forKey: DefaultsKey.teleprompterShowParagraphDividers)
        defaults.set(showLastSpokenWords, forKey: DefaultsKey.teleprompterShowLastSpokenWords)
        defaults.set(keepScreenAwake, forKey: DefaultsKey.teleprompterKeepScreenAwake)
        defaults.set(hideFromScreenSharing, forKey: DefaultsKey.teleprompterHideFromScreenSharing)
        defaults.set(focusNotchMode, forKey: DefaultsKey.teleprompterFocusNotch)
        defaults.set(showElapsedTime, forKey: DefaultsKey.teleprompterShowElapsedTime)
        defaults.set(autoNextPage, forKey: DefaultsKey.teleprompterAutoNextPage)
        defaults.set(speechLocale, forKey: DefaultsKey.teleprompterSpeechLanguage)
        defaults.set(selectedMicUID, forKey: DefaultsKey.teleprompterSelectedMicUID)
        defaults.set(remoteServerEnabled, forKey: DefaultsKey.teleprompterRemoteServerEnabled)
        defaults.set(directorServerEnabled, forKey: DefaultsKey.teleprompterDirectorServerEnabled)
        defaults.set(externalDisplayMode.rawValue, forKey: DefaultsKey.teleprompterExternalDisplayMode)
        defaults.set(externalMirrorAxis.rawValue, forKey: DefaultsKey.teleprompterExternalDisplayMirrorAxis)
        defaults.set(Int(externalScreenID), forKey: DefaultsKey.teleprompterExternalScreenID)
        savePlacementProfile(for: "notch")
    }

    private func placementProfileKey(_ key: String, mode: String) -> String {
        "\(key).surface.\(mode)"
    }

    private func savePlacementProfile(for mode: String) {
        let defaults = UserDefaults.standard
        func set(_ value: Any, _ key: String) {
            defaults.set(value, forKey: placementProfileKey(key, mode: mode))
        }
        set(fontFamily.rawValue, DefaultsKey.teleprompterFontFamily)
        set(fontSize.rawValue, DefaultsKey.teleprompterFontSize)
        set(highlightColor.rawValue, DefaultsKey.teleprompterHighlightColor)
        set(cueColor.rawValue, DefaultsKey.teleprompterCueColor)
        set(cueBrightness.rawValue, DefaultsKey.teleprompterCueBrightness)
        set(guidanceMode.rawValue, DefaultsKey.teleprompterGuidanceMode)
        set(scrollSpeed, DefaultsKey.teleprompterScrollSpeed)
        set(readingPosition.rawValue, DefaultsKey.teleprompterReadingPosition)
        set(windowWidth, DefaultsKey.teleprompterWidth)
        set(windowHeight, DefaultsKey.teleprompterHeight)
        set(speechLocale, DefaultsKey.teleprompterSpeechLanguage)
        set(selectedMicUID, DefaultsKey.teleprompterSelectedMicUID)
    }

    private func loadPlacementProfile(for mode: String) {
        let defaults = UserDefaults.standard
        let guidanceKey = placementProfileKey(DefaultsKey.teleprompterGuidanceMode, mode: mode)
        guard defaults.object(forKey: guidanceKey) != nil else { return }
        func string(_ key: String) -> String? {
            defaults.string(forKey: placementProfileKey(key, mode: mode))
        }
        func number(_ key: String) -> Double? {
            let storedKey = placementProfileKey(key, mode: mode)
            return defaults.object(forKey: storedKey) == nil ? nil : defaults.double(forKey: storedKey)
        }
        if let raw = string(DefaultsKey.teleprompterFontFamily), let value = TeleprompterFontFamilyPreset(rawValue: raw) { fontFamily = value }
        if let raw = string(DefaultsKey.teleprompterFontSize), let value = TeleprompterFontSizePreset(rawValue: raw) { fontSize = value }
        if let raw = string(DefaultsKey.teleprompterHighlightColor), let value = TeleprompterHighlightColorPreset(rawValue: raw) { highlightColor = value }
        if let raw = string(DefaultsKey.teleprompterCueColor), let value = TeleprompterCueColorPreset(rawValue: raw) { cueColor = value }
        if let raw = string(DefaultsKey.teleprompterCueBrightness), let value = TeleprompterCueBrightness(rawValue: raw) { cueBrightness = value }
        if let raw = string(DefaultsKey.teleprompterGuidanceMode), let value = GuidanceMode(rawValue: raw) { guidanceMode = value }
        if let value = number(DefaultsKey.teleprompterScrollSpeed) { scrollSpeed = Self.clampedScrollSpeed(value) }
        if let raw = string(DefaultsKey.teleprompterReadingPosition), let value = TeleprompterReadingPosition(rawValue: raw) { readingPosition = value }
        if let value = number(DefaultsKey.teleprompterWidth) { windowWidth = value }
        if let value = number(DefaultsKey.teleprompterHeight) { windowHeight = value }
        if let locale = string(DefaultsKey.teleprompterSpeechLanguage) { speechLocale = locale }
        if let mic = string(DefaultsKey.teleprompterSelectedMicUID) { selectedMicUID = mic }
    }

    /// Resets all teleprompter options to defaults, preserving user scripts and pages.
    func resetSettings() {
        guidanceMode = .wordTracking
        scrollSpeed = 2.5
        fontSize = .sm
        fontFamily = .sans
        highlightColor = .yellow
        cueColor = .yellow
        cueBrightness = .medium
        windowWidth = 560.0
        windowHeight = 280.0
        readingPosition = .centered
        showParagraphDividers = false
        showLastSpokenWords = true
        keepScreenAwake = true
        focusNotchMode = true
        showElapsedTime = true
        autoNextPage = false
        externalDisplayMode = .off
        externalMirrorAxis = .horizontal
        remoteServerEnabled = false
        directorServerEnabled = false
        savePreferences()
    }

    private func setupObservers() {
        speechRecognizer.$shouldAdvancePage
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.speechRecognizer.shouldAdvancePage = false
                if self.autoNextPage {
                    self.nextPage()
                }
            }
            .store(in: &cancellables)

        speechRecognizer.$shouldDismiss
            .filter { $0 }
            .sink { [weak self] _ in
                self?.stop()
            }
            .store(in: &cancellables)

        // Director Server Callbacks
        directorServer.onSetText = { [weak self] newText in
            self?.handleDirectorSetText(newText)
        }

        directorServer.onUpdateText = { [weak self] newText, charCount in
            self?.handleDirectorUpdateText(newText, charCount: charCount)
        }

        directorServer.onStop = { [weak self] in
            self?.stop()
        }

        directorServer.onNextPage = { [weak self] in
            self?.nextPage()
        }

        directorServer.onPrevPage = { [weak self] in
            self?.previousPage()
        }
    }

    // MARK: - Director Server Command Handlers

    private func handleDirectorSetText(_ newText: String) {
        guard isRunning else { return }
        currentScript = newText
        words = splitTextIntoWords(newText)
        if isRunning && guidanceMode != .classic && !isPaused {
            speechRecognizer.start(with: newText)
        } else if isRunning && guidanceMode != .classic {
            restartSpeechOnResume = true
        }
        updateBroadcasts()
    }

    private func handleDirectorUpdateText(_ newText: String, charCount: Int) {
        guard isRunning else { return }
        currentScript = newText
        words = splitTextIntoWords(newText)
        speechRecognizer.updateText(newText, preservingCharCount: charCount)
        updateBroadcasts()
    }

    private func updateBroadcasts() {
        let script = currentScript
        let hasNext = currentPageIndex < pages.count - 1
        if remoteServerEnabled {
            remoteServer.updateContent(words: words, totalCharCount: script.count, hasNextPage: hasNext)
        }
        if directorServerEnabled {
            directorServer.updateContent(words: words, totalCharCount: script.count)
        }
    }

    // MARK: - Multi-page Management

    func addPage() {
        if pages.isEmpty {
            pages = [text, ""]
            currentPageIndex = 1
        } else {
            pages.append("")
            currentPageIndex = pages.count - 1
        }
        savePreferences()
    }

    func removePage(at index: Int) {
        guard !pages.isEmpty, index >= 0, index < pages.count else { return }
        pages.remove(at: index)
        if pages.isEmpty {
            pages = [""]
            currentPageIndex = 0
        } else {
            currentPageIndex = min(currentPageIndex, pages.count - 1)
        }
        savePreferences()
    }

    func jumpToPage(index: Int) {
        guard !pages.isEmpty, index >= 0, index < pages.count else { return }
        currentPageIndex = index
        readPages.insert(index)
        savePreferences()
        if isRunning {
            restartCurrentPage()
        }
    }

    // MARK: - Playback Control

    /// Open the notch's ready state without starting a reading session.
    /// Starting playback opens the same notch surface in running mode.
    func openPrompter() {
        endNotchPreview()
        presentNotchSurface()
    }

    private func presentNotchSurface() {
        updateNotchSurfaceSize()
        if NotchSupport.isEnabled() {
            NotchService.shared.open(.teleprompter)
        }
    }

    func previewInNotch(autoCloseAfter inactivityInterval: TimeInterval? = nil) {
        if isRunning {
            updateNotchSurfaceSize()
        }
        guard !isRunning else { return }
        let isChangingSurface = !isPreviewingInNotch
        if isChangingSurface {
            previewPlayback.wordProgress = 0
            previewPlayback.pageIndex = 0
            previewPlayback.isPaused = false
            previewPlayback.isSpeaking = guidanceMode == .wordTracking
            previewVoiceCycleTime = 0
        }
        isPreviewingInNotch = true
        if isChangingSurface || NotchService.shared.selected != .teleprompter || !NotchService.shared.expanded {
            presentNotchSurface()
        }
        startPreviewProgressTimerIfNeeded()

        notchPreviewIdleTask?.cancel()
        guard let inactivityInterval else { return }
        notchPreviewIdleTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0, inactivityInterval) * 1_000_000_000))
            } catch {
                return
            }
            guard let self, self.isPreviewingInNotch, !self.isRunning else { return }
            self.endNotchPreview()
            NotchService.shared.collapse()
        }
    }

    func endNotchPreview() {
        notchPreviewIdleTask?.cancel()
        notchPreviewIdleTask = nil
        previewProgressTimer?.invalidate()
        previewProgressTimer = nil
        previewLastTickTime = nil
        previewVoiceCycleTime = 0
        previewPlayback.isSpeaking = false
        previewPlayback.isPaused = false
        isPreviewingInNotch = false
        NotchService.shared.setTeleprompterSurfaceSize(nil)
    }

    func closeNotchPreview() {
        let wasNotchPreview = isPreviewingInNotch
        endNotchPreview()
        if wasNotchPreview && NotchService.shared.selected == .teleprompter {
            NotchService.shared.backFromTeleprompter()
        }
    }

    private func startPreviewProgressTimerIfNeeded() {
        guard previewProgressTimer == nil else { return }
        previewLastTickTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPreviewingInNotch else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let delta = min(0.1, max(0, now - (self.previewLastTickTime ?? now)))
                self.previewLastTickTime = now
                guard !self.previewPlayback.isPaused else {
                    self.previewPlayback.isSpeaking = false
                    return
                }
                let wordCount = max(1, splitTextIntoWords(self.previewCurrentScript).count)
                if self.guidanceMode == .voiceActivated {
                    self.previewVoiceCycleTime += delta
                    let phase = self.previewVoiceCycleTime.truncatingRemainder(dividingBy: 4.2)
                    self.previewPlayback.isSpeaking = phase < 3.0
                    guard self.previewPlayback.isSpeaking else { return }
                } else {
                    self.previewPlayback.isSpeaking = self.guidanceMode == .wordTracking
                }
                let rate = self.guidanceMode == .wordTracking ? 2.5 : self.scrollSpeed
                let next = self.previewPlayback.wordProgress + rate * delta
                if next >= Double(wordCount) {
                    if self.autoNextPage, self.previewPlayback.pageIndex < Self.previewPages.count - 1 {
                        self.nextPreviewPage()
                    } else {
                        self.previewPlayback.wordProgress = Double(wordCount)
                        self.previewPlayback.isSpeaking = false
                    }
                } else {
                    self.previewPlayback.wordProgress = next
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        previewProgressTimer = timer
    }

    func previousPreviewPage() {
        guard previewPlayback.pageIndex > 0 else { return }
        previewPlayback.pageIndex -= 1
        previewPlayback.wordProgress = 0
        previewVoiceCycleTime = 0
        previewLastTickTime = ProcessInfo.processInfo.systemUptime
        previewPlayback.isSpeaking = !previewPlayback.isPaused && guidanceMode == .wordTracking
    }

    func nextPreviewPage() {
        guard previewPlayback.pageIndex < Self.previewPages.count - 1 else { return }
        previewPlayback.pageIndex += 1
        previewPlayback.wordProgress = 0
        previewVoiceCycleTime = 0
        previewLastTickTime = ProcessInfo.processInfo.systemUptime
        previewPlayback.isSpeaking = !previewPlayback.isPaused && guidanceMode == .wordTracking
    }

    func togglePreviewPause() {
        guard isPreviewingInNotch, !isRunning else { return }
        previewPlayback.isPaused.toggle()
        previewLastTickTime = ProcessInfo.processInfo.systemUptime
        previewPlayback.isSpeaking = !previewPlayback.isPaused && guidanceMode == .wordTracking
    }

    private func updateNotchSurfaceSize() {
        guard isRunning || isPreviewingInNotch else {
            NotchService.shared.setTeleprompterSurfaceSize(nil)
            return
        }
        NotchService.shared.setTeleprompterSurfaceSize(
            CGSize(width: windowWidth, height: windowHeight)
        )
    }

    func toggle() {
        if isRunning {
            if isPaused {
                resume()
            } else {
                pause()
            }
        } else {
            start()
        }
    }

    func start() {
        guard !isRunning, NotchSupport.isEnabled() else { return }
        endNotchPreview()
        isRunning = true
        isPaused = false
        restartSpeechOnResume = false
        timerWordProgress = 0
        sessionStartTime = Date()
        elapsedSeconds = 0

        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, !self.isPaused else { return }
                self.elapsedSeconds += 1
            }
        }

        if keepScreenAwake {
            IOPMAssertionCreateWithName(
                "PreventUserIdleDisplaySleep" as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Vorssaint Teleprompter Session" as CFString,
                &sleepAssertionID
            )
        }

        let script = currentScript
        words = splitTextIntoWords(script)

        if guidanceMode == .classic {
            speechRecognizer.stop()
            startAutoScrollTimer()
        } else {
            speechRecognizer.start(with: script)
            startAutoScrollTimerIfNeeded()
        }

        let hasNext = currentPageIndex < pages.count - 1

        if remoteServerEnabled {
            if !remoteServer.isRunning {
                remoteServer.start()
            }
            remoteServer.showContent(
                speechRecognizer: speechRecognizer,
                words: words,
                totalCharCount: script.count,
                hasNextPage: hasNext
            )
        }

        if directorServerEnabled {
            if !directorServer.isRunning {
                directorServer.start()
            }
            directorServer.showContent(
                speechRecognizer: speechRecognizer,
                words: words,
                totalCharCount: script.count
            )
        }

        if externalDisplayMode != .off {
            externalDisplayController.show(
                speechRecognizer: speechRecognizer,
                words: words,
                script: script,
                mode: externalDisplayMode,
                mirrorAxis: externalMirrorAxis
            )
        }

        presentNotchSurface()
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        speechRecognizer.stop()
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        if guidanceMode == .classic {
            startAutoScrollTimer()
        } else if restartSpeechOnResume {
            speechRecognizer.start(with: currentScript)
            restartSpeechOnResume = false
            startAutoScrollTimerIfNeeded()
        } else {
            speechRecognizer.resume()
            startAutoScrollTimerIfNeeded()
        }
    }

    func stop() {
        endNotchPreview()
        isRunning = false
        isPaused = false
        restartSpeechOnResume = false
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        sessionStartTime = nil
        elapsedSeconds = 0

        if sleepAssertionID != 0 {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionID = 0
        }

        speechRecognizer.stop()
        remoteServer.hideContent()
        directorServer.hideContent()
        externalDisplayController.dismiss()
        if NotchService.shared.expanded && NotchService.shared.selected == .teleprompter {
            NotchService.shared.collapse()
        }
        readPages.insert(currentPageIndex)
    }

    func jumpTo(charOffset: Int) {
        speechRecognizer.jumpTo(charOffset: charOffset)
        timerWordProgress = wordProgressForCharOffset(charOffset)
    }

    func nextPage() {
        if isRunning { readPages.insert(currentPageIndex) }
        guard !pages.isEmpty, currentPageIndex < pages.count - 1 else {
            stop()
            return
        }
        currentPageIndex += 1
        timerWordProgress = 0
        restartCurrentPage()
    }

    func previousPage() {
        guard !pages.isEmpty, currentPageIndex > 0 else { return }
        currentPageIndex -= 1
        timerWordProgress = 0
        restartCurrentPage()
    }

    private func restartCurrentPage() {
        let script = currentScript
        words = splitTextIntoWords(script)
        timerWordProgress = 0
        if !isRunning || isPaused {
            speechRecognizer.stop()
            if isRunning && isPaused && guidanceMode != .classic {
                restartSpeechOnResume = true
            }
        } else if guidanceMode == .classic {
            speechRecognizer.stop()
            startAutoScrollTimer()
        } else {
            speechRecognizer.start(with: script)
            startAutoScrollTimerIfNeeded()
        }

        let hasNext = currentPageIndex < pages.count - 1
        if remoteServerEnabled {
            remoteServer.updateContent(
                words: words,
                totalCharCount: script.count,
                hasNextPage: hasNext
            )
        }
        if directorServerEnabled {
            directorServer.updateContent(
                words: words,
                totalCharCount: script.count
            )
        }
        if externalDisplayMode != .off {
            externalDisplayController.show(
                speechRecognizer: speechRecognizer,
                words: words,
                script: script,
                mode: externalDisplayMode,
                mirrorAxis: externalMirrorAxis
            )
        }
    }

    // MARK: - Word Progress & Auto Scroll Helpers

    func charOffsetForWordProgress(_ progress: Double) -> Int {
        let wholeWord = Int(progress)
        let frac = progress - Double(wholeWord)
        var offset = 0
        let w = currentWords
        for i in 0..<min(wholeWord, w.count) {
            offset += w[i].count + 1
        }
        if wholeWord < w.count {
            offset += Int(Double(w[wholeWord].count) * frac)
        }
        return min(offset, currentScript.count)
    }

    func wordProgressForCharOffset(_ charOffset: Int) -> Double {
        var offset = 0
        let w = currentWords
        for (i, word) in w.enumerated() {
            let end = offset + word.count
            if charOffset <= end {
                let frac = Double(charOffset - offset) / Double(max(1, word.count))
                return Double(i) + frac
            }
            offset = end + 1
        }
        return Double(w.count)
    }

    // MARK: - Auto Scroll for Classic and Voice-Activated Modes

    private func startAutoScrollTimer() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, !self.isPaused else { return }
                self.tickAutoScroll()
            }
        }
    }

    private func startAutoScrollTimerIfNeeded() {
        if guidanceMode != .wordTracking { startAutoScrollTimer() }
    }

    private func tickAutoScroll() {
        guard !currentWords.isEmpty else { return }

        if guidanceMode == .voiceActivated {
            guard speechRecognizer.isSpeaking else { return }
        }

        let speed = scrollSpeed // words per second
        timerWordProgress += speed * 0.05
        let nextChar = charOffsetForWordProgress(timerWordProgress)
        speechRecognizer.recognizedCharCount = nextChar

        if timerWordProgress >= Double(currentWords.count) {
            if autoNextPage && currentPageIndex < pages.count - 1 {
                nextPage()
            } else {
                stop()
            }
        }
    }

    // MARK: - Import Presentations

    func importPPTX(url: URL) throws {
        let extracted = try PresentationNotesExtractor.extractNotes(from: url)
        pages = extracted
        currentPageIndex = 0
        readPages.removeAll()
        if let first = pages.first {
            text = first
        }
        savePreferences()
    }
}
