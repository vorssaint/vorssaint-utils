with open('Sources/Vorssaint/UI/Settings/FeatureHubSettings.swift', 'r') as f:
    content = f.read()

content = content.replace(
    '        case .autoQuit: return s.autoQuitName',
    '        case .autoQuit: return s.autoQuitName\n        case .inactiveApps: return "Inactive Apps"'
)

with open('Sources/Vorssaint/UI/Settings/FeatureHubSettings.swift', 'w') as f:
    f.write(content)
