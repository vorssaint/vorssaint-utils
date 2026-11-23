// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The island's song wallpaper page, opened like Lyrics or Up next: the song
/// wallpaper, the lyrics on the desktop, the ways to show them, and the few
/// switches that go with them.
struct NotchLyricsStylesView: View {
    @AppStorage(DefaultsKey.lyricsWallpaperStyle) private var style = "constellation"
    @AppStorage(DefaultsKey.lyricsWallpaperEnabled) private var enabled = true
    @AppStorage(DefaultsKey.lyricsLockScreenEnabled) private var lockScreen = true
    @AppStorage(DefaultsKey.lyricsKeepAwake) private var keepAwake = true
    @ObservedObject private var service = LyricsWallpaperService.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Song wallpaper").font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(get: { enabled }, set: { LyricsWallpaperService.shared.setEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                // Lyrics on the desktop: over the song wallpaper, or over the normal one when that is off.
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Show lyrics").font(.system(size: 13, weight: .semibold))
                        Text(enabled ? "Over the song wallpaper" : "Over your normal wallpaper")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(get: { lyricsShown }, set: { LyricsWallpaperService.shared.setShowLyrics($0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(LyricsMode.allCases) { mode in tile(mode) }
                }
                .opacity(lyricsShown ? 1 : 0.4).allowsHitTesting(lyricsShown)
                HStack(spacing: 12) {
                    Toggle("Lock screen", isOn: $lockScreen)
                    Toggle("Keep awake", isOn: Binding(get: { keepAwake }, set: {
                        keepAwake = $0
                        LyricsWallpaperService.shared.refreshAwake()
                    }))
                    Spacer(minLength: 0)
                    Button { service.adjustOffset(by: -0.25) } label: { Image(systemName: "minus").frame(width: 22, height: 18) }
                    Text(service.offset, format: .number.sign(strategy: .always()).precision(.fractionLength(2)))
                        .monospacedDigit().frame(minWidth: 40)
                    Button { service.adjustOffset(by: 0.25) } label: { Image(systemName: "plus").frame(width: 22, height: 18) }
                }
                .toggleStyle(.switch).controlSize(.small).font(.caption).buttonStyle(.borderless)
            }
            .foregroundStyle(.white)
        }
        .notchScrollEdgeFade()
    }

    /// Read from the switch itself, which also follows the song wallpaper until it is first set.
    private var lyricsShown: Bool {
        _ = service.showLyrics
        return NotchLyricsSupport.showsLyricsOnDesktop()
    }

    private func tile(_ mode: LyricsMode) -> some View {
        let selected = LyricsMode.from(style) == mode
        return Button { style = mode.rawValue } label: {
            VStack(spacing: 5) {
                Image(systemName: mode.symbol).font(.system(size: 16, weight: .semibold))
                Text(mode.title).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(selected ? 0.26 : 0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
    }
}
