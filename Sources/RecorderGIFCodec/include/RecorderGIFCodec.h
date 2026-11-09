// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
#ifndef RECORDER_GIF_CODEC_H
#define RECORDER_GIF_CODEC_H
#include <stddef.h>
#include <stdint.h>

// Opaque indexed pixels, up to 255 colors. The encoder reserves a separate
// palette entry for unchanged pixels.
// previous is NULL or contains pixelCount bytes using the same palette.
// On success the caller owns the returned allocation and frees it with free().
uint8_t *RecorderGIFCodecEncode(const uint8_t *pixels, const uint8_t *previous,
    size_t pixelCount, uint32_t width, uint32_t height,
    const uint8_t *palette, size_t paletteBytes, size_t *outputLength);
#endif
