with open('Sources/Vorssaint/App/FeatureRuntime.swift', 'r') as f:
    content = f.read()

# Add to the dictionary
content = content.replace('        .autoQuit: { AutoQuitService.shared.syncWithPreferences() },\n', '        .autoQuit: { AutoQuitService.shared.syncWithPreferences() },\n        .inactiveApps: { InactiveAppService.shared.syncWithPreferences() },\n')

with open('Sources/Vorssaint/App/FeatureRuntime.swift', 'w') as f:
    f.write(content)
