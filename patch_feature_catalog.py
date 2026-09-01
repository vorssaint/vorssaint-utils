with open('Sources/Vorssaint/Core/FeatureCatalog.swift', 'r') as f:
    content = f.read()

# Add to enum
content = content.replace('         commandBar, screenRecorder, killProcess', '         commandBar, screenRecorder, killProcess, inactiveApps')

# Add to group
content = content.replace('        case .quickLauncher, .quickToggles, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,\n             .cleaner, .uninstaller, .homebrew, .appUpdates, .screenshot, .cameraPreview, .radialMenu, .scratchpad, .commandBar, .screenRecorder, .killProcess:\n            return .tools', '        case .quickLauncher, .quickToggles, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,\n             .cleaner, .uninstaller, .homebrew, .appUpdates, .screenshot, .cameraPreview, .radialMenu, .scratchpad, .commandBar, .screenRecorder, .killProcess, .inactiveApps:\n            return .tools')

# Add to symbolName
content = content.replace('        case .autoQuit, .quitWindowProtection: return "rectangle.badge.xmark"', '        case .autoQuit, .quitWindowProtection: return "rectangle.badge.xmark"\n        case .inactiveApps: return "leaf.fill"')

# Add to enabledKeys
content = content.replace('        case .killProcess: return []', '        case .killProcess: return []\n        case .inactiveApps: return [DefaultsKey.inactiveAppsEnabled]')

# Add to permissions
content = content.replace('        case .monitorCPU, .monitorMemory, .monitorDisk, .monitorPower: return [.notifications]', '        case .monitorCPU, .monitorMemory, .monitorDisk, .monitorPower: return [.notifications]\n        case .inactiveApps: return [.notifications]')

content = content.replace('             .scratchpad, .monitorGPU, .monitorNetwork, .fanControl, .killProcess:\n            return []', '             .scratchpad, .monitorGPU, .monitorNetwork, .fanControl, .killProcess:\n            return []')

# Add to activeFeatures (notifications gating)
content = content.replace('            case (.monitorPower, .notifications):\n                return boolFor(DefaultsKey.monitorAlertBattery)\n                    || boolFor(DefaultsKey.monitorAlertBatteryTemperature)', '            case (.monitorPower, .notifications):\n                return boolFor(DefaultsKey.monitorAlertBattery)\n                    || boolFor(DefaultsKey.monitorAlertBatteryTemperature)\n            case (.inactiveApps, .notifications):\n                return boolFor(DefaultsKey.inactiveAppsEnabled)')

with open('Sources/Vorssaint/Core/FeatureCatalog.swift', 'w') as f:
    f.write(content)
