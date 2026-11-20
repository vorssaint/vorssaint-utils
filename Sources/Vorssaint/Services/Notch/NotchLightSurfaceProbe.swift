// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation
import SwiftUI

/// Observes system interface appearance so island lights adapt saturation and
/// contrast over a light menu bar without requesting Screen Recording permission.
final class NotchLightSurfaceProbe: ObservableObject {
    @Published private(set) var isLightSurface = false

    private var themeObserver: NSObjectProtocol?
    private var appAppearanceObserver: NSKeyValueObservation?

    init() {
        refresh()
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        appAppearanceObserver = NSApp?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    deinit {
        if let themeObserver {
            DistributedNotificationCenter.default().removeObserver(themeObserver)
        }
        appAppearanceObserver?.invalidate()
    }

    func refresh() {
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        isLightSurface = match == .aqua
    }
}

/// Applies Neon (high-chroma contrast punch) or Velours (rich chroma with soft
/// shadow grounding) when the halo sits on a light menu bar surface.
struct NotchLightSurfaceFinish: ViewModifier {
    let isLightSurface: Bool
    let surfaceStyle: NotchLightSurfaceStyle

    func body(content: Content) -> some View {
        if !isLightSurface {
            content
        } else {
            switch surfaceStyle {
            case .neon:
                content
                    .saturation(1.04)
                    .contrast(1.08)
            case .velours:
                content
                    .saturation(1.12)
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 4)
            }
        }
    }
}
