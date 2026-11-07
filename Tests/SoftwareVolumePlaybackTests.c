// SPDX-License-Identifier: GPL-3.0-or-later
#include <stdio.h>
#if __has_include("../Sources/SoftwareVolumePCM/Playback.h")
#include "../Sources/SoftwareVolumePCM/Playback.h"
#include <assert.h>
static void drift(double mismatch) {
    VSPlayback *p=vs_playback_create();assert(p);
    float data[2048];for(unsigned i=0;i<2048;i++)data[i]=.25f;
    float out[1024];AudioBufferList list={.mNumberBuffers=1,.mBuffers={{.mNumberChannels=2,.mDataByteSize=sizeof(out),.mData=out}}};
    double source=0;unsigned underruns=0;
    for(unsigned n=0;n<30000;n++) {
        source+=512*(1+mismatch);unsigned frames=(unsigned)source;source-=frames;
        vs_write(&p->queue,data,frames);vs_playback_control(p,.5f,0);
        if(!vs_playback_render(p,&list) && n>20)underruns++;
        if(n>20 && p->primed)assert(fabsf(out[0]-.125f)<1e-5f);
    }
    assert(underruns==0);assert(vs_written(&p->queue)-vs_read(&p->queue)<4096);
    vs_playback_control(p,.5f,1);vs_playback_render(p,&list);assert(out[0]==0 && out[1]==0);
    vs_playback_destroy(p);
}
static void packets(void) {
    unsigned char bytes[sizeof(VSPacket)+32];VSPacket h={.magic=VS_MAGIC,.version=VS_VERSION,.channels=2,.frames=4,.generation=7,.cursor=100,.next=104,.nonce=9,.rate=48000,.gain=.5};
    memset(bytes,0,sizeof(bytes));memcpy(bytes,&h,sizeof(h));VSPacket out;
    assert(vs_packet_validate(bytes,sizeof(bytes),9,7,100,48000,&out));
    assert(!vs_packet_validate(bytes,sizeof(bytes)-1,9,7,100,48000,&out));
    assert(!vs_packet_validate(bytes,sizeof(bytes),8,7,100,48000,&out));
    assert(!vs_packet_validate(bytes,sizeof(bytes),9,8,100,48000,&out));
    assert(!vs_packet_validate(bytes,sizeof(bytes),9,7,101,48000,&out));
    assert(!vs_packet_validate(bytes,sizeof(bytes),9,7,100,44100,&out));
    h.frames=UINT32_MAX;memcpy(bytes,&h,sizeof(h));assert(!vs_packet_validate(bytes,sizeof(bytes),9,7,100,48000,&out));
    h.frames=4;h.gain=NAN;memcpy(bytes,&h,sizeof(h));assert(!vs_packet_validate(bytes,sizeof(bytes),9,7,100,48000,&out));
}
static void large_callback(void) {
    VSPlayback *p=vs_playback_create();assert(p);
    float data[8192],out[8192];for(unsigned i=0;i<8192;i++)data[i]=.25f;
    AudioBufferList list={.mNumberBuffers=1,.mBuffers={{.mNumberChannels=2,.mDataByteSize=sizeof(out),.mData=out}}};
    vs_write(&p->queue,data,4096);vs_write(&p->queue,data,4096);
    for(unsigned n=0;n<100;n++) {vs_write(&p->queue,data,4096);vs_playback_control(p,1,0);assert(vs_playback_render(p,&list));for(unsigned i=0;i<8192;i++)assert(out[i]==.25f);}
    vs_playback_destroy(p);
}
static void scheduler_jitter(void) {
    VSPlayback *p=vs_playback_create();assert(p);
    float data[8192],out[1024];for(unsigned i=0;i<8192;i++)data[i]=.25f;
    AudioBufferList list={.mNumberBuffers=1,.mBuffers={{.mNumberChannels=2,.mDataByteSize=sizeof(out),.mData=out}}};
    unsigned pending=0,underruns=0;
    for(unsigned n=0;n<4000;n++) {
        pending+=512;
        if(n%17>1) {assert(vs_write(&p->queue,data,pending)==pending);pending=0;}
        vs_playback_control(p,1,0);
        if(!vs_playback_render(p,&list) && n>10)underruns++;
    }
    assert(underruns==0);vs_playback_destroy(p);
}
int main(void) {packets();scheduler_jitter();large_callback();drift(.001);drift(-.001);puts("Playback: +/-1000ppm drift, single master gain and immediate buffered mute passed");return 0;}
#else
int main(void){fputs("FAIL: output-only playback missing\n",stderr);return 1;}
#endif
