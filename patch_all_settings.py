with open('Sources/Vorssaint/UI/Settings/FeatureVisibilitySupport.swift', 'r') as f:
    content = f.read()

content = content.replace(
    'case mouse, switcher, keyDebounce, superKey, cutPaste, autoQuit, quitProtection, cleaner, uninstaller, urlCleaner, homebrew, appUpdates, media, clipboard, windowLayout, shelf, quickTools, textSnippets, screenshot, radialMenu, commandBar, killProcess',
    'case mouse, switcher, keyDebounce, superKey, cutPaste, autoQuit, inactiveApps, quitProtection, cleaner, uninstaller, urlCleaner, homebrew, appUpdates, media, clipboard, windowLayout, shelf, quickTools, textSnippets, screenshot, radialMenu, commandBar, killProcess'
)
content = content.replace(
    '        case .autoQuit: return FeatureSettingsDestination(.autoQuit)',
    '        case .autoQuit: return FeatureSettingsDestination(.autoQuit)\n        case .inactiveApps: return FeatureSettingsDestination(.inactiveApps)'
)
content = content.replace(
    '        case .autoQuit: return [.autoQuit]',
    '        case .autoQuit: return [.autoQuit]\n        case .inactiveApps: return [.inactiveApps]'
)

with open('Sources/Vorssaint/UI/Settings/FeatureVisibilitySupport.swift', 'w') as f:
    f.write(content)

with open('Sources/Vorssaint/UI/Settings/SettingsDirectory.swift', 'r') as f:
    dir_content = f.read()

item = """                SettingsDirectoryItem(page: .inactiveApps, title: "Inactive Apps", icon: "leaf.fill",
                                      keywords: ["idle", "memory", "quit", "leaf"]),
"""
if "page: .inactiveApps" not in dir_content:
    import re
    dir_content = re.sub(r'(                SettingsDirectoryItem\(page: \.autoQuit,.*?\n)', r'\1' + item, dir_content, flags=re.DOTALL)
    with open('Sources/Vorssaint/UI/Settings/SettingsDirectory.swift', 'w') as f:
        f.write(dir_content)

with open('Sources/Vorssaint/UI/Settings/SettingsView.swift', 'r') as f:
    view_content = f.read()

if "case .inactiveApps:" not in view_content:
    view_content = view_content.replace('            case .autoQuit:\n                AutoQuitSettings()', '            case .autoQuit:\n                AutoQuitSettings()\n            case .inactiveApps:\n                InactiveAppsSettings()')
    with open('Sources/Vorssaint/UI/Settings/SettingsView.swift', 'w') as f:
        f.write(view_content)
