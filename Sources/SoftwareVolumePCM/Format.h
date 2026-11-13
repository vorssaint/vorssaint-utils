// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef VORSSAINT_OUTPUT_FORMAT_H
#define VORSSAINT_OUTPUT_FORMAT_H
#include "PCM.h"
#include <CoreAudio/CoreAudio.h>

typedef struct {
    uint32_t version;
    uint32_t channels;
    AudioChannelDescription descriptions[VS_MAX_CHANNELS];
    uint32_t stereo[2];
} VSOutputFormat;
_Static_assert(sizeof(VSOutputFormat) == 16 + VS_MAX_CHANNELS * sizeof(AudioChannelDescription), "output format ABI");

static inline VSOutputFormat vs_format_default(unsigned channels) {
    VSOutputFormat format = {.version = VS_VERSION, .channels = channels, .stereo = {1, 2}};
    for (unsigned channel = 0; channel < channels && channel < VS_MAX_CHANNELS; channel++)
        format.descriptions[channel].mChannelLabel = channel < 2
            ? kAudioChannelLabel_Left + channel : kAudioChannelLabel_Discrete_0 + channel;
    return format;
}

static inline int vs_format_valid(const VSOutputFormat *format) {
    if (format->version != VS_VERSION || format->channels < 2 || format->channels > VS_MAX_CHANNELS
        || !format->stereo[0] || !format->stereo[1] || format->stereo[0] > format->channels
        || format->stereo[1] > format->channels || format->stereo[0] == format->stereo[1]) return 0;
    for (unsigned channel = 0; channel < format->channels; channel++)
        for (unsigned axis = 0; axis < 3; axis++)
            if (!isfinite(format->descriptions[channel].mCoordinates[axis])) return 0;
    return 1;
}

static inline int vs_format_layout(VSOutputFormat *format, const void *bytes, size_t size) {
    if (size < offsetof(AudioChannelLayout, mChannelDescriptions)) return 0;
    AudioChannelLayout layout = {0};
    memcpy(&layout, bytes, offsetof(AudioChannelLayout, mChannelDescriptions));
    size_t required = offsetof(AudioChannelLayout, mChannelDescriptions)
        + format->channels * sizeof(AudioChannelDescription);
    if (layout.mChannelLayoutTag != kAudioChannelLayoutTag_UseChannelDescriptions
        || layout.mNumberChannelDescriptions != format->channels || size < required) return 0;
    memcpy(format->descriptions, (const uint8_t *)bytes + offsetof(AudioChannelLayout, mChannelDescriptions),
           format->channels * sizeof(AudioChannelDescription));
    if (format->channels == 2) {
        for (unsigned channel = 0; channel < 2; channel++) {
            if (format->descriptions[channel].mChannelLabel == kAudioChannelLabel_Left) format->stereo[0] = channel + 1;
            if (format->descriptions[channel].mChannelLabel == kAudioChannelLabel_Right) format->stereo[1] = channel + 1;
        }
    }
    return vs_format_valid(format);
}

static inline void vs_format_preferred_stereo(VSOutputFormat *format, uint32_t left, uint32_t right) {
    if (!left || !right || left > format->channels || right > format->channels || left == right) return;
    format->stereo[0] = left;
    format->stereo[1] = right;
    if (format->channels != 2) return;
    for (unsigned channel = 0; channel < 2; channel++) {
        AudioChannelLabel label = format->descriptions[channel].mChannelLabel;
        if (label != kAudioChannelLabel_Unknown && label != kAudioChannelLabel_Unused) return;
    }
    format->descriptions[left - 1].mChannelLabel = kAudioChannelLabel_Left;
    format->descriptions[right - 1].mChannelLabel = kAudioChannelLabel_Right;
}

static inline int vs_format_channel_map(const VSOutputFormat *format, unsigned capacity,
                                       const uint32_t stereo[2], uint32_t map[VS_MAX_CHANNELS]) {
    if (!vs_format_valid(format) || capacity < format->channels) return 0;
    for (unsigned channel = 0; channel < format->channels; channel++) map[channel] = channel;
    if (capacity == format->channels) return 1;
    if (!stereo[0] || !stereo[1] || stereo[0] > capacity || stereo[1] > capacity || stereo[0] == stereo[1]) return 0;
    if (format->channels > 2) return stereo[0] <= format->channels && stereo[1] <= format->channels;
    unsigned left = VS_MAX_CHANNELS, right = VS_MAX_CHANNELS;
    for (unsigned channel = 0; channel < 2; channel++) {
        if (format->descriptions[channel].mChannelLabel == kAudioChannelLabel_Left) left = channel;
        if (format->descriptions[channel].mChannelLabel == kAudioChannelLabel_Right) right = channel;
    }
    if (left == VS_MAX_CHANNELS || right == VS_MAX_CHANNELS) return 0;
    map[left] = stereo[0] - 1;
    map[right] = stereo[1] - 1;
    return 1;
}
#endif
