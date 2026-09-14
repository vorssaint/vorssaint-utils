// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Production drag completion runs with isolated windows and preferences.
enum ShelfDragCompletionContract {
    final class Window {}
    typealias NSWindow = Window

    enum UserDefaults {
        static var standard = Store()
        struct Store {
            var closeAfterDrop = true
            var removeAfterDrop = true
            func bool(forKey key: String) -> Bool {
                key == DefaultsKey.shelfCloseAfterDrop ? closeAfterDrop
                    : key == DefaultsKey.shelfRemoveAfterDrop && removeAfterDrop
            }
        }
    }

    final class NotchService {
        static var shared = NotchService()
        var presentationWindow: Window? = Window()
        var expanded = true
        var selected: NotchModule = .files
        var showingAppPanel = false
        var showingSections = false
        var pinned = false
        var heldDrag = false
        var closures = 0
        func fileDragChanged(_ active: Bool, internalDrag: Bool) { heldDrag = active && internalDrag }
        func collapse() {
            precondition(!heldDrag, "release the drag before trying to collapse")
            closures += 1
            expanded = false
        }
    }

    static func reset() {
        UserDefaults.standard = UserDefaults.Store()
        NotchService.shared = NotchService()
    }
}

enum ShelfDragCompletionTests {
    private typealias Context = ShelfDragCompletionContract

    static func run(expect: (Bool, String) -> Void) {
        for pinned in [false, true] {
            for close in [false, true] {
                for accepted in [false, true] {
                    for merged in [false, true] {
                        Context.reset()
                        let service = Context.Service()
                        let notch = Context.NotchService.shared
                        notch.pinned = pinned
                        service.isPinned = !pinned
                        Context.UserDefaults.standard.closeAfterDrop = close
                        let id = UUID()
                        service.beginInternalDrag(ids: [id], from: notch.presentationWindow)
                        service.internalDragWasMerged = merged
                        expect(notch.heldDrag, "a drag from the notch holds its working surface")
                        service.completeInternalDrag(dropAccepted: accepted)
                        let transferred = accepted && !merged
                        expect(notch.closures == (transferred && close && !pinned ? 1 : 0),
                               "notch completion honors accepted drops, local merges, its pin and the close preference")
                        expect(service.removed == (transferred ? [id] : []) && !notch.heldDrag
                               && service.internalDragWindow == nil && service.activeInternalDragIDs.isEmpty,
                               "completion preserves removal policy and always releases the drag's source")
                        expect(service.floatingClosures == 0 && service.dockedClosures == 0,
                               "closing an embedded shelf leaves the separate presentations alone")
                    }
                }
            }
        }

        for docked in [false, true] {
            Context.reset()
            let service = Context.Service()
            let notch = Context.NotchService.shared
            let source = Context.Window()
            if docked { service.dockedPanel = source } else { service.panel = source }
            service.isVisible = !docked
            service.dockedVisible = docked
            notch.pinned = true
            Context.UserDefaults.standard.removeAfterDrop = false
            service.beginInternalDrag(ids: [UUID()], from: source)
            expect(!notch.heldDrag, "a separate shelf cannot hold an unrelated notch open")
            service.completeInternalDrag(dropAccepted: true)
            expect(service.floatingClosures == (docked ? 0 : 1) && service.dockedClosures == (docked ? 1 : 0)
                   && notch.closures == 0 && service.removed.isEmpty,
                   "separate shelf completion retains its own close, pin and removal behavior")
        }

        for changedSurface in 0..<5 {
            Context.reset()
            let service = Context.Service()
            let notch = Context.NotchService.shared
            let source = notch.presentationWindow!
            service.panel = Context.Window()
            service.isVisible = true
            service.beginInternalDrag(ids: [UUID()], from: source)
            switch changedSurface {
            case 0: notch.selected = .music
            case 1: notch.showingSections = true
            case 2: notch.showingAppPanel = true
            case 3: notch.expanded = false
            default: notch.presentationWindow = Context.Window(); notch.heldDrag = false
            }
            service.completeInternalDrag(dropAccepted: true)
            expect(notch.closures == 0 && service.floatingClosures == 0,
                   "an old drag cannot close a different destination or a replacement notch window")
        }
    }
}
