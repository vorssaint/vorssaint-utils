// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import AppKit

enum VideoThumbnailer {
    /// A real decoded frame from a video file, sized and scaled the same way
    /// ImageThumbnailer sizes image frames. Grabs a frame slightly into the
    /// video rather than at time zero: an arbitrary user video's raw first
    /// frame is often black or a title card, unlike this app's own screen
    /// recordings (see RecentCaptureService, which uses .zero because it
    /// controls what's at the start of the file).
    static func thumbnail(for url: URL, pointSize: CGFloat = ImageThumbnailer.defaultPointSize) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration),
              duration.isValid, duration.seconds > 0 else {
            return await frame(from: asset, at: .zero, pointSize: pointSize)
        }
        let offsetSeconds = min(1.0, duration.seconds * 0.1)
        let time = CMTime(seconds: offsetSeconds, preferredTimescale: 600)
        return await frame(from: asset, at: time, pointSize: pointSize)
    }

    private static func frame(from asset: AVURLAsset, at time: CMTime, pointSize: CGFloat) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // NSScreen is AppKit UI API and must only be read on the main thread;
        // this function runs off the main actor when awaited from a
        // nonisolated context, so the read is hopped back explicitly rather
        // than done inline here.
        let scale = await MainActor.run { ImageThumbnailer.backingScale }
        let maxPixels = pointSize * scale
        generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
        // Both default to infinite, which lets the generator snap to the
        // nearest keyframe instead of `time`, often back to frame zero for a
        // typical keyframe interval; zero tolerance is what makes the offset
        // above actually avoid a black or title-card first frame.
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let cgImage = try? await generator.image(at: time).image else { return nil }
        let size = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        return NSImage(cgImage: cgImage, size: size)
    }
}
