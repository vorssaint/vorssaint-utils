with open('Sources/Vorssaint/App/AppDelegate.swift', 'r') as f:
    content = f.read()

action = """        if response.actionIdentifier == Notifier.inactiveAppQuitActionID {
            if let bundleID = response.notification.request.content.userInfo["bundleID"] as? String {
                let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
                for app in apps {
                    app.terminate()
                }
            }
        }
"""
content = content.replace('        if let transactionID = Notifier.whatsAppOrganizerTransactionID(from: response) {\n', action + '        if let transactionID = Notifier.whatsAppOrganizerTransactionID(from: response) {\n')

with open('Sources/Vorssaint/App/AppDelegate.swift', 'w') as f:
    f.write(content)
