// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import AVFoundation
import Carbon.HIToolbox
import CoreAudio
import CoreGraphics
import Foundation

/// Plays a sound for clicks, key presses and scroll notches in every app.
///
/// Input is heard through a listen-only tap, so nothing a user types or
/// clicks is delayed or changed. Only the kind of event is used: a key is
/// reduced to "letter, space, return, delete or modifier" the moment it
/// arrives, and nothing about input is stored, logged or sent. Keys stay
/// silent while a password field holds Secure Input.
final class InputSoundsService: ObservableObject {
    static let shared = InputSoundsService()

    @Published private(set) var isRunning = false

    private static let ownProcessID = Int64(getpid())
    private static let microphoneCheckInterval: TimeInterval = 1

    private let player = InputSoundPlayer()
    private let stateLock = NSLock()
    private var config = InputSoundsConfig()
    private var pressTracker = InputPressTracker()
    private var pressGeneration: UInt = 0
    private var scrollTicker = InputScrollTicker()
    private var combo = InputTypingCombo()
    private var desktopBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
    private var frontmostBundleID: String?
    private var observers: [NSObjectProtocol] = []

    // Touched only on the player's queue.
    private var microphoneInUse = false
    private var microphoneCheckedAt = Date.distantPast
    private var customBuffers: [InputSoundCustomSlot: AVAudioPCMBuffer] = [:]

    private lazy var tap = ListenOnlyEventTap(name: "Vorssaint Input Sounds") { [weak self] type, event in
        self?.handle(type: type, event: event)
    }

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    // MARK: Lifecycle

    func syncWithPreferences() {
        let nextConfig = InputSoundsConfig.load()
        let wanted = AppFeature.inputSounds.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.inputSoundsEnabled)
            && nextConfig.wantsAnything
        let shouldRun = SessionActivitySupport.tapShouldRun(
            featureWanted: wanted,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        )
        stateLock.withLock {
            config = nextConfig
            pressTracker.reset()
            scrollTicker.reset()
            combo.reset()
        }

        if shouldRun {
            installObservers()
            refreshDesktopBounds()
            let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            stateLock.withLock { frontmostBundleID = frontmost }
            tap.start(mask: InputSoundsSupport.eventMask(for: nextConfig))
            player.queue.async { [weak self] in
                self?.reloadCustomSounds()
                self?.prepareSounds(for: nextConfig)
            }
        } else {
            stop()
        }
        if isRunning != shouldRun { isRunning = shouldRun }
    }

    func suspend() {
        stop()
        if isRunning { isRunning = false }
    }

    private func stop() {
        removeObservers()
        tap.stop()
        player.queue.async { [weak self] in
            self?.player.shutDown()
        }
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                  object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.stateLock.withLock { self?.frontmostBundleID = app?.bundleIdentifier }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.suspend()
                self?.syncWithPreferences()
            },
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
                self?.refreshDesktopBounds()
            },
        ]
    }

    private func removeObservers() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    /// The union of every display in event coordinates, for stereo placement.
    private func refreshDesktopBounds() {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        let union = displays.prefix(Int(count)).map(CGDisplayBounds).reduce(CGRect.null) { $0.union($1) }
        stateLock.withLock {
            desktopBounds = union.isNull ? CGRect(x: 0, y: 0, width: 1, height: 1) : union
        }
    }

    // MARK: Events (tap thread)

    private func handle(type: CGEventType, event: CGEvent) {
        // Keys this app types itself (snippets, the Command Bar) stay silent.
        guard event.getIntegerValueField(.eventSourceUnixProcessID) != Self.ownProcessID else { return }
        let timestamp = EventTimestamp.nanoseconds(of: event)
        var cues: [InputSoundCue] = []
        var scheduleLongPress: UInt?
        let (current, pan) = stateLock.withLock { () -> (InputSoundsConfig, Float) in
            let pan = config.stereoEnabled
                ? InputSoundsSupport.pan(pointerX: event.location.x, across: desktopBounds) : 0
            return (config, pan)
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard current.clicksEnabled else { return }
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            let clickState = event.getIntegerValueField(.mouseEventClickState)
            if current.doubleClickEnabled, clickState == 2 {
                cues.append(.doubleClick)
            } else {
                cues.append(.clickPress(button: button))
            }
            if type == .leftMouseDown {
                scheduleLongPress = stateLock.withLock { () -> UInt? in
                    pressTracker.press(at: timestamp, point: event.location)
                    pressGeneration &+= 1
                    return current.longPressEnabled ? pressGeneration : nil
                }
            }
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            guard current.clicksEnabled else { return }
            if type == .leftMouseUp {
                let dragged = stateLock.withLock { () -> Bool in
                    pressGeneration &+= 1
                    return pressTracker.release()
                }
                if dragged, current.dragEnabled { cues.append(.drop) }
            }
            cues.append(.clickRelease(button: Int(event.getIntegerValueField(.mouseEventButtonNumber))))
        case .leftMouseDragged:
            guard current.clicksEnabled, current.dragEnabled else { return }
            let started = stateLock.withLock { pressTracker.drag(to: event.location) }
            if started { cues.append(.dragStart) }
        case .scrollWheel:
            guard current.scrollEnabled else { return }
            let vertical = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            let horizontal = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
            let delta = abs(vertical) >= abs(horizontal) ? vertical : horizontal
            let tick = stateLock.withLock {
                scrollTicker.shouldTick(
                    delta: delta,
                    isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
                    isMomentum: event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0,
                    timestamp: timestamp)
            }
            if tick { cues.append(.scrollTick) }
        case .keyDown, .keyUp:
            // A password field holds Secure Input; stay out of it entirely.
            guard !IsSecureEventInputEnabled() else { return }
            let kind = InputSoundsSupport.keyKind(keyCode: event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if type == .keyDown {
                guard !isRepeat else { return }
                if current.keyboardEnabled { cues.append(.key(kind, isRelease: false)) }
                if current.typingComboEnabled,
                   let step = stateLock.withLock({ combo.registerKey(at: timestamp) }) {
                    cues.append(.combo(step: step))
                }
            } else if current.keyboardEnabled {
                cues.append(.key(kind, isRelease: true))
            }
        case .flagsChanged:
            guard current.keyboardEnabled, current.modifierKeysEnabled, !IsSecureEventInputEnabled(),
                  let isDown = InputSoundsSupport.modifierIsDown(
                    keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags)
            else { return }
            cues.append(.key(.modifier, isRelease: !isDown))
        default:
            return
        }

        if !cues.isEmpty {
            let frontmost = stateLock.withLock { frontmostBundleID }
            player.queue.async { [weak self] in
                self?.play(cues, config: current, pan: pan, frontmostBundleID: frontmost)
            }
        }
        if let generation = scheduleLongPress {
            player.queue.asyncAfter(deadline: .now() + .nanoseconds(Int(InputPressTracker.longPressNanoseconds))) {
                [weak self] in
                guard let self else { return }
                let fire = self.stateLock.withLock { () -> Bool in
                    guard generation == self.pressGeneration else { return false }
                    return self.pressTracker.checkLongPress(now: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
                }
                guard fire else { return }
                let frontmost = self.stateLock.withLock { self.frontmostBundleID }
                self.play([.longPress], config: current, pan: pan, frontmostBundleID: frontmost)
            }
        }
    }

    // MARK: Playback (player queue)

    private func play(_ cues: [InputSoundCue], config: InputSoundsConfig, pan: Float, frontmostBundleID: String?) {
        if config.quietDuringMicrophone { refreshMicrophoneState() }
        guard !InputSoundsSupport.shouldStayQuiet(config: config,
                                                  frontmostBundleID: frontmostBundleID,
                                                  microphoneInUse: microphoneInUse) else { return }
        for cue in cues { play(cue, config: config, pan: pan) }
    }

    private func play(_ cue: InputSoundCue, config: InputSoundsConfig, pan: Float) {
        let clickVolume = Float(config.clickVolume)
        let keyVolume = Float(config.keyboardVolume)
        let clickPack = InputSoundLibrary.pack(id: config.clickPackID)
            ?? InputSoundLibrary.pack(id: InputSoundLibrary.defaultPackID)!
        let keyPack = InputSoundLibrary.pack(id: config.keyboardPackID) ?? clickPack

        switch cue {
        case .clickPress(let button), .clickRelease(let button):
            let isRelease: Bool
            if case .clickRelease = cue { isRelease = true } else { isRelease = false }
            if config.clickPackID == InputSoundsSupport.customPackID,
               let buffer = customBuffers[isRelease ? .release : .press] {
                player.play(buffer: buffer, volume: clickVolume, pan: pan)
                return
            }
            // A secondary click sits a little lower, so the two are easy to
            // tell apart by ear.
            let pitch = button == 1 ? 0.9 : 1
            player.play(key: "click.\(isRelease ? "release" : "press").\(clickPack.id).\(button == 1 ? 1 : 0)",
                        recipe: (isRelease ? clickPack.release : clickPack.press).adjusted(pitch: pitch),
                        volume: clickVolume, pan: pan)
        case .doubleClick:
            player.play(key: "double.\(clickPack.id)", recipe: InputSoundLibrary.doubleClick(clickPack),
                        volume: clickVolume, pan: pan)
        case .longPress:
            player.play(key: "longPress", recipe: InputSoundLibrary.longPress, volume: clickVolume, pan: pan)
        case .dragStart:
            player.play(key: "dragStart", recipe: InputSoundLibrary.dragStart, volume: clickVolume, pan: pan)
        case .drop:
            player.play(key: "drop", recipe: InputSoundLibrary.drop, volume: clickVolume, pan: pan)
        case .key(let kind, let isRelease):
            if config.keyboardPackID == InputSoundsSupport.customPackID,
               let buffer = customBuffers[isRelease ? .release : .press] {
                player.play(buffer: buffer, volume: keyVolume * (isRelease ? 0.7 : 1), pan: pan)
                return
            }
            player.play(key: "key.\(keyPack.id).\(kind).\(isRelease)",
                        recipe: InputSoundLibrary.keyRecipe(keyPack, kind: kind, isRelease: isRelease),
                        volume: keyVolume, pan: pan)
        case .scrollTick:
            if let buffer = customBuffers[.scroll], config.clickPackID == InputSoundsSupport.customPackID {
                player.play(buffer: buffer, volume: clickVolume, pan: pan)
                return
            }
            player.play(key: "scroll.\(config.scrollStyle.rawValue)", recipe: config.scrollStyle.recipe,
                        volume: clickVolume, pan: pan)
        case .combo(let step):
            player.play(key: "combo.\(step)", recipe: InputSoundLibrary.comboChime(step: step),
                        volume: keyVolume, pan: 0)
        }
    }

    private func prepareSounds(for config: InputSoundsConfig) {
        player.clearCache()
        if config.clicksEnabled, let pack = InputSoundLibrary.pack(id: config.clickPackID) {
            player.prepare(key: "click.press.\(pack.id).0", recipe: pack.press)
            player.prepare(key: "click.release.\(pack.id).0", recipe: pack.release)
        }
        if config.keyboardEnabled, let pack = InputSoundLibrary.pack(id: config.keyboardPackID) {
            player.prepare(key: "key.\(pack.id).\(InputKeyKind.regular).false",
                           recipe: InputSoundLibrary.keyRecipe(pack, kind: .regular, isRelease: false))
        }
    }

    /// Whether another app is recording from the default microphone. Read at
    /// most once a second; the microphone itself is never opened.
    private func refreshMicrophoneState() {
        guard Date().timeIntervalSince(microphoneCheckedAt) >= Self.microphoneCheckInterval else { return }
        microphoneCheckedAt = Date()
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                         &size, &device) == noErr,
              device != kAudioObjectUnknown else {
            microphoneInUse = false
            return
        }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        microphoneInUse = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr
            && running != 0
    }

    // MARK: Custom recordings

    private func reloadCustomSounds() {
        customBuffers.removeAll()
        for slot in InputSoundCustomSlot.allCases {
            if let url = InputSoundCustomStore.url(for: slot), let buffer = player.loadCustom(url: url) {
                customBuffers[slot] = buffer
            }
        }
    }

    /// Copies a recording in for `slot`, replacing any earlier one. False
    /// when the file is not audio this Mac can read.
    func importCustomSound(from url: URL, slot: InputSoundCustomSlot, completion: @escaping (Bool) -> Void) {
        player.queue.async { [weak self] in
            guard let self, self.player.loadCustom(url: url) != nil,
                  InputSoundCustomStore.save(from: url, slot: slot) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.reloadCustomSounds()
            DispatchQueue.main.async { completion(true) }
        }
    }

    func removeCustomSound(_ slot: InputSoundCustomSlot) {
        player.queue.async { [weak self] in
            InputSoundCustomStore.remove(slot)
            self?.reloadCustomSounds()
        }
    }

    // MARK: Previews (Settings)

    /// Plays a sound from Settings, whether or not input sounds are on.
    func preview(packID: String, keyboard: Bool) {
        let volume = Float(Defaults.sanitizedInputSoundsVolume(UserDefaults.standard.double(
            forKey: keyboard ? DefaultsKey.inputSoundsKeyboardVolume : DefaultsKey.inputSoundsVolume)))
        player.queue.async { [weak self] in
            guard let self else { return }
            if packID == InputSoundsSupport.customPackID {
                if self.customBuffers.isEmpty { self.reloadCustomSounds() }
                if let press = self.customBuffers[.press] {
                    self.player.play(buffer: press, volume: max(volume, 0.2), pan: 0)
                }
                return
            }
            guard let pack = InputSoundLibrary.pack(id: packID) else { return }
            let press = keyboard ? InputSoundLibrary.keyRecipe(pack, kind: .regular, isRelease: false) : pack.press
            let release = keyboard ? InputSoundLibrary.keyRecipe(pack, kind: .regular, isRelease: true) : pack.release
            self.player.play(key: "preview.press.\(packID).\(keyboard)", recipe: press,
                             volume: max(volume, 0.2), pan: 0)
            self.player.queue.asyncAfter(deadline: .now() + 0.09) {
                self.player.play(key: "preview.release.\(packID).\(keyboard)", recipe: release,
                                 volume: max(volume, 0.2), pan: 0)
            }
        }
    }

    func previewScroll(_ style: InputScrollStyle) {
        let volume = Float(Defaults.sanitizedInputSoundsVolume(
            UserDefaults.standard.double(forKey: DefaultsKey.inputSoundsVolume)))
        player.queue.async { [weak self] in
            guard let self else { return }
            for index in 0..<4 {
                self.player.queue.asyncAfter(deadline: .now() + 0.06 * Double(index)) {
                    self.player.play(key: "scroll.\(style.rawValue)", recipe: style.recipe,
                                     volume: max(volume, 0.2), pan: 0)
                }
            }
        }
    }
}

/// Where custom recordings live: the app's private Application Support
/// container, never leaving the Mac. Machine state, so backups leave it out.
enum InputSoundCustomStore {
    /// Large enough for any short sound, small enough to refuse a song.
    static let maximumFileBytes = 8 * 1_024 * 1_024

    static var directory: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("InputSounds", isDirectory: true)
    }

    static func url(for slot: InputSoundCustomSlot) -> URL? {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path),
              let name = names.first(where: { ($0 as NSString).deletingPathExtension == slot.rawValue })
        else { return nil }
        return directory.appendingPathComponent(name)
    }

    static func hasSound(for slot: InputSoundCustomSlot) -> Bool {
        url(for: slot) != nil
    }

    static func save(from source: URL, slot: InputSoundCustomSlot) -> Bool {
        guard let directory, PrivateFileStore.createDirectory(at: directory),
              let size = try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= maximumFileBytes,
              let data = try? Data(contentsOf: source) else { return false }
        remove(slot)
        let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension.lowercased()
        return PrivateFileStore.write(data, to: directory.appendingPathComponent("\(slot.rawValue).\(ext)"))
    }

    static func remove(_ slot: InputSoundCustomSlot) {
        while let url = url(for: slot) {
            guard (try? FileManager.default.removeItem(at: url)) != nil else { return }
        }
    }
}
