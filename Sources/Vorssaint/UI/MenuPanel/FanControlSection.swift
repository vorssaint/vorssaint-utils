// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct FanControlSection: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var service = FanControlService(smc: SMCClient())
    @ObservedObject private var service = FanControlService.shared
    var collapsible = true

    private var strings: FanControlFeatureStrings {
        FeatureStrings.fanControl(l10n.language)
    }

    var body: some View {
        PanelSection(.fanControl, title: strings.title, collapsible: collapsible) {
            FanControlCardContent(strings: strings,
                                  betaLabel: l10n.s.betaBadge,
                                  snapshot: service.snapshot,
                                  accessState: service.accessState,
                                  error: service.error,
                                  isWorking: service.isWorking,
                                  remainingSeconds: service.remainingSeconds,
                                  authorize: service.authorize,
                                  startCooling: service.startMaximumCooling,
                                  stopCooling: service.restoreAutomatic)
                .panelCard()
                .onAppear { service.panelDidAppear() }
                .onDisappear { service.panelDidDisappear() }
        }
    }
}

                if service.fans.isEmpty {
                    Text("No fans detected or lacking SMC permission.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                } else {
                    ForEach($service.fans) { $fan in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(fan.name).font(.system(size: 11, weight: .medium))
                                Spacer()
                                Text("\(Int(fan.actualSpeed)) RPM").font(.system(size: 11)).monospacedDigit()
                            }
                            Picker("", selection: Binding(
                                get: { fan.isManual ? "manual" : "automatic" },
                                set: { mode in
                                    service.setManualMode(for: fan.id, manual: mode == "manual")
                                }
                            )) {
                                Text(l10n.s.fanControlModeAutomatic).tag("automatic")
                                Text(l10n.s.fanControlModeManual).tag("manual")
                            }
                            .pickerStyle(.segmented)
                            
                            if fan.isManual {
                                Slider(
                                    value: Binding(
                                        get: { fan.targetSpeed },
                                        set: { speed in
                                            service.setTargetSpeed(for: fan.id, speed: speed)
                                        }
                                    ),
                                    in: fan.minSpeed...fan.maxSpeed,
                                    step: 10
                                )
                                HStack {
                                    Text("\(Int(fan.minSpeed))").font(.system(size: 9)).foregroundStyle(.tertiary)
                                    Spacer()
                                    Text("\(Int(fan.maxSpeed))").font(.system(size: 9)).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .panelCard()
            .onAppear {
                service.refresh()
            }
struct FanControlCardContent: View {
    let strings: FanControlFeatureStrings
    let betaLabel: String
    let snapshot: FanControlSnapshot
    let accessState: FanControlService.AccessState
    let error: FanControlErrorCode?
    let isWorking: Bool
    let remainingSeconds: TimeInterval?
    let authorize: () -> Void
    let startCooling: () -> Void
    let stopCooling: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader

            if !snapshot.fans.isEmpty {
                fanRows
            }

            if let message = stateMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(messageIsError ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            action

            if controlsCanAppear {
                Text(strings.safetyCaption)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.secondary.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.isCooling ? "fanblades.fill" : "fanblades")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(snapshot.isCooling ? AnyShapeStyle(Color.cyan)
                                                     : AnyShapeStyle(Color.secondary))
                .symbolEffect(.variableColor.iterative, options: .repeating,
                              isActive: snapshot.isCooling)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(strings.title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(betaLabel)
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                }
                Text(statusText)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(snapshot.isCooling ? Color.cyan : Color.secondary)
            }
            Spacer()
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var fanRows: some View {
        VStack(spacing: 5) {
            ForEach(snapshot.fans) { fan in
                HStack(spacing: 6) {
                    Text(String(format: strings.fanNameFormat, fan.index + 1))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: strings.rpmFormat, Int(fan.actualRPM.rounded())))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                }
            }
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var action: some View {
        if error == .noFans || error == .unsupportedHardware || error == .alreadyControlled {
            EmptyView()
        } else if accessState == .notRegistered, !snapshot.fans.isEmpty {
            Button(strings.allowControl, action: authorize)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        } else if accessState == .requiresApproval, !snapshot.fans.isEmpty {
            Button(strings.openSettings, action: authorize)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        } else if accessState == .enabled, !snapshot.fans.isEmpty,
                  error == nil || snapshot.isCooling {
            if snapshot.isCooling {
                Button(strings.stopCooling, action: stopCooling)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isWorking)
                    .frame(maxWidth: .infinity)
            } else {
                Button(strings.startCooling, action: startCooling)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isWorking)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var statusText: String {
        guard snapshot.isCooling else { return strings.automatic }
        guard let remainingSeconds else { return strings.maximumCooling }
        let seconds = max(0, Int(remainingSeconds.rounded(.up)))
        return "\(strings.maximumCooling) · \(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private var stateMessage: String? {
        if error == .noFans { return strings.noFans }
        if accessState == .unavailable { return strings.unsupported }
        switch error {
        case .alreadyControlled: return strings.alreadyControlled
        case .unsupportedHardware: return strings.unsupported
        case .helperUnavailable, .controlFailed: return strings.failed
        case .authorizationRequired: return strings.approvalCaption
        case .noFans, .none: break
        }
        if accessState == .notRegistered, !snapshot.fans.isEmpty { return strings.approvalCaption }
        if accessState == .requiresApproval { return strings.approvalCaption }
        switch snapshot.stopReason {
        case .timeLimit: return strings.timeLimitStopped
        case .appDisconnected, .heartbeatLost, .hardwareChanged,
             .thermalPressure, .recovery:
            return strings.safetyStopped
        case .none:
            return nil
        }
    }

    private var messageIsError: Bool {
        switch error {
        case .alreadyControlled, .unsupportedHardware, .helperUnavailable, .controlFailed:
            return true
        default:
            return false
        }
    }

    private var controlsCanAppear: Bool {
        !snapshot.fans.isEmpty && (error == nil || snapshot.isCooling)
    }
}
