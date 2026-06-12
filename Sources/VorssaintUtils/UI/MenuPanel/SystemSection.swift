import SwiftUI

/// Which per-app breakdown is expanded in the System section.
enum BreakdownKind {
    case cpu, gpu, memory
}

/// The "System" section of the panel: component temperatures, hardware usage
/// and memory pressure — only the readings that matter, presented cleanly.
/// Tapping CPU, GPU or Memory expands the top consumers of that resource.
struct SystemSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @State private var expanded: BreakdownKind?
    @State private var breakdownRows: [ProcessUsage] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(l10n.s.systemSection)
            VStack(alignment: .leading, spacing: 10) {
                temperatureGrid
                Divider()
                usageRows
                Divider()
                memoryRows
            }
            .panelCard()
        }
        .onReceive(monitor.$snapshot) { _ in
            refreshBreakdown()
        }
        .onDisappear {
            expanded = nil
            breakdownRows = []
        }
    }

    // MARK: Per-app breakdown

    private func toggleBreakdown(_ kind: BreakdownKind) {
        if expanded == kind {
            expanded = nil
            breakdownRows = []
        } else {
            expanded = kind
            breakdownRows = []
            refreshBreakdown()
        }
    }

    private func refreshBreakdown() {
        guard let kind = expanded else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let rows: [ProcessUsage]
            switch kind {
            case .cpu: rows = ProcessUsageService.shared.topCPU()
            case .gpu: rows = ProcessUsageService.shared.topGPU()
            case .memory: rows = ProcessUsageService.shared.topMemory()
            }
            DispatchQueue.main.async {
                guard expanded == kind else { return }
                breakdownRows = rows
            }
        }
    }

    @ViewBuilder
    private func breakdownList(for kind: BreakdownKind) -> some View {
        if expanded == kind {
            VStack(alignment: .leading, spacing: 4) {
                if breakdownRows.isEmpty {
                    Text(l10n.s.breakdownMeasuring)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 38)
                } else {
                    ForEach(breakdownRows) { row in
                        HStack(spacing: 6) {
                            Image(nsImage: ResponsibleProcess.icon(for: row.pid))
                                .resizable()
                                .frame(width: 14, height: 14)
                            Text(row.name)
                                .font(.system(size: 10.5))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(kind == .memory ? formatMemory(UInt64(row.value))
                                                 : String(format: "%.1f%%", row.value))
                                .font(.system(size: 10.5, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 38)
                    }
                }
            }
            .transition(.opacity)
        }
    }


    // MARK: Temperatures

    private var temperatureGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            subsectionLabel(l10n.s.temperatures)
            HStack(spacing: 8) {
                temperatureCell(icon: "cpu", label: l10n.s.cpuLabel,
                                value: monitor.snapshot.cpuTemperature)
                temperatureCell(icon: "memorychip", label: l10n.s.gpuLabel,
                                value: monitor.snapshot.gpuTemperature)
                temperatureCell(icon: "battery.100", label: l10n.s.batteryLabel,
                                value: monitor.snapshot.batteryTemperature)
            }
            if monitor.snapshot.cpuTemperature == nil,
               monitor.snapshot.gpuTemperature == nil,
               monitor.snapshot.batteryTemperature == nil {
                Text(l10n.s.monitorUnavailable)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func temperatureCell(icon: String, label: String, value: Double?) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(value.map { String(format: "%.0f °C", $0) } ?? "—")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    // MARK: Hardware usage

    private var usageRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            subsectionLabel(l10n.s.usageSection)
            usageRow(label: l10n.s.cpuLabel, fraction: monitor.snapshot.cpuUsage, kind: .cpu)
            breakdownList(for: .cpu)
            usageRow(label: l10n.s.gpuLabel, fraction: monitor.snapshot.gpuUsage, kind: .gpu)
            breakdownList(for: .gpu)
        }
    }

    private func usageRow(label: String, fraction: Double?, kind: BreakdownKind) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { toggleBreakdown(kind) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded == kind ? 90 : 0))
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .leading)
                UsageBar(fraction: fraction ?? 0)
                Text(fraction.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Memory

    private var memoryRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            subsectionLabel(l10n.s.memorySection)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { toggleBreakdown(.memory) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded == .memory ? 90 : 0))
                    Text(l10n.s.memoryPressure)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    PressureIndicator(pressure: monitor.snapshot.memoryPressure)
                    Spacer()
                    if let used = monitor.snapshot.memoryUsed, let total = monitor.snapshot.memoryTotal {
                        Text("\(formatMemory(used)) / \(formatMemory(total))")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            breakdownList(for: .memory)
        }
    }

    private func subsectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// Thin capacity bar for CPU/GPU usage.
private struct UsageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(barColor)
                    .frame(width: max(3, proxy.size.width * min(1, fraction)))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
        }
        .frame(height: 5)
    }

    private var barColor: Color {
        switch fraction {
        case ..<0.6: return .accentColor
        case ..<0.85: return .yellow
        default: return .red
        }
    }
}

/// Traffic-light pill for memory pressure: green = normal, yellow = caution,
/// red = critical.
struct PressureIndicator: View {
    @ObservedObject private var l10n = L10n.shared
    let pressure: MemoryPressure

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.6), radius: 2)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.13)))
    }

    private var color: Color {
        switch pressure {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .unknown: return .secondary
        }
    }

    private var label: String {
        switch pressure {
        case .normal: return l10n.s.pressureNormal
        case .warning: return l10n.s.pressureWarning
        case .critical: return l10n.s.pressureCritical
        case .unknown: return "—"
        }
    }
}
