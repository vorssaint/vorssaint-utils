with open('Sources/Vorssaint/Services/Clipboard/ClipboardHistoryService.swift', 'r') as f:
    content = f.read()

# Add signal property
content = content.replace('    @Published var history: [ClipboardEntry] = []\n    @Published var pinned: [ClipboardEntry] = []\n', '    @Published var history: [ClipboardEntry] = []\n    @Published var pinned: [ClipboardEntry] = []\n\n    @Published var newlyCopiedPreview: String? = nil\n')

# Use signal instead of direct controller call
content = content.replace('ClipboardToastController.shared.show(preview: preview)', 'self.newlyCopiedPreview = preview')

with open('Sources/Vorssaint/Services/Clipboard/ClipboardHistoryService.swift', 'w') as f:
    f.write(content)
