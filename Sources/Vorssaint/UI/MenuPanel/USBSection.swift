// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct USBSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var usbMonitor = USBMonitorService.shared
    @Environment(\.colorScheme) private var colorScheme
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
                            usbDeviceRow(device)
                        }
                    }
                }
            }
            .panelCard()
        }
    }

    private func usbDeviceRow(_ device: USBDeviceItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.isExternalStorage ? "externaldrive.fill" : "cable.connector")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    if let vendor = device.vendor, !vendor.isEmpty, vendor != device.name {
                        Text("(\(vendor))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 6) {
                    Text(device.versionLabel)
                        .font(.system(size: 9.5, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                        )
                        .foregroundStyle(.secondary)

                    Text(device.speedLabel)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if device.isExternalStorage {
                Button {
                    usbMonitor.eject(device)
                } label: {
                    Image(systemName: "eject.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help(l10n.s.usbEject)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.02))
        )
    }
}
