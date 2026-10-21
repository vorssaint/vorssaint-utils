// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum FinderTerminalTarget: String, CaseIterable, Identifiable {
    case terminal = "Terminal", iTerm = "iTerm", ghostty = "Ghostty", cmux = "cmux", kaku = "Kaku"
    var id: String { rawValue }
}

enum FinderTerminalMode: String, CaseIterable, Identifiable {
    case window, tab
    var id: String { rawValue }
    func title(_ language: String) -> String {
        let names: [String]
        switch language {
        case "pt-BR": names = ["Nova janela", "Nova aba"]
        case "es": names = ["Nueva ventana", "Nueva pestaña"]
        case "fr": names = ["Nouvelle fenêtre", "Nouvel onglet"]
        case "de": names = ["Neues Fenster", "Neuer Tab"]
        case "it": names = ["Nuova finestra", "Nuova scheda"]
        case "tr": names = ["Yeni Pencere", "Yeni Sekme"]
        case "sk": names = ["Nové okno", "Nová karta"]
        case "ru": names = ["Новое окно", "Новая вкладка"]
        case "uk": names = ["Нове вікно", "Нова вкладка"]
        case "ja": names = ["新規ウインドウ", "新規タブ"]
        case "ko": names = ["새 윈도우", "새 탭"]
        case "zh-Hans": names = ["新建窗口", "新建标签页"]
        case "zh-TW", "zh-HK": names = ["新增視窗", "新增分頁"]
        default: names = ["New Window", "New Tab"]
        }
        return names[self == .window ? 0 : 1]
    }
}

/// Terminal uses its native Finder Services; other terminals use their documented
/// scripting/CLI interfaces. Directory paths are data, never unquoted shell text.
enum FinderTerminalAdapter {
    static func open(_ target: FinderTerminalTarget, mode: FinderTerminalMode, selection: [URL],
                     completion: @escaping (Error?) -> Void) {
        do {
            guard selection.count == 1, let first = selection.first else {
                throw FinderFileActionError.invalidRequest("Select one folder or file for the terminal.")
            }
            let folder = try first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                ? first : first.deletingLastPathComponent()
            guard !folder.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw FinderFileActionError.invalidRequest("Terminal paths cannot contain control characters.")
            }
            if target == .terminal {
                let pasteboard = NSPasteboard.withUniqueName()
                defer { pasteboard.releaseGlobally() }
                pasteboard.writeObjects([folder as NSURL])
                pasteboard.setString(folder.path, forType: .string)
                let service = mode == .tab ? "New Terminal Tab at Folder" : "New Terminal at Folder"
                guard NSPerformService(service, pasteboard) else { throw CocoaError(.featureUnsupported) }
                completion(nil)
                return
            }
            let locations = [URL(fileURLWithPath: "/Applications", isDirectory: true),
                             FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
            guard let app = locations.map({ $0.appendingPathComponent(target.rawValue + ".app") })
                .first(where: { FileManager.default.fileExists(atPath: $0.path) }),
                  let bundleID = Bundle(url: app)?.bundleIdentifier else {
                throw FinderFileActionError.invalidRequest("\(target.rawValue) is not installed in Applications.")
            }
            NSWorkspace.shared.openApplication(at: app, configuration: .init()) { _, error in
                if let error { DispatchQueue.main.async { completion(error) }; return }
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Result {
                        if target == .iTerm || target == .ghostty {
                            guard AppleScriptRunner.consentToAutomate(bundleID: bundleID) else { throw CocoaError(.fileReadNoPermission) }
                            let script = try script(target, mode: mode, application: app, folder: folder)
                            let result = AppleScriptRunner.runDetailed(script)
                            guard result.ok else {
                                throw FinderFileActionError.operationFailed(operation: "open terminal", url: folder,
                                    reason: result.output.isEmpty ? "The terminal rejected the automation request." : result.output)
                            }
                        } else {
                            let relative = target == .kaku ? "Contents/MacOS/kaku" : "Contents/Resources/bin/cmux"
                            let executable = app.appendingPathComponent(relative)
                            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                                throw FinderFileActionError.unsupported(app, "The terminal's bundled command-line interface is unavailable")
                            }
                            let arguments = target == .kaku
                                ? ["cli", "spawn", "--cwd", folder.path] + (mode == .window ? ["--new-window"] : [])
                                : ["new-workspace", "--cwd", folder.path]
                            let result = BoundedProcessRunner.run(executable.path, arguments, timeout: 15, maxOutputBytes: 65_536)
                            guard !result.timedOut, result.status == 0 else {
                                throw FinderFileActionError.operationFailed(operation: "open terminal", url: folder,
                                    reason: String(decoding: result.output, as: UTF8.self))
                            }
                        }
                    }
                    DispatchQueue.main.async { completion(result.failure) }
                }
            }
        } catch { completion(error) }
    }

    static func script(_ target: FinderTerminalTarget, mode: FinderTerminalMode,
                       application: URL, folder: URL) throws -> String {
        let command: String
        switch target {
        case .iTerm:
            let creation = mode == .tab
                ? "if (count of windows) = 0 then\nset win to (create window with default profile)\nset terminalSession to current session of win\nelse\ntell current window\nset newTab to (create tab with default profile)\nset terminalSession to current session of newTab\nend tell\nend if"
                : "set win to (create window with default profile)\nset terminalSession to current session of win"
            command = "\(creation)\ntell terminalSession to write text (\"cd -- \" & quoted form of \(AppleScriptRunner.literal(folder.path)))"
        case .ghostty:
            let creation = mode == .tab
                ? "if (count of windows) = 0 then\nnew window with configuration cfg\nelse\nnew tab in front window with configuration cfg\nend if"
                : "new window with configuration cfg"
            command = "set cfg to new surface configuration\nset initial working directory of cfg to \(AppleScriptRunner.literal(folder.path))\n\(creation)"
        default: throw CocoaError(.featureUnsupported)
        }
        return "with timeout of 15 seconds\ntell application \(AppleScriptRunner.literal(application.path))\nactivate\n\(command)\nend tell\nend timeout"
    }
}

private extension Result where Success == Void, Failure == Error {
    var failure: Error? { if case .failure(let error) = self { return error }; return nil }
}
