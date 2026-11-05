// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin

/// `vors` is this executable under a second name. Power assertions end with the
/// process that took them, so it only passes the command to the running app and
/// prints the answer, opening the app first when a session needs it.
enum CommandLineTool {
    /// Long enough for the app to finish launching.
    private static let answerTimeout: TimeInterval = 15
    /// A request posted before the app starts listening is lost, so it repeats.
    private static let requestInterval: TimeInterval = 0.5
    private static var requestObserver: NSObjectProtocol?
    private static var lastRequestID: String?

    // MARK: - Tool

    static func runCommandAndExit(_ command: CommandLineSupport.Command) -> Never {
        switch command {
        case .help:
            print(CommandLineSupport.usage)
        case .invalid(let message):
            failCommand("\(message)\n\(CommandLineSupport.usage)")
        case .keepAwake(let action):
            runKeepAwake(action)
        }
        exit(EXIT_SUCCESS)
    }

    private static func runKeepAwake(_ action: CommandLineSupport.KeepAwakeAction) {
        guard let app = appBundle(), let bundleIdentifier = app.bundleIdentifier else {
            failCommand("run this from the installed app")
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { $0.processIdentifier != pid }
        if !running {
            if action == .off || action == .status {
                print("Keep awake is off")
                return
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: app.bundleURL, configuration: configuration)
        }
        guard let answer = ask(action, bundleIdentifier: bundleIdentifier) else {
            failCommand("the running Vorssaint did not answer. If it is an older version, quit it and try again")
        }
        guard answer.isAvailable else { failCommand("Keep awake is uninstalled in the Features hub") }
        if !answer.isActive, action != .off, action != .status { failCommand("Keep awake did not start") }
        print(statusLine(answer))
    }

    /// `Bundle.main` finds nothing from the `vors` link, so the app is found
    /// from where the executable really is.
    private static func appBundle() -> Bundle? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(ProcessInfo.processInfo.processIdentifier, &buffer, UInt32(buffer.count)) > 0 else {
            return nil
        }
        let macOS = URL(fileURLWithPath: String(cString: buffer)).deletingLastPathComponent()
        return Bundle(url: macOS.deletingLastPathComponent().deletingLastPathComponent())
    }

    private static func ask(_ action: CommandLineSupport.KeepAwakeAction,
                            bundleIdentifier: String) -> CommandLineSupport.Answer? {
        let center = DistributedNotificationCenter.default()
        let request = CommandLineSupport.Request(id: UUID().uuidString, action: action)
        var answer: CommandLineSupport.Answer?
        let observer = center.addObserver(
            forName: CommandLineSupport.answerName(bundleIdentifier: bundleIdentifier),
            object: nil, queue: nil) { note in
            guard let reply = CommandLineSupport.Answer(userInfo: note.userInfo), reply.id == request.id else { return }
            answer = reply
        }
        defer { center.removeObserver(observer) }
        let deadline = Date().addingTimeInterval(answerTimeout)
        while answer == nil, Date() < deadline {
            center.postNotificationName(CommandLineSupport.requestName(bundleIdentifier: bundleIdentifier),
                                        object: nil, userInfo: request.userInfo, deliverImmediately: true)
            CFRunLoopRunInMode(.defaultMode, requestInterval, true)
        }
        return answer
    }

    private static func statusLine(_ answer: CommandLineSupport.Answer) -> String {
        guard answer.isActive else { return "Keep awake is off" }
        guard let end = answer.endDate else { return "Keep awake is on with no end time" }
        let date: Date.FormatStyle.DateStyle = Calendar.current.isDateInToday(end) ? .omitted : .abbreviated
        return "Keep awake is on until \(end.formatted(date: date, time: .shortened))"
    }

    private static func failCommand(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(CommandLineSupport.toolName): \(message)\n".utf8))
        exit(EXIT_FAILURE)
    }

    // MARK: - Running app

    static func startListening() {
        guard requestObserver == nil, let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        requestObserver = DistributedNotificationCenter.default().addObserver(
            forName: CommandLineSupport.requestName(bundleIdentifier: bundleIdentifier),
            object: nil, queue: .main) { note in
            // The repeats of a request the app was still launching through.
            guard let request = CommandLineSupport.Request(userInfo: note.userInfo),
                  request.id != lastRequestID else { return }
            lastRequestID = request.id
            perform(request.action)
            let awake = KeepAwakeManager.shared
            let answer = CommandLineSupport.Answer(id: request.id, isAvailable: AppFeature.keepAwake.isAvailable,
                                                   isActive: awake.isActive, endDate: awake.endDate)
            DistributedNotificationCenter.default().postNotificationName(
                CommandLineSupport.answerName(bundleIdentifier: bundleIdentifier),
                object: nil, userInfo: answer.userInfo, deliverImmediately: true)
        }
    }

    private static func perform(_ action: CommandLineSupport.KeepAwakeAction) {
        let awake = KeepAwakeManager.shared
        switch action {
        case .start:
            if !awake.isActive { awake.startLastPick() }
        case .minutes(let minutes):
            if let end = CommandLineSupport.endDate(forMinutes: minutes, now: Date()) {
                awake.activate(until: end)
            } else {
                awake.activate(minutes: minutes)
            }
        case .off:
            // Not `deactivate`: automation would start the session again at once.
            if awake.isActive { awake.toggle() }
        case .status:
            break
        }
    }
}
