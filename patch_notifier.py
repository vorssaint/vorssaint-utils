with open('Sources/Vorssaint/Services/Notifier.swift', 'r') as f:
    content = f.read()

funcs = """    static func postInactiveApp(appName: String, bundleID: String, memoryMB: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\\(appName) is Idle"
        content.body = "It has been idle and is using \\(memoryMB) MB of memory."
        content.categoryIdentifier = "inactiveApp"
        content.userInfo = ["bundleID": bundleID]
        
        let request = UNNotificationRequest(identifier: "inactive-\\(bundleID)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    static let inactiveAppQuitActionID = "inactiveAppQuitAction"
"""

content = content.replace('    static func postWhatsAppOrganization(', funcs + '\n    static func postWhatsAppOrganization(')

# Now in `registerCategories`
cat = """        let inactiveQuitAction = UNNotificationAction(
            identifier: inactiveAppQuitActionID,
            title: "Quit App",
            options: .destructive
        )
        let inactiveCategory = UNNotificationCategory(
            identifier: "inactiveApp",
            actions: [inactiveQuitAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "",
            options: .customDismissAction
        )
"""
content = content.replace('        let whatsAppUndoAction = UNNotificationAction(', cat + '\n        let whatsAppUndoAction = UNNotificationAction(')

content = content.replace('Set([whatsAppCategory, downloadCategory])', 'Set([whatsAppCategory, downloadCategory, inactiveCategory])')

with open('Sources/Vorssaint/Services/Notifier.swift', 'w') as f:
    f.write(content)
