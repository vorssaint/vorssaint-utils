// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Cocoa
import ScreenCaptureKit

struct ScreenCapture {
    let screen: NSScreen
    let image: CGImage
}

class ScreenshotOverlayController: NSObject {
    static let shared = ScreenshotOverlayController()
    
    private var windows: [ScreenshotOverlayWindow] = []
    
    func startCapture() {
        dismiss()
        
        Task {
            let screens = NSScreen.screens
            guard !screens.isEmpty else { return }
            
            var captures: [ScreenCapture] = []
            
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                
                for screen in screens {
                    // Match screen by display ID
                    let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                    guard let display = content.displays.first(where: { $0.displayID == screenNumber }) else { continue }
                    
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    let scale = Int(screen.backingScaleFactor)
                    config.width = display.width * scale
                    config.height = display.height * scale
                    config.showsCursor = true
                    config.captureResolution = .best
                    
                    if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                        captures.append(ScreenCapture(screen: screen, image: image))
                    }
                }
            } catch {
                return
            }
            
            guard captures.count == screens.count else { return }
            
            let finalCaptures = captures
            await MainActor.run {
                for capture in finalCaptures {
                    let overlayWindow = ScreenshotOverlayWindow(capture: capture, controller: self)
                    self.windows.append(overlayWindow)
                    overlayWindow.orderFrontRegardless()
                    overlayWindow.makeKey()
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    func dismiss() {
        for win in windows {
            win.orderOut(nil)
        }
        windows.removeAll()
    }
    
    func confirmCapture(cgImage: CGImage, rect: NSRect, screen: NSScreen) {
        let croppedCG = cropCGImage(cgImage, to: rect, screen: screen)
        
        if let finalCG = croppedCG {
            let nsImage = NSImage(cgImage: finalCG, size: NSSize(width: rect.width, height: rect.height))
            
            let mode = UserDefaults.standard.integer(forKey: DefaultsKey.screenshotQuickCaptureMode)
            
            // 1. Copy to Clipboard (mode 1 or 2)
            if mode == 1 || mode == 2 {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([nsImage])
            }
            
            // Dismiss overlays BEFORE presenting save dialogs or floating previews
            dismiss()
            
            // 2. Save to file (mode 0 or 2)
            if mode == 0 || mode == 2 {
                saveImageDirectly(nsImage)
            }
            
            // 3. Show floating thumbnail
            if UserDefaults.standard.bool(forKey: DefaultsKey.screenshotShowThumbnail) {
                FloatingThumbnailController.shared.show(image: nsImage)
            }
        } else {
            dismiss()
        }
    }
    
    private func saveImageDirectly(_ image: NSImage) {
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
            }
        }
    }
    
    private func cropCGImage(_ image: CGImage, to viewRect: NSRect, screen: NSScreen) -> CGImage? {
        let scale = CGFloat(image.width) / screen.frame.width
        let cropRect = CGRect(
            x: viewRect.origin.x * scale,
            y: (screen.frame.height - viewRect.maxY) * scale,
            width: viewRect.width * scale,
            height: viewRect.height * scale
        )
        return image.cropping(to: cropRect)
    }
}

class ScreenshotOverlayWindow: NSPanel {
    private let controller: ScreenshotOverlayController
    
    init(capture: ScreenCapture, controller: ScreenshotOverlayController) {
        self.controller = controller
        super.init(
            contentRect: capture.screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = NSWindow.Level(257)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.animationBehavior = .none
        
        let view = ScreenshotOverlayView(capture: capture, controller: controller)
        view.frame = NSRect(origin: .zero, size: capture.screen.frame.size)
        self.contentView = view
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class ScreenshotOverlayView: NSView {
    private let capture: ScreenCapture
    private weak var controller: ScreenshotOverlayController?
    
    private var selectionStart: NSPoint = .zero
    private var selectionRect: NSRect = .zero
    private var isDragging = false
    
    private var hoveredWindowRect: NSRect?
    
    init(capture: ScreenCapture, controller: ScreenshotOverlayController) {
        self.capture = capture
        self.controller = controller
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            let options: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers
        if event.keyCode == 53 || chars == "\u{1B}" {
            controller?.dismiss()
        } else if chars == "f" || chars == "F" {
            controller?.confirmCapture(cgImage: capture.image, rect: bounds, screen: capture.screen)
        } else {
            super.keyDown(with: event)
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let context = NSGraphicsContext.current?.cgContext
        context?.draw(capture.image, in: bounds)
        
        NSColor.black.withAlphaComponent(0.25).set()
        bounds.fill()
        
        if isDragging && !selectionRect.isEmpty {
            context?.saveGState()
            let path = NSBezierPath(rect: selectionRect)
            path.addClip()
            context?.draw(capture.image, in: bounds)
            context?.restoreGState()
            
            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1.5
            border.stroke()
        } else if let snapRect = hoveredWindowRect, !snapRect.isEmpty {
            context?.saveGState()
            let path = NSBezierPath(rect: snapRect)
            path.addClip()
            context?.draw(capture.image, in: bounds)
            context?.restoreGState()
            
            NSColor.systemBlue.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: snapRect, xRadius: 4, yRadius: 4).fill()
            
            NSColor.systemBlue.withAlphaComponent(0.85).setStroke()
            let border = NSBezierPath(roundedRect: snapRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            border.lineWidth = 2
            border.stroke()
        }
        
        if !UserDefaults.standard.bool(forKey: DefaultsKey.screenshotHideInstructions), !isDragging {
            drawInstructions()
        }
    }
    
    private func drawInstructions() {
        let text = "Drag to select area • Click to snap window • F for full screen • Esc to cancel"
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let paddingX: CGFloat = 16
        let paddingY: CGFloat = 8
        let width = textSize.width + paddingX * 2
        let height = textSize.height + paddingY * 2
        
        let x = (bounds.width - width) / 2
        let y = bounds.height - height - 40
        
        let capsuleRect = NSRect(x: x, y: y, width: width, height: height)
        
        NSColor.black.withAlphaComponent(0.65).set()
        let path = NSBezierPath(roundedRect: capsuleRect, xRadius: height / 2, yRadius: height / 2)
        path.fill()
        
        NSColor.white.withAlphaComponent(0.15).setStroke()
        path.lineWidth = 1
        path.stroke()
        
        let textRect = NSRect(
            x: x + paddingX,
            y: y + paddingY,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
    }
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        selectionStart = location
        selectionRect = .zero
        isDragging = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let location = convert(event.locationInWindow, from: nil)
        
        let minX = min(selectionStart.x, location.x)
        let maxX = max(selectionStart.x, location.x)
        let minY = min(selectionStart.y, location.y)
        let maxY = max(selectionStart.y, location.y)
        
        selectionRect = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        
        let location = convert(event.locationInWindow, from: nil)
        let dragDistance = hypot(location.x - selectionStart.x, location.y - selectionStart.y)
        
        if dragDistance < 5, let snapRect = hoveredWindowRect, !snapRect.isEmpty {
            controller?.confirmCapture(cgImage: capture.image, rect: snapRect, screen: capture.screen)
        } else if selectionRect.width > 5 && selectionRect.height > 5 {
            controller?.confirmCapture(cgImage: capture.image, rect: selectionRect, screen: capture.screen)
        } else {
            selectionRect = .zero
            needsDisplay = true
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        guard !isDragging else { return }
        
        let screenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let windowOrigin = window?.frame.origin ?? .zero
        
        if let result = ScreenshotOverlayView.windowRectOnBackground(
            screenPoint: screenPoint,
            overlayWindowNumber: window?.windowNumber ?? 0,
            windowOrigin: windowOrigin,
            viewBounds: bounds,
            screenH: mainHeight
        ) {
            hoveredWindowRect = result.rect
        } else {
            hoveredWindowRect = nil
        }
        needsDisplay = true
    }
    
    private struct WindowSnapCandidate {
        let rect: NSRect
        let windowID: CGWindowID
        let area: CGFloat
    }
    
    private static func windowRectOnBackground(
        screenPoint: NSPoint,
        overlayWindowNumber: Int,
        windowOrigin: NSPoint,
        viewBounds: NSRect,
        screenH: CGFloat
    ) -> WindowSnapResult? {
        guard
            let windowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        
        var frontmost: WindowSnapCandidate?
        
        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let winNum = info[kCGWindowNumber as String] as? Int,
                  winNum != overlayWindowNumber
            else { continue }
            
            let cgX = boundsDict["X"] ?? 0
            let cgY = boundsDict["Y"] ?? 0
            let cgW = boundsDict["Width"] ?? 0
            let cgH = boundsDict["Height"] ?? 0
            guard cgW > 10 && cgH > 10 else { continue }
            
            let appKitRect = NSRect(x: cgX, y: screenH - cgY - cgH, width: cgW, height: cgH)
            if appKitRect.contains(screenPoint) {
                let viewRect = NSRect(
                    x: appKitRect.origin.x - windowOrigin.x,
                    y: appKitRect.origin.y - windowOrigin.y,
                    width: appKitRect.width,
                    height: appKitRect.height
                )
                let candidate = WindowSnapCandidate(
                    rect: viewRect.intersection(viewBounds),
                    windowID: CGWindowID(winNum),
                    area: cgW * cgH
                )
                if frontmost == nil {
                    frontmost = candidate
                }
            }
        }
        
        guard let best = frontmost else { return nil }
        return WindowSnapResult(rect: best.rect, windowID: best.windowID)
    }
}

struct WindowSnapResult {
    let rect: NSRect
    let windowID: CGWindowID
}
