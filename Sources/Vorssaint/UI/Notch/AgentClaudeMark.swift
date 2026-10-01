// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Claude's spark, drawn from its published vector so it stays sharp at any
/// size and shows on a Mac without the Claude app. The path is the one
/// Simple Icons carries for Claude (CC0), on a 24-point canvas.
enum AgentClaudeMark {
    static let canvas: CGFloat = 24

    static let data = """
    m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z
    """

    /// A template, so it takes the agent's color. The spark fills the middle
    /// two thirds of its box, as in the menu bar image Claude's app ships,
    /// so the sizes tuned for that image still hold.
    static let image: NSImage? = {
        guard let path = path(data) else { return nil }
        let inset = canvas / 6
        let scale = (canvas - 2 * inset) / canvas
        path.transform(using: AffineTransform(m11: scale, m12: 0, m21: 0, m22: scale, tX: inset, tY: inset))
        let image = NSImage(size: CGSize(width: canvas, height: canvas), flipped: true) { _ in
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    /// Reads SVG path data in y-down coordinates: moves, lines, horizontal
    /// and vertical lines, cubic curves and closes, absolute or relative.
    /// Anything else, or a malformed number, reads as nothing.
    static func path(_ data: String) -> NSBezierPath? {
        var scanner = PathScanner(bytes: Array(data.utf8))
        let path = NSBezierPath()
        var command: UInt8?
        var current = CGPoint.zero
        var start = CGPoint.zero
        while true {
            if let letter = scanner.letter() {
                command = letter
            } else if scanner.isAtEnd() {
                break
            }
            // Numbers without a letter repeat the last command, but a close takes none.
            guard let letter = command else { return nil }
            let relative = letter >= UInt8(ascii: "a")
            let origin = relative ? current : .zero
            switch letter | 0x20 {
            case UInt8(ascii: "m"):
                guard let point = scanner.point() else { return nil }
                current = point.offset(by: origin)
                start = current
                path.move(to: current)
                // Pairs after a move are lines.
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
            case UInt8(ascii: "l"):
                guard let point = scanner.point() else { return nil }
                current = point.offset(by: origin)
                path.line(to: current)
            case UInt8(ascii: "h"):
                guard let x = scanner.number() else { return nil }
                current.x = x + origin.x
                path.line(to: current)
            case UInt8(ascii: "v"):
                guard let y = scanner.number() else { return nil }
                current.y = y + origin.y
                path.line(to: current)
            case UInt8(ascii: "c"):
                guard let first = scanner.point(), let second = scanner.point(), let end = scanner.point() else { return nil }
                current = end.offset(by: origin)
                path.curve(to: current, controlPoint1: first.offset(by: origin), controlPoint2: second.offset(by: origin))
            case UInt8(ascii: "z"):
                path.close()
                current = start
                command = nil
            default:
                return nil
            }
        }
        return path.isEmpty ? nil : path
    }
}

private struct PathScanner {
    let bytes: [UInt8]
    var index = 0

    mutating func isAtEnd() -> Bool {
        skipSeparators()
        return index >= bytes.count
    }

    mutating func letter() -> UInt8? {
        skipSeparators()
        guard index < bytes.count, Self.isLetter(bytes[index]) else { return nil }
        defer { index += 1 }
        return bytes[index]
    }

    /// A sign or a second point starts the next number, as in `.079-.2307`.
    mutating func number() -> CGFloat? {
        skipSeparators()
        let begin = index
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") || bytes[index] == UInt8(ascii: "+") { index += 1 }
        var digits = false
        var point = false
        while index < bytes.count {
            let byte = bytes[index]
            if (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
                digits = true
            } else if byte == UInt8(ascii: "."), !point {
                point = true
            } else {
                break
            }
            index += 1
        }
        guard digits, let value = Double(String(decoding: bytes[begin..<index], as: UTF8.self)) else {
            index = begin
            return nil
        }
        return CGFloat(value)
    }

    mutating func point() -> CGPoint? {
        guard let x = number(), let y = number() else { return nil }
        return CGPoint(x: x, y: y)
    }

    private mutating func skipSeparators() {
        while index < bytes.count, [UInt8(ascii: " "), UInt8(ascii: ","), UInt8(ascii: "\n"), UInt8(ascii: "\t")].contains(bytes[index]) {
            index += 1
        }
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }
}

private extension CGPoint {
    func offset(by origin: CGPoint) -> CGPoint { CGPoint(x: x + origin.x, y: y + origin.y) }
}
