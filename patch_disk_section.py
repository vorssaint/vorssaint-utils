with open('Sources/Vorssaint/UI/MenuPanel/DiskSection.swift', 'r') as f:
    content = f.read()

hero = r"""    private func usageBlock(disk: DiskDeviceReading, editing: Bool) -> some View {
        if !diskUsage {
            PanelHiddenItemRow(title: l10n.s.monitorItemDiskUsage,
                               systemImage: "internaldrive",
                               isVisible: $diskUsage)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                blockHeader(l10n.s.monitorItemDiskUsage, editing: editing, visible: $diskUsage)
                VStack(alignment: .leading, spacing: 8) {
                    diskTitleRow(disk)
                    
                    HStack(alignment: .firstTextBaseline) {
                        Text(MetricFormat.diskBytes(disk.freeBytes))
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text(l10n.s.diskAvailable)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    DiskUsageBar(fraction: disk.usedFraction)
                    
                    HStack(spacing: 6) {
                        Text("\(MetricFormat.diskBytes(disk.usedBytes)) \(l10n.s.diskUsed) / \(MetricFormat.diskBytes(disk.totalBytes))")
                        Spacer()
                        let cleaner = JunkCleaner.shared
                        if cleaner.totalSize > 0 {
                            Text("\(MetricFormat.diskBytes(UInt64(cleaner.totalSize))) Reclaimable")
                                .foregroundStyle(PanelMetricColor.yellow(for: colorScheme))
                        } else if let purgeable = disk.purgeableBytes, purgeable >= 500_000_000 {
                            Text("\(MetricFormat.diskBytes(purgeable)) \(l10n.s.diskPurgeable)")
                        }
                    }
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                if AppFeature.cleaner.isAvailable && !JunkCleaner.shared.isScanning {
                    JunkCleaner.shared.scan()
                }
            }
        }
    }"""

import re
content = re.sub(r'    private func usageBlock\(disk: DiskDeviceReading, editing: Bool\) -> some View \{.*?(?=    @ViewBuilder\n    private func activityBlock)', hero + '\n\n', content, flags=re.DOTALL)

with open('Sources/Vorssaint/UI/MenuPanel/DiskSection.swift', 'w') as f:
    f.write(content)
