// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// What the island shows closed, drawn for another display. It takes no
/// clicks itself: a click on its window brings the island there, open.
struct NotchMirrorView: View {
    @ObservedObject var service: NotchService
    @ObservedObject var mirror: NotchMirrorModel

    var body: some View {
        content
            .frame(width: mirror.size.width, height: mirror.size.height, alignment: .top)
            .foregroundStyle(.white)
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
            .environment(\.notchPresentation, true)
            .tint(.white)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var content: some View {
        let geometry = mirror.geometry
        let size = mirror.size
        if let activity = mirror.activity {
            if geometry.floats {
                switch activity {
                case .timer: NotchCapsuleTimerStrip(service: service, size: size, displayGeometry: geometry)
                case .downloads: NotchCapsuleDownloadStrip(service: service, size: size, displayGeometry: geometry)
                case .cursor: NotchCapsuleCursorStrip(service: service, size: size, displayGeometry: geometry)
                case .agents: NotchCapsuleAgentStrip(service: service, size: size, displayGeometry: geometry)
                case .calendar: NotchCapsuleCalendarStrip(service: service, size: size, displayGeometry: geometry)
                case .music: NotchCapsuleMusicStrip(service: service, size: size, displayGeometry: geometry)
                case .keepAwake: NotchCapsuleKeepAwakeStrip(service: service, size: size, displayGeometry: geometry)
                }
            } else {
                switch activity {
                case .timer: NotchTimerStrip(service: service, displayGeometry: mirror.strip)
                case .downloads: NotchDownloadStrip(service: service, displayGeometry: mirror.strip)
                case .cursor: NotchCursorStrip(service: service, displayGeometry: mirror.strip)
                case .agents: NotchAgentStrip(service: service, displayGeometry: mirror.strip)
                case .calendar: NotchCalendarStrip(service: service, displayGeometry: mirror.strip)
                case .music: NotchMusicStrip(service: service, displayGeometry: mirror.strip)
                case .keepAwake: NotchKeepAwakeStrip(service: service, displayGeometry: mirror.strip)
                }
            }
        } else if geometry.floats {
            NotchCapsuleRestingView(service: service, size: size, displayGeometry: geometry)
        } else {
            NotchRestingStrip(service: service, displayGeometry: geometry)
        }
    }
}
