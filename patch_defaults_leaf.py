with open('Sources/Vorssaint/Core/Defaults.swift', 'r') as f:
    content = f.read()

keys = """    static let inactiveAppsEnabled = "inactiveAppsEnabled"
    static let inactiveAppsIdleMinutes = "inactiveAppsIdleMinutes"
    static let inactiveAppsMemoryFloorMB = "inactiveAppsMemoryFloorMB"
    static let inactiveAppsAutoQuit = "inactiveAppsAutoQuit"
    static let inactiveAppsExceptions = "inactiveAppsExceptions"
"""
content = content.replace('    static let autoQuitEnabled = "autoQuitEnabled"\n', '    static let autoQuitEnabled = "autoQuitEnabled"\n' + keys)

defaults = """        DefaultsKey.inactiveAppsEnabled: false,
        DefaultsKey.inactiveAppsIdleMinutes: 60,
        DefaultsKey.inactiveAppsMemoryFloorMB: 500,
        DefaultsKey.inactiveAppsAutoQuit: false,
        DefaultsKey.inactiveAppsExceptions: [String](),
"""
content = content.replace('        DefaultsKey.autoQuitEnabled: false,\n', '        DefaultsKey.autoQuitEnabled: false,\n' + defaults)

with open('Sources/Vorssaint/Core/Defaults.swift', 'w') as f:
    f.write(content)
