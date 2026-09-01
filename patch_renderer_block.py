with open('Sources/Vorssaint/App/MenuBarRenderer.swift', 'r') as f:
    content = f.read()

old_block = """            case .diskUsage:
                if let disk = primaryDisk(from: snapshot.disk) {
                    if usesBars {
                        groups.append([.usageBarBlock(label: "DSK",
                                                      fraction: disk.usedFraction,
                                                      style: style,
                                                      pressure: nil)])
                    } else {
                        groups.append([.metricBlock(label: "DSK",
                                                    value: percent(disk.usedFraction),
                                                    minimumValue: "100%",
                                                    style: style,
                                                    pressure: nil)])
                    }
                }"""

new_block = """            case .diskUsage:
                if let disk = primaryDisk(from: snapshot.disk) {
                    if usesBars {
                        groups.append([.usageBarBlock(label: "DSK",
                                                      fraction: disk.usedFraction,
                                                      style: style,
                                                      pressure: nil)])
                    } else {
                        let valueText: String
                        let minVal: String
                        switch DiskMenuBarStyle.current {
                        case .free:
                            valueText = MetricFormat.diskBytes(disk.freeBytes)
                            minVal = "999 GB"
                        case .percent:
                            valueText = percent(disk.usedFraction)
                            minVal = "100%"
                        case .both:
                            valueText = MetricFormat.diskBytes(disk.freeBytes) + " · " + percent(disk.usedFraction)
                            minVal = "999 GB · 100%"
                        }
                        groups.append([.metricBlock(label: "DSK",
                                                    value: valueText,
                                                    minimumValue: minVal,
                                                    style: style,
                                                    pressure: nil)])
                    }
                }"""

content = content.replace(old_block, new_block)

# Also update reservedWidth
width_old = """        case (_, .diskUsage):
            return 11      // symbol + " DSK 100%\""""
width_new = """        case (_, .diskUsage):
            switch DiskMenuBarStyle.current {
            case .free: return 14
            case .percent: return 11
            case .both: return 20
            }"""

content = content.replace(width_old, width_new)

with open('Sources/Vorssaint/App/MenuBarRenderer.swift', 'w') as f:
    f.write(content)
