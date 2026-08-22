// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct DeepMetricsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var loading = true
    
    @State private var batteryInfo = ""
    @State private var storageInfo = ""
    @State private var networkInfo = ""
    @State private var cpuGpuInfo = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(PanelMetricColor.cyan(for: colorScheme))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Relatório Profundo")
                        .font(.title2.bold())
                    Text("Hardware & Powermetrics")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fechar") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()

            if loading {
                loadingView
            } else {
                metricsScrollView
            }
        }
        .frame(width: 700, height: 600)
        .onAppear {
            DispatchQueue.global().async {
                let battery = HardwareInfo.getBatteryInfo()
                let storage = HardwareInfo.getStorageInfo()
                let network = HardwareInfo.getNetworkInfo()
                let cpuGpu = runSudoAppleScript(commands: ["/usr/bin/powermetrics -n 1 --samplers cpu_power,gpu_power,thermal,tasks"])
                
                DispatchQueue.main.async {
                    self.batteryInfo = battery
                    self.storageInfo = storage
                    self.networkInfo = network
                    self.cpuGpuInfo = cpuGpu
                    self.loading = false
                }
            }
        }
    }
    
    private func runSudoAppleScript(commands: [String]) -> String {
        let script = "do shell script \"\(commands.joined(separator: " && "))\" with administrator privileges"
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let output = appleScript.executeAndReturnError(&error)
            if let err = error {
                return "Error: \(err)"
            }
            return output.stringValue ?? "Success"
        }
        return "AppleScript initialization failed."
    }
    
    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Coletando métricas profundas e autenticando...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
    }
    
    @ViewBuilder
    private var metricsScrollView: some View {
        ScrollView {
            VStack(spacing: 20) {
                MetricCard(title: "Bateria e Energia", icon: "battery.100.bolt", color: PanelMetricColor.green(for: colorScheme), content: batteryInfo)
                MetricCard(title: "Armazenamento", icon: "internaldrive.fill", color: PanelMetricColor.orange(for: colorScheme), content: storageInfo)
                MetricCard(title: "Rede", icon: "network", color: PanelMetricColor.cyan(for: colorScheme), content: networkInfo)
                MetricCard(title: "CPU / GPU (Sudo)", icon: "memorychip.fill", color: PanelMetricColor.pink(for: colorScheme), content: cpuGpuInfo)
            }
            .padding(20)
        }
        .background(Color(NSColor.underPageBackgroundColor))
    }
}

private struct MetricCard: View {
    let title: String
    let icon: String
    let color: Color
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .bold))
            }
            
            Divider()
            
            Text(content)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .lineSpacing(2)
                .foregroundStyle(.primary.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}
