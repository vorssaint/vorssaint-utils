// SPDX-License-Identifier: GPL-3.0-or-later
#include <stdio.h>
#if __has_include("../Sources/SoftwareVolumePCM/PCM.h")
#include "../Sources/SoftwareVolumePCM/PCM.h"
#include <assert.h>
#include <pthread.h>
static void *producer(void *p) {
    VSQueue *q=p;
    for (unsigned i=1;i<=200000;i++) {
        float frame[2]={(float)i,-(float)i};
        while (vs_write(q,frame,1)!=1) {}
    }
    return NULL;
}
int main(void) {
    VSQueue *q=vs_create(); assert(q);
    float frames[8]={.4f,.2f,.3f,.1f,.8f,.6f,.2f,.1f},out[8]={0};
    assert(vs_write(q,frames,4)==4);
    assert(vs_copy(q,0,out,4)==4 && out[0]==.4f && out[7]==.1f);
    assert(vs_copy(q,0,out,4)==4); // retry is idempotent until acknowledged
    assert(!vs_ack(q,5) && vs_ack(q,2));
    assert(vs_copy(q,0,out,4)==0 && vs_copy(q,2,out,4)==2 && out[0]==.8f);
    vs_ack(q,4);
    for(unsigned i=0;i<VS_CAPACITY;i++) assert(vs_write(q,frames,1)==1);
    assert(vs_write(q,frames,1)==0); // bounded drop-new, no overwrite
    assert(vs_ack(q,vs_written(q)));
    uint64_t session=vs_written(q);
    assert(vs_write_generation(q,frames,4,1)==4);
    assert(vs_copy_generation(q,session,out,4,2)==4 && out[0]==0 && out[7]==0);
    assert(vs_ack(q,vs_written(q)));
    pthread_t thread; pthread_create(&thread,NULL,producer,q);
    unsigned next=1;
    while(next<=200000) {
        uint64_t cursor=vs_read(q); float f[2];
        if(vs_copy(q,cursor,f,1)) {assert(f[0]==(float)next && f[1]==-(float)next);assert(vs_ack(q,cursor+1));next++;}
    }
    pthread_join(thread,NULL); vs_destroy(q);
    puts("PCM transport: order, retries, bounds and 200000 concurrent frames passed");
    return 0;
}
#else
int main(void) {fputs("FAIL: output-only PCM transport missing\n",stderr);return 1;}
#endif
