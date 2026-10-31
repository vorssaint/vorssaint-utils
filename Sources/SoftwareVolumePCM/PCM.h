// SPDX-License-Identifier: GPL-3.0-or-later
// Fixed stereo float PCM protocol. No pointers cross the HAL boundary.
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
#define VS_VERSION 1u
// Private to each process: single producer, serialized single consumer.
// Producer drops NEW frames on full; unread storage is never overwritten.
typedef struct {
    _Atomic uint64_t read;
    _Atomic uint64_t written;
    float samples[VS_CAPACITY * 2];
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
static inline VSQueue *vs_create(void) {return calloc(1,sizeof(VSQueue));}
static inline void vs_destroy(VSQueue *q) {free(q);}
static inline uint64_t vs_written(VSQueue *q) {return atomic_load_explicit(&q->written,memory_order_acquire);}
static inline uint64_t vs_read(VSQueue *q) {return atomic_load_explicit(&q->read,memory_order_relaxed);}
static inline uint32_t vs_write_generation(VSQueue *q,const float *data,uint32_t frames,uint64_t generation) {
    uint64_t w=atomic_load_explicit(&q->written,memory_order_relaxed),r=atomic_load_explicit(&q->read,memory_order_acquire);
    if(w-r>VS_CAPACITY || frames>VS_CAPACITY-(w-r)) return 0;
    for(uint32_t i=0;i<frames;i++) {
        size_t at=((w+i)%VS_CAPACITY)*2;
        q->generations[(w+i)%VS_CAPACITY]=generation;
        q->samples[at]=isfinite(data[i*2]) ? data[i*2]:0;
        q->samples[at+1]=isfinite(data[i*2+1]) ? data[i*2+1]:0;
    }
    atomic_store_explicit(&q->written,w+frames,memory_order_release);
    return frames;
}
static inline uint32_t vs_write(VSQueue *q,const float *data,uint32_t frames) {return vs_write_generation(q,data,frames,0);}
static inline uint32_t vs_copy(VSQueue *q,uint64_t cursor,float *out,uint32_t frames) {
    uint64_t r=vs_read(q),w=vs_written(q);
    if(cursor<r || cursor>w || w-cursor>VS_CAPACITY) return 0;
    if(frames>w-cursor) frames=(uint32_t)(w-cursor);
    for(uint32_t i=0;i<frames;i++) {
        size_t at=((cursor+i)%VS_CAPACITY)*2;
        out[i*2]=q->samples[at];out[i*2+1]=q->samples[at+1];
    }
    return frames;
}
static inline int vs_ack(VSQueue *q,uint64_t next) {
    if(next<vs_read(q) || next>vs_written(q)) return 0;
    atomic_store_explicit(&q->read,next,memory_order_release);return 1;
}
static inline uint32_t vs_copy_generation(VSQueue *q,uint64_t cursor,float *out,uint32_t frames,uint64_t generation) {
    uint32_t n=vs_copy(q,cursor,out,frames);
    for(uint32_t i=0;i<n;i++) if(q->generations[(cursor+i)%VS_CAPACITY]!=generation) out[i*2]=out[i*2+1]=0;
    return n;
}
#endif
