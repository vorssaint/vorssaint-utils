// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum ScreenshotCanvasSupport {
    enum Fill: Equatable {
        case transparent
        case color(red: Double, green: Double, blue: Double)
        static let white = Fill.color(red: 1, green: 1, blue: 1)
        var cgColor: CGColor {
            switch self {
            case .transparent: return CGColor(gray: 0, alpha: 0)
            case let .color(red, green, blue):
                return CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
            }
        }
    }

    static func validSize(_ size: CGSize) -> Bool {
        let limit = CGFloat(ScreenshotSupport.scrollingCaptureMaximumPixels)
        return size.width.isFinite && size.height.isFinite
            && size.width >= 1 && size.height >= 1
            && size.width == size.width.rounded() && size.height == size.height.rounded()
            && size.width <= limit && size.height <= limit
            && size.width <= limit / size.height
    }

    static func expandedRect(size: CGSize, handle: ScreenshotSupport.Handle,
                             point: CGPoint) -> CGRect? {
        guard validSize(size), point.x.isFinite, point.y.isFinite else { return nil }
        var x: CGFloat = 0, y: CGFloat = 0
        var right = size.width, bottom = size.height
        switch handle {
        case .topLeft: x = min(0, point.x.rounded()); y = min(0, point.y.rounded())
        case .top: y = min(0, point.y.rounded())
        case .topRight: right = max(right, point.x.rounded()); y = min(0, point.y.rounded())
        case .right: right = max(right, point.x.rounded())
        case .bottomRight: right = max(right, point.x.rounded()); bottom = max(bottom, point.y.rounded())
        case .bottom: bottom = max(bottom, point.y.rounded())
        case .bottomLeft: x = min(0, point.x.rounded()); bottom = max(bottom, point.y.rounded())
        case .left: x = min(0, point.x.rounded())
        }
        let rect = CGRect(x: x, y: y, width: right - x, height: bottom - y)
        return validSize(rect.size) ? rect : nil
    }

    static func expandedImage(_ image: CGImage, to rect: CGRect, fill: Fill) -> CGImage? {
        let old = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard validSize(rect.size), rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.minX == rect.minX.rounded(), rect.minY == rect.minY.rounded(),
              rect.contains(old),
              let context = CGContext(data: nil, width: Int(rect.width), height: Int(rect.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(fill.cgColor)
        context.fill(CGRect(origin: .zero, size: rect.size))
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        let destination = CGRect(x: -rect.minX, y: rect.height + rect.minY - old.height,
                                 width: old.width, height: old.height)
        context.draw(image, in: destination)
        return context.makeImage()
    }
    /// Centered on whole pixels: a layer drawn off the pixel grid is
    /// resampled, and a pasted screenshot's text would export blurred.
    static func fittedImageRect(_ image: CGImage, canvas: CGSize) -> CGRect {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let factor = min(1, min(canvas.width / width, canvas.height / height))
        let size = CGSize(width: width * factor, height: height * factor)
        return CGRect(x: ((canvas.width - size.width) / 2).rounded(.down),
                      y: ((canvas.height - size.height) / 2).rounded(.down),
                      width: size.width, height: size.height)
    }
    static let imageHandles = ScreenshotSupport.Handle.allCases

    /// How close to an expansion grip, in points on screen, a press picks it
    /// up. The grips sit centered on the capture's edge, so the editor takes
    /// presses this far outside the canvas too.
    static let expansionGripReach: CGFloat = 10

    static func expansionHandle(at point: CGPoint, rect: CGRect,
                                tolerance: CGFloat) -> ScreenshotSupport.Handle? {
        let radius = min(tolerance, max(2, min(rect.width, rect.height) / 4))
        return ScreenshotSupport.Handle.allCases.filter {
            let position = $0.position(in: rect)
            return abs(position.x - point.x) <= radius && abs(position.y - point.y) <= radius
        }.min {
            let a = $0.position(in: rect), b = $1.position(in: rect)
            return hypot(a.x - point.x, a.y - point.y) < hypot(b.x - point.x, b.y - point.y)
        }
    }

    static func resizedImageRect(_ rect: CGRect, handle: ScreenshotSupport.Handle,
                                 point: CGPoint) -> CGRect {
        guard rect.width > 0, rect.height > 0 else { return rect }
        switch handle {
        case .left:
            return CGRect(x: min(point.x, rect.maxX - 1), y: rect.minY,
                          width: max(1, rect.maxX - point.x), height: rect.height)
        case .right:
            return CGRect(x: rect.minX, y: rect.minY,
                          width: max(1, point.x - rect.minX), height: rect.height)
        case .top:
            return CGRect(x: rect.minX, y: min(point.y, rect.maxY - 1),
                          width: rect.width, height: max(1, rect.maxY - point.y))
        case .bottom:
            return CGRect(x: rect.minX, y: rect.minY,
                          width: rect.width, height: max(1, point.y - rect.minY))
        default:
            break
        }
        let left = handle == .topLeft || handle == .bottomLeft
        let top = handle == .topLeft || handle == .topRight
        let anchor = CGPoint(x: left ? rect.maxX : rect.minX, y: top ? rect.maxY : rect.minY)
        let dx = (left ? -1 : 1) * (point.x - anchor.x)
        let dy = (top ? -1 : 1) * (point.y - anchor.y)
        let ratio = rect.width / rect.height
        let width = max(1, max(dx, dy * ratio))
        let height = width / ratio
        return CGRect(x: left ? anchor.x - width : anchor.x,
                      y: top ? anchor.y - height : anchor.y, width: width, height: height)
    }

    static func imageHandle(at point: CGPoint, rect: CGRect,
                            tolerance: CGFloat) -> ScreenshotSupport.Handle? {
        let radius = min(tolerance, max(2, min(rect.width, rect.height) / 4))
        return imageHandles.filter {
            let position = $0.position(in: rect)
            return abs(position.x - point.x) <= radius && abs(position.y - point.y) <= radius
        }.min {
            let a = $0.position(in: rect), b = $1.position(in: rect)
            return hypot(a.x - point.x, a.y - point.y) < hypot(b.x - point.x, b.y - point.y)
        }
    }
}
