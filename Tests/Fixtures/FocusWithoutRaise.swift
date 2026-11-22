// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

// Built only by Tests/focus_without_raise.py. Focus requests are addressed
// to windows created by these two helper processes.
import AppKit
import ApplicationServices
import Darwin

var interrupted = false
func stopProbe(_ signalNumber: Int32) { interrupted = true }
func uptime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
func spin(_ seconds: TimeInterval) {
    let end = uptime() + seconds
    while uptime() < end {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: min(0.015, end - uptime())))
    }
}
struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
func require(_ condition: Bool, _ why: String) throws {
    if !condition { throw ProbeError(why) }
}
@MainActor func front() -> pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
func preflight() -> Bool {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
    let console = session["kCGSSessionOnConsoleKey"] as? Bool == true
    let loggedIn = session["kCGSessionLoginDoneKey"] as? Bool == true
    let user = (session["kCGSSessionUserIDKey"] as? NSNumber)?.uint32Value == getuid()
    let unlocked = session["CGSSessionScreenIsLocked"] as? Bool != true
    let ax = AXIsProcessTrusted()
    let post = CGPreflightPostEventAccess()
    print("Preflight console=\(console) loggedIn=\(loggedIn) matchingUser=\(user) unlocked=\(unlocked) AX=\(ax) post=\(post)")
    return console && loggedIn && user && unlocked && ax && post
}

typealias State = [String: Int]
func writeState(_ state: State, _ url: URL) {
    if let data = try? JSONEncoder().encode(state) { try? data.write(to: url, options: .atomic) }
}
func readState(_ url: URL) -> State? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(State.self, from: data)
}

final class RefusingWindow: NSWindow {
    override var canBecomeKey: Bool { false }
}

final class OrderingOnPressWindow: NSWindow {
    private(set) var presses = 0
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            presses += 1
            orderFront(nil)
        }
        super.sendEvent(event)
    }
}

@MainActor final class Fixture: NSObject {
    let base: URL
    let role: String
    let parent: pid_t
    var sequence = 0
    var windows: [String: NSWindow] = [:]
    init(base: URL, role: String, parent: pid_t) {
        self.base = base
        self.role = role
        self.parent = parent
    }
    func install() {
        guard getppid() == parent, let screen = NSScreen.main else { exit(2) }
        let area = screen.visibleFrame
        let pointerX = NSEvent.mouseLocation.x
        let anchor = area.midX < pointerX ? area.minX + 40 : area.maxX - 290
        let y = area.midY - 70
        var positions = role == "A" ? [("B", 0), ("A", 42)] : [("C", 24)]
        if role == "A", base.lastPathComponent == "superseded" { positions.insert(("D", -20), at: 0) }
        for (name, shift) in positions {
            let rect = NSRect(x: anchor + CGFloat(shift), y: y + CGFloat(shift / 2), width: 200, height: 120)
            let w: NSWindow
            if name == "B", ["refused", "refusedCross"].contains(base.lastPathComponent) {
                w = RefusingWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            } else if name == "B", base.lastPathComponent == "orderOnPress" {
                w = OrderingOnPressWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            } else {
                w = NSWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            }
            w.title = "Disposable focus probe \(name)"
            w.isReleasedWhenClosed = false
            w.isRestorable = false
            w.orderFront(nil)
            windows[name] = w
        }
        _ = Timer.scheduledTimer(timeInterval: 0.02, target: self, selector: #selector(tick),
                                 userInfo: nil, repeats: true)
        publish()
    }

    // Publish only our own window numbers and key state in the private run directory.
    func publish() {
        var state: State = ["pid": Int(getpid()), "key": NSApp.keyWindow?.windowNumber ?? 0,
                            "active": NSApp.isActive ? 1 : 0, "seq": sequence]
        for (name, window) in windows {
            state[name] = window.windowNumber
            state[name + "Key"] = window.isKeyWindow ? 1 : 0
            state[name + "CanBeKey"] = window.canBecomeKey ? 1 : 0
            if let observing = window as? OrderingOnPressWindow { state["BPresses"] = observing.presses }
        }
        writeState(state, base.appendingPathComponent(role + ".state"))
    }
    @objc func tick() {
        guard getppid() == parent else { exit(0) }
        guard let request = readState(base.appendingPathComponent(role + ".request")),
              let seq = request["seq"], seq > sequence else { return }
        sequence = seq
        let expectedFront = request["from"].flatMap { pid_t(exactly: $0) }
        switch request["cmd"] {
        case 1:
            guard let expectedFront, front() == expectedFront || front() == getpid() else {
                publish()
                return
            }
            if #available(macOS 14, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            windows["B"]?.orderFront(nil)
            windows[role]?.makeKeyAndOrderFront(nil)
        case 2:
            if front() == getpid(), let value = request["to"], let pid = pid_t(exactly: value), pid > 0,
               let recipient = NSRunningApplication(processIdentifier: pid), !recipient.isTerminated {
                if #available(macOS 14, *) { NSApp.yieldActivation(to: recipient) }
                _ = recipient.activate(options: [])
            }
        case 3:
            if front() == getpid() { windows["B"]?.makeKey() }
        case 4:
            if front() == getpid(), let next = windows["D"] {
                next.makeKey()
            }
        default:
            break
        }
        publish()
    }
}

@MainActor final class Child {
    let role: String
    let base: URL
    let process = Process()
    var seq = 0
    init(_ role: String, in base: URL) throws {
        self.role = role
        self.base = base
        process.executableURL = base.deletingLastPathComponent().appendingPathComponent(role + ".app/Contents/MacOS/FocusFixture")
        process.arguments = ["--fixture", role, base.path, String(getpid())]
        try process.run()
    }
    func state() -> State? {
        guard let s = readState(base.appendingPathComponent(role + ".state")),
              s["pid"] == Int(process.processIdentifier) else { return nil }
        return s
    }
    func send(_ cmd: Int = 0, to: pid_t = 0, from: pid_t = 0, cleanup: Bool = false) throws -> State {
        seq += 1
        writeState(["seq": seq, "cmd": cmd, "to": Int(to), "from": Int(from)],
                   base.appendingPathComponent(role + ".request"))
        let end = uptime() + 2
        while process.isRunning && uptime() < end && (cleanup || !interrupted) {
            if let state = state(), state["seq"] == seq { return state }
            spin(0.025)
        }
        throw ProbeError("No fresh observation from disposable fixture \(role).")
    }
    func stop() {
        if process.isRunning { process.terminate() }
        let end = uptime() + 1
        while process.isRunning && uptime() < end { spin(0.02) }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }
}

@MainActor final class Experiment {
    let base: URL
    let original: NSRunningApplication
    var children: [Child] = []
    var a: Child { children[0] }
    var c: Child { children[1] }
    var ids = [String: CGWindowID]()
    init(_ base: URL, _ original: NSRunningApplication) {
        self.base = base
        self.original = original
    }
    func start() throws {
        for role in ["A", "C"] {
            try require(!interrupted, "Interrupted.")
            try require(front() == original.processIdentifier || participantIsFront(),
                        "Foreground app changed before launching a fixture.")
            let helper = try Child(role, in: base)
            children.append(helper)
            let s = try helper.send()
            var names = role == "A" ? ["A", "B"] : ["C"]
            if role == "A", base.lastPathComponent == "superseded" { names.append("D") }
            for name in names {
                guard let n = s[name], let id = CGWindowID(exactly: n), id > 0 else {
                    throw ProbeError("Missing own fixture window \(name).")
                }
                ids[name] = id
                // AppKit can allocate the number before WindowServer publishes it.
                let deadline = uptime() + 1.5
                while !owns(id, helper) && helper.process.isRunning && !interrupted && uptime() < deadline {
                    spin(0.025)
                }
                try require(owns(id, helper), "Window \(name) does not belong to expected fixture.")
            }
        }
        try require(Set(ids.values).count == ids.count, "Fixture window IDs are not unique.")
    }
    func owns(_ id: CGWindowID, _ child: Child) -> Bool {
        guard child.process.isRunning, child.state() != nil,
              let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let row = rows.first,
              (row[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id else { return false }
        return (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == child.process.processIdentifier
    }
    func order() throws -> [String] {
        let byID = Dictionary(uniqueKeysWithValues: ids.map { ($0.value, $0.key) })
        // AppKit returns numbers in z-order on the current Space. Never fetch
        // titles, bounds, or owners for other applications' windows.
        guard let numbers = NSWindow.windowNumbers(options: [.allApplications]) else {
            throw ProbeError("Window order is unavailable.")
        }
        let names = numbers.compactMap { byID[$0.uint32Value] }
        guard names.count == ids.count, Set(names) == Set(ids.keys) else {
            throw ProbeError("Incomplete fixture window order: \(names).")
        }
        return names
    }
    func participantIsFront() -> Bool {
        children.contains { $0.process.isRunning && $0.process.processIdentifier == front() }
    }
    func bringOwnToFront(_ child: Child) throws {
        try require(!interrupted, "Interrupted.")
        if let active = children.first(where: { $0.process.processIdentifier == front() && $0 !== child }) {
            _ = try active.send(2, to: child.process.processIdentifier)
        } else if front() != original.processIdentifier && !participantIsFront() {
            throw ProbeError("An unrelated app became frontmost; aborting measurements.")
        }
        guard let current = front(), current == original.processIdentifier || participantIsFront() else {
            throw ProbeError("Foreground app changed during setup.")
        }
        _ = try child.send(1, from: current)
        let until = uptime() + 2.5
        var observed = State()
        while uptime() < until {
            spin(0.08)
            observed = try child.send()
            if front() == child.process.processIdentifier && observed["active"] == 1
                && observed["key"] == observed[child.role] && observed[child.role + "Key"] == 1
                && WindowActivator.focusedWindowID(for: child.process.processIdentifier) == ids[child.role]
                && (try? order())?.first == child.role { return }
        }
        throw ProbeError("Setup cannot make own \(child.role) key: app front=\(front() == child.process.processIdentifier) state=\(observed).")
    }
    func take(_ child: Child) throws -> (pid_t?, State, CGWindowID?, [String]) {
        let s = try child.send()
        return (front(), s, try WindowActivator.observedFocus(for: child.process.processIdentifier), try order())
    }
    enum Trial: String { case control, same, cross, refused, refusedCross, superseded, orderOnPress }

    enum Outcome { case passed, acceptedWithoutFocus, edgeFailure }

    func trial(_ trial: Trial) throws -> Outcome {
        let cross = trial == .cross || trial == .refusedCross
        let refused = trial == .refused || trial == .refusedCross
        try bringOwnToFront(a)
        if cross { try bringOwnToFront(c) }
        let source = cross ? c : a
        let (frontPID, sourceState, sourceFocus, before) = try take(source)
        guard let sourceID = ids[source.role], let b = ids["B"],
              let aPosition = before.firstIndex(of: "A"), let bPosition = before.firstIndex(of: "B"),
              aPosition < bPosition, before.first == source.role,
              frontPID == source.process.processIdentifier, sourceState["key"] == Int(sourceID),
              sourceFocus == sourceID, owns(sourceID, source), owns(b, a), !interrupted else {
            throw ProbeError("Unusable baseline: order=\(before), AX=\(String(describing: sourceFocus)), source=\(source.role).")
        }
        if refused {
            let targetState = cross ? try a.send() : sourceState
            try require(targetState["BCanBeKey"] == 0, "B was eligible for keyboard focus.")
        }
        if trial == .orderOnPress { try require(sourceState["BPresses"] == 0, "B received a press during setup.") }
        var cancelled = false
        var observedSupersession = false
        var accepted: Bool?
        var orderChanged = false
        func sampleOrder() throws {
            let actual = try order()
            if actual != before && !orderChanged {
                orderChanged = true
                print("\(trial.rawValue): order changed from \(before) to \(actual).")
            }
        }
        if trial == .control {
            // Positive control. A and B belong to the active process itself.
            // makeKey() changes its key window without explicitly ordering B.
            _ = try a.send(3)
        } else {
            let owner = a.process.processIdentifier
            SpaceWindowBridge.focusWithoutRaise(b, ownerPID: owner, replacing: cross ? nil : sourceFocus,
                while: {
                    if cancelled {
                        observedSupersession = true
                        return false
                    }
                    return !interrupted && self.owns(b, self.a) && self.participantIsFront()
                },
                completion: { accepted = $0 })
            if trial == .superseded {
                try require(accepted == nil, "No pending handoff to cancel.")
                // The caller changes its selection to D while the old request
                // is pending. The bridge must honor the cancellation on resuming.
                cancelled = true
                _ = try a.send(4)
            }
            let deadline = uptime() + 1
            while accepted == nil && uptime() < deadline && !interrupted {
                try sampleOrder()
                spin(0.015)
            }
            try require(accepted != nil && !interrupted, "No completion from production handoff.")
            print("\(trial.rawValue): production completion=\(accepted == true).")
        }
        let started = uptime()
        let expected = refused ? source.role : (trial == .superseded ? "D" : "B")
        let expectedApp = refused ? source : a
        guard let expectedID = ids[expected] else { throw ProbeError("Missing observed window.") }
        var consistentlyFocused = true
        var consistentlyMissing = true
        for delay in [0.25, 0.8] {
            repeat {
                try sampleOrder()
                let remaining = started + delay - uptime()
                if remaining <= 0 { break }
                spin(min(0.015, remaining))
            } while !interrupted
            try require(!interrupted && participantIsFront(), "Focus left both fixtures.")
            let (frontPID, state, axID, after) = try take(expectedApp)
            let appIsFront = frontPID == expectedApp.process.processIdentifier
            try require(frontPID == a.process.processIdentifier || frontPID == c.process.processIdentifier,
                        "Foreground changed during observation.")
            let isKey = state["key"] == Int(expectedID) && state[expected + "Key"] == 1
            let hasFocus = appIsFront && state["active"] == 1 && isKey && axID == expectedID
            consistentlyFocused = consistentlyFocused && hasFocus
            consistentlyMissing = consistentlyMissing && appIsFront && state["BKey"] == 0
                && state["key"] != Int(b) && axID != b
            orderChanged = orderChanged || after != before
            print("\(trial.rawValue) @\(delay)s: expected app front=\(appIsFront), key \(expected)=\(isKey), " +
                  "AX \(expected)=\(axID == expectedID), order=\(before)->\(after).")
            if trial == .orderOnPress { print("B received \(state["BPresses"] ?? 0) mouse presses.") }
        }
        // This case isolates stacking. The ordinary same-app trial checks focus.
        if trial == .orderOnPress { return orderChanged ? .edgeFailure : .passed }
        if trial == .superseded {
            try require(observedSupersession, "The bridge did not recheck the cancelled handoff.")
            return consistentlyFocused && !orderChanged && accepted == false ? .passed : .edgeFailure
        }
        if refused {
            // A transport result describes delivery. The old key window and the
            // stacking order must survive even if an ineligible target refuses.
            return consistentlyFocused && !orderChanged ? .passed : .edgeFailure
        }
        try require(!orderChanged, "Fixture stacking order changed.")
        if trial == .control {
            try require(consistentlyFocused, "Local makeKey() did not establish the positive control.")
        } else {
            try require(accepted == true, "Production handoff reported failure.")
            if consistentlyMissing { return .acceptedWithoutFocus }
        }
        try require(consistentlyFocused, "Focus observations were inconsistent or the target app never became frontmost.")
        return .passed
    }
    func restore() -> Bool {
        if let active = children.first(where: { $0.process.isRunning && $0.process.processIdentifier == front() }),
           !original.isTerminated {
            _ = try? active.send(2, to: original.processIdentifier, cleanup: true)
            let deadline = uptime() + 1
            while participantIsFront() && uptime() < deadline { spin(0.03) }
        }
        // If the user selected a different app during the run, leave it alone.
        for child in children.reversed() { child.stop() }
        spin(0.15)
        return front() == original.processIdentifier
    }
}

@MainActor func controller(_ base: URL, edgeCases: Bool) -> Int32 {
    guard preflight(), let original = NSWorkspace.shared.frontmostApplication, !original.isTerminated,
          original.activationPolicy == .regular else {
        print("SKIP: cannot verify active console, permissions, or a restorable frontmost app.")
        return 2
    }
    for sig in [SIGINT, SIGTERM, SIGHUP] { signal(sig, stopProbe) }
    var result: Int32 = 0
    let trials: [Experiment.Trial] = edgeCases
        ? [.control, .refused, .refusedCross, .orderOnPress, .superseded] : [.control, .same, .cross]
    for trial in trials {
        guard !interrupted, !original.isTerminated, front() == original.processIdentifier else {
            print("INCONCLUSIVE: foreground changed before the next trial; stopping.")
            return 2
        }
        let directory = base.appendingPathComponent(trial.rawValue, isDirectory: true)
        // Each run gets fresh state/request files even when a PID is reused.
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false) }
        catch { print("SKIP: could not create fixture directory."); return 2 }
        let experiment = Experiment(directory, original)
        do {
            try experiment.start()
            switch try experiment.trial(trial) {
            case .edgeFailure:
                print("EDGE FAILURE: \(trial.rawValue) did not preserve the expected focus and order.")
                result = 3
            case .passed:
                print("PASS: \(trial.rawValue).")
            case .acceptedWithoutFocus:
                print("REPRODUCED: \(trial.rawValue) handoff reported success with the target app in front " +
                      "and stable stacking order, but neither AppKit nor AX identified B as focused at either sample.")
                result = 1
            }
        } catch {
            print("INCONCLUSIVE \(trial.rawValue): \(error)")
            result = 2
        }
        let restored = experiment.restore()
        if !restored || interrupted {
            print("INCONCLUSIVE: interrupted or foreground app changed; stopped fixtures.")
            return 2
        }
        if result == 2 { return result }
    }
    return result
}

@main
enum FocusProbe {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.count == 2 && args[1] == "--preflight" { exit(preflight() ? 0 : 2) }
        if args.count == 3 && ["--controller", "--edge-cases"].contains(args[1]) {
            let directory = URL(fileURLWithPath: args[2], isDirectory: true).resolvingSymlinksInPath()
            guard directory.path == URL(fileURLWithPath: args[0]).resolvingSymlinksInPath().deletingLastPathComponent().path else {
                print("Run the controller from the directory prepared by Tests/focus_without_raise.py.")
                exit(2)
            }
            exit(controller(directory, edgeCases: args[1] == "--edge-cases"))
        }
        if args.count == 5 && args[1] == "--fixture", ["A", "C"].contains(args[2]),
           let parent = Int32(args[4]), getppid() == parent,
           Bundle.main.bundleIdentifier == "org.local.vorss.focusprobe." + args[2].lowercased() {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            app.finishLaunching()
            let fixture = Fixture(base: URL(fileURLWithPath: args[3], isDirectory: true), role: args[2], parent: parent)
            fixture.install()
            app.run()
        } else { exit(2) }
    }
}
