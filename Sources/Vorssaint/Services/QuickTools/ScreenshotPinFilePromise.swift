// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import UniformTypeIdentifiers

/// The provider owns its immutable capture, and its delegate outlives all pins.
/// Closing a pin after dropping cannot invalidate a deferred export request.
enum ScreenshotPinFilePromise {
    static func make(image: CGImage, scale: CGFloat, fileName: String) -> NSFilePromiseProvider {
        let provider = NSFilePromiseProvider(fileType: UTType.png.identifier, delegate: Writer.shared)
        provider.userInfo = Capture(image: image, scale: scale, fileName: fileName)
        return provider
    }

    private struct Capture {
        let image: CGImage
        let scale: CGFloat
        let fileName: String
    }

    private final class Writer: NSObject, NSFilePromiseProviderDelegate {
        static let shared = Writer()
        private let queue: OperationQueue = {
            let queue = OperationQueue()
            queue.qualityOfService = .utility
            queue.maxConcurrentOperationCount = 2
            return queue
        }()

        func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { queue }

        func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
            (provider.userInfo as? Capture)?.fileName ?? "Screenshot.png"
        }

        func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                                 completionHandler: @escaping (Error?) -> Void) {
            do {
                guard let capture = provider.userInfo as? Capture,
                      let data = ScreenshotRenderer.pngData(from: capture.image, scale: capture.scale) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try data.write(to: url, options: .withoutOverwriting)
                completionHandler(nil)
            } catch { completionHandler(error) }
        }
    }
}
