// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Reusable controls for screenshot tool order and shortcut assignments.
struct ScreenshotToolOrderControls: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var orderRaw: String
    @Binding var shortcutsEnabled: Bool
    var showsTitle = true
    @AppStorage(DefaultsKey.screenshotToolShortcuts) private var bindingsRaw = ""
    @State private var recordingTool: ScreenshotSupport.Tool?
    @State private var errorText: String?

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    private var movementStrings: ClipboardFeatureStrings {
        FeatureStrings.clipboard(l10n.language)
    }

    private var orderedTools: [ScreenshotSupport.Tool] {
        ScreenshotSupport.Tool.ordered(from: orderRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle {
                Text(strings.toolShortcutsTitle)
                    .font(.headline)
            }

            Toggle(strings.toolShortcutsToggle, isOn: $shortcutsEnabled)
            Text(strings.toolShortcutsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 2) {
                ForEach(orderedTools, id: \.self) { tool in
                    toolRow(tool)
                    if tool != orderedTools.last {
                        Divider().padding(.leading, 28)
                    }
                }
            }

            Text(errorText ?? (recordingTool == nil ? " "
                : ShortcutRecordingCaption.text(l10n.s, canClear: true)))
                .font(.caption)
                .foregroundStyle(errorText == nil ? Color.secondary : .orange)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                .accessibilityHidden(errorText == nil && recordingTool == nil)

            HStack {
                Spacer()
                Button(l10n.s.shortcutReset) {
                    orderRaw = ScreenshotSupport.Tool.defaultOrderStorage
                    bindingsRaw = ""
                    errorText = nil
                }
                .disabled(orderRaw == ScreenshotSupport.Tool.defaultOrderStorage && bindingsRaw.isEmpty)
            }
        }
        .onChange(of: l10n.language) { _, _ in errorText = nil }
    }

    private func toolRow(_ tool: ScreenshotSupport.Tool) -> some View {
        let index = orderedTools.firstIndex(of: tool) ?? 0

        return HStack(spacing: 7) {
            Image(systemName: tool.screenshotSymbolName)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(tool.screenshotTitle(strings))
                .lineLimit(1)
            Spacer(minLength: 4)

            Group {
                if ScreenshotSupport.Tool.bindings(from: bindingsRaw)[tool] != nil {
                    Button {
                        var bindings = ScreenshotSupport.Tool.bindings(from: bindingsRaw)
                        bindings[tool] = nil
                        bindingsRaw = ScreenshotSupport.Tool.bindingsStorage(bindings)
                        errorText = nil
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 22)
                            .background(Color.primary.opacity(0.045),
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(l10n.s.shortcutReset)
                    .accessibilityLabel(tool.screenshotTitle(strings) + ": " + l10n.s.shortcutReset)
                } else {
                    Color.clear.frame(width: 20, height: 22)
                }
            }

            shortcutRecorder(for: tool)
                .opacity(shortcutsEnabled ? 1 : 0.48)

            Button {
                move(tool, by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 20, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            .accessibilityLabel(movementStrings.moveUp)

            Button {
                move(tool, by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 20, height: 22)
            }
            .buttonStyle(.borderless)
            .disabled(index == orderedTools.count - 1)
            .accessibilityLabel(movementStrings.moveDown)
        }
        .frame(minHeight: 26)
        .contentShape(Rectangle())
    }

    private func shortcutRecorder(for tool: ScreenshotSupport.Tool) -> some View {
        let binding = ScreenshotSupport.Tool.bindings(from: bindingsRaw)[tool]
        // The position digit is a title, not a shortcut: the field shows it
        // as its empty state so nothing else (Delete, reset) treats it as a
        // recorded key.
        let label = ScreenshotSupport.Tool.shortcutLabel(
            for: tool, orderRaw: orderRaw, bindingsRaw: bindingsRaw, enabled: true)
        return ShortcutRecorderButton(
            shortcut: binding ?? .keepAwakeDefault,
            isEnabled: true,
            waitingTitle: l10n.s.shortcutPressKeys,
            requiresModifier: false,
            emptyTitle: binding == nil ? (label ?? l10n.s.shortcutNone) : nil,
            clearAction: { assign(nil, to: tool) },
            notCapturedAction: { errorText = l10n.s.shortcutNotCaptured },
            recordingChanged: { recording in
                recordingTool = recording ? tool : nil
                if recording { errorText = nil }
            },
            invalidAction: { errorText = l10n.s.shortcutNotCaptured },
            captureAction: { assign($0, to: tool) })
            .frame(width: 86)
            .accessibilityLabel(tool.screenshotTitle(strings))
    }

    private func move(_ tool: ScreenshotSupport.Tool, by offset: Int) {
        var order = orderedTools
        guard let index = order.firstIndex(of: tool) else { return }
        let destination = index + offset
        guard order.indices.contains(destination) else { return }
        withAnimation(.easeInOut(duration: 0.14)) {
            order.swapAt(index, destination)
            persist(order)
        }
    }

    /// A digit moves the tool and skips every conflict check. Anything else
    /// has to be free before it is saved; a rejection leaves the previous
    /// binding in place and says who owns the key.
    private func assign(_ shortcut: GlobalShortcut?, to tool: ScreenshotSupport.Tool) {
        let digit = shortcut.flatMap(ScreenshotSupport.Tool.shortcutDigit)
        if let shortcut, digit == nil, let rejection = ScreenshotSupport.Tool.bindingRejection(
            for: shortcut, excluding: tool, bindingsRaw: bindingsRaw,
            roleConflict: { GlobalShortcutRole.conflict(for: $0, excluding: nil) },
            windowLayoutConflict: { WindowLayoutService.shared.shortcutConflictTitle($0) },
            systemConflict: { $0.conflictsWithSystemShortcut }) {
            let reason: String
            switch rejection {
            case .reserved:
                reason = strings.toolShortcutReserved
            case .tool(let other):
                reason = String(format: l10n.s.shortcutConflictFormat, other.screenshotTitle(strings))
            case .role(let role):
                reason = String(format: l10n.s.shortcutConflictFormat, role.title(l10n.s))
            case .windowLayout(let title):
                reason = String(format: l10n.s.shortcutConflictFormat, title)
            case .system:
                reason = String(format: l10n.s.shortcutConflictFormat, "macOS")
            }
            errorText = tool.screenshotTitle(strings) + " · " + shortcut.displayString + "\n" + reason
            return
        }
        let assignment = ScreenshotSupport.Tool.assigningBinding(
            shortcut, digit: digit, to: tool, orderRaw: orderRaw, bindingsRaw: bindingsRaw)
        orderRaw = assignment.orderRaw
        bindingsRaw = assignment.bindingsRaw
        errorText = nil
    }

    private func persist(_ order: [ScreenshotSupport.Tool]) {
        orderRaw = order.map(\.rawValue).joined(separator: ",")
    }
}
