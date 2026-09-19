// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

// Read-only evidence for #698. Build separately from the app; see
// docs/MENU-BAR-DIAGNOSTICS.md. Never opens menus or changes item positions.
import AppKit
import ApplicationServices

struct InventoryItem: Encodable {
    let path: [Int]
    let role: String
    let hasIdentifier: Bool
    let frame: [Double]?
}

struct ApplicationInventory: Encodable {
    let bundleID: String?
    let pid: pid_t
    var status = "ok"
    var errors: [String: Int32] = [:]
    var items: [InventoryItem] = []
}

// The same bounded traversal serves live AX and the fixture tests. Paths are
// snapshot-local addresses, not identities that survive rearranging or relaunch.
func visitExtras<Node>(root: Node, children: (Node) -> [Node],
                       isItem: (Node) -> Bool, mayRead: () -> Bool,
                       visit: (Node, [Int]) -> Void) -> Bool {
    var remaining = 128
    var complete = true
    func walk(_ node: Node, path: [Int]) {
        guard remaining > 0, mayRead() else { complete = false; return }
        remaining -= 1
        if isItem(node) {
            visit(node, path)
            return // Do not descend into the item's menu, even when open.
        }
        let nested = children(node)
        guard path.count < 3 else {
            if !nested.isEmpty { complete = false }
            return
        }
        for (index, child) in nested.enumerated() {
            guard remaining > 0, mayRead() else { complete = false; break }
            walk(child, path: path + [index])
        }
    }
    walk(root, path: [])
    return complete
}

func usableFrame(position: CGPoint, size: CGSize) -> [Double]? {
    let values = [Double(position.x), Double(position.y), Double(size.width), Double(size.height)]
    guard values.allSatisfy({ $0.isFinite }), size.width > 0, size.height > 0 else { return nil }
    return values // AX coordinates: global display space, no Cocoa flip.
}

func runTests() {
    struct Node {
        var item = false
        var children: [Node] = []
    }
    func collect(_ root: Node, allowed: Bool = true) -> (Bool, [[Int]]) {
        var paths: [[Int]] = []
        let complete = visitExtras(root: root, children: { $0.children },
                                   isItem: { $0.item }, mayRead: { allowed }) { _, path in
            paths.append(path)
        }
        return (complete, paths)
    }
    let item = Node(item: true)
    let direct = collect(Node(children: [item, item]))
    precondition(direct.0 && direct.1 == [[0], [1]])
    let wrapped = collect(Node(children: [Node(children: [item])]))
    precondition(wrapped.0 && wrapped.1 == [[0, 0]])
    let openMenu = collect(Node(children: [Node(item: true, children: [item])]))
    precondition(openMenu.0 && openMenu.1 == [[0]])
    precondition(!collect(Node(children: Array(repeating: item, count: 200))).0)
    precondition(collect(Node(children: Array(repeating: item, count: 200))).1.count == 127)
    precondition(!collect(Node(children: [Node(children: [Node(children: [Node(children: [item])])])])).0)
    let denied = collect(Node(children: [item]), allowed: false)
    precondition(!denied.0 && denied.1.isEmpty)
    precondition(usableFrame(position: CGPoint(x: -100, y: 20), size: CGSize(width: 24, height: 24)) == [-100, 20, 24, 24])
    precondition(usableFrame(position: .zero, size: .zero) == nil)
    precondition(usableFrame(position: CGPoint(x: Double.nan, y: 0), size: CGSize(width: 1, height: 1)) == nil)
    print("MENU BAR INVENTORY TESTS OK")
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--selftest"] {
    runTests()
    exit(0)
}
guard arguments.isEmpty else {
    FileHandle.standardError.write(Data("usage: MenuBarInventory [--selftest]\n".utf8))
    exit(64)
}
guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("Accessibility permission is missing; no inventory collected. Run from an authorized terminal.\n".utf8))
    exit(2)
}

let deadline = ProcessInfo.processInfo.systemUptime + 10
var applications: [ApplicationInventory] = []
var timedOut = false
for app in NSWorkspace.shared.runningApplications.sorted(by: { $0.processIdentifier < $1.processIdentifier }) {
    guard ProcessInfo.processInfo.systemUptime < deadline else { timedOut = true; break }
    let appDeadline = min(deadline, ProcessInfo.processInfo.systemUptime + 1)
    var result = ApplicationInventory(bundleID: app.bundleIdentifier, pid: app.processIdentifier)
    func read(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        guard ProcessInfo.processInfo.systemUptime < appDeadline else {
            result.status = "truncated"
            return nil
        }
        AXUIElementSetMessagingTimeout(element, 0.15)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        if error != .success { result.errors[attribute] = error.rawValue }
        return error == .success ? value : nil
    }
    let owner = AXUIElementCreateApplication(app.processIdentifier)
    if let raw = read(owner, kAXExtrasMenuBarAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() {
        let root = unsafeBitCast(raw, to: AXUIElement.self)
        let complete = visitExtras(root: root, children: { element in
            guard let rawChildren = read(element, kAXChildrenAttribute) else { return [] }
            guard let children = rawChildren as? [AXUIElement] else {
                result.status = "invalid-children"
                return []
            }
            return children
        }, isItem: { element in
            let role = read(element, kAXRoleAttribute) as? String
            if role == kAXMenuBarItemRole { return true }
            return read(element, kAXSubroleAttribute) as? String == "AXMenuExtra"
        }, mayRead: { ProcessInfo.processInfo.systemUptime < appDeadline }) { element, path in
            var frame: [Double]?
            if let rawPosition = read(element, kAXPositionAttribute),
               let rawSize = read(element, kAXSizeAttribute),
               CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() {
                let positionValue = unsafeBitCast(rawPosition, to: AXValue.self)
                let sizeValue = unsafeBitCast(rawSize, to: AXValue.self)
                var position = CGPoint.zero
                var size = CGSize.zero
                if AXValueGetType(positionValue) == .cgPoint, AXValueGetType(sizeValue) == .cgSize,
                   AXValueGetValue(positionValue, .cgPoint, &position), AXValueGetValue(sizeValue, .cgSize, &size) {
                    frame = usableFrame(position: position, size: size)
                }
            }
            result.items.append(InventoryItem(path: path,
                                              role: read(element, kAXRoleAttribute) as? String ?? "unknown",
                                              hasIdentifier: !(read(element, kAXIdentifierAttribute) as? String ?? "").isEmpty,
                                              frame: frame))
        }
        if !complete { result.status = "truncated" }
        if result.status == "ok", !result.errors.isEmpty { result.status = "partial" }
    } else if result.status == "ok" {
        let error = result.errors[kAXExtrasMenuBarAttribute]
        result.status = (error == AXError.noValue.rawValue || error == AXError.attributeUnsupported.rawValue)
            ? "no-extras" : "unavailable"
    }
    applications.append(result)
}

struct Report: Encodable {
    let schemaVersion = 1
    let os: String
    let timedOut: Bool
    let applications: [ApplicationInventory]
}
let report = Report(os: ProcessInfo.processInfo.operatingSystemVersionString,
                    timedOut: timedOut, applications: applications)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(report))
FileHandle.standardOutput.write(Data("\n".utf8))
if timedOut || applications.contains(where: { ["truncated", "unavailable", "invalid-children"].contains($0.status) }) {
    exit(3)
}
