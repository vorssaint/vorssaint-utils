// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Clock-style duration segments. The fields stay mounted while typing, so
/// changing keyboard focus never changes the island's layout.
struct NotchTimerDurationPicker: View {
    @Binding var seconds: Int
    let text: NotchActivityStrings

    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            segment(text.hours, divisor: 3600, maximum: 23)
            separator
            segment(text.minutes, divisor: 60, maximum: 59)
            separator
            segment(text.seconds, divisor: 1, maximum: 59)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
    }

    private var separator: some View {
        Text(":")
            .font(.system(size: 26, weight: .thin))
            .foregroundStyle(.orange)
            .frame(width: 7, height: 34)
            .accessibilityHidden(true)
    }

    private func segment(_ label: String, divisor: Int, maximum: Int) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.65)
            NotchTimerNumberField(value: Binding(
                get: { seconds / divisor % (maximum + 1) },
                set: { seconds += ($0 - seconds / divisor % (maximum + 1)) * divisor }),
                range: 0...maximum, label: label)
                .frame(height: 34)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .frame(width: 38)
    }
}

struct NotchTimerNumberField: NSViewRepresentable {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let label: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NotchTimerNumberNativeField {
        let field = NotchTimerNumberNativeField()
        field.delegate = context.coordinator
        field.formatter = NotchTimerNumberFormatter(range: range)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 26, weight: .thin)
        field.cell?.wraps = false
        field.cell?.isScrollable = false
        return field
    }

    func updateNSView(_ field: NotchTimerNumberNativeField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = context.environment.isEnabled
        field.textColor = context.environment.isEnabled ? .systemOrange : .disabledControlTextColor
        field.setAccessibilityLabel(label)
        field.toolTip = "\(range.lowerBound)–\(range.upperBound)"
        if field.currentEditor() == nil { field.stringValue = String(format: "%02d", value) }
    }

    static func dismantleNSView(_ field: NotchTimerNumberNativeField, coordinator: Coordinator) {
        field.delegate = nil
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NotchTimerNumberField
        private var originalValue = 0
        init(_ parent: NotchTimerNumberField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) {
            originalValue = parent.value
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            // A cleared positive-only field is an unfinished edit, not zero.
            if field.stringValue.isEmpty, parent.range.lowerBound > 0 { return }
            if let value = NotchTimerSupport.component(field.stringValue, maximum: parent.range.upperBound) {
                parent.value = value
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            (notification.object as? NSTextField)?.stringValue = String(format: "%02d", parent.value)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
                (control as? NotchTimerNumberNativeField)?.moveToAdjacent(
                    backwards: selector == #selector(NSResponder.insertBacktab(_:)))
            case #selector(NSResponder.cancelOperation(_:)):
                parent.value = originalValue
                control.window?.makeFirstResponder(nil)
            case #selector(NSResponder.insertNewline(_:)):
                control.window?.makeFirstResponder(nil)
            case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
                let delta = selector == #selector(NSResponder.moveUp(_:)) ? 1 : -1
                parent.value = min(parent.range.upperBound, max(parent.range.lowerBound, parent.value + delta))
                textView.string = String(format: "%02d", parent.value)
                textView.selectAll(nil)
            default: return false
            }
            return true
        }
    }
}

final class NotchTimerNumberNativeField: NSTextField {
    func moveToAdjacent(backwards: Bool) {
        guard let window, let root = window.contentView else { return }
        // SwiftUI's hosting view does not link these fields into AppKit's key loop.
        func fields(in view: NSView) -> [NotchTimerNumberNativeField] {
            if let field = view as? NotchTimerNumberNativeField,
               !field.isHiddenOrHasHiddenAncestor { return [field] }
            return view.subviews.flatMap { fields(in: $0) }
        }
        let ordered = fields(in: root).sorted { $0.convert(.zero, to: nil).x < $1.convert(.zero, to: nil).x }
        guard let index = ordered.firstIndex(where: { $0 === self }) else { return }
        let next = ordered[(index + (backwards ? -1 : 1) + ordered.count) % ordered.count]
        window.makeFirstResponder(next)
        next.selectText(nil)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
        selectText(nil)
    }
}

/// AppKit validates partial edits before changing the field or its binding.
final class NotchTimerNumberFormatter: Formatter {
    let range: ClosedRange<Int>
    init(range: ClosedRange<Int>) {
        self.range = range
        super.init()
    }
    required init?(coder: NSCoder) { nil }

    private func accepts(_ text: String) -> Bool {
        if text.isEmpty { return true }
        guard let value = NotchTimerSupport.component(text, maximum: range.upperBound) else { return false }
        return range.contains(value)
    }

    override func string(for obj: Any?) -> String? { obj as? String }

    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                                 for string: String,
                                 errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        obj?.pointee = string as NSString
        return accepts(string)
    }

    override func isPartialStringValid(_ partialString: String,
                                       newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                       errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        accepts(partialString)
    }
}
