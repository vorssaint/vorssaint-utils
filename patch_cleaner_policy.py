import re
with open('Sources/Vorssaint/Services/Cleaner/CleanerPolicy.swift', 'r') as f:
    content = f.read()

enum_def = """
enum DeveloperCacheRisk {
    case safe
    case caution
    case risky
}

"""

if 'enum DeveloperCacheRisk' not in content:
    content = content.replace('enum CleanerPolicy {', enum_def + 'enum CleanerPolicy {')

old_paths = """    static let developerJunkPaths: [String] = [
        "/Library/Developer/Xcode/DerivedData",
        "/Library/Developer/Xcode/DocumentationCache",
        "/Library/Developer/CoreSimulator/Caches",
        "/Library/Developer/Xcode/iOS DeviceSupport",
        "/Library/Developer/Xcode/watchOS DeviceSupport",
        "/Library/Developer/Xcode/tvOS DeviceSupport",
    ]"""

new_paths = """    static let developerJunkPaths: [(path: String, risk: DeveloperCacheRisk)] = [
        ("/Library/Developer/Xcode/DerivedData", .safe),
        ("/Library/Developer/Xcode/DocumentationCache", .safe),
        ("/Library/Developer/CoreSimulator/Caches", .safe),
        ("/Library/Developer/Xcode/iOS DeviceSupport", .safe),
        ("/Library/Developer/Xcode/watchOS DeviceSupport", .safe),
        ("/Library/Developer/Xcode/tvOS DeviceSupport", .safe),
        ("/.gradle/caches", .safe),
        ("/.cargo/registry/cache", .safe),
        ("/.npm/_cacache", .safe),
        ("/.yarn/cache", .safe),
        ("/.cocoapods/repos", .safe),
        ("/.m2/repository", .caution),
        ("/.pub-cache", .safe),
        ("/.nuget/packages", .safe),
        ("/Library/Caches/CocoaPods", .safe),
        ("/Library/Caches/Homebrew", .safe),
        ("/Library/Caches/pip", .safe),
        ("/Library/Caches/Yarn", .safe),
        ("/Library/Caches/com.apple.dt.Xcode", .safe)
    ]"""

content = content.replace(old_paths, new_paths)

with open('Sources/Vorssaint/Services/Cleaner/CleanerPolicy.swift', 'w') as f:
    f.write(content)
