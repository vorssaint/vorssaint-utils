with open('Sources/Vorssaint/UI/Settings/FeatureVisibilitySupport.swift', 'r') as f:
    content = f.read()

content = content.replace(
    '        case .autoQuit: return FeatureSettingsDestination(.autoQuit)',
    '        case .autoQuit: return FeatureSettingsDestination(.autoQuit)\n        case .inactiveApps: return FeatureSettingsDestination(.autoQuit) // Fallback to AutoQuit view or create .inactiveApps if it exists'
)

# wait, is there a FeatureSettingsDestination(.inactiveApps)? I didn't create one. Let's see FeatureSettingsDestination in SettingsDirectory.swift.
