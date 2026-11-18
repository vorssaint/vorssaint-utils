// SPDX-License-Identifier: GPL-3.0-or-later
#include "../Sources/SoftwareVolumePCM/Playback.h"
#include <assert.h>
#include <stdio.h>
#include <pthread.h>
#include "../Sources/SoftwareVolumePCM/Format.h"

static void channel_identity(unsigned channels, unsigned outputChannels, double rate, int planar) {
    VSPlayback *playback = vs_playback_create_channels(channels);
    assert(playback);
    vs_playback_rate(playback, rate);
    float input[VS_PACKET_FRAMES * VS_MAX_CHANNELS];
    for (unsigned frame = 0; frame < VS_PACKET_FRAMES; frame++)
        for (unsigned channel = 0; channel < channels; channel++)
            input[frame * channels + channel] = (channel + 1) * 0.05f;
    assert(vs_write(&playback->queue, input, VS_PACKET_FRAMES) == VS_PACKET_FRAMES);
    float output[64 * VS_MAX_CHANNELS] = {0};
    struct { UInt32 count; AudioBuffer buffers[VS_MAX_CHANNELS]; } list = {0};
    list.count = planar ? outputChannels : 1;
    for (unsigned buffer = 0; buffer < list.count; buffer++) {
        list.buffers[buffer].mNumberChannels = planar ? 1 : outputChannels;
        list.buffers[buffer].mDataByteSize = 64 * sizeof(float) * list.buffers[buffer].mNumberChannels;
        list.buffers[buffer].mData = output + buffer * 64;
    }
    vs_playback_control(playback, 0.5f, 0);
    assert(vs_playback_render(playback, (AudioBufferList *)&list));
    for (unsigned channel = 0; channel < outputChannels; channel++)
        for (unsigned frame = 0; frame < 64; frame++) {
            float value = planar ? output[channel * 64 + frame] : output[frame * outputChannels + channel];
            float expected = channel < channels ? (channel + 1) * 0.025f : 0;
            assert(fabsf(value - expected) < 0.00001f);
        }
    vs_playback_control(playback, 0.5f, 1);
    assert(vs_playback_render(playback, (AudioBufferList *)&list));
    for (unsigned buffer = 0; buffer < list.count; buffer++)
        for (unsigned sample = 0; sample < list.buffers[buffer].mDataByteSize / sizeof(float); sample++)
            assert(((float *)list.buffers[buffer].mData)[sample] == 0);
    vs_playback_destroy(playback);
}

static void *produce(void *context) {
    VSQueue *queue = context;
    for (unsigned frame = 1; frame <= 40000; frame++) {
        float samples[VS_MAX_CHANNELS];
        for (unsigned channel = 0; channel < queue->channels; channel++) samples[channel] = frame * VS_MAX_CHANNELS + channel;
        while (!vs_write(queue, samples, 1)) {}
    }
    return NULL;
}

static void concurrent_channels(unsigned channels) {
    VSQueue *queue = vs_create_channels(channels);
    assert(queue);
    pthread_t thread;
    assert(pthread_create(&thread, NULL, produce, queue) == 0);
    for (unsigned frame = 1; frame <= 40000;) {
        float samples[VS_MAX_CHANNELS]; uint64_t cursor = vs_read(queue);
        if (!vs_copy(queue, cursor, samples, 1)) continue;
        for (unsigned channel = 0; channel < channels; channel++) assert(samples[channel] == frame * VS_MAX_CHANNELS + channel);
        assert(vs_ack(queue, cursor + 1)); frame++;
    }
    assert(pthread_join(thread, NULL) == 0);
    vs_destroy(queue);
}

static void packet_bounds(unsigned channels) {
    uint8_t bytes[sizeof(VSPacket) + VS_MAX_CHANNELS * sizeof(float)] = {0};
    VSPacket packet = {.magic=VS_MAGIC,.version=VS_VERSION,.channels=channels,.frames=1,
                       .generation=5,.cursor=20,.next=21,.nonce=7,.rate=192000,.gain=1};
    size_t size = sizeof(packet) + channels * sizeof(float);
    memcpy(bytes, &packet, sizeof(packet));
    VSPacket header;
    assert(vs_packet_validate_channels(bytes,size,7,5,20,192000,channels,&header));
    assert(!vs_packet_validate_channels(bytes,size,7,5,20,96000,channels,&header));
    assert(!vs_packet_validate_channels(bytes,size,7,5,20,192000,channels==8 ? 6 : 8,&header));
    assert(!vs_packet_validate_channels(bytes,size-1,7,5,20,192000,channels,&header));
    packet.version=1; memcpy(bytes,&packet,sizeof(packet));
    assert(!vs_packet_validate_channels(bytes,size,7,5,20,192000,channels,&header));
}

static void stereo_destination(void) {
    VSOutputFormat format = vs_format_default(2);
    uint32_t preferred[2] = {3,4}, map[VS_MAX_CHANNELS] = {0};
    assert(vs_format_channel_map(&format,6,preferred,map));
    assert(map[0]==2 && map[1]==3);
    VSPlayback *playback = vs_playback_create_channels(2);
    assert(vs_playback_set_channel_map(playback,map,2));
    float input[4096*2];
    for (unsigned i=0;i<4096;i++) { input[i*2]=0.1f; input[i*2+1]=0.2f; }
    assert(vs_write(&playback->queue,input,4096)==4096);
    vs_playback_control(playback,1,0);
    float output[64*6];
    AudioBufferList buffers={.mNumberBuffers=1,.mBuffers={{.mNumberChannels=6,.mDataByteSize=sizeof(output),.mData=output}}};
    assert(vs_playback_render(playback,&buffers));
    for (unsigned frame=0;frame<64;frame++)
        for (unsigned channel=0;channel<6;channel++) {
            float expected=channel==2 ? 0.1f : channel==3 ? 0.2f : 0;
            assert(fabsf(output[frame*6+channel]-expected)<0.00001f);
        }
    vs_playback_destroy(playback);

    struct { UInt32 tag, bitmap, count; AudioChannelDescription descriptions[2]; } reversed = {
        .tag=kAudioChannelLayoutTag_UseChannelDescriptions, .count=2,
        .descriptions={{.mChannelLabel=kAudioChannelLabel_Right},{.mChannelLabel=kAudioChannelLabel_Left}}
    };
    format=vs_format_default(2);
    assert(vs_format_layout(&format,&reversed,sizeof(reversed)));
    assert(format.stereo[0]==2 && format.stereo[1]==1);
    preferred[0]=4; preferred[1]=3;
    assert(vs_format_channel_map(&format,6,preferred,map));
    assert(map[0]==2 && map[1]==3);
    format.descriptions[0].mChannelLabel=kAudioChannelLabel_Unknown;
    format.descriptions[1].mChannelLabel=kAudioChannelLabel_Unknown;
    vs_format_preferred_stereo(&format,2,1);
    assert(format.descriptions[1].mChannelLabel==kAudioChannelLabel_Left
           && format.descriptions[0].mChannelLabel==kAudioChannelLabel_Right);
}

int main(void) {
    assert(!vs_playback_create_channels(0));
    assert(!vs_playback_create_channels(VS_MAX_CHANNELS + 1));
    for (unsigned channels = 2; channels <= VS_MAX_CHANNELS; channels++)
        for (unsigned rate = 48000; rate <= 192000; rate *= 2)
            for (int planar = 0; planar <= 1; planar++)
                channel_identity(channels, channels, rate, planar);
    for (unsigned channels = 2; channels <= VS_MAX_CHANNELS; channels++) {
        concurrent_channels(channels);
        packet_bounds(channels);
    }
    channel_identity(2,6,48000,0);
    channel_identity(6,8,48000,0);
    channel_identity(6,8,48000,1);
    stereo_destination();
    puts("Multichannel playback: channel identity, planar/interleaved, 48/96/192 kHz and buffered mute passed");
}
