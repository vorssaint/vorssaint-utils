// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Cocoa

class FloatingThumbnailController: NSObject, NSDraggingSource {
    static let shared = FloatingThumbnailController()
    
    private var window: NSPanel?
    private var dismissTimer: Timer?
    private var image: NSImage?
    
    func show(image: NSImage) {
        dismiss()
        
        self.image = image
        
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let width: CGFloat = 220
        let height: CGFloat = 140
        let padding: CGFloat = 16
        
        let x = screenFrame.maxX - width - padding
        let y = screenFrame.minY + padding
        
        let panel = NSPanel(
            contentRect: NSRect(x: x + 200, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.acceptsMouseMovedEvents = true
        
        let view = FloatingThumbnailView(image: image, controller: self)
        view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        panel.contentView = view
        
        self.window = panel
        panel.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }, completionHandler: nil)
        
        startDismissTimer()
    }
    
    func startDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.slideOutAndDismiss()
        }
    }
    
    func stopDismissTimer() {
        dismissTimer?.invalidate()
        dismissTimer = nil
    }
    
    func slideOutAndDismiss() {
        guard let panel = window else { return }
        let currentFrame = panel.frame
        let targetX = currentFrame.origin.x + currentFrame.size.width + 50
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(NSRect(x: targetX, y: currentFrame.origin.y, width: currentFrame.size.width, height: currentFrame.size.height), display: true)
        }, completionHandler: { [weak self] in
            self?.dismiss()
        })
    }
    
    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        window?.orderOut(nil)
        window = nil
        image = nil
    }
    
    static func generateUniqueURL(in directoryURL: URL, date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let dateString = formatter.string(from: date)
        let baseName = "Screenshot \(dateString)"
        let fileExtension = "png"
        
        let fileManager = FileManager.default
        var candidateURL = directoryURL.appendingPathComponent("\(baseName).\(fileExtension)")
        var counter = 1
        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = directoryURL.appendingPathComponent("\(baseName) (\(counter)).\(fileExtension)")
            counter += 1
        }
        return candidateURL
    }
    
    static func saveImageToPictures(image: NSImage) -> URL? {
        let fileManager = FileManager.default
        let picturesURL = fileManager.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        let folderURL = picturesURL.appendingPathComponent("Vorssaint Screenshots")
        
        if !fileManager.fileExists(atPath: folderURL.path) {
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        let fileURL = FloatingThumbnailController.generateUniqueURL(in: folderURL, date: Date())
        
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: fileURL)
            return fileURL
        }
        return nil
    }
    
    func saveToPictures() {
        guard let image = image else { return }
        let saveAction = UserDefaults.standard.integer(forKey: DefaultsKey.screenshotSaveAction)
        
        if saveAction == 1 { // Ask where to save
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
            panel.nameFieldStringValue = "Screenshot \(formatter.string(from: Date())).png"
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            
            if let customDir = UserDefaults.standard.string(forKey: DefaultsKey.screenshotSaveDirectory) {
                panel.directoryURL = URL(fileURLWithPath: customDir)
            }
            
            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let fileURL = panel.url {
                guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                let rep = NSBitmapImageRep(cgImage: cgImage)
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: fileURL)
                    NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
                }
            }
        } else { // Save to default folder
            let folderPath = UserDefaults.standard.string(forKey: DefaultsKey.screenshotSaveDirectory) ?? Defaults.defaultScreenshotDirectoryPath
            let fileManager = FileManager.default
            let folderURL = URL(fileURLWithPath: folderPath)
            
            if !fileManager.fileExists(atPath: folderURL.path) {
                try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
            }
            
            let fileURL = FloatingThumbnailController.generateUniqueURL(in: folderURL, date: Date())
            
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: fileURL)
                NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: folderURL.path)
            }
        }
        slideOutAndDismiss()
    }
    
    func copyToClipboard() {
        guard let image = image else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        slideOutAndDismiss()
    }
    
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
    
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dismiss()
    }
}

class FloatingThumbnailView: NSView {
    private let image: NSImage
    private weak var controller: FloatingThumbnailController?
    
    private var isHovered = false
    private var trackingArea: NSTrackingArea?
    
    private var mouseDownPoint: NSPoint = .zero
    private var isSwipeDismissing = false
    
    private var buttons: [NSButton] = []
    
    init(image: NSImage, controller: FloatingThumbnailController) {
        self.image = image
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        layer?.borderWidth = 1.5
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        controller?.stopDismissTimer()
        needsDisplay = true
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        controller?.startDismissTimer()
        needsDisplay = true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.1, alpha: 0.85).set()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        path.fill()
        
        let imageSize = image.size
        let viewSize = bounds.size
        let targetRect = calculateAspectFitRect(imageSize: imageSize, viewSize: viewSize)
        image.draw(in: targetRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        
        if isHovered {
            NSColor.black.withAlphaComponent(0.3).set()
            path.fill()
            drawOverlayButtons()
        }
    }
    
    private func calculateAspectFitRect(imageSize: NSSize, viewSize: NSSize) -> NSRect {
        let imageRatio = imageSize.width / imageSize.height
        let viewRatio = viewSize.width / viewSize.height
        
        var targetWidth = viewSize.width
        var targetHeight = viewSize.height
        
        if imageRatio > viewRatio {
            targetHeight = viewSize.width / imageRatio
        } else {
            targetWidth = viewSize.height * imageRatio
        }
        
        let x = (viewSize.width - targetWidth) / 2
        let y = (viewSize.height - targetHeight) / 2
        return NSRect(x: x, y: y, width: targetWidth, height: targetHeight)
    }
    
    private func drawOverlayButtons() {
        if buttons.isEmpty {
            setupButtons()
        }
        for btn in buttons {
            btn.isHidden = false
        }
    }
    
    private func setupButtons() {
        let buttonSize: CGFloat = 32
        let spacing: CGFloat = 16
        
        let names = ["square.and.arrow.down", "doc.on.clipboard", "xmark"]
        let actions = [#selector(savePressed), #selector(copyPressed), #selector(closePressed)]
        
        let totalWidth = CGFloat(names.count) * buttonSize + CGFloat(names.count - 1) * spacing
        var startX = (bounds.width - totalWidth) / 2
        let y = (bounds.height - buttonSize) / 2
        
        for i in 0..<names.count {
            let btn = NSButton(frame: NSRect(x: startX, y: y, width: buttonSize, height: buttonSize))
            btn.bezelStyle = .shadowlessSquare
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = buttonSize / 2
            btn.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
            btn.image = NSImage(systemSymbolName: names[i], accessibilityDescription: nil)
            btn.imagePosition = .imageOnly
            btn.imageScaling = .scaleProportionallyDown
            btn.contentTintColor = .white
            btn.target = self
            btn.action = actions[i]
            
            addSubview(btn)
            buttons.append(btn)
            startX += buttonSize + spacing
        }
    }
    
    override func viewWillDraw() {
        super.viewWillDraw()
        for btn in buttons {
            btn.isHidden = !isHovered
        }
    }
    
    @objc private func savePressed() {
        controller?.saveToPictures()
    }
    
    @objc private func copyPressed() {
        controller?.copyToClipboard()
    }
    
    @objc private func closePressed() {
        controller?.slideOutAndDismiss()
    }
    
    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        isSwipeDismissing = false
    }
    
    override func mouseDragged(with event: NSEvent) {
        let currentPoint = event.locationInWindow
        let deltaX = currentPoint.x - mouseDownPoint.x
        let deltaY = currentPoint.y - mouseDownPoint.y
        
        if abs(deltaX) > 15 && abs(deltaY) < 10 && !isSwipeDismissing {
            isSwipeDismissing = true
        }
        
        if isSwipeDismissing {
            guard let window = window else { return }
            var frame = window.frame
            if deltaX > 0 {
                frame.origin.x = window.frame.origin.x + deltaX
                window.setFrame(frame, display: true)
            }
        } else if abs(deltaX) > 5 || abs(deltaY) > 5 {
            triggerSystemDrag(with: event)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if isSwipeDismissing {
            let currentPoint = event.locationInWindow
            let deltaX = currentPoint.x - mouseDownPoint.x
            if deltaX > 50 {
                controller?.slideOutAndDismiss()
            } else {
                if let panel = window {
                    let screen = NSScreen.main ?? NSScreen.screens[0]
                    let screenFrame = screen.visibleFrame
                    let x = screenFrame.maxX - bounds.width - 16
                    panel.animator().setFrame(NSRect(x: x, y: panel.frame.origin.y, width: bounds.width, height: bounds.height), display: true)
                }
            }
            isSwipeDismissing = false
        }
    }
    
    private func triggerSystemDrag(with event: NSEvent) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("screenshot.png")
        try? data.write(to: tempURL)
        
        let draggingItem = NSDraggingItem(pasteboardWriter: tempURL as NSURL)
        draggingItem.setDraggingFrame(bounds, contents: image)
        
        beginDraggingSession(with: [draggingItem], event: event, source: controller!)
    }
}
