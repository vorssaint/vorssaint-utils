// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics

/// Layout Fix: a tap of the trigger key retypes the last word, or the
/// selection, in another enabled keyboard layout and switches to it. The key
/// tap, the observers and the buffer only exist while the feature is on.
/// Requires Accessibility (the tap and the field checks).
final class LayoutFixService: ObservableObject {
    static let shared = LayoutFixService()
    @Published private(set) var isRunning = false

    // The tap callback and its state live off the main thread, like Text
    // Snippets, so a busy app in front cannot hold up the keyboard.
    private let tapLifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingTapRestart = false

    /// Everything the tap reads and writes, mirrored behind one lock so the
    /// callback never asks AppKit or the text input server.
    private let inputLock = NSLock()
    private var buffer = LayoutFixBuffer()
    private var triggerState = LayoutFixTriggerState(trigger: .rightOption)
    private var currentLayoutID: String?
    /// One of Vorssaint's own windows takes the keys, such as a panel that
    /// never activates the app.
    private var ownWindowIsKey = false
    /// The app in front, mirrored for the tap: keys belong to the app they
    /// were typed in.
    private var frontmostProcessID: Int32 = 0

    // Main thread only.
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private(set) var layouts: [LayoutFixLayout] = []
    private(set) var recency: [String] = []

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.layoutFix.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.layoutFixEnabled)
        let trigger = LayoutFixTrigger.sanitized(UserDefaults.standard.string(forKey: DefaultsKey.layoutFixTrigger))
        inputLock.withLock {
            if triggerState.trigger != trigger { triggerState = LayoutFixTriggerState(trigger: trigger) }
        }
        MouseAppExceptions.shared.setSourceTracking(enabled, for: .layoutFix)
        if SessionActivitySupport.tapShouldRun(featureWanted: enabled,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            startObserving()
            start()
        } else {
            stop()
        }
    }

    func suspend() { stop() }

    // MARK: - Mirrors

    private func startObserving() {
        refreshLayouts()
        noteCurrentLayout()
        guard observers.isEmpty, distributedObservers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.append(distributed.addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in self?.noteCurrentLayout() })
        distributedObservers.append(distributed.addObserver(
            forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshLayouts() })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshLayouts() })
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in self?.noteOwnKeyWindow() })
        }
        // The keys stay with the app they were typed in: switching to another
        // desktop and back leaves the caret where it was. Typing in another
        // app starts over, and the Accessibility Keyboard types into the app
        // that was already in front.
        noteFrontmost(NSWorkspace.shared.frontmostApplication)
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.noteFrontmost(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        })
    }

    private func stopObserving() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        distributedObservers.removeAll()
    }

    /// The enabled layouts taking part, in the Input menu order.
    private func refreshLayouts() {
        let excluded = Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.layoutFixExcludedLayouts) ?? [])
        let refreshed = Self.enabledLayouts().filter { !excluded.contains($0.id) }
        if refreshed != layouts { layouts = refreshed }
    }

    /// Every enabled keyboard layout with its key tables. Input methods have
    /// no key table and are left out.
    static func enabledLayouts() -> [LayoutFixLayout] {
        InputSourceSelection.selectableInputSources().compactMap { source in
            guard InputSourceSelection.inputSourceString(source, property: kTISPropertyInputSourceType)
                    == kTISTypeKeyboardLayout as String,
                  let id = InputSourceSelection.inputSourceString(source, property: kTISPropertyInputSourceID),
                  let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else { return nil }
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
            let language = InputSourceSelection.languages(of: source).first?
                .split(separator: "-").first.map(String.init) ?? ""
            return LayoutFixLayout(id: id, language: language,
                                   table: LayoutFixSupport.table(from: data, capsLock: false),
                                   capsTable: LayoutFixSupport.table(from: data, capsLock: true),
                                   deadChords: LayoutFixSupport.deadChords(from: data))
        }
    }

    private func noteCurrentLayout() {
        guard let id = InputSourceSelection.currentSourceID() else { return }
        inputLock.withLock { currentLayoutID = id }
        noteRecent(id)
    }

    private func noteRecent(_ id: String) {
        recency.removeAll { $0 == id }
        recency.insert(id, at: 0)
    }

    private func noteFrontmost(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != AssistiveKeyboard.bundleID else { return }
        inputLock.withLock { frontmostProcessID = app.processIdentifier }
    }

    private func noteOwnKeyWindow() {
        let ownKey = NSApp.keyWindow != nil
        inputLock.withLock {
            ownWindowIsKey = ownKey
            buffer.apply(.reset, key: nil)
        }
    }

    private func resetBuffer() {
        inputLock.withLock { buffer.apply(.reset, key: nil) }
    }

    /// The buffer as the tap sees it now, for a trigger that does not come
    /// from the tap: the Super key solo action.
    func performExternalTrigger() {
        performFix(snapshot: inputLock.withLock { buffer })
    }

    // MARK: - Fixing (main thread)

    /// The taps on the word being fixed, and the buffer generation right
    /// after the last retype: any key typed since ends the cycle.
    private var cycle: LayoutFixCycle?
    private var cycleGeneration: UInt64?
    /// The cycle's word was typed before a click: only a field that shows it
    /// may be retyped.
    private var cycleNeedsFieldCheck = false

    /// Runs one fix on the main thread, once the trigger's modifiers are up:
    /// typed while ⌥ is still down, every character would come out as ⌥-text.
    func performFix(snapshot: LayoutFixBuffer) {
        whenModifiersUp(attempt: 0) { [weak self] in
            self?.fix(snapshot: snapshot)
        }
    }

    private func whenModifiersUp(attempt: Int, then work: @escaping () -> Void) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if held.isEmpty { return work() }
        guard attempt < 100 else { return NSSound.beep() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
            self?.whenModifiersUp(attempt: attempt + 1, then: work)
        }
    }

    private func fix(snapshot: LayoutFixBuffer) {
        let generation = snapshot.generation
        guard isRunning, !IsSecureEventInputEnabled(), NSApp.keyWindow == nil,
              let app = NSWorkspace.shared.frontmostApplication else { return }
        let exceptions = Set(MouseAppExceptions.shared.lists[.layoutFix] ?? [])
        guard !MouseAppExceptionSupport.isExcepted(app.bundleIdentifier, exceptions: exceptions) else { return }
        let processID = app.processIdentifier

        let now = inputLock.withLock { buffer.generation }
        if var current = cycle, cycleGeneration == now {
            let shown = current.shown
            let next = current.advance()
            retype(current, from: shown, to: next, processID: processID, generation: now,
                   needsFieldCheck: cycleNeedsFieldCheck)
            return
        }
        cycle = nil
        // Keys typed after the tap: the word it was meant for is gone.
        let fresh = now == generation
        let owner = inputLock.withLock { buffer.ownerProcessID }
        let word = fresh && owner == processID ? snapshot.wordForFix() : nil
        let field = SelectedTextReader.focusedTextSelection(processID: processID, timeout: 0.15,
                                                            includingCaret: true)
        // A range selection is one typing replaces; a web page selection
        // comes as text markers and has no range here. An inline completion
        // after the typed word belongs to the word.
        let wordText = word.flatMap { LayoutFixSupport.renderOriginal($0.word, layouts: layouts) }
            .map { $0 + String(repeating: " ", count: word?.trailingSpaces ?? 0) }
        let completion = field.map { field in
            wordText.map {
                LayoutFixSupport.isCompletion(selection: field.range, textLength: field.textLength,
                                              expected: $0, textBefore: field.text(in:))
            } ?? false
        } ?? false
        switch LayoutFixSupport.target(selectionLength: field?.range.length ?? 0,
                                       selectionFromTextMarkers: false,
                                       bundleID: app.bundleIdentifier,
                                       hasWord: word != nil,
                                       selectionIsCompletion: completion) {
        case .selection:
            if let selected = field.flatMap({ $0.text(in: $0.range) }),
               fixSelection(selected, generation: now) { return }
            NSSound.beep()
        case .lastWord:
            guard let word else { return }
            fixWord(word.word, trailingSpaces: word.trailingSpaces, processID: processID, generation: now,
                    needsFieldCheck: word.needsFieldCheck)
        case .nothing:
            // A stray tap of the key with nothing typed stays silent.
            break
        }
    }

    private func fixWord(_ word: [LayoutFixKey], trailingSpaces spaces: Int, processID: pid_t,
                         generation: UInt64, needsFieldCheck: Bool) {
        // A dead key composes two keys into one character: the counts differ.
        guard !LayoutFixSupport.containsDeadKey(word, layouts: layouts),
              let originalText = LayoutFixSupport.renderOriginal(word, layouts: layouts)
        else { return NSSound.beep() }
        let available = Set(NSSpellChecker.shared.availableLanguages)
        let candidates = LayoutFixSupport.candidates(keys: word, originalText: originalText,
                                                     layouts: layouts) { text, language in
            LayoutFixSupport.isWord(text, language: language, available: available, check: Self.spellCheck)
        }
        guard !candidates.isEmpty else { return NSSound.beep() }
        var started = LayoutFixCycle(keys: word, trailingSpaces: spaces,
                                     original: LayoutFixCandidate(text: originalText,
                                                                  layoutIDs: word.last.map { [$0.layoutID] } ?? []),
                                     candidates: candidates)
        let shown = started.shown
        let next = started.advance()
        retype(started, from: shown, to: next, processID: processID, generation: generation,
               needsFieldCheck: needsFieldCheck)
    }

    /// Types the best reading over the selection. Later taps continue from
    /// the typed text, which then sits right before the caret.
    private func fixSelection(_ text: String, generation: UInt64) -> Bool {
        let currentID = inputLock.withLock { currentLayoutID }
        let available = Set(NSSpellChecker.shared.availableLanguages)
        guard let found = LayoutFixSupport.selectionCandidates(text: text, layouts: layouts,
                                                               currentID: currentID, isWord: { text, language in
            LayoutFixSupport.isWord(text, language: language, available: available, check: Self.spellCheck)
        }), !found.candidates.isEmpty else { return false }
        var started = LayoutFixCycle(keys: [], trailingSpaces: 0, original: found.original,
                                     candidates: found.candidates)
        let next = started.advance()
        // A key typed while the field was asked replaced the selection already.
        guard inputLock.withLock({ buffer.generation }) == generation,
              TextSnippetService.postExpansion(deleteCount: 0, typedTrigger: "", text: next.text,
                                               trailingKeyCode: nil, trailingFlags: [],
                                               marker: OwnKeyEvent.layoutFixMarker) else { return false }
        let target = targetLayoutID(for: next)
        let switched = InputSourceSelection.select(sourceID: target)
        inputLock.withLock {
            // What was typed before the selection is no longer before the caret.
            buffer.apply(.reset, key: nil)
            if switched { currentLayoutID = target }
            cycleGeneration = buffer.generation
        }
        if switched { noteRecent(target) }
        cycle = started
        cycleNeedsFieldCheck = false
        return true
    }

    /// Replaces what the field shows with the next candidate, after checking
    /// that the field really ends with it, then switches the input source.
    private func retype(_ updated: LayoutFixCycle, from shown: LayoutFixCandidate,
                        to next: LayoutFixCandidate, processID: pid_t, generation: UInt64,
                        needsFieldCheck: Bool) {
        let spaces = String(repeating: " ", count: updated.trailingSpaces)
        let expected = shown.text + spaces
        let field = SelectedTextReader.focusedTextSelection(processID: processID, timeout: 0.15,
                                                            includingCaret: true)
        let check = LayoutFixSupport.fieldGuard(selection: field?.range, textLength: field?.textLength ?? 0,
                                                expected: expected) { field?.text(in: $0) }
        guard check != .mismatch, !(needsFieldCheck && check == .unknown) else { return abandon() }
        // Asking the field takes time; a key typed meanwhile sits after the
        // word, and the backspaces would take it instead.
        guard inputLock.withLock({ buffer.generation }) == generation else { return abandon() }
        let posted = TextSnippetService.postExpansion(deleteCount: shown.text.count + updated.trailingSpaces,
                                                      typedTrigger: expected,
                                                      text: next.text + spaces,
                                                      trailingKeyCode: nil,
                                                      trailingFlags: [],
                                                      marker: OwnKeyEvent.layoutFixMarker)
        guard posted else { return abandon() }
        let backToOriginal = next == updated.original
        let target = backToOriginal
            ? (updated.keys.last?.layoutID ?? updated.original.layoutIDs.first ?? "")
            : targetLayoutID(for: next)
        let switched = InputSourceSelection.select(sourceID: target)
        inputLock.withLock {
            if backToOriginal {
                buffer.restoreWord(updated.keys, trailingSpaces: updated.trailingSpaces)
            } else {
                buffer.relabelWord(count: updated.keys.count, trailingSpaces: updated.trailingSpaces,
                                   layoutID: target)
            }
            // The next keys are typed in the new layout even before the
            // system's change notification arrives.
            if switched { currentLayoutID = target }
            cycleGeneration = buffer.generation
        }
        if switched { noteRecent(target) }
        cycle = updated
        cycleNeedsFieldCheck = needsFieldCheck
    }

    /// The field is not what the buffer says: nothing is deleted, and the
    /// buffer starts over from here.
    private func abandon() {
        NSSound.beep()
        cycle = nil
        cycleGeneration = nil
        resetBuffer()
    }

    /// Where typing goes after `candidate`: a layout whose dictionary knows
    /// the word, else one without a dictionary (Kazakh), else the rest.
    private func targetLayoutID(for candidate: LayoutFixCandidate) -> String {
        let available = Set(NSSpellChecker.shared.availableLanguages)
        return LayoutFixSupport.targetLayoutID(for: candidate, recency: recency, layouts: layouts,
                                               isWord: { text, language in
                                                   LayoutFixSupport.isWord(text, language: language,
                                                                           available: available,
                                                                           check: Self.spellCheck)
                                               },
                                               hasDictionary: available.contains)
    }

    private static func spellCheck(_ text: String, language: String) -> Bool {
        NSSpellChecker.shared.checkSpelling(of: text, startingAt: 0, language: language, wrap: false,
                                            inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    }

    // MARK: - Tap lifecycle

    private func start() {
        let thread = tapLifecycleLock.withLock { () -> Thread? in
            if tapThread != nil {
                if shouldStopTapThread { pendingTapRestart = true }
                return nil
            }
            shouldStopTapThread = false
            pendingTapRestart = false
            let thread = Thread { [weak self] in self?.runEventTap() }
            thread.name = "Vorssaint Layout Fix"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return thread
        }
        thread?.start()
    }

    private func stop() {
        let snapshot = tapLifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool) in
            shouldStopTapThread = true
            pendingTapRestart = false
            return (tapRunLoop, tap, tapThread != nil)
        }
        if let tap = snapshot.tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            tapLifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
        stopObserving()
        resetBuffer()
        if isRunning { isRunning = false }
    }

    private func runEventTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            tapLifecycleLock.withLock { tapRunLoop = runLoop }
            guard !tapLifecycleLock.withLock({ shouldStopTapThread }) else {
                if clearEventTapThread() { startOnMain() }
                return
            }

            let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.rightMouseDown.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<LayoutFixService>.fromOpaque(userInfo).takeUnretainedValue()
                    service.handle(type: type, event: event)
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            tapLifecycleLock.withLock { self.tap = tap }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            DispatchQueue.main.async { [weak self] in self?.tapDidStart(tap) }

            if tapLifecycleLock.withLock({ shouldStopTapThread }) {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            if clearEventTapThread() { startOnMain() }
        }
    }

    private func clearEventTapThread() -> Bool {
        tapLifecycleLock.withLock {
            let shouldRestart = pendingTapRestart
            tap = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingTapRestart = false
            return shouldRestart
        }
    }

    private func startOnMain() {
        DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
    }

    private func tapDidStart(_ startedTap: CFMachPort) {
        let active = tapLifecycleLock.withLock { tap === startedTap && !shouldStopTapThread }
        if isRunning != active { isRunning = active }
    }

    // MARK: - Tap

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let currentTap = tapLifecycleLock.withLock { shouldStopTapThread ? nil : tap }
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            } else if currentTap != nil {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return
        }
        // Our own retype is already accounted for; anything else Vorssaint
        // types (a snippet expansion) changes the field behind the buffer.
        switch LayoutFixSupport.ownEvent(userData: event.getIntegerValueField(.eventSourceUserData),
                                         isPosted: OwnKeyEvent.isPosted(event)) {
        case .retype: return
        case .otherFeature: return resetBuffer()
        case .typing: break
        }
        if type == .leftMouseDown || type == .rightMouseDown {
            // A click on the Accessibility Keyboard types a key and leaves
            // the caret alone. Any other click may move it (in the text) or
            // not (a toolbar button): the word stays for a field check.
            guard !AssistiveKeyboard.ownsPoint(event.location) else { return }
            inputLock.withLock {
                buffer.noteClick()
                _ = triggerState.fires(.mouse)
            }
            return
        }
        // Password fields: nothing typed there is remembered.
        guard !IsSecureEventInputEnabled() else { return resetBuffer() }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        if type == .flagsChanged {
            let timestamp = EventTimestamp.nanoseconds(of: event)
            let down = Self.modifierIsDown(keyCode: keyCode, flags: flags)
            let fired = inputLock.withLock { () -> LayoutFixBuffer? in
                let event: LayoutFixTriggerEvent = down
                    ? .modifierDown(keyCode: keyCode, timestamp: timestamp)
                    : .modifierUp(keyCode: keyCode, timestamp: timestamp)
                return triggerState.fires(event) ? buffer : nil
            }
            if let fired {
                DispatchQueue.main.async { [weak self] in
                    self?.performFix(snapshot: fired)
                }
            }
            return
        }
        guard type == .keyDown else { return }
        // Keys typed into Vorssaint's own windows are not the app's text.
        guard !inputLock.withLock({ ownWindowIsKey }) else { return resetBuffer() }
        let action = LayoutFixSupport.bufferAction(keyCode: keyCode,
                                                   command: flags.contains(.maskCommand),
                                                   control: flags.contains(.maskControl))
        inputLock.withLock {
            _ = triggerState.fires(.otherKey)
            let key = LayoutFixKey(keyCode: UInt16(clamping: keyCode),
                                   shift: flags.contains(.maskShift),
                                   option: flags.contains(.maskAlternate),
                                   capsLock: flags.contains(.maskAlphaShift),
                                   layoutID: currentLayoutID ?? "")
            if action == .append { buffer.noteTyping(in: frontmostProcessID) }
            buffer.apply(action, key: action == .append ? key : nil)
        }
    }

    /// Whether a modifier key's flagsChanged event is its press. The flag of
    /// the key's own side is read where macOS reports it, so holding the left
    /// key does not make a tap of the right one look like a release.
    static func modifierIsDown(keyCode: Int, flags: CGEventFlags) -> Bool {
        let raw = flags.rawValue
        switch keyCode {
        case kVK_RightOption: return raw & UInt64(NX_DEVICERALTKEYMASK) != 0
        case kVK_Option: return raw & UInt64(NX_DEVICELALTKEYMASK) != 0
        case kVK_RightShift: return raw & UInt64(NX_DEVICERSHIFTKEYMASK) != 0
        case kVK_Shift: return raw & UInt64(NX_DEVICELSHIFTKEYMASK) != 0
        case kVK_RightCommand: return raw & UInt64(NX_DEVICERCMDKEYMASK) != 0
        case kVK_Command: return raw & UInt64(NX_DEVICELCMDKEYMASK) != 0
        case kVK_RightControl: return raw & UInt64(NX_DEVICERCTLKEYMASK) != 0
        case kVK_Control: return raw & UInt64(NX_DEVICELCTLKEYMASK) != 0
        default: return false
        }
    }
}
