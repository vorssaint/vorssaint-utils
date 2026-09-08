// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct StatusItemContextMenuOrderDropDelegate: DropDelegate {
    let target: StatusItemContextMenuItemID
    @Binding var order: [StatusItemContextMenuItemID]
    @Binding var dragging: StatusItemContextMenuItemID?

    func dropEntered(info: DropInfo) {
        guard let dragging,
              dragging != target,
              let from = order.firstIndex(of: dragging),
              let to = order.firstIndex(of: target) else { return }

        withAnimation(.easeInOut(duration: 0.12)) {
            order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        StatusItemContextMenuLayout.setOrder(order)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        StatusItemContextMenuLayout.setOrder(order)
        return true
    }
}
