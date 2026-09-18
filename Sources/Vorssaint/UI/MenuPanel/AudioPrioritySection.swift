// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Audio priority disclosure shown inside the shared audio device card.
/// Contains independent Output and Microphone priority subsections. Each one
/// is a complete ordered list of discovered devices, and its position is the
/// priority used by automatic selection.
struct AudioPriorityDisclosure: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var priority = AudioPriorityService.shared
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var inputManager = AudioInputDeviceManager.shared
    private let showsHeader: Bool
    @State private var expanded: Bool

    init(initiallyExpanded: Bool = false, showsHeader: Bool = true) {
        self.showsHeader = showsHeader
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                Button {
                    expanded.toggle()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "list.number")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(l10n.s.audioPrioritySection)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(l10n.s.audioPriorityCaption)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    outputPrioritySubsection
                    Divider()
                    inputPrioritySubsection
                }
                .padding(.leading, showsHeader ? 19 : 0)
            }
        }
    }

    // MARK: - Output priority

    private var outputPrioritySubsection: some View {
        VStack(alignment: .leading, spacing: 5) {
            priorityHeader(title: l10n.s.audioPriorityOutputList,
                           systemImage: "speaker.wave.2.fill",
                           enabled: outputPriorityEnabledBinding,
                           help: l10n.s.audioPriorityOutputEnable)
            PriorityDeviceList(
                priorityUIDs: priority.outputPriorityUIDs,
                isAvailable: priority.isOutputAvailable,
                displayName: priority.displayName,
                currentUID: mixer.currentOutputDeviceUID,
                onMove: { priority.setOutputPriorityUIDs($0) })
        }
    }

    private func priorityHeader(title: String,
                                systemImage: String,
                                enabled: Binding<Bool>,
                                help: String) -> some View {
        HStack(spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Toggle(help, isOn: enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help(help)
                .accessibilityLabel(help)
        }
    }

    // MARK: - Input priority

    private var inputPrioritySubsection: some View {
        VStack(alignment: .leading, spacing: 5) {
            priorityHeader(title: l10n.s.audioPriorityInputList,
                           systemImage: "mic.fill",
                           enabled: inputPriorityEnabledBinding,
                           help: l10n.s.audioPriorityInputEnable)
            PriorityDeviceList(
                priorityUIDs: priority.inputPriorityUIDs,
                isAvailable: priority.isInputAvailable,
                displayName: priority.displayName,
                currentUID: inputManager.currentInputDeviceUID,
                onMove: { priority.setInputPriorityUIDs($0) })
        }
    }

    // MARK: - Bindings

    private var outputPriorityEnabledBinding: Binding<Bool> {
        Binding(
            get: { priority.outputPriorityEnabled },
            set: { priority.setOutputPriorityEnabled($0) }
        )
    }

    private var inputPriorityEnabledBinding: Binding<Bool> {
        Binding(
            get: { priority.inputPriorityEnabled },
            set: { priority.setInputPriorityEnabled($0) }
        )
    }
}

/// A selected-device priority list. Disconnected entries remain in their
/// stored position and use their last-known name. The visible control is a
/// drag handle; VoiceOver keeps equivalent move actions without adding UI.
private struct PriorityDeviceList: View {
    @ObservedObject private var l10n = L10n.shared
    let priorityUIDs: [String]
    let isAvailable: (String) -> Bool
    let displayName: (String) -> String?
    let currentUID: String?
    let onMove: ([String]) -> Void

    @State private var draggingUID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if priorityUIDs.isEmpty {
                Text(l10n.s.audioPriorityEmpty)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(priorityUIDs.enumerated()), id: \.element) { index, uid in
                        priorityRow(uid: uid, index: index)
                    }
                }
            }
        }
    }

    private func priorityRow(uid: String, index: Int) -> some View {
        let available = isAvailable(uid)
        let name = displayName(uid) ?? uid
        let isCurrent = uid == currentUID

        return HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(available ? .primary : .secondary)
                    if isCurrent {
                        Text(l10n.s.audioPriorityCurrent)
                            .font(.system(size: 9))
                            .foregroundStyle(Color.accentColor)
                            .fixedSize()
                    }
                }
                if !available {
                    Text(l10n.s.audioPriorityUnavailable)
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())
        }
        .font(.system(size: 9, weight: .semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isCurrent ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isCurrent ? Color.accentColor.opacity(0.65) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .opacity(draggingUID == uid ? 0.45 : 1)
        .onDrag {
            draggingUID = uid
            return NSItemProvider(object: uid as NSString)
        } preview: {
            // A full-row preview lingers briefly while AppKit concludes the
            // drop. The real row has already moved by then, which makes the
            // two copies look like a slow settle. Keep native drag/drop, but
            // preview only the affordance so there is no duplicate row.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .accessibilityAction(named: Text(l10n.s.audioPriorityMoveUp)) {
            move(uid, by: -1)
        }
        .accessibilityAction(named: Text(l10n.s.audioPriorityMoveDown)) {
            move(uid, by: 1)
        }
        .onDrop(of: [UTType.text],
                delegate: PriorityDeviceDropDelegate(
                    targetUID: uid,
                    priorityUIDs: priorityUIDs,
                    onMove: onMove,
                    draggingUID: $draggingUID))
    }

    private func move(_ uid: String, by offset: Int) {
        guard let index = priorityUIDs.firstIndex(of: uid) else { return }
        let destination = index + offset
        guard priorityUIDs.indices.contains(destination) else { return }
        var reordered = priorityUIDs
        reordered.swapAt(index, destination)
        onMove(reordered)
    }
}

private struct PriorityDeviceDropDelegate: DropDelegate {
    let targetUID: String
    let priorityUIDs: [String]
    let onMove: ([String]) -> Void
    @Binding var draggingUID: String?

    func dropEntered(info: DropInfo) {
        guard let draggingUID,
              draggingUID != targetUID,
              let from = priorityUIDs.firstIndex(of: draggingUID),
              let to = priorityUIDs.firstIndex(of: targetUID) else { return }

        var reordered = priorityUIDs
        reordered.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        onMove(reordered)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingUID = nil
        return true
    }
}

/// A compact panel section shown when Audio device priority is installed but
/// Volume mixer is not. The complete ordered lists are the control surface;
/// manual Output/Microphone pickers remain part of Volume mixer.
struct AudioPrioritySection: View {
    @ObservedObject private var l10n = L10n.shared
    var collapsible = true

    var body: some View {
        PanelSection(.mixer, title: l10n.s.audioPrioritySection, collapsible: collapsible) {
            AudioPriorityDisclosure(initiallyExpanded: true, showsHeader: false)
                .panelCard()
        }
    }
}
