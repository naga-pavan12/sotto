#include "include/resampler.h"
#include <AudioToolbox/AudioToolbox.h>
#include <stdlib.h>
#include <string.h>

struct Resampler {
    AudioConverterRef conv;
    const float *inPtr;
    uint32_t inFrames;
    uint32_t inPos;
};

static AudioStreamBasicDescription monoFloat(double rate) {
    AudioStreamBasicDescription a = {0};
    a.mSampleRate = rate;
    a.mFormatID = kAudioFormatLinearPCM;
    a.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    a.mBitsPerChannel = 32;
    a.mChannelsPerFrame = 1;
    a.mBytesPerFrame = 4;
    a.mFramesPerPacket = 1;
    a.mBytesPerPacket = 4;
    return a;
}

Resampler *rs_create(double in_rate, double out_rate) {
    Resampler *r = (Resampler *)calloc(1, sizeof(Resampler));
    if (!r) return NULL;
    AudioStreamBasicDescription in = monoFloat(in_rate), out = monoFloat(out_rate);
    if (AudioConverterNew(&in, &out, &r->conv) != noErr) {
        free(r);
        return NULL;
    }
    return r;
}

static OSStatus feed(AudioConverterRef conv, UInt32 *ioPackets, AudioBufferList *ioData,
                     AudioStreamPacketDescription **outPkts, void *userData) {
    (void)conv;
    (void)outPkts;
    Resampler *r = (Resampler *)userData;
    uint32_t remaining = r->inFrames - r->inPos;
    uint32_t give = (*ioPackets < remaining) ? *ioPackets : remaining;
    ioData->mNumberBuffers = 1;
    ioData->mBuffers[0].mNumberChannels = 1;
    ioData->mBuffers[0].mData = (void *)(r->inPtr + r->inPos);
    ioData->mBuffers[0].mDataByteSize = give * sizeof(float);
    r->inPos += give;
    *ioPackets = give;
    return noErr;
}

uint32_t rs_process(Resampler *r, const float *in, uint32_t n_in, float *out, uint32_t max_out) {
    if (!r || !in || !out) return 0;
    r->inPtr = in;
    r->inFrames = n_in;
    r->inPos = 0;
    AudioBufferList abl;
    abl.mNumberBuffers = 1;
    abl.mBuffers[0].mNumberChannels = 1;
    abl.mBuffers[0].mDataByteSize = max_out * sizeof(float);
    abl.mBuffers[0].mData = out;
    UInt32 outPackets = max_out;
    OSStatus st = AudioConverterFillComplexBuffer(r->conv, feed, r, &outPackets, &abl, NULL);
    if (st != noErr && outPackets == 0) return 0;
    return outPackets;
}

void rs_destroy(Resampler *r) {
    if (!r) return;
    if (r->conv) AudioConverterDispose(r->conv);
    free(r);
}
