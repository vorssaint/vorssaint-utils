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
        ViewThatFits(in: .horizontal) {
            // Measure each segment at its label's width. If the entire row is
            // too wide, keep every name and count visible on its own line.
            FilterSegments(selection: $selection, title: strings.homebrewInstalled, labels: labels)
                .fixedSize()
            Picker(strings.homebrewInstalled, selection: $selection) {
                ForEach(PanelHomebrewFilter.allCases, id: \.self) { filter in
                    Text(labels[filter.rawValue]).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FilterSegments: NSViewRepresentable {
    @Binding var selection: PanelHomebrewFilter
    let title: String
    let labels: [String]

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.selectFilter(_:)))
        control.controlSize = .small
        control.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        control.segmentDistribution = .fit
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        for (index, label) in labels.enumerated() where control.label(forSegment: index) != label {
            control.setLabel(label, forSegment: index)
        }
        control.setAccessibilityLabel(title)
        control.isEnabled = context.environment.isEnabled
        if control.selectedSegment != selection.rawValue {
            control.selectedSegment = selection.rawValue
        }
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<PanelHomebrewFilter>

        init(selection: Binding<PanelHomebrewFilter>) { self.selection = selection }

        @objc func selectFilter(_ control: NSSegmentedControl) {
            if let filter = PanelHomebrewFilter(rawValue: control.selectedSegment) {
                selection.wrappedValue = filter
            }
        }
    }
}
