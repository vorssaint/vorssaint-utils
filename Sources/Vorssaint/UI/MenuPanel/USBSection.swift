// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct USBSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var usbMonitor = USBMonitorService.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DefaultsKey.usbShowTechnicalDetails) private var showTechDetails = false
    var collapsible = true

    private var chargers: [USBDeviceItem] { usbMonitor.devices.filter { $0.category == .charger } }
    private var ethernetAdapters: [USBDeviceItem] { usbMonitor.devices.filter { $0.category == .ethernet } }
    private var usbDevices: [USBDeviceItem] { usbMonitor.devices.filter { $0.category == .usbDevice } }

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
                    VStack(spacing: 8) {
                        ForEach(chargers) { device in
                            powerSupplyRow(device)
                        }

                        ForEach(ethernetAdapters) { device in
                            usbDeviceRow(device)
                        }

                        if !usbDevices.isEmpty {
                            renderUSBDevicesList(usbDevices)
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
            let devColor = deviceColor(for: device)

            // Header Row: Icon + Name + Vendor + Eject
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(devColor.opacity(0.14))
                        .frame(width: 24, height: 24)

                    Image(systemName: device.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(devColor)
                }

                Text(device.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)

                Spacer(minLength: 4)

                if let vendor = device.cleanVendor {
                    Text(vendor)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
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
                            .fill(devColor.opacity(0.12))
                    )
                    .foregroundStyle(devColor)

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

            // Line 3 & 4: Version (BCD) + Serial Number (Stacked for full line width)
            if showTechDetails && (device.usbVersionBCD != nil || device.serialFormatted != nil) {
                VStack(alignment: .leading, spacing: 3) {
                    if device.usbVersionBCD != nil {
                        Text(device.bcdHexLabel)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    if let sn = device.serialFormatted {
                        HStack {
                            Text(sn)
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.primary.opacity(0.04))
                                )
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
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

    @ViewBuilder
    private func renderUSBDevicesList(_ devices: [USBDeviceItem]) -> some View {
        let allHubs = devices.filter { $0.isHub }
        let nonHubs = devices.filter { !$0.isHub }

        if !allHubs.isEmpty {
            let hubIDs = Set(allHubs.map { $0.id })
            let masterHub = allHubs.max(by: { ($0.speedMbps ?? 0) < ($1.speedMbps ?? 0) }) ?? allHubs[0]

            // Devices physically connected under hub chips
            let hubChildren = nonHubs.filter { dev in
                guard let pId = dev.parentId else { return false }
                return hubIDs.contains(pId)
            }

            // Standalone devices connected directly to Mac ports (e.g. SL300 SSD, TP-Link LAN)
            let standaloneDevices = nonHubs.filter { dev in
                guard let pId = dev.parentId else { return true }
                return !hubIDs.contains(pId)
            }

            VStack(spacing: 8) {
                if !hubChildren.isEmpty || !allHubs.isEmpty {
                    masterHubContainer(hub: masterHub, childDevices: hubChildren)
                }

                ForEach(standaloneDevices) { device in
                    usbDeviceRow(device)
                }
            }
        } else {
            VStack(spacing: 6) {
                ForEach(nonHubs) { device in
                    usbDeviceRow(device)
                }
            }
        }
    }

    private func masterHubContainer(hub: USBDeviceItem, childDevices: [USBDeviceItem]) -> some View {
        let hubTitle = (hub.vendor != nil && !hub.vendor!.isEmpty && hub.vendor != hub.name) ? "\(hub.name) (\(hub.vendor!))" : hub.name

        return VStack(alignment: .leading, spacing: 6) {
            // Master Hub Header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.blue.opacity(0.16))
                        .frame(width: 24, height: 24)

                    Image(systemName: "rectangle.grid.2x2.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.blue)
                }

                Text(hubTitle)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                Text(hub.speedLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.12))
                    )
                    .foregroundStyle(Color.blue)
            }

            // Indented Children Sub-Devices
            if !childDevices.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(childDevices) { child in
                        HStack(spacing: 6) {
                            Rectangle()
                                .fill(Color.blue.opacity(0.35))
                                .frame(width: 2)
                                .padding(.vertical, 2)

                            usbDeviceRow(child)
                        }
                    }
                }
                .padding(.leading, 6)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.blue.opacity(0.18), lineWidth: 0.8)
        )
    }

    private func deviceColor(for device: USBDeviceItem) -> Color {
        if device.category == .charger { return .orange }
        if device.category == .ethernet { return .green }
        let combined = "\(device.name) \(device.vendor ?? "")".lowercased()
        if combined.contains("ax88") || combined.contains("rtl81") || combined.contains("ethernet") || combined.contains("lan adapter") || combined.contains("asix") {
            return .green
        }
        if combined.contains("wlan") || combined.contains("wifi") || combined.contains("802.11") || combined.contains("wireless") {
            return .cyan
        }
        if combined.contains("display") || combined.contains("monitor") || combined.contains("hdmi") || combined.contains("billboard") || combined.contains("displaylink") {
            return .indigo
        }
        guard let mbps = device.speedMbps else { return .secondary }
        if mbps >= 40000 { return .purple } // USB4 / Thunderbolt 3/4/5
        if mbps >= 5000 { return .blue }    // USB 3.0 / 3.1 / 3.2 SuperSpeed
        return .secondary                   // USB 1.1 / 2.0 High Speed
    }
}
