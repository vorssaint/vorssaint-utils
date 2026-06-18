// MemoryKill panel — vorssaint system monitor + real purge/kill actions.

import ServiceManagement
import SwiftUI

struct MemoryPanelView: View {
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var autoPurger = MemoryAutoPurger.shared
    @AppStorage(DefaultsKey.autoPurgeEnabled) private var autoPurgeEnabled = true
    @AppStorage(DefaultsKey.autoPurgeThreshold) private var autoPurgeThreshold = "warning"
    @AppStorage(DefaultsKey.autoPurgeNotify) private var autoPurgeNotify = true
    @AppStorage(DefaultsKey.purgeHotkeyEnabled) private var purgeHotkeyEnabled = true
    @AppStorage(DefaultsKey.optionClickPurge) private var optionClickPurge = true
    @AppStorage(DefaultsKey.monitorInterval) private var monitorInterval = 1
    @State private var statusMessage: String?
    @State private var isPurging = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                purgeCard
                maximizeCard
                SystemSection()
                quickActions
                footer
            }
            .padding(12)
            .frame(width: 332)
        }
        .frame(width: 332, height: 620)
        .onAppear {
            SystemMonitor.shared.setInterval(seconds: monitorInterval)
            syncHotkey()
        }
        .onChange(of: purgeHotkeyEnabled) { _, _ in syncHotkey() }
        .onChange(of: monitorInterval) { _, value in
            SystemMonitor.shared.setInterval(seconds: max(1, value))
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "memorychip")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(monitor.snapshot.memoryPressure.color)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(monitor.snapshot.memoryPressure.color.opacity(0.15))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(AppInfo.name)
                    .font(.system(size: 15, weight: .bold))
                if let used = monitor.snapshot.memoryUsed, monitor.snapshot.memoryTotal != nil {
                    Text("\(formatMemory(used)) used · \(formatMemory(MemoryPurgeService.reclaimableBytes())) free")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let used = monitor.snapshot.memoryUsed, let total = monitor.snapshot.memoryTotal, total > 0 {
                Text(String(format: "%.0f%%", Double(used) / Double(total) * 100))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(monitor.snapshot.memoryPressure.color)
            }
        }
    }

    private var purgeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FREE MEMORY")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(.secondary)

            Button { runPurge(.standard) } label: {
                Label(isPurging ? "Purging..." : "Purge Memory", systemImage: "bolt.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(monitor.snapshot.memoryPressure.color)
            .disabled(isPurging)

            HStack(spacing: 8) {
                Button("Deep Purge") { runPurge(.deep) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isPurging)

                Button("Kill Top Hog") {
                    statusMessage = MemoryPurgeService.killTopMemoryHog()
                    SystemMonitor.shared.refreshNow()
                }
                .help("Skips MemoryKill and system processes")
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .panelCard()
    }

    private var maximizeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MAXIMIZE")
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(.secondary)

            Button { runPurge(.max) } label: {
                Label("MAX Purge (everything)", systemImage: "flame.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isPurging)

            Text("Caches + DNS + 4× pressure passes + admin purge. Use when RAM is critically low.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Toggle("Auto-purge when pressure rises", isOn: $autoPurgeEnabled)
                .font(.system(size: 11))

            if autoPurgeEnabled {
                Picker("Threshold", selection: $autoPurgeThreshold) {
                    Text("Warning (75%+)").tag("warning")
                    Text("Critical only").tag("critical")
                }
                .font(.system(size: 11))
                if let last = autoPurger.lastAutoPurgeAt {
                    Text("Last auto-purge: \(last, style: .relative) ago")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }

            Toggle("Notify after auto-purge", isOn: $autoPurgeNotify)
                .font(.system(size: 11))

            Toggle("⌃⌥⌘K instant purge", isOn: $purgeHotkeyEnabled)
                .font(.system(size: 11))

            Toggle("⌥-click icon = purge", isOn: $optionClickPurge)
                .font(.system(size: 11))

            Toggle("Launch at login", isOn: $launchAtLogin)
                .font(.system(size: 11))
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            Picker("Refresh rate", selection: $monitorInterval) {
                Text("1 second").tag(1)
                Text("2 seconds").tag(2)
                Text("5 seconds").tag(5)
            }
            .font(.system(size: 11))
        }
        .panelCard()
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            Button("Flush DNS") { statusMessage = MemoryPurgeService.flushDNS() }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button("Clear Caches") {
                statusMessage = MemoryPurgeService.clearUserCaches()
                SystemMonitor.shared.refreshNow()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var footer: some View {
        HStack {
            Text("⌃⌥⌘K purge · ⌥-click purge")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func runPurge(_ mode: MemoryPurgeService.Mode) {
        guard !isPurging else { return }
        isPurging = true
        statusMessage = mode == .max ? "Running MAX purge..." : "Reclaiming memory..."
        MemoryPurgeService.purge(mode: mode) { result in
            isPurging = false
            statusMessage = result.message
            SystemMonitor.shared.refreshNow()
        }
    }

    private func syncHotkey() {
        HotkeyManager.shared.setEnabled(purgeHotkeyEnabled)
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}

private extension MemoryPressure {
    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .unknown: return .secondary
        }
    }
}