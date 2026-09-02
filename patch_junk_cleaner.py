import re
with open('Sources/Vorssaint/Services/Cleaner/JunkCleaner.swift', 'r') as f:
    content = f.read()

# Patch scanDeveloperJunk
old_scan_dev = """    private static func scanDeveloperJunk() -> [Item] {
        let fm = FileManager.default
        var found: [Item] = []
        for path in CleanerPolicy.developerJunkPaths {
            let url = URL(fileURLWithPath: NSHomeDirectory() + path)
            guard fm.fileExists(atPath: url.path) else { continue }
            let size = directorySize(of: url, fm: fm)
            guard size > 0 else { continue }
            found.append(Item(url: url, category: .developer, size: size,
                              detail: url.lastPathComponent,
                              recommended: CleanerPolicy.precheckDeveloper))
        }
        return sorted(found)
    }"""

new_scan_dev = """    private static func scanDeveloperJunk() -> [Item] {
        let fm = FileManager.default
        var found: [Item] = []
        for entry in CleanerPolicy.developerJunkPaths {
            let url = URL(fileURLWithPath: NSHomeDirectory() + entry.path)
            guard fm.fileExists(atPath: url.path) else { continue }
            let size = directorySize(of: url, fm: fm)
            guard size > 0 else { continue }
            found.append(Item(url: url, category: .developer, size: size,
                              detail: url.lastPathComponent,
                              recommended: entry.risk == .safe))
        }
        return sorted(found)
    }"""

content = content.replace(old_scan_dev, new_scan_dev)

# Patch the order and dedup
old_array = """                (.caches, { Self.scanCaches(excluding: claimed) }),
                (.logs, { Self.scanLogs(excluding: claimed) }),
                (.developer, { Self.scanDeveloperJunk() }),"""

new_array = """                (.developer, {
                    let found = Self.scanDeveloperJunk()
                    claimed.formUnion(found.map { $0.url.standardizedFileURL.path })
                    return found
                }),
                (.caches, { Self.scanCaches(excluding: claimed) }),
                (.logs, { Self.scanLogs(excluding: claimed) }),"""

content = content.replace(old_array, new_array)

with open('Sources/Vorssaint/Services/Cleaner/JunkCleaner.swift', 'w') as f:
    f.write(content)
