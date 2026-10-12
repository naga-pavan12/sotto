#include "include/spsc_ring.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

// Single-producer/single-consumer ring. `head` is advanced only by the reader,
// `tail` only by the writer. Capacity is a power of two; one slot is left empty
// so a full ring is distinguishable from an empty one. No locks, no allocation
// in read/write.
struct SpscRing {
    float *buf;
    uint32_t capacity; // power of two
    uint32_t mask;     // capacity - 1
    _Atomic uint32_t head; // next index to read
    _Atomic uint32_t tail; // next index to write
};

static uint32_t next_pow2(uint32_t v) {
    if (v < 2) return 2;
    v--;
    v |= v >> 1; v |= v >> 2; v |= v >> 4; v |= v >> 8; v |= v >> 16;
    return v + 1;
}

SpscRing *spsc_create(uint32_t capacity_frames) {
    SpscRing *r = (SpscRing *)calloc(1, sizeof(SpscRing));
    if (!r) return NULL;
    r->capacity = next_pow2(capacity_frames);
    r->mask = r->capacity - 1;
    r->buf = (float *)calloc(r->capacity, sizeof(float));
    if (!r->buf) { free(r); return NULL; }
    atomic_init(&r->head, 0);
    atomic_init(&r->tail, 0);
    return r;
}

uint32_t spsc_write(SpscRing *r, const float *src, uint32_t n) {
    if (!r || !src) return 0;
    uint32_t tail = atomic_load_explicit(&r->tail, memory_order_relaxed);
    uint32_t head = atomic_load_explicit(&r->head, memory_order_acquire);
    uint32_t free_slots = (head - tail - 1) & r->mask; // one slot kept empty
    if (n > free_slots) n = free_slots;
    for (uint32_t i = 0; i < n; i++) {
        r->buf[(tail + i) & r->mask] = src[i];
    }
    atomic_store_explicit(&r->tail, (tail + n) & r->mask, memory_order_release);
    return n;
}

uint32_t spsc_read(SpscRing *r, float *dst, uint32_t n) {
    if (!r || !dst) return 0;
    uint32_t head = atomic_load_explicit(&r->head, memory_order_relaxed);
    uint32_t tail = atomic_load_explicit(&r->tail, memory_order_acquire);
    uint32_t avail = (tail - head) & r->mask;
    if (n > avail) n = avail;
    for (uint32_t i = 0; i < n; i++) {
        dst[i] = r->buf[(head + i) & r->mask];
    }
    atomic_store_explicit(&r->head, (head + n) & r->mask, memory_order_release);
    return n;
}

uint32_t spsc_fill(const SpscRing *r) {
    if (!r) return 0;
    uint32_t head = atomic_load_explicit(&r->head, memory_order_acquire);
    uint32_t tail = atomic_load_explicit(&r->tail, memory_order_acquire);
    return (tail - head) & r->mask;
}

void spsc_destroy(SpscRing *r) {
    if (!r) return;
    free(r->buf);
    free(r);
}
