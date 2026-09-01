// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct BKBatteryHeroView: View {
    @ObservedObject private var l10n = L10n.shared
    var power: PowerReading?
    
    @State private var boltOpacity: Double = 0.5
    @State private var boltScale: CGFloat = 0.9
    
    private var percentage: Double {
        Double(power?.chargePercent ?? 0)
    }
    
    private var isCharging: Bool {
        power?.isCharging == true
    }
    
    private var isConnected: Bool {
        power?.externalConnected == true
    }
    
    private var ringColor: [Color] {
        let pct = percentage
        if pct < 20 { return [Color.red, Color.orange] }
        if pct < 50 { return [Color.orange, Color.yellow] }
        if pct >= 100 { return [Color.green, Color.teal] }
        return [Color.green, Color.cyan, Color.blue]
    }
    
    private var statusLabel: String {
        let pct = Int(percentage)
        
        if pct >= 100 && isCharging {
            return l10n.s.powerPluggedIn
        }
        if isCharging {
            if let secs = power?.timeRemainingSeconds {
                if let formatted = BatteryTimeSupport.formatted(seconds: secs) {
                    return "\(formatted) to full"
                }
            }
            return FeatureStrings.batteryTime(l10n.language).calculating
        }
        
        if isConnected {
            return "Optimized (on hold)"
        }
        
        if let secs = power?.timeRemainingSeconds, let formatted = BatteryTimeSupport.formatted(seconds: secs) {
            return formatted
        }
        
        if power?.timeRemainingSeconds == nil && !isCharging && power?.hasBattery == true {
             return FeatureStrings.batteryTime(l10n.language).calculating
        }
        return ""
    }
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.06), lineWidth: 8)
                
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(max(percentage / 100.0, 0.0), 1.0)))
                    .stroke(
                        LinearGradient(colors: ringColor, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: percentage)
                
                VStack(spacing: 2) {
                    Text("\(Int(percentage))%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.3), value: percentage)
                    
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.yellow)
                            .shadow(color: Color.yellow.opacity(0.4), radius: 3, x: 0, y: 0)
                            .scaleEffect(boltScale)
                            .opacity(boltOpacity)
                            .onAppear {
                                withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                                    boltOpacity = 1.0
                                    boltScale = 1.1
                                }
                            }
                    }
                }
            }
            .frame(width: 90, height: 90)
            
            VStack(spacing: 3) {
                if let watts = power?.batteryWatts, abs(watts) > 0.1 {
                    HStack(spacing: 4) {
                        Image(systemName: isCharging ? "bolt.fill" : "bolt.horizontal.fill")
                            .font(.system(size: 9))
                        Text(MetricFormat.watts(abs(watts)))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(isCharging ? .yellow.opacity(0.9) : .secondary)
                    .animation(.easeOut(duration: 0.3), value: isCharging)
                }
                
                HStack(spacing: 8) {
                    if let temp = SystemMonitor.shared.snapshot.batteryTemperature, temp > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "thermometer.medium")
                                .font(.system(size: 9))
                            Text(String(format: "%.0f°C", temp))
                                .font(.system(size: 10))
                        }
                        .foregroundColor(temp > 40 ? .orange : .secondary.opacity(0.8))
                    }
                    
                    if let health = power?.healthPercent, health < 100 {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                            Text(String(format: "%.0f%%", health))
                                .font(.system(size: 10))
                        }
                        .foregroundColor(health < 80 ? .orange : .secondary.opacity(0.8))
                    }
                    
                    if let cycles = power?.cycleCount {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.trianglehead.2.clockwise")
                                .font(.system(size: 9))
                            Text("\(cycles)")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                
                let label = statusLabel
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.3), value: label)
                }
                
                let peripherals = SystemMonitor.shared.snapshot.peripheralBatteries
                if !peripherals.isEmpty {
                    Divider().padding(.vertical, 4)
                    ForEach(PeripheralBatterySupport.sorted(peripherals)) { device in
                        HStack(spacing: 8) {
                            Image(systemName: peripheralIcon(for: device.kind))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(width: 10)
                            Text(device.name)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(device.percent)%")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(device.percent < 20 ? Color.red : .primary)
                        }
                    }
                }
            }
            
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func peripheralIcon(for kind: PeripheralBatteryKind) -> String {
        switch kind {
        case .keyboard: return "keyboard"
        case .mouse: return "magicmouse"
        case .trackpad: return "magicmouse.fill"
        case .audio: return "airpods"
        case .device: return "battery.100"
        }
    }
}
