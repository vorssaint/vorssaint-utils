with open('Sources/Vorssaint/UI/Settings/MonitorSettings.swift', 'r') as f:
    content = f.read()

disk_option = """
private struct DiskMenuBarOrderOption: View {
    @AppStorage(DefaultsKey.menuBarDiskUsage) private var menuBarDiskUsage = false
    @AppStorage(DefaultsKey.menuBarDiskStyle) private var diskStyle = "free"

    var body: some View {
        if menuBarDiskUsage {
            HStack(spacing: 8) {
                Text("Style")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("", selection: $diskStyle) {
                    Text("Free").tag("free")
                    Text("Percentage").tag("percent")
                    Text("Both").tag("both")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)
                Spacer()
            }
            .padding(.leading, 32)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .onAppear {
                diskStyle = Defaults.sanitizedMenuBarDiskStyle(diskStyle)
            }
        }
    }
}
"""
content = content.replace('private struct MenuBarMetricVisibilityToggle: View {', disk_option + '\nprivate struct MenuBarMetricVisibilityToggle: View {')

with open('Sources/Vorssaint/UI/Settings/MonitorSettings.swift', 'w') as f:
    f.write(content)
