// SPDX-License-Identifier: GPL-3.0-only
#include "AudioDSP.h"
#include <stdatomic.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define HE_MAX_FILTERS 16
typedef struct { double b0,b1,b2,a1,a2; } Coeff;
typedef struct { Coeff c[HE_MAX_FILTERS]; double z[2][HE_MAX_FILTERS][2]; double gain; } Bank;
struct HEDSP {
    double rate;
    _Atomic uint64_t version;
    _Atomic double pending[HE_MAX_FILTERS * 5 + 1];
    uint64_t applied;
    Bank active, next;
    uint32_t fade, fadeLength;
    _Atomic float inPeak, outPeak;
    _Atomic uint64_t frames, clipped, invalid;
};

static Coeff unity(void) { return (Coeff){1,0,0,0,0}; }
static Coeff coefficients(HEFilter f, double rate) {
    if (!isfinite(f.frequency) || !isfinite(f.gain) || !isfinite(f.q) ||
        f.frequency <= 0 || f.frequency >= rate * 0.499 || f.q < .1 || f.q > 20 || fabs(f.gain) > 24) return unity();
    double a=pow(10,f.gain/40), w=2*M_PI*f.frequency/rate, cs=cos(w), sn=sin(w);
    double alpha=sn/(2*f.q), root=2*sqrt(a)*alpha;
    double b0,b1,b2,a0,a1,a2;
    if (f.type==HELowShelf) {
        b0=a*((a+1)-(a-1)*cs+root); b1=2*a*((a-1)-(a+1)*cs); b2=a*((a+1)-(a-1)*cs-root);
        a0=(a+1)+(a-1)*cs+root; a1=-2*((a-1)+(a+1)*cs); a2=(a+1)+(a-1)*cs-root;
    } else if (f.type==HEHighShelf) {
        b0=a*((a+1)+(a-1)*cs+root); b1=-2*a*((a-1)+(a+1)*cs); b2=a*((a+1)+(a-1)*cs-root);
        a0=(a+1)-(a-1)*cs+root; a1=2*((a-1)-(a+1)*cs); a2=(a+1)-(a-1)*cs-root;
    } else {
        b0=1+alpha*a; b1=-2*cs; b2=1-alpha*a;
        a0=1+alpha/a; a1=-2*cs; a2=1-alpha/a;
    }
    return (Coeff){b0/a0,b1/a0,b2/a0,a1/a0,a2/a0};
}

double HEFilterResponse(HEFilter f, double rate, double frequency) {
    Coeff c=coefficients(f,rate);
    double w=2*M_PI*frequency/rate;
    double nr=c.b0+c.b1*cos(w)+c.b2*cos(2*w), ni=-c.b1*sin(w)-c.b2*sin(2*w);
    double dr=1+c.a1*cos(w)+c.a2*cos(2*w), di=-c.a1*sin(w)-c.a2*sin(2*w);
    return 10*log10(fmax((nr*nr+ni*ni)/(dr*dr+di*di),1e-30));
}

HEDSP *HECreate(double rate) {
    if (!isfinite(rate) || rate<32000 || rate>384000) return NULL;
    HEDSP *d=calloc(1,sizeof(*d)); if(!d) return NULL;
    d->rate=rate; d->fadeLength=(uint32_t)(rate*.025);
    d->active.gain=d->next.gain=0;
    for(int i=0;i<HE_MAX_FILTERS;i++) d->active.c[i]=d->next.c[i]=unity();
    for(int i=0;i<HE_MAX_FILTERS*5+1;i++) atomic_init(&d->pending[i],0);
    atomic_init(&d->version,0); atomic_init(&d->frames,0); atomic_init(&d->clipped,0);
    atomic_init(&d->invalid,0); atomic_init(&d->inPeak,0); atomic_init(&d->outPeak,0);
    return d;
}
void HEDestroy(HEDSP *d) { free(d); }

void HESetFilters(HEDSP *d, const HEFilter *filters, uint32_t count, double preamp) {
    if(!d || !isfinite(preamp)) return;
    // One control-thread writer. Callback never locks or allocates.
    atomic_fetch_add_explicit(&d->version,1,memory_order_acq_rel);
    for(int i=0;i<HE_MAX_FILTERS;i++) {
        Coeff c=(i<count && filters) ? coefficients(filters[i],d->rate) : unity();
        double values[5]={c.b0,c.b1,c.b2,c.a1,c.a2};
        for(int j=0;j<5;j++) atomic_store_explicit(&d->pending[i*5+j],values[j],memory_order_relaxed);
    }
    atomic_store_explicit(&d->pending[HE_MAX_FILTERS*5],pow(10,fmin(0,fmax(-60,preamp))/20),memory_order_relaxed);
    atomic_fetch_add_explicit(&d->version,1,memory_order_release);
}

static void update(HEDSP *d) {
    if(d->fade) return;
    uint64_t v=atomic_load_explicit(&d->version,memory_order_acquire);
    if(v==d->applied || (v&1)) return;
    Bank b={0};
    for(int i=0;i<HE_MAX_FILTERS;i++) {
        double x[5]; for(int j=0;j<5;j++) x[j]=atomic_load_explicit(&d->pending[i*5+j],memory_order_relaxed);
        b.c[i]=(Coeff){x[0],x[1],x[2],x[3],x[4]};
    }
    b.gain=atomic_load_explicit(&d->pending[HE_MAX_FILTERS*5],memory_order_relaxed);
    atomic_thread_fence(memory_order_acquire);
    if(v!=atomic_load_explicit(&d->version,memory_order_acquire)) return;
    d->next=b; d->applied=v; d->fade=d->fadeLength;
}
static double filter(Bank *b, int channel, double x) {
    x*=b->gain;
    for(int i=0;i<HE_MAX_FILTERS;i++) {
        Coeff c=b->c[i]; double *z=b->z[channel][i];
        double y=c.b0*x+z[0]; z[0]=c.b1*x-c.a1*y+z[1]; z[1]=c.b2*x-c.a2*y;
        if(fabs(z[0])<1e-28) z[0]=0; if(fabs(z[1])<1e-28) z[1]=0;
        x=y;
    }
    return x;
}
static void stereo(HEDSP *d, float l, float r, float *ol, float *or, float *ip, float *op, uint64_t *clip, uint64_t *invalid) {
    float in[2]={l,r}, out[2];
    double mix=d->fade ? 1-(double)d->fade/d->fadeLength : 0;
    for(int ch=0;ch<2;ch++) {
        double x=in[ch]; if(!isfinite(x)) {x=0;(*invalid)++;}
        *ip=fmaxf(*ip,fabsf((float)x));
        double y=filter(&d->active,ch,x);
        if(d->fade) y=y*(1-mix)+filter(&d->next,ch,x)*mix;
        if(!isfinite(y)) { y=0;(*invalid)++; }
        if(fabs(y)>1) { y=fmax(-1,fmin(1,y));(*clip)++; }
        out[ch]=(float)y; *op=fmaxf(*op,fabsf(out[ch]));
    }
    if(d->fade && --d->fade==0) d->active=d->next;
    *ol=out[0]; *or=out[1];
}
static void meters(HEDSP *d, uint32_t n, float ip, float op, uint64_t clip, uint64_t invalid) {
    atomic_store_explicit(&d->inPeak,ip,memory_order_relaxed);
    atomic_store_explicit(&d->outPeak,op,memory_order_relaxed);
    atomic_fetch_add_explicit(&d->frames,n,memory_order_relaxed);
    atomic_fetch_add_explicit(&d->clipped,clip,memory_order_relaxed);
    atomic_fetch_add_explicit(&d->invalid,invalid,memory_order_relaxed);
}
void HEProcessStereo(HEDSP *d, const float *in, float *out, uint32_t n) {
    update(d); float ip=0,op=0; uint64_t clip=0,invalid=0;
    for(uint32_t i=0;i<n;i++) stereo(d,in[2*i],in[2*i+1],&out[2*i],&out[2*i+1],&ip,&op,&clip,&invalid);
    meters(d,n,ip,op,clip,invalid);
}
HEMeters HEGetMeters(const HEDSP *d) {
    return (HEMeters){atomic_load(&d->inPeak),atomic_load(&d->outPeak),atomic_load(&d->frames),atomic_load(&d->clipped),atomic_load(&d->invalid)};
}
static uint32_t frames(const AudioBufferList *b) {
    uint32_t n=UINT32_MAX;
    for(uint32_t i=0;i<b->mNumberBuffers;i++) {
        const AudioBuffer *x=&b->mBuffers[i];
        if(x->mData && x->mNumberChannels) n=fmin(n,x->mDataByteSize/(sizeof(float)*x->mNumberChannels));
    }
    return n==UINT32_MAX?0:n;
}
static float sample(const AudioBufferList *b, uint32_t frame, uint32_t channel) {
    for(uint32_t i=0;i<b->mNumberBuffers;i++) {
        const AudioBuffer *x=&b->mBuffers[i];
        if(channel<x->mNumberChannels) return x->mData?((const float*)x->mData)[frame*x->mNumberChannels+channel]:0;
        channel-=x->mNumberChannels;
    }
    return 0;
}
static void put(AudioBufferList *b,uint32_t frame,uint32_t channel,float value) {
    for(uint32_t i=0;i<b->mNumberBuffers;i++) {
        AudioBuffer *x=&b->mBuffers[i];
        if(channel<x->mNumberChannels) {if(x->mData)((float*)x->mData)[frame*x->mNumberChannels+channel]=value;return;}
        channel-=x->mNumberChannels;
    }
}
OSStatus HEAudioCallback(AudioObjectID device,const AudioTimeStamp *now,const AudioBufferList *in,const AudioTimeStamp *it,AudioBufferList *out,const AudioTimeStamp *ot,void *context) {
    (void)device;(void)now;(void)it;(void)ot;
    for(uint32_t i=0;i<out->mNumberBuffers;i++) if(out->mBuffers[i].mData) memset(out->mBuffers[i].mData,0,out->mBuffers[i].mDataByteSize);
    HEDSP *d=context; if(!d) return noErr;
    update(d); uint32_t n=fmin(frames(in),frames(out)); float ip=0,op=0; uint64_t clip=0,invalid=0;
    for(uint32_t i=0;i<n;i++) {
        float l,r; stereo(d,sample(in,i,0),sample(in,i,1),&l,&r,&ip,&op,&clip,&invalid);
        put(out,i,0,l);put(out,i,1,r);
    }
    meters(d,n,ip,op,clip,invalid); return noErr;
}
