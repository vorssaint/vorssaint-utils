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
            window.setContentSize(CGSize(width: width, height: 120))
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            host.layoutSubtreeIfNeeded()
            suite.expect(abs(host.bounds.width - width) <= 1, "the filter stays within its offered width of \(width) pt")
        }

        // The card's content in the minimum custom island, menu and floating launcher.
        for (language, strings) in LocalizationTests.languages {
            for (casks, formulae) in [(0, 0), (27, 269), (1_234, 8_765)] {
                let labels = ["\(strings.homebrewAll) \(casks + formulae)", "\(strings.homebrewCasks) \(casks)",
                              "\(strings.homebrewFormulas) \(formulae)"]
                for width: CGFloat in [280, 288, 368] {
                    draw(picker(strings, casks, formulae), width: width)
                    let context = "\(language.rawValue), \(labels), \(width) pt"
                    if let control = segments(in: host) {
                        let frame = control.convert(control.bounds, to: host)
                        let titles = (0..<control.segmentCount).map { control.label(forSegment: $0) }
                        suite.expect(titles == labels && control.accessibilityLabel() == strings.homebrewInstalled,
                                     "the native filter presents the full names and counts: \(context)")
                        suite.expect(control.segmentDistribution == .fit && frame.width >= control.intrinsicContentSize.width - 1
                                     && frame.minX >= -1 && frame.maxX <= width + 1,
                                     "the segments fit their labels and stay inside the card: \(context)")
                    } else {
                        checkRadios(in: host, window: window, labels: labels, suite: suite, context: context)
                    }
                }
            }
        }

        model.selection = .formula
        draw(picker(.enUS, 27, 269), width: 368)
        guard let native = segments(in: host) else {
            suite.expect(false, "the roomy Homebrew filter uses native segments")
            return
        }
        suite.expect(native.trackingMode == .selectOne && native.selectedSegment == PanelHomebrewFilter.formula.rawValue,
                     "the native filter follows the current selection")
        native.selectedSegment = PanelHomebrewFilter.cask.rawValue
        suite.expect(native.sendAction(native.action, to: native.target) && model.selection == .cask,
                     "activating a segment selects its package kind")

        // A width that holds the longest individual title but forces the list.
        let strings = Strings.tr
        let changed = picker(strings, 1_234, 8_765)
        let labels = ["\(strings.homebrewAll) 9999", "\(strings.homebrewCasks) 1234", "\(strings.homebrewFormulas) 8765"]
        draw(changed, width: 140)
        suite.expect(segments(in: host) == nil, "a narrow filter draws the radio choices")
        let choices = checkRadios(in: host, window: window, labels: labels, suite: suite, context: "narrow Turkish filter")
        func selectsOnly(_ title: String) -> Bool {
            let radios = Self.radios(in: host)
            return radios.count == 3 && radios.allSatisfy { radio in
                let selected = attributeValue("accessibilityValue", of: radio) as? NSNumber
                return selected?.boolValue == (name(radio) == title)
            }
        }
        suite.expect(selectsOnly(labels[1]), "the narrow filter exposes the selected cask option")
        let formula = choices.first { name($0) == labels[2] }
        let pressed = formula?.accessibilityPerformPress?() ?? false
        draw(changed, width: 140)
        suite.expect(pressed && model.selection == .formula && selectsOnly(labels[2]),
                     "activating the narrow filter changes the selection and clears the previous radio")

        // A fresh host reads the current counts and selection when the panel opens again.
        host = NSHostingView(rootView: changed)
        window.contentView = host
        draw(changed, width: 368)
        let reopened = segments(in: host)
        suite.expect(reopened?.selectedSegment == PanelHomebrewFilter.formula.rawValue
                     && reopened?.label(forSegment: 2) == labels[2],
                     "reopening the filter presents the selected kind and its refreshed count")
    }

    @MainActor private static func segments(in view: NSView) -> NSSegmentedControl? {
        if let control = view as? NSSegmentedControl { return control }
        return view.subviews.lazy.compactMap { segments(in: $0) }.first
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
    private static func checkRadios(in host: NSView, window: NSWindow, labels: [String],
                                    suite: TestSuite, context: String) -> [AnyObject] {
        let choices = radios(in: host)
        suite.expect(choices.count == labels.count && Set(choices.compactMap(name)) == Set(labels),
                     "the radio group exposes every name and count: \(context)")
        let bounds = window.convertToScreen(host.convert(host.bounds, to: nil))
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        var rows = [CGRect]()
        for choice in choices {
            let frame = choice.accessibilityFrame?() ?? .zero
            let title = (name(choice) ?? "") as NSString
            let textWidth = title.size(withAttributes: [.font: font]).width
            let separateRow = rows.allSatisfy { frame.maxY <= $0.minY + 1 || $0.maxY <= frame.minY + 1 }
            suite.expect(frame.height > 0 && frame.minX >= bounds.minX - 1 && frame.maxX <= bounds.maxX + 1
                         && frame.width >= textWidth - 1 && separateRow,
                         "the full radio title fits on its own row: \(context), \(title)")
            rows.append(frame)
        }
        return choices
    }
}
