// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

/// A raw-string-backed, drag-reorderable item. The SwiftUI reordering views
/// built on this protocol live in `UI/MenuPanel/PanelLayout.swift`; kept
/// dependency-free here so `Core` types (`SelectionAction`) can conform
/// without pulling in SwiftUI. Every current conformer: `SelectionAction`,
/// each menu-panel section's own row-order `Block` (`PowerSection`,
/// `SystemSection`, `NetworkSection`, `DiskSection`), `UtilityPanelItem` and
/// `ControlPanelItem` (`MenuPanelView.swift`), and `QuickToggleAction`/
/// `QuickLauncherItem` (`Services/QuickTools/`).
protocol PanelOrderItem: RawRepresentable, CaseIterable, Hashable where RawValue == String {}
