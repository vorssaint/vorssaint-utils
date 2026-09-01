with open('Sources/Vorssaint/Core/Defaults.swift', 'r') as f:
    content = f.read()

content = content.replace('    static let menuBarMemoryStyle = "menuBarMemoryStyle"   // dot | percent | both', '    static let menuBarMemoryStyle = "menuBarMemoryStyle"   // dot | percent | both\n    static let menuBarDiskStyle = "menuBarDiskStyle"       // free | percent | both')
content = content.replace('        DefaultsKey.menuBarMemoryStyle: "percent",', '        DefaultsKey.menuBarMemoryStyle: "percent",\n        DefaultsKey.menuBarDiskStyle: "free",')
content = content.replace('    static let allowedMenuBarMemoryStyles = ["dot", "percent", "both"]', '    static let allowedMenuBarMemoryStyles = ["dot", "percent", "both"]\n    static let allowedMenuBarDiskStyles = ["free", "percent", "both"]')

sanitized = """    static func sanitizedMenuBarDiskStyle(_ style: String) -> String {
        allowedMenuBarDiskStyles.contains(style) ? style : "free"
    }

"""

content = content.replace('    static func sanitizedMenuBarMemoryStyle(_ style: String) -> String {\n', sanitized + '    static func sanitizedMenuBarMemoryStyle(_ style: String) -> String {\n')

with open('Sources/Vorssaint/Core/Defaults.swift', 'w') as f:
    f.write(content)
