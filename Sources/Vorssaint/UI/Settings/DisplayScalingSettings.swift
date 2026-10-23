// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The flexible scaling card on the Energy page: the switch, the smallest size
/// the list reaches, and one row per connected external display model with its
/// current override and the action that changes it.
struct DisplayScalingSettingsCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = DisplayScalingService.shared
    @AppStorage(DefaultsKey.displayScalingEnabled) private var enabled = false
    @AppStorage(DefaultsKey.displayScalingMinimumPercent)
    private var minimumPercent = DisplayScalingSupport.defaultMinimumPercent

    var body: some View {
        let strings = FeatureStrings.displayScaling(l10n.language)
        SettingsCard {
            SettingsRow(symbol: "rectangle.expand.vertical", title: strings.enable,
                        caption: strings.enableCaption) {
                Toggle(strings.enable, isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) { _, _ in service.syncWithPreferences() }
            }
            if enabled {
                SettingsRow(symbol: "arrow.down.right.and.arrow.up.left", title: strings.smallestSize,
                            caption: strings.smallestSizeCaption) {
                    Picker(strings.smallestSize, selection: $minimumPercent) {
                        ForEach(Defaults.allowedDisplayScalingMinimumPercents, id: \.self) { percent in
                            Text(strings.percentOfNative(percent)).tag(percent)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if service.displays.isEmpty {
                    SettingsRow(symbol: "display", title: strings.pageTitle, caption: strings.noDisplays) {
                        EmptyView()
                    }
                }
                ForEach(service.displays) { display in
                    displayRow(display, strings: strings)
                    if !display.scaleSizes.isEmpty {
                        DisplayScaleSliderRow(display: display, strings: strings)
                    }
                }
                if let outcome = service.lastOutcome {
                    Text(outcomeText(outcome, strings: strings))
                        .font(.caption)
                        .foregroundStyle(outcome == .failed ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            minimumPercent = Defaults.sanitizedDisplayScalingMinimumPercent(minimumPercent)
            service.syncWithPreferences()
        }
    }

    private func displayRow(_ display: DisplayScalingService.Display,
                            strings: DisplayScalingStrings) -> some View {
        var caption = "\(strings.native(display.nativeWidth, display.nativeHeight)) · \(strings.state(display.state))"
        if case .foreign = display.state { caption += "\n\(strings.replaceCaption)" }
        let working = service.workingModelID == display.id
        let busy = service.workingModelID != nil
        return SettingsRow(symbol: "display", title: display.name, caption: caption) {
            HStack(spacing: 8) {
                if working { ProgressView().controlSize(.small) }
                switch display.state {
                case .none:
                    Button(strings.install) { service.install(display) }
                case .vorssaint:
                    Button(strings.update) { service.install(display) }
                    Button(strings.remove) { service.remove(display) }
                case .foreign:
                    Button(strings.replace) { service.install(display) }
                }
            }
            .disabled(busy)
        }
    }

    private func outcomeText(_ outcome: DisplayScalingService.Outcome, strings: DisplayScalingStrings) -> String {
        switch outcome {
        case .installed(let reconnected): return reconnected ? strings.installedReconnectedNote : strings.installedNote
        case .removed(let reconnected): return reconnected ? strings.removedReconnectedNote : strings.removedNote
        case .failed: return strings.failedNote
        }
    }
}

/// BetterDisplay-style resolution slider over the display's HiDPI sizes. The
/// value follows the drag; the mode changes once, when the drag ends, so macOS
/// is not asked to switch modes for every stop passed on the way.
private struct DisplayScaleSliderRow: View {
    let display: DisplayScalingService.Display
    let strings: DisplayScalingStrings
    @State private var position: Double?

    var body: some View {
        let sizes = display.scaleSizes
        let currentIndex = DisplayScalingSupport.sliderIndex(of: display.current, in: sizes) ?? 0
        let index = min(max(Int((position ?? Double(currentIndex)).rounded()), 0), sizes.count - 1)
        let shown = position == nil ? (display.current ?? sizes[index]) : sizes[index]
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(strings.resolution)
                Spacer()
                Text(strings.resolutionValue(shown, percent: DisplayScalingSupport.percentOfNative(
                    shown, nativeWidth: display.nativeWidth)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if sizes.count > 1 {
                Slider(value: Binding(get: { position ?? Double(currentIndex) },
                                      set: { position = $0 }),
                       in: 0...Double(sizes.count - 1), step: 1) { editing in
                    guard !editing, let position else { return }
                    let target = sizes[min(max(Int(position.rounded()), 0), sizes.count - 1)]
                    self.position = nil
                    DisplayScalingService.shared.applyScale(target, to: display)
                }
            }
            Text(display.currentIsNative ? strings.nativeOneToOne
                 : display.currentIsHiDPI
                 ? strings.rendered(pixelWidth: display.currentPixelWidth, pixelHeight: display.currentPixelHeight,
                                    nativeWidth: display.nativeWidth, nativeHeight: display.nativeHeight)
                 : strings.notHiDPI)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 40)
    }
}
