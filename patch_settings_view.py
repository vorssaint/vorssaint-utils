with open('Sources/Vorssaint/UI/Settings/SettingsView.swift', 'r') as f:
    content = f.read()

import re
# Look for case .autoQuit: AutoQuitSettings() and add inactiveApps next to it
if 'case .autoQuit: AutoQuitSettings()' in content:
    content = content.replace('case .autoQuit: AutoQuitSettings()', 'case .autoQuit: AutoQuitSettings()\n        case .inactiveApps: InactiveAppsSettings()')
else:
    # Just add it before case .none
    content = content.replace('case .none:', 'case .inactiveApps: InactiveAppsSettings()\n        case .none:')

with open('Sources/Vorssaint/UI/Settings/SettingsView.swift', 'w') as f:
    f.write(content)
