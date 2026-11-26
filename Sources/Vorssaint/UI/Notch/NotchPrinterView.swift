// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The Bambu Cloud sign-in and the account's printer, under its section in
/// the Dynamic Island settings.
struct NotchPrinterSettingsControls: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var printer = NotchPrinterService.shared
    @AppStorage(DefaultsKey.notchPrinterEnabled) private var enabled = false
    private var text: NotchPrinterStrings { FeatureStrings.notchPrinter(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(text.title, isOn: $enabled)
                .disabled(!AppFeature.notchPrinter.isAvailable)
            Text(text.description).font(.caption).foregroundStyle(.secondary)
            if enabled {
                NotchPrinterCloudControls(text: text)
                NotchPrinterConnectionLabel(connection: printer.connection, text: text)
                    .font(.caption)
            }
        }
        .onChange(of: enabled) { NotchService.shared.syncWithPreferences() }
    }
}

private struct NotchPrinterCloudControls: View {
    let text: NotchPrinterStrings
    @ObservedObject private var account = BambuCloudAccount.shared
    @AppStorage(DefaultsKey.notchPrinterSerial) private var serial = ""
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch account.step {
            case .signedOut:
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text(text.email)
                        TextField("", text: $email).textFieldStyle(.roundedBorder)
                            .textContentType(.username)
                    }
                    GridRow {
                        Text(text.password)
                        SecureField("", text: $password).textFieldStyle(.roundedBorder)
                            .textContentType(.password)
                            .onSubmit(signIn)
                    }
                }
                .frame(maxWidth: 360)
                HStack(spacing: 10) {
                    Button(text.signIn, action: signIn)
                        .disabled(email.isEmpty || password.isEmpty || account.busy)
                    if account.busy { ProgressView().controlSize(.small) }
                }
            case .emailCode, .twoFactor:
                Text(account.step == .emailCode ? text.emailCodePrompt : text.twoFactorPrompt)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    TextField(text.code, text: $code).textFieldStyle(.roundedBorder)
                        .textContentType(.oneTimeCode)
                        .frame(maxWidth: 160)
                        .onSubmit { account.verify(code: code) }
                    Button(text.verify) { account.verify(code: code) }
                        .disabled(code.isEmpty || account.busy)
                    if account.step == .emailCode {
                        Button(text.resend) { account.resendCode() }.disabled(account.busy)
                    }
                    Button(text.cancel) { code = ""; account.cancel() }
                    if account.busy { ProgressView().controlSize(.small) }
                }
            case .signedIn:
                HStack(spacing: 10) {
                    Text(text.signedIn(account.email)).lineLimit(1).truncationMode(.middle)
                    Button(text.signOut) { account.signOut() }
                }
                HStack(spacing: 10) {
                    if account.devices.isEmpty {
                        Text(account.busy ? text.connecting : text.noPrinters).foregroundStyle(.secondary)
                    } else {
                        Picker(text.printer, selection: Binding(get: { serial }, set: { account.choose(serial: $0) })) {
                            ForEach(account.devices) { device in
                                Text(device.model.isEmpty ? device.name : "\(device.name) · \(device.model)")
                                    .tag(device.serial)
                            }
                        }
                        .frame(maxWidth: 360)
                    }
                    Button { account.refreshDevices() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .disabled(account.busy)
                        .help(text.refresh)
                }
                .onAppear { if account.devices.isEmpty { account.refreshDevices() } }
            }
            if let error = account.error {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(text.cloudHint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: account.step) {
            code = ""
            password = ""
        }
    }

    private func signIn() {
        account.signIn(email: email, password: password)
    }
}

struct NotchPrinterConnectionLabel: View {
    let connection: PrinterConnection
    let text: NotchPrinterStrings

    var body: some View {
        switch connection {
        case .off: EmptyView()
        case .notConfigured: Text(text.notConfigured).foregroundStyle(.secondary)
        case .connecting: Text(text.connecting).foregroundStyle(.secondary)
        case .connected:
            Label(text.connected, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .refused:
            Text(text.signInAgain).foregroundStyle(.orange)
        case .failed(let reason):
            Text(reason.map { text.unreachable + " · " + $0 } ?? text.unreachable)
                .foregroundStyle(.orange).lineLimit(2)
        }
    }
}

/// The page: a ring of progress beside the job, when it ends, and three
/// gauges under them for the layer and both heaters.
struct NotchPrinterView: View {
    let size: CGSize
    @ObservedObject private var printer = NotchPrinterService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchSettingsPreview) private var preview
    private var text: NotchPrinterStrings { FeatureStrings.notchPrinter(l10n.language) }

    var body: some View {
        Group {
            if preview || printer.connection != .connected {
                NotchPrinterSetupView()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 18) {
                        NotchPrinterRing(status: status, tint: tint, label: text.state(status.state))
                            .frame(width: ringSize, height: ringSize)
                        job
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 12)
                    gauges
                }
                .padding(.top, 4)
                .notchBand(leading: { band }, trailing: { EmptyView() })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var status: PrinterStatus { printer.status }
    private var tint: Color { NotchPrinterSupport.tint(for: status.state) }
    private var ringSize: CGFloat { min(112, max(84, size.height * 0.34)) }

    private var band: some View {
        HStack(spacing: 6) {
            Image(systemName: NotchModule.printer.symbol).foregroundStyle(NotchPrinterSupport.tint)
            Text(text.title).fontWeight(.semibold)
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(0.85))
    }

    /// The job's name, where it stands and when it ends.
    private var job: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(status.jobName ?? text.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .help(status.jobName ?? "")
            NotchPrinterStatePill(title: text.state(status.state), symbol: status.state.symbol, tint: tint)
            if status.state.isActive, let minutes = status.remainingMinutes,
               let left = NotchPrinterSupport.remainingText(minutes: minutes, language: l10n.language) {
                HStack(spacing: 12) {
                    Label(text.left(left), systemImage: "hourglass")
                    Label(finishTime(minutes), systemImage: "flag.checkered")
                }
                .font(.system(size: 12, weight: .medium)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.65))
                .labelStyle(NotchPrinterCompactLabel())
                .lineLimit(1)
            }
        }
    }

    private func finishTime(_ minutes: Int) -> String {
        Date().addingTimeInterval(TimeInterval(minutes * 60))
            .formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(l10n.language.formattingLocale()))
    }

    private var gauges: some View {
        HStack(spacing: 8) {
            NotchPrinterGauge(symbol: "square.stack.3d.up.fill", title: text.layerTitle,
                              value: layerText, fraction: layerFraction, tint: tint)
            heater(symbol: "flame.fill", title: text.nozzle, current: status.nozzle, target: status.nozzleTarget)
            heater(symbol: "square.bottomhalf.filled", title: text.bed, current: status.bed, target: status.bedTarget)
        }
    }

    private var layerText: String {
        guard let total = status.totalLayers, total > 0 else { return "–" }
        return "\(status.layer ?? 0)/\(total)"
    }

    private var layerFraction: Double? {
        guard let total = status.totalLayers, total > 0 else { return nil }
        return Double(status.layer ?? 0) / Double(total)
    }

    /// Orange while a heater works towards its target; quiet when it is off.
    private func heater(symbol: String, title: String, current: Double?, target: Double?) -> some View {
        let heating = (target ?? 0) > 0
        let fraction = heating ? current.map { min(1, max(0, $0 / target!)) } : nil
        return NotchPrinterGauge(symbol: symbol, title: title,
                                 value: current.map { NotchPrinterSupport.temperature($0) } ?? "–",
                                 detail: heating ? target.map { "→ " + NotchPrinterSupport.temperature($0) } : nil,
                                 fraction: fraction, tint: heating ? .orange : .white.opacity(0.35))
    }
}

/// Progress around the ring, the percentage inside it and the state's mark
/// when the job is not simply running.
private struct NotchPrinterRing: View {
    let status: PrinterStatus
    let tint: Color
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { Double(status.percent ?? 0) / 100 }

    var body: some View {
        GeometryReader { proxy in
            let line = max(7, proxy.size.width * 0.085)
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: line)
                Circle()
                    .trim(from: 0, to: max(0.001, fraction))
                    .stroke(AngularGradient(colors: [tint.opacity(0.55), tint], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360 * max(0.001, fraction))),
                            style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.45), radius: 6)
                VStack(spacing: 0) {
                    if status.state == .paused || status.state == .failed {
                        Image(systemName: status.state.symbol)
                            .font(.system(size: proxy.size.width * 0.16, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    Text("\(status.percent ?? 0)")
                        .font(.system(size: proxy.size.width * 0.28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    + Text("%")
                        .font(.system(size: proxy.size.width * 0.13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(status.percent ?? 0)%")
    }
}

private struct NotchPrinterStatePill: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
            .lineLimit(1)
    }
}

/// One measurement: its mark and name, its reading, and a thin bar of how
/// far along it is, kept even when empty so every tile has the same height.
private struct NotchPrinterGauge: View {
    let symbol: String
    let title: String
    let value: String
    var detail: String? = nil
    let fraction: Double?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .labelStyle(NotchPrinterCompactLabel())
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            GeometryReader { proxy in
                Capsule().fill(.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint)
                            .frame(width: proxy.size.width * (fraction ?? 0))
                    }
            }
            .frame(height: 4)
            .opacity(fraction == nil ? 0.5 : 1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct NotchPrinterCompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

private struct NotchPrinterSetupView: View {
    @ObservedObject private var printer = NotchPrinterService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchPrinterStrings { FeatureStrings.notchPrinter(l10n.language) }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: NotchModule.printer.symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if printer.connection == .connecting {
                ProgressView().controlSize(.small)
            } else {
                NotchPillButton(title: text.openSettings, prominent: true) {
                    NotchService.shared.openSettings(showing: .printer)
                }
            }
        }
        .frame(maxWidth: 360)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: String {
        switch printer.connection {
        case .connecting: return text.connecting
        case .refused: return text.signInAgain
        case .failed(let reason): return reason.map { text.unreachable + "\n" + $0 } ?? text.unreachable
        default: return text.setupHint
        }
    }
}

/// The closed island while a job runs: the printer at the left end and its
/// progress at the right, each anchored to its own edge.
struct NotchPrinterStrip: View {
    @ObservedObject var service: NotchService
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var printer = NotchPrinterService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { displayGeometry ?? service.compactActivityGeometry }
    private var iconSize: CGFloat { NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight) }
    private var textSize: CGFloat { NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight) }
    private var iconInset: CGFloat { geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2) }
    private var textInset: CGFloat { geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0) }
    private var tint: Color { NotchPrinterSupport.tint(for: printer.status.state) }

    var body: some View {
        Button { service.openActivity(.printer) } label: {
            HStack(spacing: 0) {
                Image(systemName: printer.status.state.symbol)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(tint)
                    .padding(.leading, iconInset)
                    .frame(width: geometry.compactActivityWingWidth, alignment: .leading)
                    .opacity(geometry.compactActivityWingWidth >= 28 ? 1 : 0)
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                Text(NotchPrinterSupport.stripReading(printer.status))
                    .font(.system(size: textSize, weight: .medium)).monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.trailing, textInset)
                    .frame(width: geometry.compactActivityWingWidth, alignment: .trailing)
                    .clipped()
            }
            .frame(height: geometry.compactActivityContentHeight)
            .padding(.horizontal, geometry.compactActivityHorizontalPadding)
            .padding(.top, geometry.compactActivityTopPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(FeatureStrings.notchPrinter(l10n.language).title)
        .accessibilityValue(NotchPrinterSupport.stripReading(printer.status))
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }
}
