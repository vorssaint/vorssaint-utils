// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Exercises the closed-lid screen-dimming decisions and their IOKit-backed
/// observer through the same production bodies and fake IOKit as the rest of
/// the closed-lid suite. `C.reset()` leaves the fixture lid closed, so every
/// scenario here opens it before arming, closing again is what triggers dimming.
enum KeepAwakeDimmingTests {
    private typealias C = KeepAwakeLidSleepContract

    /// A session with the option armed and the lid open, ready to be closed.
    private static func armed(reading: Double? = 0.6) -> C.Service {
        let service = C.reset()
        C.BrightnessService.lid = false
        service.isActive = true
        service.clamshellActive = true
        C.LidDisplayDimmer.reading = reading
        service.dimScreenOnLidClose = true
        return service
    }

    static func run(expect: (Bool, String) -> Void) {
        let alreadyClosed = C.reset()
        alreadyClosed.isActive = true
        alreadyClosed.clamshellActive = true
        C.LidDisplayDimmer.reading = 0.7
        alreadyClosed.dimScreenOnLidClose = true
        expect(C.LidDisplayDimmer.written == [0]
               && alreadyClosed.savedDisplayBrightness == 0.7,
               "enabling dimming with the lid already closed dims without waiting for another lid event")

        let closing = armed()
        C.BrightnessService.lid = true
        C.DimmingObserver.callback?()
        C.drain()
        expect(C.LidDisplayDimmer.written == [0] && closing.savedDisplayBrightness == 0.6
               && C.UserDefaults.standard.doubles[C.DefaultsKey.dimmedDisplaySavedBrightness] == 0.6,
               "closing the lid saves the current brightness and dims the panel to zero")

        for reading in [0.0, nil] as [Double?] {
            let unreadable = armed(reading: reading)
            C.BrightnessService.lid = true
            C.DimmingObserver.callback?()
            C.drain()
            expect(C.LidDisplayDimmer.written.isEmpty && unreadable.savedDisplayBrightness == nil
                   && C.UserDefaults.standard.doubles[C.DefaultsKey.dimmedDisplaySavedBrightness] == nil,
                   "a panel that already reads asleep is left alone instead of being saved as zero")
        }

        let opening = armed()
        C.BrightnessService.lid = true
        C.DimmingObserver.callback?()
        C.drain()
        C.BrightnessService.lid = false
        C.DimmingObserver.callback?()
        C.drain()
        expect(C.LidDisplayDimmer.written == [0, 0.6] && opening.savedDisplayBrightness == nil
               && C.UserDefaults.standard.doubles[C.DefaultsKey.dimmedDisplaySavedBrightness] == nil,
               "opening the lid restores the saved brightness and clears the recovery marker")

        let toggledOff = armed()
        C.BrightnessService.lid = true
        C.DimmingObserver.callback?()
        C.drain()
        toggledOff.dimScreenOnLidClose = false
        expect(C.LidDisplayDimmer.written == [0, 0.6] && toggledOff.savedDisplayBrightness == nil,
               "switching the option off while dimmed restores at once, without waiting for the lid to open")

        let sessionEnded = armed()
        C.BrightnessService.lid = true
        C.DimmingObserver.callback?()
        C.drain()
        sessionEnded.clamshellActive = false
        expect(C.LidDisplayDimmer.written == [0, 0.6] && sessionEnded.savedDisplayBrightness == nil,
               "the closed-lid session ending while dimmed restores without waiting for the lid to open")

        let tornDown = armed()
        C.BrightnessService.lid = true
        C.DimmingObserver.callback?()
        C.drain()
        let stale = C.DimmingObserver.callback
        tornDown.dimScreenOnLidClose = false
        C.LidDisplayDimmer.written = []
        stale?()
        C.drain()
        expect(C.LidDisplayDimmer.written.isEmpty,
               "a lid notification that lands after the mode already ended changes nothing")

        let recovering = C.reset()
        C.UserDefaults.standard.set(0.4, forKey: C.DefaultsKey.dimmedDisplaySavedBrightness)
        recovering.recoverDimmedDisplayIfNeeded()
        expect(C.LidDisplayDimmer.written == [0.4]
               && C.UserDefaults.standard.doubles[C.DefaultsKey.dimmedDisplaySavedBrightness] == nil,
               "a brightness saved before a crash is restored and cleared on the next launch")

        let nothingToRecover = C.reset()
        nothingToRecover.recoverDimmedDisplayIfNeeded()
        expect(C.LidDisplayDimmer.written.isEmpty, "launch recovery does nothing when no brightness was saved")

        // A restore that briefly finds no panel — right as the lid opens —
        // keeps the saved level instead of clearing it on a merely attempted
        // write, and a queued retry completes it once the panel is back.
        let retrying = armed()
        C.BrightnessService.lid = true
        C.DimmingObserver.callback?()
        C.drain()
        C.LidDisplayDimmer.writeSucceeds = false
        C.BrightnessService.lid = false
        C.DimmingObserver.callback?()
        C.drain()
        expect(C.LidDisplayDimmer.written == [0] && retrying.savedDisplayBrightness == 0.6
               && C.UserDefaults.standard.doubles[C.DefaultsKey.dimmedDisplaySavedBrightness] == 0.6,
               "a restore that finds no panel yet keeps the saved level and its marker instead of clearing them")
        C.LidDisplayDimmer.writeSucceeds = true
        C.DispatchQueue.main.advance()
        expect(C.LidDisplayDimmer.written == [0, 0.6] && retrying.savedDisplayBrightness == nil,
               "the queued retry restores it once the panel answers, with no further lid event needed")

        // Exhausting every retry while the option is switched off keeps the
        // lid observer armed instead of tearing it down, so a later real
        // lid-open event still gets a chance to finish the restore.
        let exhausted = armed()
        C.BrightnessService.lid = true
        C.DimmingObserver.callback?()
        C.drain()
        C.LidDisplayDimmer.writeSucceeds = false
        exhausted.dimScreenOnLidClose = false
        for _ in 0..<8 { C.DispatchQueue.main.advance() }
        expect(C.LidDisplayDimmer.written == [0] && exhausted.savedDisplayBrightness == 0.6
               && C.UserDefaults.standard.doubles[C.DefaultsKey.dimmedDisplaySavedBrightness] == 0.6
               && C.DimmingObserver.destroyedPorts == 0,
               "exhausting the retries after the option is switched off still owes the restore and keeps watching the lid")
        C.LidDisplayDimmer.writeSucceeds = true
        C.BrightnessService.lid = false
        C.DimmingObserver.callback?()
        C.drain()
        expect(C.LidDisplayDimmer.written == [0, 0.6] && exhausted.savedDisplayBrightness == nil
               && C.DimmingObserver.destroyedPorts == 1,
               "the lid actually opening finishes the owed restore and only then releases the observer")
    }
}
