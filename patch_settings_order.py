with open('Sources/Vorssaint/UI/Settings/MonitorSettings.swift', 'r') as f:
    content = f.read()

disk = """
                    if metric == .diskUsage {
                        DiskMenuBarOrderOption()
                    }"""

content = content.replace('                    if metric == .network {\n                        NetworkMenuBarOrderOption()\n                    }', '                    if metric == .network {\n                        NetworkMenuBarOrderOption()\n                    }' + disk)

with open('Sources/Vorssaint/UI/Settings/MonitorSettings.swift', 'w') as f:
    f.write(content)
