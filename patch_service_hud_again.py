with open('Sources/Vorssaint/Services/Clipboard/ClipboardHistoryService.swift', 'r') as f:
    content = f.read()

content = content.replace('    @Published var history: [ClipboardEntry] = []\n    @Published var pinned: [ClipboardEntry] = []\n', '    @Published var history: [ClipboardEntry] = []\n    @Published var pinned: [ClipboardEntry] = []\n\n    @Published var newlyCopiedPreview: String? = nil\n')

# replace Notifier.post(title: "Copied", body: preview) with self.newlyCopiedPreview = preview
content = content.replace('Notifier.post(title: "Copied", body: preview)', 'self.newlyCopiedPreview = preview')

with open('Sources/Vorssaint/Services/Clipboard/ClipboardHistoryService.swift', 'w') as f:
    f.write(content)
