// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The Finder right-click entries. macOS lists a Quick Action under the
/// right-click menu when a workflow sits in ~/Library/Services, so Vorssaint
/// writes four small ones: Lock and Unlock for files and folders, and Lock and
/// Unlock for apps. Each runs a one-line script that opens a `vorssaint://`
/// link in the background; Vorssaint, already running in the menu bar, asks
/// its question (a password, or Touch ID) without coming to the front.
///
/// Only workflows carrying Vorssaint's own marker are ever changed or removed.
enum PrivacyLockQuickActions {
    private static let marker = "VorssaintPrivacyLockAction"

    private struct Definition {
        let action: PrivacyLockLinkAction
        let types: [String]
        let name: (PrivacyLockFeatureStrings) -> String
    }

    private static let definitions: [Definition] = [
        // Files and ordinary folders only: an app is a package, so it matches neither type.
        Definition(action: .lockItems, types: ["public.data", "public.folder"]) { $0.lockMenuName },
        Definition(action: .unlockItems, types: ["com.vorssaint.utils.locked-item"]) { $0.unlockMenuName },
        // Finder lists a Quick Action by file type alone, and a locked app has the same type
        // as an open one, so one entry does both: it locks what is open and unlocks what is locked.
        Definition(action: .toggleApps, types: ["com.apple.application-bundle"]) { $0.toggleAppMenuName },
    ]

    private static var servicesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Services", isDirectory: true)
    }

    private static func displayName(_ definition: Definition, _ text: PrivacyLockFeatureStrings) -> String {
        definition.name(text).replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespaces)
    }

    /// The workflows Vorssaint put there, found by their marker.
    private static func installedWorkflows() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: servicesDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { url in
            guard url.pathExtension == "workflow",
                  let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { return false }
            return plist[marker] != nil
        }
    }

    static var isInstalled: Bool { installedWorkflows().count >= definitions.count }

    /// The script each action runs: every selected path, base64url in a link.
    static func script(for action: PrivacyLockLinkAction) -> String {
        """
        url="\(PrivacyLockLink.scheme)://\(PrivacyLockLink.host)/\(action.rawValue)?"
        for f in "$@"; do
          e=$(printf '%s' "$f" | /usr/bin/base64 | /usr/bin/tr '+/' '-_' | /usr/bin/tr -d '=\\n')
          url="${url}p=${e}&"
        done
        /usr/bin/open -g "$url"
        """
    }

    @discardableResult
    static func install(language: AppLanguage) -> Bool {
        remove()
        let text = FeatureStrings.privacyLock(language)
        let fm = FileManager.default
        guard (try? fm.createDirectory(at: servicesDirectory, withIntermediateDirectories: true)) != nil else {
            return false
        }
        var ok = true
        for definition in definitions {
            let name = displayName(definition, text)
            let bundle = servicesDirectory.appendingPathComponent("\(name).workflow", isDirectory: true)
            let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
            do {
                try fm.createDirectory(at: contents, withIntermediateDirectories: true)
                try plistData(info(for: definition, name: name)).write(to: contents.appendingPathComponent("Info.plist"))
                try plistData(workflow(for: definition)).write(to: contents.appendingPathComponent("document.wflow"))
            } catch {
                ok = false
            }
        }
        refreshServices()
        return ok
    }

    static func remove() {
        for url in installedWorkflows() { try? FileManager.default.removeItem(at: url) }
        refreshServices()
    }

    private static func refreshServices() {
        NSUpdateDynamicServices()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/pbs")
        process.arguments = ["-update"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: Workflow files

    private static func plistData(_ object: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
    }

    private static func info(for definition: Definition, name: String) -> [String: Any] {
        [marker: definition.action.rawValue,
         "NSServices": [[
            "NSBackgroundColorName": "background",
            "NSIconName": "NSActionTemplate",
            "NSMenuItem": ["default": name],
            "NSMessage": "runWorkflowAsService",
            "NSRequiredContext": ["NSApplicationIdentifier": "com.apple.finder"],
            "NSSendFileTypes": definition.types,
         ] as [String: Any]]]
    }

    private static func workflow(for definition: Definition) -> [String: Any] {
        let id = UUID().uuidString
        let action: [String: Any] = [
            "AMAccepts": ["Container": "List", "Optional": true, "Types": ["com.apple.cocoa.path"]] as [String: Any],
            "AMActionVersion": "2.0.3",
            "AMApplication": ["Automator"],
            "AMParameterProperties": ["COMMAND_STRING": [String: Any](), "CheckedForUserDefaultShell": [String: Any](),
                                      "inputMethod": [String: Any](), "shell": [String: Any](),
                                      "source": [String: Any]()] as [String: Any],
            "AMProvides": ["Container": "List", "Types": ["com.apple.cocoa.path"]] as [String: Any],
            "ActionBundlePath": "/System/Library/Automator/Run Shell Script.action",
            "ActionName": "Run Shell Script",
            "ActionParameters": ["COMMAND_STRING": script(for: definition.action),
                                 "CheckedForUserDefaultShell": true,
                                 "inputMethod": 1,
                                 "shell": "/bin/zsh",
                                 "source": ""] as [String: Any],
            "BundleIdentifier": "com.apple.RunShellScript",
            "CFBundleVersion": "2.0.3",
            "CanShowSelectedItemsWhenRun": false,
            "CanShowWhenRun": true,
            "Category": ["AMCategoryUtilities"],
            "Class Name": "RunShellScriptAction",
            "InputUUID": UUID().uuidString,
            "Keywords": ["Shell", "Script", "Command", "Run", "Unix"],
            "OutputUUID": UUID().uuidString,
            "UUID": id,
            "UnlocalizedApplications": ["Automator"],
            "isViewVisible": 1,
        ]
        return [
            "AMApplicationBuild": "523",
            "AMApplicationVersion": "2.10",
            "AMDocumentVersion": "2",
            "actions": [["action": action] as [String: Any]],
            "connectors": [String: Any](),
            "workflowMetaData": [
                "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
                "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
                "serviceProcessesInput": 0,
                "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
            ] as [String: Any],
        ]
    }
}
