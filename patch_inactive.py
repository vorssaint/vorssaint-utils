with open('Sources/Vorssaint/UI/Settings/InactiveAppsSettings.swift', 'r') as f:
    content = f.read()

content = content.replace(
    '                    PermissionRow(kind: .notifications)',
    '                    HStack {\\n                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)\\n                        Text("Please enable Notifications in System Settings to receive alerts.")\\n                    }'
)

with open('Sources/Vorssaint/UI/Settings/InactiveAppsSettings.swift', 'w') as f:
    f.write(content.replace('\\n', '\n'))
