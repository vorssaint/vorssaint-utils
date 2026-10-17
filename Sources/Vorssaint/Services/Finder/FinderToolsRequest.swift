// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Finder extension only asks the host to show a selection. A URL never
/// authorizes a file mutation or carries a script to execute.
struct FinderToolsRequest: Codable, Equatable {
    let selection: [URL]
    let directory: URL?
    let suggestedAction: FinderToolsAction?
    let savedActionID: UUID?

    static let maximumSelectionCount = 128
    static let maximumURLLength = 32_768

    static var scheme: String {
        #if VORSSAINT_DEVELOPMENT
        return "vorssaint-dev-files"
        #else
        return "vorssaint-files"
        #endif
    }

    var url: URL? {
        guard isValid, let data = try? JSONEncoder().encode(self) else { return nil }
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "selection"
        components.queryItems = [URLQueryItem(name: "payload", value: data.base64EncodedString())]
        guard let result = components.url,
              result.absoluteString.utf8.count <= Self.maximumURLLength else { return nil }
        return result
    }

    init(selection: [URL], directory: URL?, suggestedAction: FinderToolsAction? = nil, savedActionID: UUID? = nil) {
        self.selection = selection
        self.directory = directory
        self.suggestedAction = suggestedAction
        self.savedActionID = savedActionID
    }

    init?(url: URL) {
        guard url.absoluteString.utf8.count <= Self.maximumURLLength,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == Self.scheme, components.host == "selection",
              components.path.isEmpty, components.fragment == nil,
              components.user == nil, components.password == nil, components.port == nil,
              let query = components.queryItems, query.count == 1,
              query[0].name == "payload", let payload = query[0].value,
              let data = Data(base64Encoded: payload),
              let request = try? JSONDecoder().decode(Self.self, from: data),
              request.isValid else { return nil }
        self = request
    }

    private var isValid: Bool {
        selection.count <= Self.maximumSelectionCount
            && selection.allSatisfy(Self.isLocalFile)
            && (directory.map(Self.isLocalFile) ?? true)
            && (!selection.isEmpty || directory != nil)
    }

    private static func isLocalFile(_ url: URL) -> Bool {
        url.isFileURL && (url.host == nil || url.host == "" || url.host == "localhost")
            && url.path.hasPrefix("/") && !url.path.contains("\0")
            && url.query == nil && url.fragment == nil
    }
}
