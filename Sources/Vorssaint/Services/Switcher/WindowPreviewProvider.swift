// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Captures window thumbnails for the switcher with ScreenCaptureKit.
///
/// Thumbnails live only in this in-memory cache: stale images make cards
/// appear instantly on the next invocation while fresh captures stream in.
/// Without Screen Recording permission the provider stays silent and the
/// switcher falls back to app icons.
final class WindowPreviewProvider {
    static let shared = WindowPreviewProvider()

    /// Longest thumbnail edge, in pixels (2x for Retina sharpness).
    private static let defaultMaxPixelSize: CGFloat = 640

    private var cache: [CGWindowID: CGImage] = [:]
    private var captureTask: Task<Void, Never>?

    init() {}

    func cachedPreview(for windowID: CGWindowID) -> CGImage? {
        cache[windowID]
    }

    /// Refreshes thumbnails for the previewable `items`, invoking `onUpdate`
    /// on the main thread as each capture lands. Earlier entries are captured
    /// first, so pass items in display order. Tab entries share their host
    /// window's capture, so each backing window is captured once.
    func refreshPreviews(for items: [SwitcherItem],
                         maxPixelSize: CGFloat = defaultMaxPixelSize,
                         onUpdate: @escaping (CGWindowID, CGImage) -> Void) {
        guard Permissions.shared.screenRecording else { return }

        var seen = Set<CGWindowID>()
        let targets: [PreviewTarget] = items.compactMap { item in
            guard let id = item.previewWindowID, !seen.contains(id) else { return nil }
            seen.insert(id)
            return PreviewTarget(id: id,
                                 pid: item.pid,
                                 title: item.title,
                                 appName: item.appName,
                                 frame: item.frame)
        }

        captureTask?.cancel()
        cache = cache.filter { seen.contains($0.key) }

        captureTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false,
                                                                                      onScreenWindowsOnly: false)
            else { return }
            let scWindows = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID, $0) })

            for target in targets {
                guard !Task.isCancelled else { return }
                guard let scWindow = scWindows[target.id]
                    ?? Self.bestWindowMatch(for: target, in: content.windows) else { continue }

                let configuration = SCStreamConfiguration()
                let scale = min(1, maxPixelSize / max(target.frame.width, target.frame.height, 1))
                configuration.width = max(1, Int(target.frame.width * scale))
                configuration.height = max(1, Int(target.frame.height * scale))
                configuration.showsCursor = false

                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                              configuration: configuration)
                else { continue }
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.cache[target.id] = image
                    onUpdate(target.id, image)
                }
            }
        }
    }

    func cancel() {
        captureTask?.cancel()
        captureTask = nil
    }

    private struct PreviewTarget {
        let id: CGWindowID
        let pid: pid_t
        let title: String
        let appName: String
        let frame: CGRect
    }

    private static func bestWindowMatch(for target: PreviewTarget, in windows: [SCWindow]) -> SCWindow? {
        let candidates = windows.filter { window in
            window.owningApplication?.processID == target.pid
        }
        guard !candidates.isEmpty else { return nil }

        if let titled = candidates.first(where: { titlesMatch($0.title, target.title) }) {
            return titled
        }

        let frameMatches = candidates
            .map { window in (window: window, score: frameDistance(window.frame, target.frame)) }
            .filter { $0.score < 80 }
            .sorted { $0.score < $1.score }

        if let closest = frameMatches.first?.window {
            return closest
        }

        if candidates.count == 1 {
            return candidates[0]
        }
        return nil
    }

    private static func titlesMatch(_ lhs: String?, _ rhs: String) -> Bool {
        let left = (lhs ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right
    }

    private static func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.midX - rhs.midX)
            + abs(lhs.midY - rhs.midY)
            + abs(lhs.width - rhs.width)
            + abs(lhs.height - rhs.height)
    }
}
