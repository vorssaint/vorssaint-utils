// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
#include "include/RecorderGIFCodec.h"
#include "vendor/cgif/cgif_raw.h"
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint8_t *data;
    size_t count, capacity, limit;
} Sink;

static int writeBytes(void *context, const uint8_t *bytes, size_t count) {
    Sink *sink = context;
    if (count > sink->limit - sink->count) return 1;
    size_t needed = sink->count + count;
    if (needed > sink->capacity) {
        size_t capacity = sink->capacity ? sink->capacity : 4096;
        while (capacity < needed) {
            capacity = capacity > sink->limit / 2 ? sink->limit : capacity * 2;
        }
        void *data = realloc(sink->data, capacity);
        if (!data) return 1;
        sink->data = data;
        sink->capacity = capacity;
    }
    memcpy(sink->data + sink->count, bytes, count);
    sink->count = needed;
    return 0;
}

uint8_t *RecorderGIFCodecEncode(const uint8_t *pixels, const uint8_t *previous,
    size_t pixelCount, uint32_t width, uint32_t height,
    const uint8_t *palette, size_t paletteBytes, size_t *outputLength) {
    if (!outputLength) return NULL;
    *outputLength = 0;
    if (!pixels || !palette || !width || !height || width > 65535 || height > 65535
        || (uint64_t)width * height != pixelCount || pixelCount > 67108864
        || paletteBytes < 6 || paletteBytes > 768 || paletteBytes % 3) return NULL;
    uint32_t colors = (uint32_t)(paletteBytes / 3);
    // GIF tables are powers of two. Reserve their last entry for unchanged
    // pixels, without making a screen recording with few colors carry a
    // 256-entry palette and an eight-bit minimum LZW code on every change.
    uint16_t entries = 4;
    while (entries <= colors && entries < 256) entries *= 2;
    const uint8_t transparent = (uint8_t)(entries - 1);
    uint32_t left = 0, top = 0, right = width - 1, bottom = height - 1;
    if (previous) {
        left = width;
        top = height;
        right = bottom = 0;
    }
    for (uint32_t y = 0; y < height; ++y) {
        const uint8_t *row = pixels + (size_t)y * width;
        const uint8_t *old = previous ? previous + (size_t)y * width : NULL;
        for (uint32_t x = 0; x < width; ++x) {
            if (row[x] >= colors || row[x] == transparent) return NULL;
            if (old && row[x] != old[x]) {
                if (x < left) left = x;
                if (x > right) right = x;
                if (y < top) top = y;
                bottom = y;
            }
        }
    }
    // An identical frame is a transparent 1x1 update, retaining its delay.
    if (left == width) left = top = right = bottom = 0;
    uint32_t rectWidth = right - left + 1, rectHeight = bottom - top + 1;
    uint8_t *rectangle = malloc((size_t)rectWidth * rectHeight);
    if (!rectangle) return NULL;
    for (uint32_t y = top; y <= bottom; ++y) {
        const uint8_t *row = pixels + (size_t)y * width;
        const uint8_t *old = previous ? previous + (size_t)y * width : NULL;
        for (uint32_t x = left; x <= right; ++x) {
            rectangle[(size_t)(y - top) * rectWidth + x - left] =
                old && row[x] == old[x] ? transparent : row[x];
        }
    }
    uint8_t table[768] = {0};
    memcpy(table, palette, paletteBytes);
    // Even incompressible GIF LZW data fits comfortably within this bound.
    Sink sink = { .limit = pixelCount * 3 + 4096 };
    CGIFRaw_Config config = {0};
    config.pWriteFn = writeBytes;
    config.pContext = &sink;
    config.pGCT = table;
    config.width = (uint16_t)width;
    config.height = (uint16_t)height;
    config.sizeGCT = entries;
    config.attrFlags = CGIF_RAW_ATTR_IS_ANIMATED | CGIF_RAW_ATTR_NO_LOOP;
    CGIFRaw *gif = cgif_raw_newgif(&config);
    if (!gif) { free(rectangle); free(sink.data); return NULL; }
    CGIFRaw_FrameConfig frame = {0};
    frame.pImageData = rectangle;
    frame.width = (uint16_t)rectWidth;
    frame.height = (uint16_t)rectHeight;
    frame.left = (uint16_t)left;
    frame.top = (uint16_t)top;
    frame.disposalMethod = DISPOSAL_METHOD_LEAVE;
    frame.transIndex = transparent;
    frame.attrFlags = CGIF_RAW_FRAME_ATTR_HAS_TRANS;
    int result = cgif_raw_addframe(gif, &frame);
    int closed = cgif_raw_close(gif);
    free(rectangle);
    if (result != CGIF_OK || closed != CGIF_OK) { free(sink.data); return NULL; }
    *outputLength = sink.count;
    return sink.data;
}
