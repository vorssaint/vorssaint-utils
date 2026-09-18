// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum NotchGestureTests {
    static func run(expect: (Bool, String) -> Void) {
        nativeInteractionContracts(expect: expect)
        expect(NotchSupport.compactActivity(timer: true, downloads: true, music: true) == .timer
               && NotchSupport.compactActivity(timer: false, downloads: true, music: true) == .downloads
               && NotchSupport.compactActivity(timer: false, downloads: false, music: true) == .music
               && NotchSupport.compactActivity(timer: false, downloads: false, music: false) == nil,
               "rendering and gestures use the same compact activity priority")
        expect(!NotchSupport.gestureIsOverHeader(expanded: false, peeking: false, fromTop: 20, safeTop: 14)
               && NotchSupport.gestureIsOverHeader(expanded: true, peeking: false, fromTop: 20, safeTop: 14)
               && NotchSupport.gestureIsOverHeader(expanded: false, peeking: true, fromTop: 20, safeTop: 14),
               "a notchless compact strip has no invisible header blocking its lower half")
        var gesture = NotchGestureSupport()
        var time = 1.0
        func feed(_ x: Double = 0, _ y: Double = 0, began: Bool = false,
                  ended: Bool = false, momentum: Bool = false, precise: Bool = true, phased: Bool = true,
                  vertical: Bool = true, horizontal: Bool = true, expanded: Bool = false) -> NotchGestureSupport.Action? {
            time += 0.01
            return gesture.handle(x: x, y: y, timestamp: time, began: began, ended: ended,
                                  momentum: momentum, precise: precise, hasPhase: phased, allowVertical: vertical,
                                  allowHorizontal: horizontal, expanded: expanded)
        }
        expect(feed(0, 5, began: true) == nil && feed(0, 10) == nil && feed(0, 10) == .open,
               "small vertical movement accumulates into one intentional opening")
        expect(feed(0, -100, expanded: true) == nil,
               "the remainder of an opening gesture cannot immediately close the notch")
        expect(feed(0, 0, ended: true) == nil && feed(0, -80, momentum: true, expanded: true) == nil,
               "momentum after lifting the fingers never changes presentation")
        expect(feed(0, -30, began: true, expanded: true) == .close,
               "a separate upward gesture closes an expanded panel")
        expect(feed(-10, 0, began: true) == nil && feed(-15, 0) == nil && feed(-20, 0) == .nextTrack,
               "a left swipe changes one track after its threshold")
        for _ in 0..<100 { expect(feed(-50, 0) == nil, "one physical swipe never skips multiple tracks") }
        expect(feed(45, 0, began: true) == .previousTrack, "a right swipe selects the previous track")
        expect(feed(40, 40, began: true) == nil, "diagonal motion is not guessed as a track or panel gesture")
        expect(feed(-50, 0, began: true, horizontal: false) == nil,
               "lists, sliders and the navigation row can keep horizontal scrolling")
        expect(feed(0, -50, began: true, vertical: false, expanded: true) == nil,
               "scrolling a content list never collapses the notch")
        expect(feed(-50, 0, began: true, precise: false, phased: false) == nil,
               "an ordinary wheel tilt is not treated as a trackpad swipe")
        expect(feed(0, 24, began: true, precise: false, phased: false) == .open,
               "a discrete wheel step can open the notch")
        time += 0.4
        expect(feed(0, -24, precise: false, phased: false, expanded: true) == .close,
               "wheel sequences expire from their timestamps without a background timer")
        expect(feed(-45, 0, began: true) == .nextTrack, "a phased gesture can begin after a wheel sequence")
        time += 5
        expect(feed(-100, 0) == nil,
               "holding fingers still does not unlock a second track change in the same phased gesture")
        expect(feed(-15, 0, began: true) == nil, "a new phased gesture starts with its own distance")
        time += 5
        expect(feed(-30, 0) == .nextTrack,
               "a paused phased gesture retains its distance until its actual end")

        expect(feed(0, 0, began: true, vertical: false, horizontal: false, expanded: true) == nil,
               "a gesture that begins over a list or slider is recorded as ineligible")
        expect(feed(-80, 0, expanded: true) == nil && feed(0, -80, expanded: true) == nil,
               "moving from a list or slider onto music or the header cannot steal that phased scroll")
        time += 5
        expect(feed(-80, 0, expanded: true) == nil,
               "a pause cannot make an ineligible phased origin eligible")
        expect(feed(0, 0, ended: true) == nil && feed(-80, 0) == nil,
               "an ended or cancelled phased sequence cannot resume from an orphan changed event")
        expect(feed(-80, 0, began: true) == .nextTrack,
               "lifting fingers and starting again on music creates a new eligible gesture")
        expect(feed(0, 0, began: true, horizontal: false, expanded: true) == nil
               && feed(-80, 0, expanded: true) == nil,
               "a header origin does not acquire horizontal navigation after entering the player")
        expect(feed(-15, 0, began: true, vertical: false, expanded: true) == nil
               && feed(0, -80, expanded: true) == nil,
               "a horizontal player origin does not acquire collapse behavior after entering the header")
        expect(feed(-30, 0, vertical: false, horizontal: false, expanded: true) == .nextTrack,
               "an eligible phased scroll remains attached to its original surface as the pointer moves")

        expect(feed(-15, 0, began: true) == nil, "interruption fixture begins below the threshold")
        gesture = NotchGestureSupport()
        expect(feed(-80, 0) == nil,
               "discarding a sequence for exit, modifiers, capture, or suspension rejects its continued events")
        expect(feed(-80, 0, began: true) == .nextTrack,
               "a fresh physical gesture works after an interruption")
        expect(feed(-15, 0, began: true) == nil, "clock-regression fixture begins below the threshold")
        time -= 1
        expect(feed(-80, 0) == nil, "an out-of-order event discards a phased gesture")
        time += 1
        expect(feed(-80, 0) == nil, "ordered changed events cannot revive a discarded phased gesture")
        expect(feed(-15, 0, began: true) == nil && feed(-80, 0, momentum: true, phased: false) == nil
               && feed(-80, 0, momentum: true, phased: false) == nil && feed(-80, 0) == nil,
               "momentum never finishes a partial navigation or leaves a resumable phased sequence")
        expect(feed(0, 24, precise: false, phased: false) == .open,
               "a real wheel event after momentum can start an independent sequence")
        time += 0.4
        expect(feed(0, -24, precise: true, phased: false, expanded: true) == .close,
               "high-resolution devices without phases still use timestamp-based wheel expiration")
        expect(feed(0, 0, began: true, expanded: false) == nil
               && feed(0, -30, expanded: true) == nil,
               "an external presentation change cannot reverse the vertical action chosen by its origin")
        expect(feed(.nan, 0, began: true) == nil && feed(.infinity, 0) == nil,
               "malformed deltas never produce a gesture")
        expect(feed(-80, 0) == nil, "invalid timing or movement cannot restart a phased gesture midway")
        expect(NotchGestureSupport.movement(3, precise: true, inverted: true) == 3
               && NotchGestureSupport.movement(-3, precise: true, inverted: false) == 3
               && NotchGestureSupport.movement(-1, precise: false, inverted: false) == 24,
               "gesture direction is consistent across natural scrolling and wheel devices")

        let suite = "com.vorssaint.tests.notch-gestures"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        expect(NotchGestureSupport.isEnabled(in: defaults), "gestures start enabled with the island")
        defaults.set(false, forKey: DefaultsKey.notchGesturesEnabled)
        expect(!NotchGestureSupport.isEnabled(in: defaults), "gestures retain an independent opt-out")
        defaults.set(true, forKey: DefaultsKey.notchGesturesEnabled)
        defaults.set(false, forKey: AppFeature.notchGestures.availabilityKey)
        expect(!NotchGestureSupport.isEnabled(in: defaults), "removing gestures from the hub clears their handler")
        defaults.set(true, forKey: AppFeature.notchGestures.availabilityKey)
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        expect(!NotchGestureSupport.isEnabled(in: defaults), "gestures cannot keep the master notch alive")
        expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.notchGesturesEnabled,
                                                                 AppFeature.notchGestures.availabilityKey]),
               "gesture preferences travel in backup")
        expect(AppFeature.notchGestures.permissions.isEmpty, "window-local gestures need no global input permission")
    }

    private static func nativeInteractionContracts(expect: (Bool, String) -> Void) {
        // Native hit testing only; no windows are shown and no input is sent.
        let surface = NSView(frame: CGRect(x: 0, y: 0, width: 180, height: 32))
        let activation = NotchActivationButton(frame: surface.bounds)
        activation.isTransparent = true
        surface.addSubview(activation)
        let target = surface.hitTest(CGPoint(x: 90, y: 16))
        let interaction = NotchGestureSupport.nativeInteraction(at: target)
        expect(target === activation && !interaction.control && !interaction.scroll,
               "the transparent resting button remains clickable without blocking gestures")
        var gesture = NotchGestureSupport()
        expect(gesture.handle(x: 0, y: 40, timestamp: 1, began: true, ended: false,
                              momentum: false, precise: true, hasPhase: true,
                              allowVertical: !interaction.control, allowHorizontal: false, expanded: false) == .open,
               "a gesture beginning on the native resting button can open the notch")

        for control in [NSButton(), NSSlider(), NSTextField(), NSTextView()] as [NSView] {
            let child = NSView()
            control.addSubview(child)
            expect(NotchGestureSupport.nativeInteraction(at: child).control,
                   "real controls and their descendants retain their own input")
        }
        let scroll = NSScrollView()
        let content = NSView()
        scroll.documentView = content
        expect(NotchGestureSupport.nativeInteraction(at: content).scroll,
               "scrolling content stays recognized through its native ancestors")
        let empty = NotchGestureSupport.nativeInteraction(at: nil)
        expect(!empty.control && !empty.scroll, "an absent hit target creates no imaginary control")
    }
}
