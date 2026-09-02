with open('Sources/Vorssaint/UI/Settings/FeatureHubSettings.swift', 'r') as f:
    content = f.read()

# Fix hubTitle
content = content.replace(
    '        case .autoQuit: return s.autoQuitSection',
    '        case .autoQuit: return s.autoQuitSection\n        case .inactiveApps: return "Inactive Apps"'
)

# Fix hubDescription
content = content.replace(
    '        case .autoQuit: return hub.descAutoQuit',
    '        case .autoQuit: return hub.descAutoQuit\n        case .inactiveApps: return "Monitor and quit idle background apps to save memory."'
)

with open('Sources/Vorssaint/UI/Settings/FeatureHubSettings.swift', 'w') as f:
    f.write(content)
