// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct USBSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var usbMonitor = USBMonitorService.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DefaultsKey.usbShowTechnicalDetails) private var showTechDetails = false
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
        VStack(alignment: .leading, spacing: 6) {
            // Header Row: Icon + Name + Vendor + Eject
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: 24, height: 24)

                    Image(systemName: device.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                Text(device.name)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let vendor = device.vendor, !vendor.isEmpty, vendor != device.name {
                    Text(vendor)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if device.isExternalStorage {
                    Button {
                        usbMonitor.eject(device)
                    } label: {
                        Image(systemName: "eject.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(l10n.s.usbEject)
                }
            }

            // Line 2: Speed Badge + VID:PID Chip
            HStack(alignment: .center, spacing: 6) {
                Text(device.speedLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.12))
                    )
                    .foregroundStyle(Color.accentColor)

                Spacer(minLength: 4)

                if showTechDetails && !device.hexVIDPID.isEmpty {
                    Text(device.hexVIDPID)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                        .foregroundStyle(.secondary)
                } else if !showTechDetails {
                    Text(device.versionLabel)
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        )
                        .foregroundStyle(.secondary)
                }
            }

            // Line 3: Version (BCD) + Serial Number (Technical Details Mode)
            if showTechDetails && (device.usbVersionBCD != nil || device.serialFormatted != nil) {
                HStack(alignment: .center, spacing: 6) {
                    if device.usbVersionBCD != nil {
                        Text(device.bcdHexLabel)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    if let sn = device.serialFormatted {
                        Text(sn)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.primary.opacity(0.04))
                            )
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private func powerSupplyRow(_ device: USBDeviceItem) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.orange.opacity(0.14))
                    .frame(width: 22, height: 22)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.orange)
            }

            Text(device.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)

            if let tag = device.vendor, !tag.isEmpty {
                Text(tag)
                    .font(.system(size: 9.5, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.12))
                    )
                    .foregroundStyle(Color.orange)
            }

            Spacer()

            Text(device.speedLabel)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}
