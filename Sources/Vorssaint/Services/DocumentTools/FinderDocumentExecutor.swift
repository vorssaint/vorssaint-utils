// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum FinderDocumentExecutor {
    static func execute(_ operation: FinderToolsOperation,
                        cancellation: FinderToolsCancellation) throws -> FinderToolsResult {
        let inputs = operation.selection
        guard let first = inputs.first else { throw FinderFileActionError.invalidRequest("Select a document.") }
        if operation.action == .readQR {
            var result = FinderToolsResult()
            var payloads: [String] = []
            for input in inputs {
                try cancellation.check()
                do {
                    let image = try FinderImageTools.load(input)
                    if let reading = BarcodeDetector.read(image) { payloads.append(reading.payload) }
                    else { throw FinderFileActionError.unsupported(input, "No QR code was found") }
                } catch { result.failures.append(.init(url: input, reason: error.localizedDescription)) }
            }
            result.text = payloads.isEmpty ? nil : payloads.joined(separator: "\n")
            return result
        }
        guard let destination = operation.destination else {
            throw FinderFileActionError.invalidRequest("Choose a destination folder.")
        }
        switch operation.action {
        case .diskImage, .encryptedDiskImage:
            try requireCount(inputs, count: 1)
            if operation.action == .encryptedDiskImage, operation.password?.isEmpty != false {
                throw FinderFileActionError.invalidRequest("Enter a password for the encrypted image.")
            }
            let name = operation.name.lowercased().hasSuffix(".dmg") ? operation.name : operation.name + ".dmg"
            let output = try FinderDiskImageOperation.create(from: first, to: destination.appendingPathComponent(name),
                password: operation.action == .encryptedDiskImage ? operation.password : nil, cancellation: cancellation)
            return FinderToolsResult(outputs: [output])
        case .extractAudio:
            try requireCount(inputs, count: 1)
            let name = operation.name.lowercased().hasSuffix(".m4a") ? operation.name : operation.name + ".m4a"
            return FinderToolsResult(outputs: [try FinderAudioTools.extract(from: first,
                to: destination.appendingPathComponent(name), cancellation: cancellation)])
        case .compressPresentation:
            try requireCount(inputs, count: 1)
            let name = operation.name.lowercased().hasSuffix(".pptx") ? operation.name : operation.name + ".pptx"
            return FinderToolsResult(outputs: [try FinderPresentationTools.compress(first,
                to: destination.appendingPathComponent(name), cancellation: cancellation)])
        case .compressPDF:
            try requireCount(inputs, count: 1)
            return FinderToolsResult(outputs: [try FinderPDFTools.compress(first, in: destination,
                named: operation.name, cancellation: cancellation)])
        case .mergePDF:
            return FinderToolsResult(outputs: [try FinderPDFTools.merge(inputs, in: destination,
                named: operation.name, cancellation: cancellation)])
        case .splitPDF:
            try requireCount(inputs, count: 1)
            return FinderToolsResult(outputs: try FinderPDFTools.split(first, in: destination,
                named: operation.name, cancellation: cancellation))
        case .watermarkPDF:
            try requireCount(inputs, count: 1)
            return FinderToolsResult(outputs: [try FinderPDFTools.watermark(first, text: operation.watermark,
                in: destination, named: operation.name, cancellation: cancellation)])
        case .stitchHorizontal, .stitchVertical:
            guard inputs.count <= 32 else { throw FinderFileActionError.invalidRequest("Select at most 32 images.") }
            var images: [CGImage] = []
            var pixelCount = 0
            for input in inputs {
                try cancellation.check()
                let image = try FinderImageTools.load(input)
                pixelCount += image.width * image.height
                guard pixelCount <= FinderImageTools.maximumPixels else {
                    throw FinderFileActionError.invalidRequest("The combined images exceed 64 megapixels.")
                }
                images.append(image)
            }
            let output = try FinderImageTools.stitch(images, horizontal: operation.action == .stitchHorizontal,
                                                    cancellation: cancellation)
            return FinderToolsResult(outputs: [try FinderImageTools.savePNG(output, in: destination,
                named: operation.name, cancellation: cancellation)])
        case .rotateLeft, .rotateRight, .removeBackground, .replaceBackground, .recolor:
            try requireCount(inputs, count: operation.action == .replaceBackground ? 2 : 1)
            let image = try FinderImageTools.load(first)
            let output: CGImage
            switch operation.action {
            case .rotateLeft, .rotateRight:
                output = try FinderImageTools.rotate(image, clockwise: operation.action == .rotateRight)
            case .recolor:
                output = try FinderImageTools.recolor(image, red: operation.red, green: operation.green, blue: operation.blue)
            default:
                let background = inputs.count == 2 ? try FinderImageTools.load(inputs[1]) : nil
                output = try FinderImageTools.removeBackground(image, replacement: background, cancellation: cancellation)
            }
            return FinderToolsResult(outputs: [try FinderImageTools.savePNG(output, in: destination,
                named: operation.name, cancellation: cancellation)])
        default:
            throw FinderFileActionError.invalidRequest("Choose a supported document operation.")
        }
    }

    private static func requireCount(_ inputs: [URL], count: Int) throws {
        guard inputs.count == count else {
            throw FinderFileActionError.invalidRequest("This action requires exactly \(count) selected item(s).")
        }
    }
}
