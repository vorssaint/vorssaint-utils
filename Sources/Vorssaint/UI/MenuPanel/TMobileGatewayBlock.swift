// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Shares a single reader with the pinned menu bar indicator.
struct TMobileGatewayBlock: View {
    @Binding var isVisible: Bool
    var editing: Bool
    @ObservedObject private var service = TMobileGatewayMonitor.shared.service
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.tMobileGatewayAddress) private var address = TMobileGatewayService.defaultBaseURL
    @State private var configuring = false
    @State private var lastUpdated: Date?
    @State private var showingTips = false
    @Environment(\.colorScheme) private var colorScheme

    private var strings: TMobileGatewayStrings { .localized(l10n.language) }

    var body: some View {
        Group {
            if !isVisible {
                PanelHiddenItemRow(title: strings.title, systemImage: "antenna.radiowaves.left.and.right",
                                   isVisible: $isVisible)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Label(strings.title, systemImage: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button { configuring = true } label: {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.plain)
                        .help(strings.configure)
                        .accessibilityLabel(strings.configure)
                        .popover(isPresented: $configuring) { TMobileGatewayAddressEditor() }
                        if editing { PanelInlineHideButton(isVisible: $isVisible) }
                    }
                    if let snapshot = service.snapshot {
                        readings(snapshot)
                    } else {
                        status
                    }
                    Button(strings.signalGuide) { showingTips = true }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .onAppear { updatePolling() }
        .onChange(of: isVisible) { _, _ in updatePolling() }
        .onChange(of: address) { _, _ in updatePolling() }
        .onReceive(service.$snapshot) { snapshot in
            lastUpdated = snapshot == nil ? nil : Date()
        }
        .onDisappear { TMobileGatewayMonitor.shared.setPanelVisible(false) }
        .sheet(isPresented: $showingTips) { TMobileGatewayTipsView(snapshot: service.snapshot, strings: strings) }
    }

    private func updatePolling() {
        TMobileGatewayMonitor.shared.setPanelVisible(isVisible)
    }

    @ViewBuilder private var status: some View {
        if service.phase == .loading {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(strings.loading)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(failureMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(strings.retry) { service.refresh() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var failureMessage: String {
        guard case .failed(let failure) = service.phase else { return strings.unknown }
        switch failure {
        case .invalidAddress: return strings.invalidAddress
        case .authenticationRequired: return strings.authenticationRequired
        case .unavailable: return strings.unavailable
        case .invalidResponse: return strings.invalidResponse
        }
    }

    private func readings(_ snapshot: TMobileGatewaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                if let model = snapshot.model { Text(model).fontWeight(.medium) }
                Spacer(minLength: 0)
                if let state = snapshot.registration { Text(registration(state)) }
                if snapshot.roaming == true { Text(strings.roaming) }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            ForEach(TMobileGatewayRadioPresentation.sections(snapshot, strings: strings)) { section in
                radioReadings(section)
            }
            HStack(spacing: 6) {
                if let firmware = snapshot.firmware {
                    Text("\(strings.firmware): \(firmware)")
                }
                Spacer(minLength: 0)
                if let uptime = snapshot.uptime, uptime < Double(Int.max) {
                    Text("\(strings.uptime): \(MetricFormat.uptime(Int(uptime)))")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            if let lastUpdated {
                HStack(spacing: 4) {
                    Text(strings.lastUpdated)
                    Text(lastUpdated, style: .time)
                    Spacer(minLength: 0)
                    Button { service.refresh() } label: {
                        if service.phase == .loading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                        .buttonStyle(.plain)
                        .disabled(service.phase == .loading)
                        .help(strings.refresh)
                        .accessibilityLabel(service.phase == .loading ? strings.refreshing : strings.refresh)
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
        }
    }

    private func registration(_ value: String?) -> String {
        switch value?.lowercased() {
        case "registered": return strings.registered
        case "not registered", "notregistered", "unregistered", "searching": return strings.notRegistered
        default: return value ?? ""
        }
    }

    private func radioReadings(_ section: TMobileGatewayRadioPresentation.Section) -> some View {
        let radio = section.radio
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(section.title).fontWeight(.semibold)
                if let bands = section.rows.first(where: { $0.id == .bands }) {
                    Text(bands.value)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let bars = radio.bars, section.rows.contains(where: { $0.id == .bars }) {
                    TMobileSignalBars(bars: bars, radio: section.title, strings: strings,
                                      quality: TMobileGatewayDiagnostics.quality(for: radio.rsrp, metric: .rsrp))
                }
            }
            HStack(alignment: .top, spacing: 16) {
                if let row = TMobileGatewayRadioPresentation.measurementRow(radio, metric: .rsrp, strings: strings) {
                    metric(row)
                }
                if let row = TMobileGatewayRadioPresentation.measurementRow(radio, metric: .sinr, strings: strings) {
                    metric(row)
                }
            }
        }
        .font(.system(size: 11))
        .monospacedDigit()
        .padding(.vertical, 3)
    }

    private func metric(_ row: TMobileGatewayRadioPresentation.Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.label).foregroundStyle(.secondary)
            Text(row.value).fontWeight(.medium)
            if let rating = row.qualityLabel {
                Text(rating).font(.system(size: 10, weight: .medium))
            }
        }
        .foregroundStyle(row.quality.presentationColor(for: colorScheme))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityValue)
    }

}

/// An explicit save avoids polling partial addresses while the user types.
struct TMobileGatewayAddressEditor: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.tMobileGatewayAddress) private var address = TMobileGatewayService.defaultBaseURL
    @State private var draft = ""
    @Environment(\.dismiss) private var dismiss

    private var strings: TMobileGatewayStrings { .localized(l10n.language) }
    private var valid: Bool { TMobileGatewaySupport.privateLANBaseURL(draft) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(strings.configure).font(.headline)
            TextField(strings.gatewayAddress, text: $draft)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(strings.gatewayAddress)
                .onSubmit { save() }
            Text(strings.addressHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !valid && !draft.isEmpty {
                Text(strings.invalidAddress).font(.caption).foregroundStyle(.secondary)
            }
            Button(strings.save) { save() }
                .disabled(!valid)
            Divider()
            Text(strings.menuBarHint)
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { draft = address }
    }

    private func save() {
        guard let url = TMobileGatewaySupport.privateLANBaseURL(draft) else { return }
        address = url.absoluteString
        dismiss()
    }
}

private struct TMobileSignalBars: View {
    let bars: Int
    let radio: String
    let strings: TMobileGatewayStrings
    let quality: TMobileSignalQuality
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let spoken = String(format: strings.barsSpokenFormat, radio, String(bars))
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index <= bars ? quality.presentationColor(for: colorScheme) : Color.secondary.opacity(0.25))
                    .frame(width: 3, height: CGFloat(index * 2 + 3))
            }
            Text("\(bars)/5").padding(.leading, 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quality == .unknown ? spoken
                            : spoken + "; " + String(format: strings.rsrpQualityFormat, quality.label(strings)))
        .help(strings.barsHelp)
    }
}

extension TMobileSignalQuality {
    func presentationColor(for scheme: ColorScheme) -> Color {
        switch self {
        case .excellent, .good: return PanelMetricColor.green(for: scheme)
        case .fair: return PanelMetricColor.yellow(for: scheme)
        case .poor: return PanelMetricColor.red(for: scheme)
        case .unknown: return .primary
        }
    }
}

private struct TMobileGatewayTipsView: View {
    let snapshot: TMobileGatewaySnapshot?
    let strings: TMobileGatewayStrings
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(strings.guideTitle).font(.title2.bold()); Spacer(); Button(strings.done) { dismiss() }.keyboardShortcut(.cancelAction) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(strings.guideIntro)
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(TMobileSignalMetric.allCases, id: \.self) { metric in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(metric.label) · \(metric.unit)").font(.headline)
                            Text(metric.explanation(strings))
                            HStack(spacing: 20) {
                                guideReading("LTE", radio: snapshot?.lte, metric: metric)
                                guideReading("5G", radio: snapshot?.fiveG, metric: metric)
                            }.font(.callout).monospacedDigit()
                        }
                    }
                    if let snapshot {
                        Divider()
                        Text(strings.tipsHeading).font(.headline)
                        ForEach(Array(TMobileGatewayDiagnostics.tips(for: snapshot, strings: strings).enumerated()), id: \.offset) { index, tip in Text("\(index + 1). \(tip)") }
                        ForEach(Array(Set((snapshot.lte?.bands ?? []) + (snapshot.fiveG?.bands ?? []))).sorted(), id: \.self) { band in
                            if let description = TMobileGatewayDiagnostics.bandDescription(band, strings: strings) { Text("\(band): \(description)") }
                        }
                        if let apn = snapshot.apn { Text("\(strings.reportedAPN): \(apn)").font(.caption) }
                    }
                    Divider()
                    Text(strings.guideFooter)
                        .font(.callout).foregroundStyle(.secondary)
                    Link(strings.networkInfoLink, destination: URL(string: "https://www.t-mobile.com/support/coverage/t-mobile-network")!)
                    Link(strings.placementLink, destination: URL(string: "https://www.t-mobile.com/support/home-internet/t-mobile-gateway/network-speed")!)
                    Link(strings.coverageMapLink, destination: URL(string: "https://www.t-mobile.com/coverage/coverage-map")!)
                }.textSelection(.enabled).padding(.trailing, 8)
            }
        }.padding(20).frame(width: 590, height: 660)
    }
    @ViewBuilder private func guideReading(_ label: String, radio: TMobileRadioSignal?, metric: TMobileSignalMetric) -> some View {
        if let radio, let row = TMobileGatewayRadioPresentation.measurementRow(radio, metric: metric, strings: strings) {
            Text("\(label): \(row.value)\(row.qualityLabel.map { " · " + $0 } ?? "")")
        }
    }
}
