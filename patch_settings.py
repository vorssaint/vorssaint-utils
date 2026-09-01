import re

with open('Sources/Vorssaint/UI/Settings/SettingsDirectory.swift', 'r') as f:
    content = f.read()

# Add to SettingsPage enum
content = content.replace('    case autoQuit\n', '    case autoQuit\n    case inactiveApps\n')

# Add to directory array
item = """                SettingsDirectoryItem(page: .inactiveApps, title: "Inactive Apps", icon: "leaf.fill",
                                      keywords: ["idle", "memory", "quit", "leaf"]),
"""
content = content.replace('                SettingsDirectoryItem(page: .autoQuit, title: s.autoQuitName, icon: "xmark.rectangle",\n                                      keywords: [s.autoQuitEnable]),\n', '                SettingsDirectoryItem(page: .autoQuit, title: s.autoQuitName, icon: "xmark.rectangle",\n                                      keywords: [s.autoQuitEnable]),\n' + item)

with open('Sources/Vorssaint/UI/Settings/SettingsDirectory.swift', 'w') as f:
    f.write(content)

with open('Sources/Vorssaint/UI/Settings/SettingsView.swift', 'r') as f:
    content2 = f.read()

content2 = content2.replace('            case .autoQuit:\n                AutoQuitSettings()\n', '            case .autoQuit:\n                AutoQuitSettings()\n            case .inactiveApps:\n                InactiveAppsSettings()\n')

with open('Sources/Vorssaint/UI/Settings/SettingsView.swift', 'w') as f:
    f.write(content2)
