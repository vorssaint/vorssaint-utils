with open('Sources/Vorssaint/Services/Notifier.swift', 'r') as f:
    content = f.read()

old = """    static func postInactiveApp(appName: String, bundleID: String, memoryMB: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\\(appName) is Idle"
        content.body = "It has been idle and is using \\(memoryMB) MB of memory."
        content.categoryIdentifier = "inactiveApp"
        content.userInfo = ["bundleID": bundleID]
        
        let request = UNNotificationRequest(identifier: "inactive-\\(bundleID)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }"""

new = """    static func postInactiveApp(appName: String, bundleID: String, memoryMB: Int) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
            
            let content = UNMutableNotificationContent()
            content.title = "\\(appName) is Idle"
            content.body = "It has been idle and is using \\(memoryMB) MB of memory."
            content.categoryIdentifier = "inactiveApp"
            content.userInfo = ["bundleID": bundleID]
            
            let request = UNNotificationRequest(identifier: "inactive-\\(bundleID)", content: content, trigger: nil)
            center.add(request)
        }
    }"""

content = content.replace(old, new)

with open('Sources/Vorssaint/Services/Notifier.swift', 'w') as f:
    f.write(content)
