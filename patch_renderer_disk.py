with open('Sources/Vorssaint/App/MenuBarRenderer.swift', 'r') as f:
    content = f.read()

enum_str = """
enum DiskMenuBarStyle: String, CaseIterable {
    case free, percent, both

    static var current: DiskMenuBarStyle {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.menuBarDiskStyle) ?? ""
        let style = Defaults.sanitizedMenuBarDiskStyle(raw)
        return DiskMenuBarStyle(rawValue: style) ?? .free
    }
}
"""
content = content.replace('enum MemoryMenuBarStyle: String, CaseIterable {', enum_str + '\nenum MemoryMenuBarStyle: String, CaseIterable {')

metric = """            case .diskUsage:
                if let disk = primaryDisk(from: snapshot.disk) {
                    let text: String
                    switch DiskMenuBarStyle.current {
                    case .free:
                        text = "DSK " + MetricFormat.diskBytes(disk.freeBytes)
                    case .percent:
                        text = "DSK " + percent(disk.usedFraction)
                    case .both:
                        text = "DSK " + MetricFormat.diskBytes(disk.freeBytes) + " · " + percent(disk.usedFraction)
                    }
                    items.append(MetricItem(metric: metric,
                                            segments: [.symbol(metric.symbolName), .text(" " + text)],
                                            width: reservedWidth(for: metric, preset: preset)))
                }"""
import re
content = re.sub(r'            case \.diskUsage:\n                if let disk = primaryDisk\(from: snapshot\.disk\) \{\n                    let text = "DSK " \+ percent\(disk\.usedFraction\)\n                    items\.append\(MetricItem\(metric: metric,\n                                            segments: \[\.symbol\(metric\.symbolName\), \.text\(" " \+ text\)\],\n                                            width: reservedWidth\(for: metric, preset: preset\)\)\)\n                \}', metric, content)

block = """            case .diskUsage:
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
content = re.sub(r'            case \.diskUsage:\n                if let disk = primaryDisk\(from: snapshot\.disk\) \{\n                    if usesBars \{\n                        groups\.append\(\[\.usageBarBlock\(label: "DSK",\n                                                      fraction: disk\.usedFraction,\n                                                      style: style,\n                                                      pressure: nil\)\)\n                    \} else \{\n                        groups\.append\(\[\.metricBlock\(label: "DSK",\n                                                    value: percent\(disk\.usedFraction\),\n                                                    minimumValue: "100%",\n                                                    style: style,\n                                                    pressure: nil\)\)\]\)\n                    \}\n                \}', block, content)
# wait, groups.append([.usageBarBlock(...)]) not )). Let's just use string replace.

with open('Sources/Vorssaint/App/MenuBarRenderer.swift', 'w') as f:
    f.write(content)
