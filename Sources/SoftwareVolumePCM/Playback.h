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
    double phase,ratio;
    int primed;
} VSPlayback;
static inline void *vs_playback_create(void) {
    VSPlayback *p=calloc(1,sizeof(*p));if(!p)return NULL;
    mach_timebase_info_data_t info;mach_timebase_info(&info);
    p->expiryTicks=(uint64_t)(1e9*info.denom/info.numer);p->ratio=1;p->targetFrames=1024;
    atomic_store(&p->gain,1);return p;
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
static inline int vs_packet_validate(const void *bytes,size_t size,uint64_t nonce,uint64_t generation,uint64_t cursor,double rate,VSPacket *header) {
    if(!bytes || size<sizeof(VSPacket) || size>sizeof(VSPacket)+VS_PACKET_FRAMES*8)return 0;
    VSPacket h;memcpy(&h,bytes,sizeof(h));
    if(h.magic!=VS_MAGIC || h.version!=VS_VERSION || h.channels!=2 || h.frames>VS_PACKET_FRAMES
        || size!=sizeof(h)+h.frames*8 || h.nonce!=nonce || h.next<h.cursor || h.next-h.cursor!=h.frames
        || !h.generation || !isfinite(h.rate) || h.rate!=rate || !isfinite(h.gain) || h.gain<0 || h.gain>1 || h.muted>1)return 0;
    if(generation && (h.generation!=generation || h.cursor!=cursor))return 0;
    if(!generation && h.frames)return 0;
    *header=h;return 1;
}
static inline void vs_playback_push(void *context,const void *bytes,size_t size) {
    VSPlayback *p=context;VSPacket h;memcpy(&h,bytes,sizeof(h));
    if(h.frames) {float samples[VS_PACKET_FRAMES*2];memcpy(samples,(const uint8_t*)bytes+sizeof(h),h.frames*8);if(vs_write(&p->queue,samples,h.frames)!=h.frames)atomic_fetch_add(&p->dropped,h.frames);}
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
        if(!buffer->mNumberChannels || !buffer->mData || buffer->mDataByteSize%(4*buffer->mNumberChannels))return 0;
        uint32_t n=buffer->mDataByteSize/(4*buffer->mNumberChannels);if(n<frames)frames=n;
        channelCount+=buffer->mNumberChannels;
    }
    if(channelCount<2 || frames==UINT32_MAX || !vs_playback_healthy(p))return 0;
    uint64_t r=vs_read(&p->queue),w=vs_written(&p->queue),available=w-r;
    if(frames>VS_PACKET_FRAMES)return 0;
    const unsigned target=p->targetFrames>frames*3 ? p->targetFrames:frames*3;
    if(available>target*4) {atomic_fetch_add(&p->trimmed,available-target*2);r=w-target*2;vs_ack(&p->queue,r);p->phase=0;available=w-r;}
    if(!p->primed) {if(available<target)return 0;p->primed=1;p->phase=0;}
    double correction=((double)available-target)/target*.003;
    if(correction>.005)correction=.005;if(correction<-.005)correction=-.005;
    p->ratio+=(1+correction-p->ratio)*.02;
    float gain=atomic_load(&p->muted) ? 0:atomic_load(&p->gain);
    float *dest[2]={0};uint32_t strides[2]={0},found=0;
    for(uint32_t b=0;b<output->mNumberBuffers && found<2;b++)for(uint32_t c=0;c<output->mBuffers[b].mNumberChannels && found<2;c++) {
        dest[found]=(float*)output->mBuffers[b].mData+c;strides[found++]=output->mBuffers[b].mNumberChannels;
    }
    unsigned rendered=0;
    for(uint32_t f=0;f<frames;f++) {
        uint64_t whole=(uint64_t)p->phase;
        if(whole+1>=available) {atomic_fetch_add(&p->underruns,1);p->primed=0;break;}
        float fraction=(float)(p->phase-whole);
        size_t a=((r+whole)%VS_CAPACITY)*2,b=((r+whole+1)%VS_CAPACITY)*2;
        for(unsigned c=0;c<2;c++)dest[c][f*strides[c]]=(p->queue.samples[a+c]+(p->queue.samples[b+c]-p->queue.samples[a+c])*fraction)*gain;
        p->phase+=p->ratio;rendered++;
    }
    uint64_t consumed=(uint64_t)p->phase;if(consumed>available)consumed=available;
    vs_ack(&p->queue,r+consumed);p->phase-=consumed;
    return rendered==frames;
}
#endif
