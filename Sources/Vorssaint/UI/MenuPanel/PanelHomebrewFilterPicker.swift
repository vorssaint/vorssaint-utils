// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum PanelHomebrewFilter: Int, CaseIterable {
    case all, cask, formula
}

struct PanelHomebrewFilterPicker: View {
    @Binding var selection: PanelHomebrewFilter
    let strings: Strings
    let totalCount: Int
    let caskCount: Int
    let formulaCount: Int

    var body: some View {
        let labels = PanelHomebrewFilter.allCases.map { filter in
            switch filter {
            case .all: return "\(strings.homebrewAll) \(totalCount)"
            case .cask: return "\(strings.homebrewCasks) \(caskCount)"
            case .formula: return "\(strings.homebrewFormulas) \(formulaCount)"
            }
        }
        FilterControl(labels: labels, title: strings.homebrewInstalled, selection: $selection)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FilterControl: NSViewRepresentable {
    let labels: [String]
    let title: String
    @Binding var selection: PanelHomebrewFilter

    func makeNSView(context: Context) -> Control {
        Control(labels: labels, selection: $selection)
    }

    func updateNSView(_ control: Control, context: Context) {
        control.update(labels: labels, title: title, selection: $selection,
                       enabled: context.environment.isEnabled)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Control, context: Context) -> CGSize? {
        nsView.size(forWidth: proposal.width)
    }

    final class Control: NSView {
        private let segments: NSSegmentedControl
        private let radios: NSStackView
        private let buttons: [NSButton]
        private var labels: [String]
        private var segmentSize: CGSize
        private var selection: Binding<PanelHomebrewFilter>

        private static func makeSegments(_ labels: [String]) -> NSSegmentedControl {
            let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: nil, action: nil)
            control.controlSize = .small
            control.segmentDistribution = .fit
            return control
        }

        init(labels: [String], selection: Binding<PanelHomebrewFilter>) {
            self.labels = labels
            self.selection = selection
            segments = Self.makeSegments(labels)
            segmentSize = segments.intrinsicContentSize
            buttons = labels.map { title in
                let button = NSButton(radioButtonWithTitle: title, target: nil, action: nil)
                button.controlSize = .small
                return button
            }
            radios = NSStackView(views: buttons)
            super.init(frame: .zero)
            radios.orientation = .vertical
            radios.alignment = .leading
            radios.spacing = 2
            radios.setAccessibilityElement(true)
            radios.setAccessibilityRole(.radioGroup)
            segments.target = self
            segments.action = #selector(chooseSegment)
            for (index, button) in buttons.enumerated() {
                button.tag = index
                button.target = self
                button.action = #selector(chooseRadio(_:))
            }
        }

        required init?(coder: NSCoder) { nil }

        func update(labels: [String], title: String, selection: Binding<PanelHomebrewFilter>, enabled: Bool) {
            self.selection = selection
            if self.labels != labels {
                self.labels = labels
                // The mounted control can report its previous intrinsic width after setLabel.
                segmentSize = Self.makeSegments(labels).intrinsicContentSize
                for (index, label) in labels.enumerated() {
                    segments.setLabel(label, forSegment: index)
                    buttons[index].title = label
                }
                needsLayout = true
            }
            segments.setAccessibilityLabel(title)
            radios.setAccessibilityLabel(title)
            let selected = selection.wrappedValue.rawValue
            if segments.selectedSegment != selected { segments.selectedSegment = selected }
            segments.isEnabled = enabled
            for button in buttons {
                button.state = button.tag == selected ? .on : .off
                button.isEnabled = enabled
            }
        }

        func size(forWidth proposed: CGFloat?) -> CGSize {
            let width = proposed.flatMap { $0.isFinite ? $0 : nil } ?? segmentSize.width
            return CGSize(width: width, height: width >= segmentSize.width ? segmentSize.height : radios.fittingSize.height)
        }

        override func layout() {
            super.layout()
            let showSegments = bounds.width >= segmentSize.width
            let next: NSView = showSegments ? segments : radios
            next.frame = NSRect(origin: .zero, size: showSegments ? segmentSize : bounds.size)
            guard next.superview == nil else { return }

            let old: NSView = showSegments ? radios : segments
            addSubview(next)
            // While both controls are attached, the current responder tells us
            // whether the user is still in the outgoing control.
            if old.superview === self, let window, let responder = window.firstResponder as? NSView,
               responder === old || responder.isDescendant(of: old) {
                window.makeFirstResponder(showSegments ? segments : buttons[selection.wrappedValue.rawValue])
            }
            old.removeFromSuperview()
            // The island's panel keeps its key view loop when subviews change.
            if let window, !window.autorecalculatesKeyViewLoop { window.recalculateKeyViewLoop() }
        }

        @objc private func chooseSegment() {
            if let filter = PanelHomebrewFilter(rawValue: segments.selectedSegment) { selection.wrappedValue = filter }
        }

        @objc private func chooseRadio(_ button: NSButton) {
            if let filter = PanelHomebrewFilter(rawValue: button.tag) { selection.wrappedValue = filter }
        }
    }
}
