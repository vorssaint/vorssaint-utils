import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// A floating "shelf" that holds files, images, text and links you drop on it,
/// to drag back out into any app later. It's summoned at the cursor by a global
/// shortcut (⌃⌥⌘D) or, optionally, by shaking the mouse mid-drag. Items live
/// only while the app runs.
///
/// No permissions required: the shortcut is a Carbon hot key, and the shake
/// detector is a passive global mouse monitor.
final class ShelfService: ObservableObject {
    static let shared = ShelfService()

    struct Item: Identifiable, Equatable {
        let id = UUID()
        enum Payload: Equatable {
            case file(URL)
            case text(String)
            case link(URL)
        }
        let payload: Payload
        let title: String
        let icon: NSImage
        let isImage: Bool

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.id == rhs.id }
    }

    @Published private(set) var items: [Item] = []

    private var panel: NSPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var mouseMonitor: Any?
    private var shakeSamples: [(t: TimeInterval, x: CGFloat)] = []
    private var lastSummon: TimeInterval = 0

    private let tempDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("VorssaintShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - Lifecycle

    func syncWithPreferences() {
        if UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled) {
            registerHotkey()
            syncShakeMonitor()
        } else {
            unregisterHotkey()
            stopShakeMonitor()
            hide()
        }
    }

    /// Re-reads only the shake sub-preference (called when the user toggles it).
    func syncShakeMonitor() {
        let wanted = UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled)
            && UserDefaults.standard.bool(forKey: DefaultsKey.shelfShakeToOpen)
        if wanted { startShakeMonitor() } else { stopShakeMonitor() }
    }

    // MARK: - Triggers

    private func registerHotkey() {
        guard hotKeyRef == nil else { return }
        if hotKeyHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
                guard let userData else { return noErr }
                var id = EventHotKeyID()
                if let event {
                    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &id)
                }
                guard id.id == 2 else { return noErr }
                let service = Unmanaged<ShelfService>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { service.toggle() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        }
        let id = EventHotKeyID(signature: 0x5655_5348, id: 2) // 'VUSH'
        RegisterEventHotKey(UInt32(kVK_ANSI_D),
                            UInt32(controlKey | optionKey | cmdKey),
                            id, GetEventDispatcherTarget(), 0, &hotKeyRef)
    }

    private func unregisterHotkey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func startShakeMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleDrag(event)
        }
    }

    private func stopShakeMonitor() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        shakeSamples.removeAll()
    }

    /// Detects a back-and-forth shake of the pointer during a drag: enough
    /// horizontal direction reversals and travel in a short window.
    private func handleDrag(_ event: NSEvent) {
        let t = event.timestamp
        shakeSamples.append((t, NSEvent.mouseLocation.x))
        shakeSamples.removeAll { t - $0.t > 0.5 }
        guard shakeSamples.count >= 5 else { return }

        var reversals = 0
        var travel: CGFloat = 0
        var lastDirection = 0
        for i in 1..<shakeSamples.count {
            let dx = shakeSamples[i].x - shakeSamples[i - 1].x
            travel += abs(dx)
            let direction = dx > 6 ? 1 : (dx < -6 ? -1 : 0)
            if direction != 0 {
                if lastDirection != 0, direction != lastDirection { reversals += 1 }
                lastDirection = direction
            }
        }
        if reversals >= 3, travel > 220, t - lastSummon > 1.0 {
            lastSummon = t
            shakeSamples.removeAll()
            DispatchQueue.main.async { [weak self] in self?.summon() }
        }
    }

    // MARK: - Items

    func accept(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        url.isFileURL ? self?.addFile(url) : self?.addLink(url)
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSImage.self) { [weak self] image, _ in
                    guard let image = image as? NSImage else { return }
                    DispatchQueue.main.async { self?.addImage(image) }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] string, _ in
                    guard let string = string as? String else { return }
                    DispatchQueue.main.async { self?.addText(string) }
                }
            }
        }
        return handled
    }

    func removeItem(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func clear() {
        items = []
    }

    /// The drag-out representation for an item.
    func provider(for item: Item) -> NSItemProvider {
        switch item.payload {
        case let .file(url): return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
        case let .text(text): return NSItemProvider(object: text as NSString)
        case let .link(url): return NSItemProvider(object: url as NSURL)
        }
    }

    private func addFile(_ url: URL) {
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "bmp", "webp"]
        let isImage = imageExtensions.contains(url.pathExtension.lowercased())
        let icon = (isImage ? NSImage(contentsOf: url) : nil) ?? NSWorkspace.shared.icon(forFile: url.path)
        append(Item(payload: .file(url), title: url.lastPathComponent, icon: icon, isImage: isImage))
    }

    private func addImage(_ image: NSImage) {
        let url = tempDir.appendingPathComponent("\(UUID().uuidString).png")
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            append(Item(payload: .file(url), title: L10n.shared.s.shelfItemImage, icon: image, isImage: true))
        }
    }

    private func addText(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
        let icon = symbol("doc.plaintext")
        append(Item(payload: .text(string), title: String(firstLine.prefix(48)), icon: icon, isImage: false))
    }

    private func addLink(_ url: URL) {
        append(Item(payload: .link(url), title: url.host ?? url.absoluteString, icon: symbol("link"), isImage: false))
    }

    private func append(_ item: Item) {
        items.append(item)
    }

    private func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }

    // MARK: - Panel

    func toggle() {
        isVisible ? hide() : summon()
    }

    func summon() {
        let panel = ensurePanel()
        position(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func position(_ panel: NSPanel) {
        let view = panel.contentViewController!.view
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        let mouse = NSEvent.mouseLocation
        let screen = screenWithMouse().visibleFrame
        var x = mouse.x - size.width / 2
        var y = mouse.y - size.height - 16
        x = min(max(screen.minX + 8, x), screen.maxX - size.width - 8)
        y = min(max(screen.minY + 8, y), screen.maxY - size.height - 8)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: ShelfView().environmentObject(self))
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }

    private func screenWithMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
