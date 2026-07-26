// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Vision

/// Offline 2D code detection shared by the screen text tool and the
/// screenshot preview. Restricted to matrix symbologies (QR and its
/// relatives): 1D barcodes false fire on any striped area of a normal
/// screen, and the useful case here is scanning a QR shown on screen.
enum BarcodeDetector {
    /// Matrix codes only. Kept as a fast, lightweight pass that runs before
    /// the heavier text recognition.
    static let symbologies: [VNBarcodeSymbology] = [.qr, .microQR, .aztec, .dataMatrix, .pdf417]

    static func decode(_ image: CGImage) -> [QuickToolsSupport.DecodedBarcode] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = symbologies
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
            let box = observation.boundingBox
            return QuickToolsSupport.DecodedBarcode(payload: payload,
                                                    x: Double(box.minX),
                                                    y: Double(box.midY))
        }
    }

    /// A finished read of an image: the joined payload, and an openable link
    /// only when a single code carries a plain web address. Nil when nothing
    /// was found. Shared by the screenshot preview and the annotation editor.
    struct Reading: Equatable {
        let payload: String
        let url: URL?
    }

    static func read(_ image: CGImage) -> Reading? {
        let codes = decode(image)
        let payload = QuickToolsSupport.joinedBarcodePayloads(codes)
        guard !payload.isEmpty else { return nil }
        let url = codes.count == 1 ? QuickToolsSupport.openableURL(from: payload) : nil
        return Reading(payload: payload, url: url)
    }
}
