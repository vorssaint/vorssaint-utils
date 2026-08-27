// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import AppKit

/// One action the Selection Actions bar can offer. Raw values are storage
/// ids for the list of actions the person switched off and the order they
/// dragged them into, so they never change. Declaration order is the
/// canonical/default order, used the first time (and whenever a future case
/// is appended) — see `PanelLayout.itemOrder`.
enum SelectionAction: String, CaseIterable, Identifiable, PanelOrderItem {
    case copy
    case cut
    case paste
    case delete

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .cut: return "scissors"
        case .paste: return "clipboard"
        case .delete: return "delete.left"
        }
    }

    /// Rewrites the selection in place (needs an editable focused element)
    /// rather than just reading it.
    var isTransform: Bool {
        switch self {
        case .cut, .paste, .delete:
            return true
        case .copy:
            return false
        }
    }

    /// Whether this row shows a settings gear beside its on/off switch. The
    /// switch always means on/off; the gear (when present) only ever holds
    /// the action's own configuration.
    var hasSettings: Bool {
        false
    }

    /// Whether this action makes sense for the given selection right now.
    /// Every transform needs an editable target; a few actions also need the
    /// text itself (or something else) to look a particular way. An empty
    /// selection (an editable field with nothing selected in it, offered so
    /// there's still a way to Paste without a keyboard) rules out everything
    /// except Paste itself.
    func appliesTo(text: String, isEditable: Bool) -> Bool {
        if isTransform, !isEditable { return false }
        if text.isEmpty, self != .paste { return false }
        switch self {
        case .paste:
            return NSPasteboard.general.string(forType: .string) != nil
        default: return true
        }
    }
}

/// Whether the bar shows each action as an icon or as a short word.
enum SelectionActionsDisplayStyle: String {
    case icon
    case word

    static func sanitized(_ raw: String?) -> SelectionActionsDisplayStyle {
        SelectionActionsDisplayStyle(rawValue: raw ?? "") ?? .icon
    }
}

enum SelectionActionCatalog {
    /// The everyday actions a fresh install starts with; everything else is
    /// one switch away in Settings rather than cluttering the bar by default.
    static let defaultEnabled: Set<SelectionAction> = [
        .copy, .cut, .paste,
    ]

    /// Persisted as the *enabled* set, not the disabled one: a future update
    /// that adds a new `SelectionAction` case must have that case come up
    /// off for anyone who already customized their toggles, not silently on
    /// because it's absent from an old "disabled" string written before the
    /// case existed.
    static func enabledActions(from raw: String) -> Set<SelectionAction> {
        Set(raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap(SelectionAction.init(rawValue:)))
    }

    /// Sorted so the same set always writes the same string.
    static func storageValue(for actions: Set<SelectionAction>) -> String {
        actions.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// The default value for `DefaultsKey.selectionActionsEnabledActions`.
    static var defaultEnabledStorageValue: String {
        storageValue(for: defaultEnabled)
    }

    static func isEnabled(_ action: SelectionAction, enabledRaw: String) -> Bool {
        enabledActions(from: enabledRaw).contains(action)
    }

    /// The actions to offer for a selection right now: enabled in Settings,
    /// applicable to this particular text/context, in the person's order.
    static func availableActions(for text: String,
                                 isEditable: Bool,
                                 enabledRaw: String,
                                 orderRaw: String) -> [SelectionAction] {
        let order = Defaults.sanitizedPanelItemOrder(orderRaw,
                                                      defaultOrder: SelectionAction.allCases.map(\.rawValue))
            .compactMap(SelectionAction.init(rawValue:))
        return order.filter {
            isEnabled($0, enabledRaw: enabledRaw) && $0.appliesTo(text: text, isEditable: isEditable)
        }
    }
}
