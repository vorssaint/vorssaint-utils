// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

protocol BreakDelivery: AnyObject {
    /// False when the surface cannot show it now; the coordinator moves down the chain.
    func present(_ prompt: BreakPrompt, respond: @escaping (BreakAction) -> Void) -> Bool
    func dismiss(id: UUID)
}
