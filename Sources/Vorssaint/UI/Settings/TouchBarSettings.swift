// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

struct TouchBarSettings: View {
    @AppStorage(DefaultsKey.touchBarEnabled) private var enabled = false
    @AppStorage(DefaultsKey.touchBarShowKeepAwake) private var showKeepAwake = true
    @AppStorage(DefaultsKey.touchBarShowMicMute) private var showMicMute = true
    @AppStorage(DefaultsKey.touchBarShowClipboard) private var showClipboard = true
    @AppStorage(DefaultsKey.touchBarShowSystemMetrics) private var showSystemMetrics = true
    @AppStorage(DefaultsKey.touchBarShowQuickLauncher) private var showQuickLauncher = true
    @AppStorage(DefaultsKey.touchBarShowKillProcess) private var showKillProcess = true
    @State private var order = TouchBarControl.ordered
    @State private var dragging: TouchBarControl?

    var body: some View {
        Form {
            Section("Touch Bar") {
                Toggle("Enable Vorssaint Touch Bar", isOn: $enabled)
            }

            Section("Controls") {
                ForEach(order, id: \.self) { control in
                    TouchBarControlRow(
                        control: control,
                        isVisible: visibilityBinding(for: control),
                        dragProvider: {
                            dragging = control
                            return NSItemProvider(object: control.rawValue as NSString)
                        }
                    )
                    .onDrop(
                        of: [UTType.text],
                        delegate: TouchBarControlDropDelegate(
                            target: control,
                            order: $order,
                            dragging: $dragging
                        )
                    )
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: enabled) { _, _ in refreshTouchBar() }
        .onChange(of: showKeepAwake) { _, _ in refreshTouchBar() }
        .onChange(of: showMicMute) { _, _ in refreshTouchBar() }
        .onChange(of: showClipboard) { _, _ in refreshTouchBar() }
        .onChange(of: showSystemMetrics) { _, _ in refreshTouchBar() }
        .onChange(of: showQuickLauncher) { _, _ in refreshTouchBar() }
        .onChange(of: showKillProcess) { _, _ in refreshTouchBar() }
    }

    private func visibilityBinding(for control: TouchBarControl) -> Binding<Bool> {
        switch control {
        case .keepAwake:
            return $showKeepAwake
        case .micMute:
            return $showMicMute
        case .clipboard:
            return $showClipboard
        case .systemMetrics:
            return $showSystemMetrics
        case .quickLauncher:
            return $showQuickLauncher
        case .killProcess:
            return $showKillProcess
        }
    }

    private func refreshTouchBar() {
        TouchBarService.shared.syncWithPreferences()
    }
}

private struct TouchBarControlRow: View {
    let control: TouchBarControl
    @Binding var isVisible: Bool
    let dragProvider: () -> NSItemProvider

    private var title: String {
        let language = L10n.shared.language
        let strings = FeatureStrings.touchBar(language)

        switch control {
        case .keepAwake: return strings.keepAwake
        case .micMute: return strings.microphoneMute
        case .clipboard: return FeatureStrings.clipboard(language).title
        case .systemMetrics: return strings.systemMetrics
        case .quickLauncher: return strings.quickLauncher
        case .killProcess: return FeatureStrings.killProcess(language).pageTitle
        }
    }

    private var symbolName: String {
        switch control {
        case .keepAwake: return "cup.and.saucer"
        case .micMute: return "mic.fill"
        case .clipboard: return "doc.on.clipboard"
        case .systemMetrics: return "chart.bar.fill"
        case .quickLauncher: return "square.grid.2x2"
        case .killProcess: return "xmark.octagon"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)

            Image(systemName: symbolName)
                .frame(width: 24)

            Text(title)

            Spacer()

            Toggle(title, isOn: $isVisible)
                .labelsHidden()
        }
        .contentShape(Rectangle())
        .onDrag(dragProvider)
    }
}

private struct TouchBarControlDropDelegate: DropDelegate {
    let target: TouchBarControl
    @Binding var order: [TouchBarControl]
    @Binding var dragging: TouchBarControl?

    func dropEntered(info: DropInfo) {
        guard let dragging,
              dragging != target,
              let from = order.firstIndex(of: dragging),
              let to = order.firstIndex(of: target) else { return }

        withAnimation(.easeInOut(duration: 0.12)) {
            order.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: to > from ? to + 1 : to
            )
        }
        TouchBarControl.setOrder(order)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        TouchBarControl.setOrder(order)
        return true
    }
}
