#ifndef SOTTO_RESAMPLER_H
#define SOTTO_RESAMPLER_H

#include <stdint.h>

// Mono float resampler wrapping Apple's AudioConverter. Used to bring a physical
// mic at any rate to the 48 kHz the denoiser and bridge require.
typedef struct Resampler Resampler;

// Create a resampler from in_rate to out_rate (mono). NULL on failure.
Resampler *rs_create(double in_rate, double out_rate);

// Convert n_in input frames to output; returns frames written (<= max_out).
uint32_t rs_process(Resampler *r, const float *in, uint32_t n_in, float *out, uint32_t max_out);

void rs_destroy(Resampler *r);

#endif
