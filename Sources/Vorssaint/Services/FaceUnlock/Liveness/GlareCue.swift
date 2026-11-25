// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived from Glance (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.
//
//  Pixel-domain half of the gloss/glare cue (see `LivenessCues.glossGlare`);
//  no Vision/CoreImage import, so it stays usable from `tools/liveness_selftest.swift`.
//  Populated by `GlareCueExtractor.extract(faceCrop:)`.

import CoreGraphics

struct GlareSample: Equatable {
    /// Native pixel width of the measured crop; `renderCrop` only ever downsamples, so this
    /// is an honest detail measure — the cue confidence-weights down as it shrinks.
    let cropPixelWidth: CGFloat

    /// Fraction of crop pixels that are near-saturated and low-chroma — direct specular reflection.
    let specularFraction: Float

    /// How concentrated the specular pixels are into one region (densest 8x8 grid cell's
    /// share) vs. scattered — distinguishes glass glare from a shiny forehead.
    let specularClusterRatio: Float
}
