// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

/// A raw-string-backed, drag-reorderable item — conformed to by both the menu
/// panel's own sections (`PanelSectionID`, in `UI/MenuPanel/PanelLayout.swift`,
/// which also has the SwiftUI reordering views built on this protocol) and
/// other independently reorderable lists (`SelectionAction`). Kept dependency-
/// free here rather than in that UI file so Core types can conform to it
/// without pulling in SwiftUI.
protocol PanelOrderItem: RawRepresentable, CaseIterable, Hashable where RawValue == String {}
