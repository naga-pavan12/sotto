#ifndef SOTTO_DENOISER_H
#define SOTTO_DENOISER_H

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

/**
 * Opaque denoiser handle, created by [`sotto_denoiser_new`].
 */
typedef struct SottoDenoiser SottoDenoiser;

/**
 * Create a denoiser with the embedded DeepFilterNet3 model (mono, 48 kHz).
 * Returns NULL if the model fails to load.
 */
struct SottoDenoiser *sotto_denoiser_new(void);

/**
 * Samples consumed and produced per [`sotto_denoiser_process`] call (480).
 *
 * # Safety
 * `d` must be null or a valid handle from [`sotto_denoiser_new`].
 */
uint32_t sotto_denoiser_hop_size(const struct SottoDenoiser *d);

/**
 * Algorithmic look-ahead latency in samples.
 *
 * # Safety
 * `d` must be null or a valid handle from [`sotto_denoiser_new`].
 */
uint32_t sotto_denoiser_latency_samples(const struct SottoDenoiser *d);

/**
 * Set the attenuation limit in dB. 0 means no reduction (passthrough); values at
 * or above 100 mean unlimited reduction. Sotto maps `strength` (0..100) to
 * `strength * 0.4` dB, with strength 100 passed as 100.0 for full reduction.
 *
 * # Safety
 * `d` must be null or a valid handle from [`sotto_denoiser_new`].
 */
void sotto_denoiser_set_atten_lim_db(struct SottoDenoiser *d, float db);

/**
 * Enhance one hop of `hop_size` mono samples.
 *
 * Returns 0 on success, -2 for a null argument, -1 if the model errors (in which
 * case `output` is left untouched and the caller should pass the input through).
 *
 * # Safety
 * `d` must be null or a valid handle; `input` and `output` must each point to at
 * least `hop_size` writable/readable floats.
 */
int32_t sotto_denoiser_process(struct SottoDenoiser *d, const float *input, float *output);

/**
 * Reset internal model state (e.g. after a device change).
 *
 * # Safety
 * `d` must be null or a valid handle from [`sotto_denoiser_new`].
 */
void sotto_denoiser_reset(struct SottoDenoiser *d);

/**
 * Free a denoiser created by [`sotto_denoiser_new`].
 *
 * # Safety
 * `d` must be null or a valid handle from [`sotto_denoiser_new`], not freed before.
 */
void sotto_denoiser_free(struct SottoDenoiser *d);

#endif  /* SOTTO_DENOISER_H */
