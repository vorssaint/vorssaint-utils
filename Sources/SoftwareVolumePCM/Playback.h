// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef VORSSAINT_PLAYBACK_H
#define VORSSAINT_PLAYBACK_H
#include "PCM.h"
#include <CoreAudio/CoreAudio.h>
#include <mach/mach_time.h>
typedef struct {
    VSQueue queue;
    _Atomic float gain;
    _Atomic uint32_t muted;
    _Atomic uint64_t lastGood;
    _Atomic uint64_t underruns,trimmed,dropped;
    uint64_t expiryTicks;
    unsigned targetFrames;
    uint32_t channelMap[VS_MAX_CHANNELS];
    // Written only by the background PCM pump, outside the realtime callback.
    float packetSamples[VS_PACKET_FRAMES * VS_MAX_CHANNELS];
    double phase,ratio;
    int primed;
} VSPlayback;
static inline void *vs_playback_create_channels(unsigned channels) {
    if (channels < 2 || channels > VS_MAX_CHANNELS) return NULL;
    VSPlayback *p=calloc(1,sizeof(*p));if(!p)return NULL;
    p->queue.channels = channels;
    for (unsigned channel = 0; channel < channels; channel++) p->channelMap[channel] = channel;
    mach_timebase_info_data_t info;mach_timebase_info(&info);
    p->expiryTicks=(uint64_t)(1e9*info.denom/info.numer);p->ratio=1;p->targetFrames=1024;
    atomic_store(&p->gain,1);return p;
}
static inline void *vs_playback_create(void) {return vs_playback_create_channels(2);}
// Configure before starting the physical IOProc. Rendering never mutates this map.
static inline int vs_playback_set_channel_map(void *context,const uint32_t *map,unsigned channels) {
    VSPlayback *p = context;
    if (!map || channels != vs_channels(&p->queue)) return 0;
    for (unsigned channel = 0; channel < channels; channel++)
        for (unsigned previous = 0; previous < channel; previous++)
            if (map[channel] == map[previous]) return 0;
    memcpy(p->channelMap,map,channels*sizeof(uint32_t));
    return 1;
}
static inline void vs_playback_rate(void *context,double rate) {
    VSPlayback *p=context;p->targetFrames=(unsigned)fmin(VS_CAPACITY/2,fmax(1024,ceil(rate*.02)));
}
static inline void vs_playback_destroy(void *context) {free(context);}
static inline void vs_playback_control(void *context,float gain,uint32_t muted) {
    VSPlayback *p=context;atomic_store(&p->gain,gain);atomic_store(&p->muted,muted);
    atomic_store(&p->lastGood,mach_absolute_time());
}
static inline int vs_playback_healthy(void *context) {
    VSPlayback *p=context;uint64_t good=atomic_load(&p->lastGood);
    return good && mach_absolute_time()-good<p->expiryTicks;
}
static inline int vs_packet_validate_channels(const void *bytes,size_t size,uint64_t nonce,uint64_t generation,uint64_t cursor,double rate,unsigned channels,VSPacket *header) {
    if(channels < 2 || channels > VS_MAX_CHANNELS || !bytes || size<sizeof(VSPacket)
        || size>sizeof(VSPacket)+VS_PACKET_FRAMES*channels*sizeof(float))return 0;
    VSPacket h;memcpy(&h,bytes,sizeof(h));
    if(h.magic!=VS_MAGIC || h.version!=VS_VERSION || h.channels!=channels || h.frames>VS_PACKET_FRAMES
        || size!=sizeof(h)+h.frames*channels*sizeof(float) || h.nonce!=nonce || h.next<h.cursor || h.next-h.cursor!=h.frames
        || !h.generation || !isfinite(h.rate) || h.rate!=rate || !isfinite(h.gain) || h.gain<0 || h.gain>1 || h.muted>1)return 0;
    if(generation && (h.generation!=generation || h.cursor!=cursor))return 0;
    if(!generation && h.frames)return 0;
    *header=h;return 1;
}
static inline int vs_packet_validate(const void *bytes,size_t size,uint64_t nonce,uint64_t generation,uint64_t cursor,double rate,VSPacket *header) {
    return vs_packet_validate_channels(bytes,size,nonce,generation,cursor,rate,2,header);
}
static inline void vs_playback_push(void *context,const void *bytes,size_t size) {
    VSPlayback *p=context;VSPacket h;memcpy(&h,bytes,sizeof(h));
    if(h.frames) {memcpy(p->packetSamples,(const uint8_t*)bytes+sizeof(h),h.frames*vs_channels(&p->queue)*sizeof(float));if(vs_write(&p->queue,p->packetSamples,h.frames)!=h.frames)atomic_fetch_add(&p->dropped,h.frames);}
    vs_playback_control(p,h.gain,h.muted);
}
// Exactly one physical output IOProc consumes this queue. Inputs are never read.
typedef struct {uint64_t queued,underruns,trimmed,dropped;} VSPlaybackStats;
static inline VSPlaybackStats vs_playback_stats(void *context) {
    VSPlayback *p=context;
    uint64_t read=vs_read(&p->queue),written=vs_written(&p->queue);
    return (VSPlaybackStats){written-read,atomic_load(&p->underruns),atomic_load(&p->trimmed),atomic_load(&p->dropped)};
}
static inline int vs_playback_render(void *context,AudioBufferList *output) {
    VSPlayback *p=context;uint32_t frames=UINT32_MAX,channelCount=0;
    for(uint32_t b=0;b<output->mNumberBuffers;b++)if(output->mBuffers[b].mData)memset(output->mBuffers[b].mData,0,output->mBuffers[b].mDataByteSize);
    for(uint32_t b=0;b<output->mNumberBuffers;b++) {
        AudioBuffer *buffer=&output->mBuffers[b];
        if(!buffer->mNumberChannels || buffer->mNumberChannels>UINT32_MAX/sizeof(float) || !buffer->mData || buffer->mDataByteSize%(4*buffer->mNumberChannels))return 0;
        uint32_t n=buffer->mDataByteSize/(4*buffer->mNumberChannels);if(n<frames)frames=n;
        if (channelCount > UINT32_MAX-buffer->mNumberChannels) return 0;
        channelCount+=buffer->mNumberChannels;
    }
    unsigned channels = vs_channels(&p->queue);
    if(channelCount<channels || frames==UINT32_MAX || !vs_playback_healthy(p))return 0;
    uint64_t r=vs_read(&p->queue),w=vs_written(&p->queue),available=w-r;
    if(frames>VS_PACKET_FRAMES)return 0;
    const unsigned target=p->targetFrames>frames*3 ? p->targetFrames:frames*3;
    if(available>target*4) {atomic_fetch_add(&p->trimmed,available-target*2);r=w-target*2;vs_ack(&p->queue,r);p->phase=0;available=w-r;}
    if(!p->primed) {if(available<target)return 0;p->primed=1;p->phase=0;}
    double correction=((double)available-target)/target*.003;
    if(correction>.005)correction=.005;if(correction<-.005)correction=-.005;
    p->ratio+=(1+correction-p->ratio)*.02;
    float gain=atomic_load(&p->muted) ? 0:atomic_load(&p->gain);
    float *dest[VS_MAX_CHANNELS]={0};uint32_t strides[VS_MAX_CHANNELS]={0},physicalChannel=0;
    for(uint32_t b=0;b<output->mNumberBuffers;b++)for(uint32_t c=0;c<output->mBuffers[b].mNumberChannels;c++,physicalChannel++) {
        for (unsigned channel=0;channel<channels;channel++) if (p->channelMap[channel]==physicalChannel) {
            dest[channel]=(float*)output->mBuffers[b].mData+c;strides[channel]=output->mBuffers[b].mNumberChannels;
        }
    }
    for (unsigned channel=0;channel<channels;channel++) if (!dest[channel]) return 0;
    unsigned rendered=0;
    for(uint32_t f=0;f<frames;f++) {
        uint64_t whole=(uint64_t)p->phase;
        if(whole+1>=available) {atomic_fetch_add(&p->underruns,1);p->primed=0;break;}
        float fraction=(float)(p->phase-whole);
        size_t a=((r+whole)%VS_CAPACITY)*channels,b=((r+whole+1)%VS_CAPACITY)*channels;
        for(unsigned c=0;c<channels;c++)dest[c][f*strides[c]]=(p->queue.samples[a+c]+(p->queue.samples[b+c]-p->queue.samples[a+c])*fraction)*gain;
        p->phase+=p->ratio;rendered++;
    }
    uint64_t consumed=(uint64_t)p->phase;if(consumed>available)consumed=available;
    vs_ack(&p->queue,r+consumed);p->phase-=consumed;
    return rendered==frames;
}
#endif
