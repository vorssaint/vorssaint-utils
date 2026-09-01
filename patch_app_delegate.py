with open('Sources/Vorssaint/App/AppDelegate.swift', 'r') as f:
    content = f.read()

obs = """        L10n.shared.$language
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.installMainMenu() }
            .store(in: &cancellables)

        ClipboardHistoryService.shared.$newlyCopiedPreview
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { preview in
                ClipboardToastController.shared.show(preview: preview)
            }
            .store(in: &cancellables)"""
            
content = content.replace('        L10n.shared.$language\n            .dropFirst()\n            .receive(on: DispatchQueue.main)\n            .sink { [weak self] _ in self?.installMainMenu() }\n            .store(in: &cancellables)', obs)

with open('Sources/Vorssaint/App/AppDelegate.swift', 'w') as f:
    f.write(content)
