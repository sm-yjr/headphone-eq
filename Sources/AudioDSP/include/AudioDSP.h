// SPDX-License-Identifier: GPL-3.0-only
#ifndef AUDIO_DSP_H
#define AUDIO_DSP_H
#include <CoreAudio/CoreAudio.h>
#include <stdint.h>

typedef enum { HEPeak = 0, HELowShelf = 1, HEHighShelf = 2 } HEFilterType;
typedef struct { double frequency, gain, q; HEFilterType type; } HEFilter;
typedef struct HEDSP HEDSP;
typedef struct { float inputPeak, outputPeak; uint64_t frames, clipped, invalidSamples; } HEMeters;

HEDSP * _Nullable HECreate(double sampleRate);
void HEDestroy(HEDSP * _Nullable dsp);
void HESetFilters(HEDSP * _Nonnull dsp, const HEFilter * _Nullable filters, uint32_t count, double preampDB);
HEMeters HEGetMeters(const HEDSP * _Nonnull dsp);
double HEFilterResponse(HEFilter filter, double sampleRate, double frequency);
void HEProcessStereo(HEDSP * _Nonnull dsp, const float * _Nonnull input, float * _Nonnull output, uint32_t frames);
OSStatus HEAudioCallback(AudioObjectID device, const AudioTimeStamp * _Nonnull now,
    const AudioBufferList * _Nonnull input, const AudioTimeStamp * _Nonnull inputTime,
    AudioBufferList * _Nonnull output, const AudioTimeStamp * _Nonnull outputTime, void * _Nullable context);
#endif
