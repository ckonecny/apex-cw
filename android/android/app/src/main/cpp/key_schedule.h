// Sample-accurate keying for CwGenerator.
//
// The generator queues "tone on/off for N ms" segments a little ahead of time
// and the audio callback counts them off in samples, so an edge lands on the
// right sample wherever the audio blocks happen to fall. Without this a tone
// could only start or stop at a block boundary: harmless with the 2 ms blocks
// of the speaker path, audibly uneven over Bluetooth (DECISIONS.md).
//
// Threads: push()/setEpoch() run on generator threads (a stopping generator can
// briefly overlap the next one, hence the producer mutex). beginBlock(),
// nextSample() and endBlock() run on the audio callback and never lock.
//
// An epoch identifies one playback. Changing it drops whatever is queued or
// playing, at the next block, and restarts the played-time count.

#pragma once

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <mutex>

class KeySchedule {
public:
    static constexpr uint32_t kCapacity = 1u << 12;  // far above the ~100 ms the generator queues

    enum Key { kNothing = -1, kOff = 0, kOn = 1 };

    void setEpoch(int32_t epoch) { epoch_.store(epoch, std::memory_order_release); }

    // False if the queue is full (the caller waits and retries).
    bool push(int32_t epoch, bool on, int32_t ms) { return add(Segment{epoch, ms, on, false}); }

    // Silence until [ms] have passed since the last queued segment ended,
    // counted in samples, so a separate playback can start at an exact distance
    // from the previous one. Nothing if that much silence has already passed.
    bool pushIdleGap(int32_t epoch, int32_t ms) { return add(Segment{epoch, ms, false, true}); }

    // How much of this epoch's queue has been rendered, in ms. -1 while its
    // first tone or pause has not begun: another epoch is current, nothing has
    // been queued yet, or an idle gap is still running.
    int64_t playedMs(int32_t epoch) const {
        const uint64_t p = position_.load(std::memory_order_acquire);
        if ((p >> kEpochShift) != epochBits(epoch)) return -1;
        const uint64_t micros = p & kMicrosMask;
        return micros == kMicrosMask ? -1 : static_cast<int64_t>(micros / 1000);
    }

    void beginBlock(double sampleRate) {
        rate_ = sampleRate;
        const int32_t e = epoch_.load(std::memory_order_acquire);
        if (e != active_) {
            active_ = e;
            left_ = 0;
            done_ = 0;
            segMicros_ = 0;
            finishedMicros_ = 0;
            waiting_ = false;
            started_ = false;
        }
    }

    // State for the next sample; kNothing when no segment is scheduled.
    Key nextSample() {
        if (left_ == 0 && !popSegment()) {
            ++idleFrames_;
            return kNothing;
        }
        --left_;
        ++done_;
        return on_ ? kOn : kOff;
    }

    void endBlock() {
        const int64_t partial = rate_ > 0 ? std::llround(done_ * 1e6 / rate_) : 0;
        const uint64_t micros = (waiting_ || !started_) ? kMicrosMask
            : std::min(static_cast<uint64_t>(finishedMicros_ + partial), kMicrosMask - 1);
        position_.store((epochBits(active_) << kEpochShift) | micros, std::memory_order_release);
    }

private:
    struct Segment { int32_t epoch; int32_t ms; bool on; bool untilIdle; };

    bool add(const Segment& s) {
        if (s.ms <= 0) return true;
        std::lock_guard<std::mutex> lock(producerMutex_);
        const uint32_t h = head_.load(std::memory_order_relaxed);
        if (h - tail_.load(std::memory_order_acquire) >= kCapacity) return false;
        ring_[h & (kCapacity - 1)] = s;
        head_.store(h + 1, std::memory_order_release);
        return true;
    }

    static constexpr int kEpochShift = 40;
    static constexpr uint64_t kMicrosMask = (1ULL << kEpochShift) - 1;
    static uint64_t epochBits(int32_t epoch) { return static_cast<uint32_t>(epoch) & 0xFFFFFFu; }

    bool popSegment() {
        finishedMicros_ += segMicros_;
        segMicros_ = 0;
        done_ = 0;
        waiting_ = false;
        uint32_t t = tail_.load(std::memory_order_relaxed);
        const uint32_t h = head_.load(std::memory_order_acquire);
        bool found = false;
        while (t != h && !found) {
            const Segment s = ring_[t & (kCapacity - 1)];
            // Queued for a playback that began during this block: its turn is next block.
            if (s.epoch != active_ && s.epoch == epoch_.load(std::memory_order_acquire)) break;
            ++t;
            if (s.epoch != active_) continue;  // left over from a stopped playback
            const int64_t frames = std::max<int64_t>(1, std::llround(s.ms * rate_ / 1000.0));
            if (s.untilIdle) {
                if (frames <= idleFrames_) continue;   // already that quiet
                left_ = frames - idleFrames_;
                on_ = false;
                waiting_ = true;                       // not part of the played time
            } else {
                left_ = frames;
                on_ = s.on;
                segMicros_ = s.ms * 1000LL;
                idleFrames_ = 0;
                started_ = true;
            }
            found = true;
        }
        tail_.store(t, std::memory_order_release);
        return found;
    }

    Segment ring_[kCapacity] = {};
    std::atomic<uint32_t> head_{0};
    std::atomic<uint32_t> tail_{0};
    std::atomic<int32_t> epoch_{0};
    std::atomic<uint64_t> position_{0};
    std::mutex producerMutex_;

    // Audio callback only.
    int32_t active_ = 0;
    double rate_ = 48000.0;
    int64_t left_ = 0;
    int64_t done_ = 0;
    int64_t segMicros_ = 0;
    int64_t finishedMicros_ = 0;
    int64_t idleFrames_ = 1LL << 40;  // long silence before the first playback
    bool on_ = false;
    bool waiting_ = false;
    bool started_ = false;
};
