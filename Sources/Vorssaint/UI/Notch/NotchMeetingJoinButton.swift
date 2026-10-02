// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A call service's logo from Resources/Images, or a video mark for one
/// without a logo there.
struct NotchMeetingLogo: View {
    let platform: NotchMeetingPlatform
    var side: CGFloat = 13

    private static var cache: [String: NSImage] = [:]

    private static func image(_ name: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Images"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }

    var body: some View {
        Group {
            if let name = platform.logo, let image = Self.image(name) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "video.fill").resizable().aspectRatio(contentMode: .fit)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// Join, which opens the call at once, with its service's logo, and a menu
/// beside it for the event, the link and the browser.
struct NotchMeetingJoinButton: View {
    let meeting: NotchMeetingLink
    let text: NotchCalendarStrings
    /// Shows the event in Calendar.
    let viewEvent: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: join) {
                HStack(spacing: 5) {
                    NotchMeetingLogo(platform: meeting.platform)
                    Text(text.join).font(.system(size: 11, weight: .semibold))
                }
                .padding(.leading, 7).padding(.trailing, 6)
                .frame(height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(text.join) · \(meeting.platform.name)")
            .accessibilityLabel("\(text.join) · \(meeting.platform.name)")
            Rectangle().fill(.white.opacity(0.25)).frame(width: 0.5, height: 14)
                .accessibilityHidden(true)
            Menu {
                Button(text.openCalendar, action: viewEvent)
                Button(text.copyLink) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(meeting.url.absoluteString, forType: .string)
                }
                Button(text.openInBrowser) { open(meeting.url) }
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 5)
            .frame(height: 22)
        }
        .foregroundStyle(.white)
        // Neutral, so every service's logo, colored or white, stays legible.
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .fixedSize()
    }

    /// The service's app when it handles its own link, the link otherwise.
    /// The island folds, since the call is what comes next.
    private func join() {
        if let native = meeting.nativeURL, NSWorkspace.shared.urlForApplication(toOpen: native) != nil {
            open(native)
        } else {
            open(meeting.url)
        }
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        NotchService.shared.collapse()
    }
}
