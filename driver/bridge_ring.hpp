#ifndef SOTTO_BRIDGE_RING_HPP
#define SOTTO_BRIDGE_RING_HPP

#include <atomic>
#include <cstdint>
#include <cstring>
#include <vector>

// Sample-time-indexed circular buffer for the bridge->mic path.
//
// The frame for absolute sample time t lives at index (t mod capacity). The
// single writer (the Sotto app, via the bridge output) stores frames and
// advances an atomic write-end marker; any number of readers (call apps, via
// the mic input) fetch by absolute time without consuming, so multiple apps can
// read the same mic concurrently. Lock-free and allocation-free on the IO path.
class BridgeRing {
public:
    explicit BridgeRing(uint32_t capacity_frames = 8192) {
        uint32_t cap = 2;
        while (cap < capacity_frames) cap <<= 1;
        capacity_ = cap;
        mask_ = cap - 1;
        buf_.assign(cap, 0.0f);
        write_end_.store(0, std::memory_order_relaxed);
        started_.store(false, std::memory_order_relaxed);
    }

    // Store n frames beginning at absolute sample time `ts`.
    void store(int64_t ts, const float* src, uint32_t n) {
        for (uint32_t i = 0; i < n; i++) {
            buf_[(uint64_t)(ts + i) & mask_] = src[i];
        }
        write_end_.store(ts + n, std::memory_order_release);
        started_.store(true, std::memory_order_release);
    }

    // Fetch n frames beginning at absolute sample time `ts` into dst.
    // Frames outside the written window are zero-filled. Returns true if the
    // whole request was inside the written window.
    bool fetch(int64_t ts, float* dst, uint32_t n) const {
        if (!started_.load(std::memory_order_acquire)) {
            std::memset(dst, 0, n * sizeof(float));
            return false;
        }
        int64_t end = write_end_.load(std::memory_order_acquire);
        int64_t begin = end - (int64_t)capacity_;
        bool complete = true;
        for (uint32_t i = 0; i < n; i++) {
            int64_t t = ts + i;
            if (t >= begin && t < end) {
                dst[i] = buf_[(uint64_t)t & mask_];
            } else {
                dst[i] = 0.0f;
                complete = false;
            }
        }
        return complete;
    }

private:
    std::vector<float> buf_;
    uint32_t capacity_ = 0;
    uint32_t mask_ = 0;
    std::atomic<int64_t> write_end_;
    std::atomic<bool> started_;
};

#endif
