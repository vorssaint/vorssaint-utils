// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum PanelHomebrewFilterPickerTests {
    private final class Model: ObservableObject {
        @Published var selection = PanelHomebrewFilter.all
    }

    private struct Fixture: View {
        @ObservedObject var model: Model
        let strings: Strings
        let casks: Int
        let formulae: Int

        var labels: [String] {
            ["\(strings.homebrewAll) \(casks + formulae)", "\(strings.homebrewCasks) \(casks)",
             "\(strings.homebrewFormulas) \(formulae)"]
        }

        var body: some View {
            PanelHomebrewFilterPicker(selection: $model.selection, strings: strings, totalCount: casks + formulae,
                                      caskCount: casks, formulaCount: formulae)
        }
    }

    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated { check(suite) }
    }

    @MainActor private static func check(_ suite: TestSuite) {
        _ = NSApplication.shared
        let attribute = "AXEnhancedUserInterface"
        let getter = NSSelectorFromString("accessibilityAttributeValue:")
        let setter = NSSelectorFromString("accessibilitySetValue:forAttribute:")
        let previous = NSApp.perform(getter, with: attribute)?.takeUnretainedValue() as? NSNumber ?? false
        NSApp.perform(setter, with: true, with: attribute)
        defer { NSApp.perform(setter, with: previous, with: attribute) }

        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 368, height: 120),
                              styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }

        let model = Model()
        func picker(_ strings: Strings, _ casks: Int, _ formulae: Int) -> Fixture {
            Fixture(model: model, strings: strings, casks: casks, formulae: formulae)
        }
        var host = NSHostingView(rootView: picker(.enUS, 0, 0))
        window.contentView = host
        func draw(_ view: Fixture, width: CGFloat) {
            host.rootView = view
            if window.contentLayoutRect.width != width {
                window.setContentSize(CGSize(width: width, height: 120))
            }
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            host.layoutSubtreeIfNeeded()
            suite.expect(abs(host.bounds.width - width) <= 1,
                         "the filter stays within \(width) pt, got \(host.bounds.width) pt for \(view.labels)")
        }
        func mount(_ view: Fixture, width: CGFloat) {
            host = NSHostingView(rootView: view)
            window.contentView = host
            draw(view, width: width)
        }

        // The card's content in the minimum custom island, menu and floating launcher.
        for (language, strings) in LocalizationTests.languages {
            for (casks, formulae) in [(0, 0), (27, 269), (1_234, 8_765)] {
                let view = picker(strings, casks, formulae)
                let labels = view.labels
                for width: CGFloat in [280, 288, 368] {
                    draw(view, width: width)
                    let context = "\(language.rawValue), \(labels), \(width) pt"
                    if let control = segments(in: host) {
                        let frame = control.convert(control.bounds, to: host)
                        let titles = (0..<control.segmentCount).map { control.label(forSegment: $0) }
                        suite.expect(titles == labels && control.accessibilityLabel() == strings.homebrewInstalled,
                                     "the native filter presents the full names and counts: \(context)")
                        suite.expect(control.segmentDistribution == .fit && frame.width >= control.intrinsicContentSize.width - 1
                                     && frame.minX >= -1 && frame.maxX <= width + 1,
                                     "the segments fit their labels and stay inside the card: \(context), "
                                     + "frame \(frame), intrinsic width \(control.intrinsicContentSize.width)")
                    } else {
                        checkRadios(in: host, window: window, title: strings.homebrewInstalled,
                                    labels: labels, suite: suite, context: context)
                    }
                }
            }
        }

        model.selection = .formula
        mount(picker(.enUS, 0, 0), width: 368)
        guard let native = segments(in: host) else {
            suite.expect(false, "the roomy Homebrew filter uses native segments")
            return
        }
        suite.expect(native.trackingMode == .selectOne && native.selectedSegment == PanelHomebrewFilter.formula.rawValue,
                     "the native filter follows the current selection")
        let focused = window.makeFirstResponder(native)
        suite.expect(focused && window.firstResponder === native,
                     "the mounted segments take keyboard focus before counts change")
        for (casks, formulae) in [(27, 269), (1_234, 8_765)] {
            let updated = picker(.enUS, casks, formulae)
            draw(updated, width: 368)
            let current = segments(in: host)
            suite.expect(current === native && window.firstResponder === native,
                         "refreshing counts to \(updated.labels) keeps the same control and its keyboard focus")
            let titles = (0..<native.segmentCount).compactMap { native.label(forSegment: $0) }
            suite.expect(titles == updated.labels && native.selectedSegment == PanelHomebrewFilter.formula.rawValue,
                         "the focused filter keeps the formula selection and shows \(updated.labels), got \(titles)")
        }
        native.selectedSegment = PanelHomebrewFilter.cask.rawValue
        suite.expect(native.sendAction(native.action, to: native.target) && model.selection == .cask,
                     "activating a segment selects its package kind")

        // A width that holds the longest individual title but forces the list.
        let strings = Strings.tr
        let changed = picker(strings, 1_234, 8_765)
        let labels = changed.labels
        draw(changed, width: 140)
        suite.expect(segments(in: host) == nil, "a narrow filter draws the radio choices")
        let choices = checkRadios(in: host, window: window, title: strings.homebrewInstalled,
                                  labels: labels, suite: suite, context: "narrow Turkish filter")
        func selectsOnly(_ title: String) -> Bool {
            let radios = Self.radios(in: host)
            return radios.count == 3 && radios.allSatisfy { radio in
                let selected = attributeValue("accessibilityValue", of: radio) as? NSNumber
                return selected?.boolValue == (name(radio) == title)
            }
        }
        suite.expect(selectsOnly(labels[1]), "the narrow filter exposes the selected cask option")
        let formula = choices.first { name($0) == labels[2] }
        // NSButtonCell can return false after delivering AXPress. Verify its effect on the binding and AX values.
        _ = formula?.accessibilityPerformPress?()
        draw(changed, width: 140)
        suite.expect(model.selection == .formula && selectsOnly(labels[2]),
                     "activating the narrow filter changes the selection and clears the previous radio")

        // A fresh host reads the current counts and selection when the panel opens again.
        mount(changed, width: 368)
        let reopened = segments(in: host)
        suite.expect(reopened?.selectedSegment == PanelHomebrewFilter.formula.rawValue
                     && reopened?.label(forSegment: 2) == labels[2],
                     "reopening the filter presents the selected kind and its refreshed count")

        // Find a width where freshly mounted versions differ on this macOS.
        // Only the counts change during the round trip in the final host.
        let usual = picker(strings, 27, 269)
        func drawsSegmentsWhenOpened(_ view: Fixture, at width: Int) -> Bool {
            mount(view, width: CGFloat(width))
            return segments(in: host) != nil
        }
        func firstSegmentedWidth(_ view: Fixture) -> Int {
            var low = 140, high = 368
            while low < high {
                let middle = (low + high) / 2
                if drawsSegmentsWhenOpened(view, at: middle) { high = middle }
                else { low = middle + 1 }
            }
            return low
        }
        var width = 280
        if !drawsSegmentsWhenOpened(usual, at: width) || drawsSegmentsWhenOpened(changed, at: width) {
            let usualMinimum = firstSegmentedWidth(usual)
            let changedMinimum = firstSegmentedWidth(changed)
            guard usualMinimum < changedMinimum else {
                suite.expect(false, "the shorter and longer Turkish counts need different segment widths, got "
                             + "\(usualMinimum) and \(changedMinimum) pt")
                return
            }
            width = (usualMinimum + changedMinimum - 1) / 2
        }
        model.selection = .cask
        mount(usual, width: CGFloat(width))
        suite.expect(segments(in: host)?.selectedSegment == PanelHomebrewFilter.cask.rawValue,
                     "the 296-package filter opens with the cask segment selected at \(width) pt")
        draw(changed, width: CGFloat(width))
        let refreshed = checkRadios(in: host, window: window, title: strings.homebrewInstalled, labels: changed.labels,
                                    suite: suite, context: "growing from 296 to 9999 packages at \(width) pt")
        suite.expect(segments(in: host) == nil && selectsOnly(changed.labels[1]),
                     "growing counts at \(width) pt switches to the radio group with casks still selected")
        _ = refreshed.first { name($0) == changed.labels[2] }?.accessibilityPerformPress?()
        draw(usual, width: CGFloat(width))
        let restored = segments(in: host)
        let restoredTitles = restored.map { control in
            (0..<control.segmentCount).compactMap { control.label(forSegment: $0) }
        }
        suite.expect(model.selection == .formula && restored?.selectedSegment == PanelHomebrewFilter.formula.rawValue
                     && restoredTitles == usual.labels, "shrinking counts at \(width) pt restores the segments with the "
                     + "selection made in the radio group and the current titles, got \(String(describing: restoredTitles))")

        checkFocusTransfers(suite, window: window, usual: usual, changed: changed, width: CGFloat(width))
    }

    private enum FieldFocus: CaseIterable {
        case keepFilterFocus, beforeUpdate, beforeLayout, afterLayout
    }

    @MainActor private static func checkFocusTransfers(_ suite: TestSuite, window: NSWindow,
                                                       usual: Fixture, changed: Fixture, width: CGFloat) {
        let size = CGSize(width: width, height: 180)
        let content = NSView(frame: CGRect(origin: .zero, size: size))
        window.contentView = content
        window.setContentSize(size)
        let host = NSHostingView(rootView: usual)
        host.frame = CGRect(x: 0, y: 30, width: width, height: 120)
        let before = NSTextField(string: "before filter")
        before.frame = CGRect(x: 0, y: 154, width: width, height: 24)
        let after = NSTextField(string: "package name")
        after.frame = CGRect(x: 0, y: 0, width: width, height: 24)
        content.addSubview(before)
        content.addSubview(host)
        content.addSubview(after)
        // The island hosts SwiftUI inside an AppKit panel with a fixed key view loop.
        window.autorecalculatesKeyViewLoop = false
        func settle() {
            content.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            content.layoutSubtreeIfNeeded()
        }
        func fieldHasFocus(_ field: NSTextField) -> Bool {
            if window.firstResponder === field { return true }
            guard let editor = field.currentEditor() else { return false }
            return window.firstResponder === editor
        }
        func moveToField(_ context: String) {
            suite.expect(window.makeFirstResponder(after) && fieldHasFocus(after), "the text field receives focus: \(context)")
        }
        func activeControl(radio: Bool) -> NSControl? {
            if radio {
                let title = changed.labels[PanelHomebrewFilter.cask.rawValue]
                return visibleControl(in: host) { (button: NSButton) in button.title == title && button.state == .on }
            }
            return segments(in: host)
        }
        func checkTabOrder(_ target: NSControl, _ context: String) {
            func filterHasFocus() -> Bool {
                (window.firstResponder as? NSControl)?.isDescendant(of: host) == true
            }
            for backwards in [false, true] {
                let key = backwards ? "Shift-Tab" : "Tab"
                let destination = backwards ? before : after
                if backwards { window.selectKeyView(preceding: after) }
                else { window.selectKeyView(following: before) }
                suite.expect(target.canBecomeKeyView ? filterHasFocus() : fieldHasFocus(destination),
                             "\(key) enters the filter when Keyboard navigation allows it: \(context)")

                // AppKit can visit each radio on the way out of the filter.
                suite.expect(window.makeFirstResponder(target) && window.firstResponder === target,
                             "the selected filter control has focus before pressing \(key): \(context)")
                for _ in PanelHomebrewFilter.allCases where filterHasFocus() {
                    if backwards { window.selectPreviousKeyView(nil) }
                    else { window.selectNextKeyView(nil) }
                }
                suite.expect(fieldHasFocus(destination), "\(key) reaches the neighboring field: \(context)")
            }
        }
        usual.model.selection = .cask
        settle()
        window.recalculateKeyViewLoop()
        if let segments = segments(in: host) { checkTabOrder(segments, "initial segments") }
        for timing in FieldFocus.allCases {
            for toRadio in [true, false] {
                let context = "\(toRadio ? "segments to radios" : "radios to segments"), \(timing), \(width) pt"
                if let source = activeControl(radio: !toRadio) {
                    suite.expect(window.makeFirstResponder(source) && window.firstResponder === source,
                                 "the source control takes keyboard focus: \(context)")
                } else {
                    suite.expect(false, "the source control is visible: \(context)")
                }
                if timing == .beforeUpdate { moveToField(context) }
                host.rootView = toRadio ? changed : usual
                if timing == .beforeLayout { moveToField(context) }
                host.layoutSubtreeIfNeeded()
                if timing == .afterLayout {
                    suite.expect(activeControl(radio: toRadio) != nil, "layout draws the new control before focus leaves: \(context)")
                    moveToField(context)
                }
                settle()
                guard let target = activeControl(radio: toRadio) else {
                    suite.expect(false, "the new control is visible: \(context)")
                    continue
                }
                let expected = timing == .keepFilterFocus ? window.firstResponder === target : fieldHasFocus(after)
                suite.expect(expected, "focus stays with the user's control: \(context), got \(String(describing: window.firstResponder))")
                if timing == .keepFilterFocus { checkTabOrder(target, context) }
            }
        }
    }

    @MainActor private static func segments(in view: NSView) -> NSSegmentedControl? {
        visibleControl(in: view) { (_: NSSegmentedControl) in true }
    }

    @MainActor private static func visibleControl<T: NSControl>(in view: NSView, matching: (T) -> Bool) -> T? {
        guard !view.isHidden else { return nil }
        if let control = view as? T, matching(control) { return control }
        for child in view.subviews {
            if let match = visibleControl(in: child, matching: matching) { return match }
        }
        return nil
    }

    @MainActor private static func radios(in element: AnyObject) -> [AnyObject] {
        if element.accessibilityRole?() == .radioButton { return [element] }
        return (element.accessibilityChildren?() ?? []).flatMap { radios(in: $0 as AnyObject) }
    }

    @MainActor private static func name(_ element: AnyObject) -> String? {
        if let label = element.accessibilityLabel?(), !label.isEmpty { return label }
        return attributeValue("accessibilityTitle", of: element) as? String
    }

    @MainActor private static func attributeValue(_ attribute: String, of element: AnyObject) -> AnyObject? {
        let selector = NSSelectorFromString(attribute)
        guard let object = element as? NSObject, object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue()
    }

    @MainActor @discardableResult
    private static func checkRadios(in host: NSView, window: NSWindow, title: String, labels: [String],
                                    suite: TestSuite, context: String) -> [AnyObject] {
        let choices = radios(in: host)
        let group = choices.first?.accessibilityParent?() as AnyObject?
        suite.expect(group?.accessibilityRole?() == .radioGroup && group.flatMap(name) == title,
                     "the radio buttons belong to the named installed filter: \(context)")
        suite.expect(choices.compactMap(name) == labels,
                     "the radio group exposes every name and count: \(context)")
        let bounds = window.convertToScreen(host.convert(host.bounds, to: nil))
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        var rows = [CGRect]()
        for choice in choices {
            let frame = choice.accessibilityFrame?() ?? .zero
            let title = (name(choice) ?? "") as NSString
            let textWidth = title.size(withAttributes: [.font: font]).width
            let separateRow = rows.allSatisfy { frame.maxY <= $0.minY + 1 || $0.maxY <= frame.minY + 1 }
            suite.expect(frame.height > 0 && bounds.insetBy(dx: -1, dy: -1).contains(frame)
                         && frame.width >= textWidth - 1 && separateRow,
                         "the full radio title fits on its own row: \(context), \(title)")
            rows.append(frame)
        }
        return choices
    }
}
