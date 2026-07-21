// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct USBSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var usbMonitor = USBMonitorService.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DefaultsKey.usbShowTechnicalDetails) private var showTechDetails = true
    var collapsible = true

    var body: some View {
        PanelSection(.usb, title: l10n.s.usbSection, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(l10n.s.usbConnectedDevices)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showTechDetails.toggle()
                        }
                    } label: {
                        Image(systemName: showTechDetails ? "info.circle.fill" : "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(showTechDetails ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.s.usbShowTechDetails)

                    Button {
                        usbMonitor.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.s.homebrewRefresh)
                }

                if usbMonitor.devices.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "cable.connector.slash")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                        Text(l10n.s.usbNoDevices)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                } else {
                    VStack(spacing: 6) {
                        ForEach(usbMonitor.devices) { device in
                            if device.category == .charger {
                                powerSupplyRow(device)
                            } else {
                                usbDeviceRow(device)
                            }
                        }
                    }
                }
            }
            .panelCard()
        }
    }

    private func usbDeviceRow(_ device: USBDeviceItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: device.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                    )

                Text(device.name)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)

                Spacer()

                if let vendor = device.vendor, !vendor.isEmpty, vendor != device.name {
                    Text(vendor)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if device.isExternalStorage {
                    Button {
                        usbMonitor.eject(device)
                    } label: {
                        Image(systemName: "eject.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(l10n.s.usbEject)
                }
            }

            HStack(alignment: .center, spacing: 6) {
                Text(device.speedLabel)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if showTechDetails && !device.hexVIDPID.isEmpty {
                    Text(device.hexVIDPID)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if !showTechDetails {
                    Text(device.versionLabel)
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                        )
                        .foregroundStyle(.secondary)
                }
            }

            if showTechDetails && (device.usbVersionBCD != nil || device.serialFormatted != nil) {
                HStack(alignment: .center, spacing: 6) {
                    if device.usbVersionBCD != nil {
                        Text(device.bcdHexLabel)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if let sn = device.serialFormatted {
                        Text(sn)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.02))
        )
    }

    private func powerSupplyRow(_ device: USBDeviceItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.accentColor)

            Text(device.name)
                .font(.system(size: 12, weight: .bold))

            if let tag = device.vendor, !tag.isEmpty {
                Text(tag)
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.12))
                    )
                    .foregroundStyle(Color.accentColor)
            }

            Spacer()

            Text(device.speedLabel)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.02))
        )
    }
}
