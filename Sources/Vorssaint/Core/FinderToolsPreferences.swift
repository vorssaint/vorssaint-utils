// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FinderToolsMenuConfiguration: Codable, Equatable {
    var order: [String] = []
    var hidden: Set<String> = [FinderToolsAction.permanentDelete.rawValue]
    var titles: [String: String] = [:]
    var grouped = true
    var icons: [String: String]?
    var shortcuts: [String: String]?

    func icon(for action: FinderToolsAction) -> String? {
        guard let symbol = icons?[action.rawValue], !symbol.isEmpty, symbol.count <= 80,
              symbol.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }) else { return nil }
        return symbol
    }

    func shortcut(for action: FinderToolsAction) -> String {
        guard let key = shortcuts?[action.rawValue]?.lowercased(), key.count == 1,
              key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              visibleActions.first(where: { shortcuts?[$0.rawValue]?.lowercased() == key }) == action else { return "" }
        return key
    }

    var orderedActions: [FinderToolsAction] {
        var seen = Set<FinderToolsAction>()
        return (order.compactMap(FinderToolsAction.init(rawValue:)) + FinderToolsAction.allCases)
            .filter { seen.insert($0).inserted }
    }

    var visibleActions: [FinderToolsAction] { orderedActions.filter { !hidden.contains($0.rawValue) } }

    func title(for action: FinderToolsAction, language: String) -> String {
        guard let title = titles[action.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty, title.count <= 80,
              !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return action.title(languageCode: language)
        }
        return title
    }

    mutating func move(_ action: FinderToolsAction, by offset: Int) {
        var actions = orderedActions
        guard let index = actions.firstIndex(of: action), actions.indices.contains(index + offset) else { return }
        actions.swapAt(index, index + offset)
        order = actions.map(\.rawValue)
    }
}

struct FinderToolsSavedAction: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case folder, application, template, script, website, icon
    }
    var id = UUID()
    var title: String
    var kind: Kind
    var location: URL
    var group: String?

    var isValid: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 80,
              !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              (group?.count ?? 0) <= 80,
              group?.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) != true else { return false }
        if kind == .website {
            return ["https", "http"].contains(location.scheme) && location.host?.isEmpty == false
                && location.user == nil && location.password == nil
        }
        return location.isFileURL && [nil, "", "localhost"].contains(location.host)
            && location.path.hasPrefix("/") && !location.path.contains("\0")
            && location.query == nil && location.fragment == nil
    }
}

struct FinderToolsConfiguration: Codable, Equatable {
    var version = 1
    var menu = FinderToolsMenuConfiguration()
    var savedActions: [FinderToolsSavedAction] = []
    var creation: FinderCreationPreferences?

    static func decode(_ string: String?) -> Self {
        guard let data = string?.data(using: .utf8), data.count <= 1_048_576,
              var configuration = try? JSONDecoder().decode(Self.self, from: data),
              configuration.version == 1 else { return Self() }
        var seen = Set<UUID>()
        configuration.savedActions = configuration.savedActions.prefix(200).filter { action in
            seen.insert(action.id).inserted && action.isValid
        }
        return configuration
    }

    var encoded: String {
        guard let data = try? JSONEncoder().encode(self), let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }
}

struct FinderCreationPreferences: Codable, Equatable {
    var openAfterCreation = false
    var hideExtension = false
    var playSound = false
    var uniqueNames = true
}

/// Only menu presentation crosses the sandbox boundary. Script bodies, paths,
/// clipboard content and other preferences stay in the containing application.
struct FinderToolsMenuSnapshot: Codable {
    struct SavedItem: Codable {
        let id: UUID
        let title: String
        var group: String?
    }
    let enabled: Bool
    let language: String
    let menu: FinderToolsMenuConfiguration
    let savedItems: [SavedItem]

    static let preferenceKey = "finderToolsMenuSnapshot"

    static var sharedDefaults: UserDefaults? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FinderToolsAppGroup") as? String,
              !group.isEmpty else { return nil }
        return UserDefaults(suiteName: group)
    }

    static func read() -> Self? {
        guard let data = sharedDefaults?.data(forKey: preferenceKey), data.count <= 1_048_576 else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func publish() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.sharedDefaults?.set(data, forKey: Self.preferenceKey)
    }
}
