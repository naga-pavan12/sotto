#ifndef SOTTO_SPSC_RING_H
#define SOTTO_SPSC_RING_H

#include <stdint.h>

/// Lock-free single-producer/single-consumer float ring buffer.
/// One thread calls spsc_write, one thread calls spsc_read; no locks, no
/// allocation in read/write, safe to use from a Core Audio real-time thread.
typedef struct SpscRing SpscRing;

/// Create a ring holding at least `capacity_frames` floats (rounded up to a
/// power of two). Returns NULL on allocation failure.
SpscRing *spsc_create(uint32_t capacity_frames);

/// Write up to `n` floats from `src`. Returns the number actually written
/// (fewer than `n` if the ring is near full).
uint32_t spsc_write(SpscRing *r, const float *src, uint32_t n);

/// Read up to `n` floats into `dst`. Returns the number actually read.
uint32_t spsc_read(SpscRing *r, float *dst, uint32_t n);

/// Current number of readable floats.
uint32_t spsc_fill(const SpscRing *r);

/// Free a ring created by spsc_create.
void spsc_destroy(SpscRing *r);

#endif
