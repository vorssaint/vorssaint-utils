// SPDX-License-Identifier: GPL-3.0-or-later
// Bounded interleaved Float32 PCM protocol. No pointers cross the HAL boundary.
#ifndef VORSSAINT_PCM_H
#define VORSSAINT_PCM_H
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#define VS_CAPACITY 16384u
#define VS_PACKET_FRAMES 4096u
#define VS_MAGIC 0x56535043u
#define VS_VERSION 2u
#define VS_MAX_CHANNELS 32u
// Private to each process: single producer, serialized single consumer.
// Producer drops NEW frames on full; unread storage is never overwritten.
typedef struct {
    _Atomic uint64_t read;
    _Atomic uint64_t written;
    uint32_t channels;
    float samples[VS_CAPACITY * VS_MAX_CHANNELS];
    uint64_t generations[VS_CAPACITY];
} VSQueue;
typedef struct {
    uint32_t magic,version,maxFrames,reserved;
    uint64_t generation,cursor,nonce;
    uint8_t key[32];
} VSRequest;
typedef struct {
    uint32_t magic,version,frames,channels;
    uint64_t generation,cursor,next,nonce;
    double rate;
    float gain;
    uint32_t muted;
} VSPacket;
_Static_assert(sizeof(VSRequest)==72,"request ABI");
_Static_assert(sizeof(VSPacket)==64,"packet ABI");
static inline VSRequest vs_request(uint64_t generation,uint64_t cursor,uint64_t nonce,uint32_t frames,const void *key) {
    VSRequest r={.magic=VS_MAGIC,.version=VS_VERSION,.maxFrames=frames,.generation=generation,.cursor=cursor,.nonce=nonce};
    memcpy(r.key,key,32);return r;
}
static inline unsigned vs_channels(const VSQueue *q) {return q->channels ? q->channels : 2;}
static inline VSQueue *vs_create_channels(unsigned channels) {
    if (channels < 2 || channels > VS_MAX_CHANNELS) return NULL;
    VSQueue *q = calloc(1, sizeof(VSQueue));
    if (q) q->channels = channels;
    return q;
}
static inline VSQueue *vs_create(void) {return vs_create_channels(2);}
static inline void vs_destroy(VSQueue *q) {free(q);}
static inline uint64_t vs_written(VSQueue *q) {return atomic_load_explicit(&q->written,memory_order_acquire);}
static inline uint64_t vs_read(VSQueue *q) {return atomic_load_explicit(&q->read,memory_order_relaxed);}
static inline uint32_t vs_write_generation(VSQueue *q,const float *data,uint32_t frames,uint64_t generation) {
    uint64_t w=atomic_load_explicit(&q->written,memory_order_relaxed),r=atomic_load_explicit(&q->read,memory_order_acquire);
    if(w-r>VS_CAPACITY || frames>VS_CAPACITY-(w-r)) return 0;
    unsigned channels = vs_channels(q);
    for(uint32_t i=0;i<frames;i++) {
        size_t at=((w+i)%VS_CAPACITY)*channels;
        q->generations[(w+i)%VS_CAPACITY]=generation;
        for (unsigned channel = 0; channel < channels; channel++) {
            float sample = data[i * channels + channel];
            q->samples[at + channel] = isfinite(sample) ? sample : 0;
        }
    }
    atomic_store_explicit(&q->written,w+frames,memory_order_release);
    return frames;
}
static inline uint32_t vs_write(VSQueue *q,const float *data,uint32_t frames) {return vs_write_generation(q,data,frames,0);}
static inline uint32_t vs_copy(VSQueue *q,uint64_t cursor,float *out,uint32_t frames) {
    uint64_t r=vs_read(q),w=vs_written(q);
    if(cursor<r || cursor>w || w-cursor>VS_CAPACITY) return 0;
    if(frames>w-cursor) frames=(uint32_t)(w-cursor);
    unsigned channels = vs_channels(q);
    for(uint32_t i=0;i<frames;i++) {
        size_t at=((cursor+i)%VS_CAPACITY)*channels;
        memcpy(out + i * channels, q->samples + at, channels * sizeof(float));
    }
    return frames;
}
static inline int vs_ack(VSQueue *q,uint64_t next) {
    if(next<vs_read(q) || next>vs_written(q)) return 0;
    atomic_store_explicit(&q->read,next,memory_order_release);return 1;
}
static inline uint32_t vs_copy_generation(VSQueue *q,uint64_t cursor,float *out,uint32_t frames,uint64_t generation) {
    uint32_t n=vs_copy(q,cursor,out,frames);
    for(uint32_t i=0;i<n;i++) if(q->generations[(cursor+i)%VS_CAPACITY]!=generation)
        memset(out + i * vs_channels(q), 0, vs_channels(q) * sizeof(float));
    return n;
}
#endif
