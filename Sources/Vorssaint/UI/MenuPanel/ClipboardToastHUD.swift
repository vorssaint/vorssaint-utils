import SwiftUI
import AppKit

struct ClipboardToastHUD: View {
    let previewText: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("Copied")
                .font(.headline)
            Text(previewText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .padding(16)
        .frame(width: 200, height: 120)
        .background(.regularMaterial)
        .cornerRadius(16)
    }
}

final class ClipboardToastController: NSWindowController {
    static let shared = ClipboardToastController()
    private var hideTask: DispatchWorkItem?
    
    init() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        super.init(window: panel)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func show(preview: String) {
        let hudView = ClipboardToastHUD(previewText: preview)
        window?.contentView = NSHostingView(rootView: hudView)
        
        if let screen = NSScreen.main, let window = window {
            let size = window.contentView!.intrinsicContentSize
            let x = screen.frame.midX - (size.width / 2)
            let y = screen.frame.minY + 120
            window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }
        
        window?.orderFrontRegardless()
        
        hideTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.window?.animator().alphaValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.window?.orderOut(nil)
                self?.window?.alphaValue = 1
            }
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
    }
}
