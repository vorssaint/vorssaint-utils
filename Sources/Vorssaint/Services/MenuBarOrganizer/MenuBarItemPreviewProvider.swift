// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Captures only the inventoried status-item windows, on demand. Pixels never
/// leave memory, and opening the organizer never prompts for screen access.
@MainActor
final class MenuBarItemPreviewProvider: ObservableObject {
    @Published private(set) var images: [CGWindowID: NSImage] = [:]
    private var owners: [CGWindowID: pid_t] = [:]
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    private let permitted: () -> Bool
    private let validate: (ManagedMenuBarItem) -> Bool
    private let capture: (CGWindowID) async -> CGImage?

    init(permitted: @escaping () -> Bool,
         validate: @escaping (ManagedMenuBarItem) -> Bool,
         capture: @escaping (CGWindowID) async -> CGImage?) {
        self.permitted = permitted
        self.validate = validate
        self.capture = capture
    }

    func refresh(_ items: [ManagedMenuBarItem]) {
        guard permitted() else {
            stop()
            return
        }
        let targets = Array(items.prefix(128))
        let liveOwners = Dictionary(targets.map { ($0.windowID, $0.ownerPID) }, uniquingKeysWith: { first, _ in first })
        images = images.filter { owners[$0.key] == liveOwners[$0.key] && liveOwners[$0.key] != nil }
        owners = liveOwners
        guard task == nil else { return }
        let expected = generation
        task = Task { [weak self] in
            guard let self else { return }
            defer { if generation == expected { task = nil } }
            for item in targets {
                guard !Task.isCancelled, generation == expected else { return }
                guard permitted() else { stop(); return }
                guard owners[item.windowID] == item.ownerPID else { continue }
                guard validate(item) else { images[item.windowID] = nil; continue }
                guard let image = await capture(item.windowID) else { continue }
                guard !Task.isCancelled, generation == expected else { return }
                guard permitted() else { stop(); return }
                guard owners[item.windowID] == item.ownerPID, validate(item) else {
                    images[item.windowID] = nil
                    continue
                }
                guard
                      image.width > 0, image.height > 0, image.width <= 4_096, image.height <= 256,
                      let thumbnail = Self.thumbnail(image) else { continue }
                images[item.windowID] = NSImage(cgImage: thumbnail, size: item.frame.size)
            }
        }
    }

    private static func thumbnail(_ image: CGImage) -> CGImage? {
        let scale = min(1, 280.0 / Double(image.width), 64.0 / Double(image.height))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    func stop() {
        generation &+= 1
        task?.cancel()
        task = nil
        images = [:]
        owners = [:]
    }
}
