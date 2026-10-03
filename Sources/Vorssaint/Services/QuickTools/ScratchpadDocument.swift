// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ScratchpadFolder: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
}

enum ScratchpadCollection: Hashable {
    case all, inbox, pinned, trash, folder(UUID)
}

struct ScratchpadPad: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var text: String
    var modifiedAt: Date?
    var folderID: UUID? = nil
    var isPinned = false
    var isTemporary = false
    var deletedAt: Date? = nil
    var usesAutomaticTitle = false

    private enum CodingKeys: String, CodingKey {
        case id, name, text, modifiedAt, folderID, isPinned, isTemporary, deletedAt, usesAutomaticTitle
    }

    init(id: UUID, name: String, text: String, modifiedAt: Date?, folderID: UUID? = nil,
         isPinned: Bool = false, isTemporary: Bool = false, deletedAt: Date? = nil,
         usesAutomaticTitle: Bool = false) {
        self.id = id; self.name = name; self.text = text; self.modifiedAt = modifiedAt
        self.folderID = folderID; self.isPinned = isPinned
        self.isTemporary = isTemporary; self.deletedAt = deletedAt
        self.usesAutomaticTitle = usesAutomaticTitle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        text = try c.decode(String.self, forKey: .text)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt)
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isTemporary = try c.decodeIfPresent(Bool.self, forKey: .isTemporary) ?? false
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        // Names in existing documents and imports belong to the user.
        usesAutomaticTitle = try c.decodeIfPresent(Bool.self, forKey: .usesAutomaticTitle) ?? false
    }
}

/// Saved notes and open tabs are separate. Closing a tab never destroys a note.
struct ScratchpadDocument: Codable, Equatable {
    static let currentVersion = 2
    static let maximumNameLength = 120

    var schemaVersion = currentVersion
    var pads: [ScratchpadPad]
    var selectedID: UUID
    var folders: [ScratchpadFolder] = []
    var openIDs: [UUID]

    init(pads: [ScratchpadPad], selectedID: UUID, folders: [ScratchpadFolder] = [], openIDs: [UUID]? = nil) {
        self.pads = pads; self.selectedID = selectedID; self.folders = folders
        self.openIDs = openIDs ?? pads.filter { $0.deletedAt == nil }.map(\.id)
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, pads, selectedID, folders, openIDs }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1...Self.currentVersion).contains(version) else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: c,
                                                  debugDescription: "Unsupported scratchpad version")
        }
        pads = try c.decode([ScratchpadPad].self, forKey: .pads)
        selectedID = try c.decode(UUID.self, forKey: .selectedID)
        folders = try c.decodeIfPresent([ScratchpadFolder].self, forKey: .folders) ?? []
        openIDs = try c.decodeIfPresent([UUID].self, forKey: .openIDs) ?? pads.map(\.id)
        guard Set(pads.map(\.id)).count == pads.count,
              Set(folders.map(\.id)).count == folders.count else {
            throw DecodingError.dataCorruptedError(forKey: .pads, in: c,
                                                  debugDescription: "Duplicate scratchpad identifiers")
        }
    }

    static func initial(defaultName: String, id: UUID = UUID(), text: String = "",
                        modifiedAt: Date? = nil) -> ScratchpadDocument {
        let pad = ScratchpadPad(id: id,
            name: ScratchpadSupport.nextPadName(defaultName: defaultName, existingNames: []),
            text: text, modifiedAt: text.isEmpty ? nil : modifiedAt, usesAutomaticTitle: text.isEmpty)
        return .init(pads: [pad], selectedID: id)
    }

    static func decoded(_ data: Data?, defaultName: String) -> ScratchpadDocument? {
        guard let data, let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        return decoded.sanitized(defaultName: defaultName)
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    func sanitized(defaultName: String) -> ScratchpadDocument {
        var next = self
        let folderIDs = Set(folders.map(\.id))
        for index in next.pads.indices {
            let name = ScratchpadSupport.sanitizedPadName(next.pads[index].name)
            next.pads[index].name = name.isEmpty ? defaultName : name
            if let folder = next.pads[index].folderID, !folderIDs.contains(folder) {
                next.pads[index].folderID = nil
            }
        }
        let liveIDs = Set(next.pads.filter { $0.deletedAt == nil }.map(\.id))
        var seen = Set<UUID>()
        next.openIDs = next.openIDs.filter { liveIDs.contains($0) && seen.insert($0).inserted }
        if !liveIDs.contains(next.selectedID) {
            if let first = next.openIDs.first ?? next.pads.first(where: { $0.deletedAt == nil })?.id {
                next.selectedID = first
            } else {
                let empty = Self.initial(defaultName: defaultName)
                next.pads.append(contentsOf: empty.pads)
                next.selectedID = empty.selectedID
                next.openIDs = empty.openIDs
            }
        }
        return next
    }

    func addingPad(defaultName: String, id: UUID = UUID()) -> ScratchpadDocument? {
        guard !pads.contains(where: { $0.id == id }) else { return nil }
        var next = self
        let name = ScratchpadSupport.nextPadName(defaultName: defaultName, existingNames: pads.map(\.name))
        next.pads.append(.init(id: id, name: name, text: "", modifiedAt: nil, usesAutomaticTitle: true))
        next.openIDs.append(id)
        next.selectedID = id
        return next
    }

    func selecting(_ id: UUID) -> ScratchpadDocument? {
        guard pads.contains(where: { $0.id == id && $0.deletedAt == nil }) else { return nil }
        var next = self
        if !next.openIDs.contains(id) { next.openIDs.append(id) }
        next.selectedID = id
        return next
    }

    func duplicating(_ sourceID: UUID, id: UUID = UUID(), now: Date) -> ScratchpadDocument? {
        guard let source = pads.first(where: { $0.id == sourceID && $0.deletedAt == nil }),
              !pads.contains(where: { $0.id == id }) else { return nil }
        var next = self
        let suffixLength = " \(pads.count + 2)".count
        let base = String(source.name.prefix(Self.maximumNameLength - suffixLength))
        let name = ScratchpadSupport.nextPadName(defaultName: base, existingNames: pads.map(\.name))
        next.pads.append(.init(id: id, name: name, text: source.text, modifiedAt: now, folderID: source.folderID))
        next.openIDs.append(id)
        next.selectedID = id
        return next
    }

    func renaming(_ id: UUID, to proposedName: String) -> ScratchpadDocument? {
        let name = ScratchpadSupport.sanitizedPadName(proposedName)
        guard !name.isEmpty, let index = pads.firstIndex(where: { $0.id == id }) else { return nil }
        var next = self
        next.pads[index].name = name
        next.pads[index].usesAutomaticTitle = false
        return next
    }

    func removing(_ id: UUID) -> ScratchpadDocument? {
        guard let index = openIDs.firstIndex(of: id) else { return nil }
        var next = self
        next.openIDs.remove(at: index)
        if selectedID == id, !next.openIDs.isEmpty {
            next.selectedID = next.openIDs[min(index, next.openIDs.count - 1)]
        }
        return next
    }

    mutating func updateSelectedText(_ text: String, modifiedAt: Date) {
        updateText(text, for: selectedID, modifiedAt: modifiedAt)
    }

    mutating func updateText(_ text: String, for id: UUID, modifiedAt: Date) {
        guard let index = pads.firstIndex(where: { $0.id == id && $0.deletedAt == nil }),
              pads[index].text != text else { return }
        pads[index].text = text
        pads[index].modifiedAt = modifiedAt
        if pads[index].usesAutomaticTitle, let title = ScratchpadMarkdown.suggestedTitle(in: text) {
            pads[index].name = title
        }
    }

    mutating func applyRetention(_ retention: ScratchpadRetention, now: Date) {
        for index in pads.indices where pads[index].isTemporary && pads[index].deletedAt == nil
            && ScratchpadSupport.shouldClear(lastEdited: pads[index].modifiedAt, now: now, retention: retention) {
            pads[index].deletedAt = now
        }
        self = sanitized(defaultName: "Scratchpad")
    }

    func notes(in collection: ScratchpadCollection, query: String = "") -> [ScratchpadPad] {
        pads.filter { pad in
            let included: Bool
            switch collection {
            case .all: included = pad.deletedAt == nil
            case .inbox: included = pad.deletedAt == nil && pad.folderID == nil
            case .pinned: included = pad.deletedAt == nil && pad.isPinned
            case .trash: included = pad.deletedAt != nil
            case .folder(let id): included = pad.deletedAt == nil && pad.folderID == id
            }
            return included && (query.isEmpty || pad.name.localizedStandardContains(query)
                                || pad.text.localizedStandardContains(query))
        }
    }

    mutating func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        for index in pads.indices where pads[index].folderID == id { pads[index].folderID = nil }
    }

    mutating func trash(_ id: UUID, now: Date, defaultName: String) {
        guard let index = pads.firstIndex(where: { $0.id == id }) else { return }
        pads[index].deletedAt = now
        self = sanitized(defaultName: defaultName)
    }

    mutating func restore(_ id: UUID) {
        guard let index = pads.firstIndex(where: { $0.id == id }) else { return }
        pads[index].deletedAt = nil
        pads[index].isTemporary = false
        if let next = selecting(id) { self = next }
    }

    mutating func reorderTab(_ id: UUID, before destination: UUID) {
        guard id != destination, openIDs.contains(id), openIDs.contains(destination) else { return }
        openIDs.removeAll { $0 == id }
        if let index = openIDs.firstIndex(of: destination) { openIDs.insert(id, at: index) }
    }
}
