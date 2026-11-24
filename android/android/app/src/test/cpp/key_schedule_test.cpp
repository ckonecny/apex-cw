// Host test for KeySchedule: every tone and pause must come out exactly as many
// samples long as queued, whatever the audio block size and however blocks
// straddle the edges. Run by tools/run_native_cpp_tests.sh with ASan/UBSan.

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <vector>

#include "../../main/cpp/key_schedule.h"

static int failures = 0;

static void check(bool ok, const char* what, long a = 0, long b = 0) {
    if (!ok) {
        std::printf("FAIL %s (%ld vs %ld)\n", what, a, b);
        ++failures;
    }
}

struct Run { bool on; long frames; };

// Renders until the schedule is empty and returns the runs of equal key state.
static std::vector<Run> render(KeySchedule& k, double rate, int block, bool jitterBlocks = false) {
    std::vector<Run> runs;
    for (int guard = 0; guard < 10000000; ++guard) {
        const int n = jitterBlocks ? 1 + std::rand() % (block * 2) : block;
        k.beginBlock(rate);
        bool idle = false;
        for (int i = 0; i < n; ++i) {
            const KeySchedule::Key s = k.nextSample();
            if (s == KeySchedule::kNothing) { idle = true; continue; }
            check(!idle, "samples after the schedule ran empty");
            const bool on = s == KeySchedule::kOn;
            if (runs.empty() || runs.back().on != on) runs.push_back({on, 0});
            ++runs.back().frames;
        }
        k.endBlock();
        if (idle) return runs;
    }
    check(false, "schedule never ran empty");
    return runs;
}

static void exactLengths() {
    for (double rate : {8000.0, 44100.0, 48000.0, 96000.0}) {
        for (int block : {1, 7, 48, 96, 240, 480, 768, 1920, 4096}) {
            for (bool jitter : {false, true}) {
                static int epoch = 0;
                KeySchedule* k = new KeySchedule();
                k->setEpoch(++epoch);
                const std::vector<std::pair<bool, int>> plan =
                    {{true, 60}, {false, 60}, {true, 180}, {false, 180}, {true, 20}, {false, 420}, {true, 1}};
                for (auto& p : plan) check(k->push(epoch, p.first, p.second), "push");
                const auto runs = render(*k, rate, block, jitter);
                check(runs.size() == plan.size(), "run count", (long)runs.size(), (long)plan.size());
                for (size_t i = 0; i < runs.size() && i < plan.size(); ++i) {
                    const long want = std::max<long>(1, std::lround(plan[i].second * rate / 1000.0));
                    check(runs[i].on == plan[i].first, "run state");
                    check(runs[i].frames == want, "run length", runs[i].frames, want);
                }
                long totalMs = 0;
                for (auto& p : plan) totalMs += p.second;
                check(k->playedMs(epoch) == totalMs, "played", (long)k->playedMs(epoch), totalMs);
                delete k;
            }
        }
    }
}

static void newEpochDropsTheOldQueue() {
    KeySchedule* k = new KeySchedule();
    k->setEpoch(1);
    k->push(1, true, 1000);
    k->beginBlock(48000); for (int i = 0; i < 96; ++i) k->nextSample(); k->endBlock();
    check(k->playedMs(1) == 2, "played 2 ms", (long)k->playedMs(1), 2);
    k->setEpoch(2);
    check(k->playedMs(2) == -1, "new epoch has not started");
    k->push(1, true, 500);      // a stopping generator that is still queueing
    k->push(2, false, 10);
    const auto runs = render(*k, 48000, 96);
    check(runs.size() == 1 && !runs[0].on && runs[0].frames == 480, "only the new epoch plays");
    check(k->playedMs(1) == -1, "old epoch no longer reports");
    delete k;
}

// A tone, then idle samples, then a new epoch that waits for an idle gap.
static long gapBetweenPlaybacks(int block, long idleBlocksBefore, int gapMs) {
    KeySchedule* k = new KeySchedule();
    k->setEpoch(1);
    k->push(1, true, 10);
    long lastOn = -1, firstOn2 = -1, frame = 0;
    int epoch = 1;
    long idleLeft = idleBlocksBefore;
    for (int guard = 0; guard < 200000 && firstOn2 < 0; ++guard) {
        k->beginBlock(48000);
        bool ended = false;
        for (int i = 0; i < block; ++i, ++frame) {
            const KeySchedule::Key s = k->nextSample();
            if (s == KeySchedule::kOn) {
                if (epoch == 1) lastOn = frame;
                else { firstOn2 = frame; break; }
            }
            if (epoch == 1 && lastOn >= 0 && s == KeySchedule::kNothing) ended = true;
        }
        k->endBlock();
        if (epoch == 1 && ended && idleLeft-- <= 0) {
            epoch = 2;
            k->setEpoch(2);
            k->pushIdleGap(2, gapMs);
            k->push(2, true, 10);
            check(k->playedMs(2) == -1, "gap not started");
        }
    }
    delete k;
    return firstOn2 - lastOn - 1;
}

static void idleGapIsExact() {
    const int gapMs = 420;
    const long want = gapMs * 48;
    for (int block : {1, 96, 240, 480, 768, 1920}) {
        // Requested early enough: the gap is exact to the sample.
        for (long idle : {0L, 3L}) {
            if ((idle + 2) * block >= want) continue;
            const long got = gapBetweenPlaybacks(block, idle, gapMs);
            check(got == want, "idle gap exact", got, want);
        }
    }
    // Requested only after the gap has passed: starts at once, not a gap later.
    const long late = gapBetweenPlaybacks(96, 400, gapMs);
    check(late > want && late <= 96 * 403, "late start", late, want);
}

// A playback queued while a block is already running must wait for the next block.
static void epochChangeDuringABlockKeepsTheNewQueue() {
    KeySchedule* k = new KeySchedule();
    k->setEpoch(1);
    k->beginBlock(48000);
    k->setEpoch(2);
    k->push(2, true, 10);
    check(k->nextSample() == KeySchedule::kNothing, "waits for the next block");
    k->endBlock();
    const auto runs = render(*k, 48000, 96);
    check(runs.size() == 1 && runs[0].on && runs[0].frames == 480, "first tone is not lost");
    delete k;
}

static void notStartedUntilTheFirstSegment() {
    KeySchedule* k = new KeySchedule();
    k->setEpoch(1);
    k->beginBlock(48000); k->nextSample(); k->endBlock();
    check(k->playedMs(1) == -1, "no position before the first segment");
    k->push(1, true, 10);
    k->beginBlock(48000); k->nextSample(); k->endBlock();
    check(k->playedMs(1) == 0, "started", (long)k->playedMs(1), 0);
    delete k;
}

static void emptyMeansNothing() {
    KeySchedule* k = new KeySchedule();
    k->beginBlock(48000);
    check(k->nextSample() == KeySchedule::kNothing, "empty schedule");
    k->endBlock();
    delete k;
}

static void fullQueueRefuses() {
    KeySchedule* k = new KeySchedule();
    k->setEpoch(1);
    for (uint32_t i = 0; i < KeySchedule::kCapacity; ++i) check(k->push(1, true, 1), "fill");
    check(!k->push(1, true, 1), "full queue must refuse");
    delete k;
}

// Renders [frames] samples in blocks of 96 at [rate], noting the first and
// the last tone sample (frame indices counted on in [frame]).
static void renderFrames(KeySchedule& k, double rate, long frames, long& frame, long& firstOn, long& lastOn) {
    long left = frames;
    while (left > 0) {
        const int n = static_cast<int>(std::min<long>(96, left));
        k.beginBlock(rate);
        for (int i = 0; i < n; ++i, ++frame) {
            if (k.nextSample() == KeySchedule::kOn) {
                lastOn = frame;
                if (firstOn < 0) firstOn = frame;
            }
        }
        k.endBlock();
        left -= n;
    }
}

// Plays [first] for [beforeStopMs], stops it with a new epoch that waits for a
// 420 ms gap and plays a tone; returns the silence between the last tone
// sample before the stop and the first tone sample after it.
static long gapAfterStop(const std::vector<std::pair<bool, int>>& first, long beforeStopMs) {
    KeySchedule* k = new KeySchedule();
    k->setEpoch(1);
    for (auto& p : first) k->push(1, p.first, p.second);
    long frame = 0, firstOn1 = -1, lastOn1 = -1;
    renderFrames(*k, 48000, beforeStopMs * 48, frame, firstOn1, lastOn1);
    k->setEpoch(2);
    k->pushIdleGap(2, 420);
    k->push(2, true, 10);
    long firstOn2 = -1, lastOn2 = -1;
    renderFrames(*k, 48000, 2000 * 48, frame, firstOn2, lastOn2);
    delete k;
    return firstOn2 - lastOn1 - 1;
}

// #193: the gap is measured from the last tone, also when the previous
// playback was stopped in one of its pauses or in the middle of a tone.
static void gapAfterAStoppedPlaybackCountsFromItsLastTone() {
    const long want = 420 * 48;
    // stopped 100 ms into a 500 ms pause: those 100 ms are already silence
    long got = gapAfterStop({{true, 10}, {false, 500}, {true, 10}}, 110);
    check(got == want, "gap after a stop in a pause", got, want);
    // stopped 200 ms into a 1 s tone: the tone ends at the stop
    got = gapAfterStop({{true, 1000}}, 200);
    check(got == want, "gap after a stop mid-tone", got, want);
}

// #193: a new stream at another sample rate keeps the durations: the silence
// already counted and the rest of a running segment.
static void sampleRateChangeKeepsDurations() {
    {
        KeySchedule* k = new KeySchedule();
        k->setEpoch(1);
        k->push(1, true, 10);
        long frame = 0, firstOn = -1, lastOn = -1;
        renderFrames(*k, 48000, 210 * 48, frame, firstOn, lastOn);   // tone + 200 ms silence
        k->setEpoch(2);
        k->pushIdleGap(2, 420);
        k->push(2, true, 10);
        // the rest of the gap, 220 ms, at 24 kHz
        long silent = 0;
        bool on = false;
        for (int guard = 0; guard < 1000 && !on; ++guard) {
            k->beginBlock(24000);
            for (int i = 0; i < 48 && !on; ++i) {
                if (k->nextSample() == KeySchedule::kOn) on = true; else ++silent;
            }
            k->endBlock();
        }
        check(silent == 220 * 24, "rest of the gap after a rate change", silent, 220 * 24);
        delete k;
    }
    {
        KeySchedule* k = new KeySchedule();
        k->setEpoch(1);
        k->push(1, true, 100);
        long frame = 0, firstOn = -1, lastOn = -1;
        renderFrames(*k, 48000, 50 * 48, frame, firstOn, lastOn);
        const auto runs = render(*k, 24000, 48);
        check(runs.size() == 1 && runs[0].on && runs[0].frames == 50 * 24,
              "rest of a tone after a rate change", runs.empty() ? 0 : runs[0].frames, 50 * 24);
        check(k->playedMs(1) == 100, "played after a rate change", (long)k->playedMs(1), 100);
        delete k;
    }
}

int main() {
    exactLengths();
    newEpochDropsTheOldQueue();
    idleGapIsExact();
    epochChangeDuringABlockKeepsTheNewQueue();
    notStartedUntilTheFirstSegment();
    emptyMeansNothing();
    fullQueueRefuses();
    gapAfterAStoppedPlaybackCountsFromItsLastTone();
    sampleRateChangeKeepsDurations();
    if (failures) { std::printf("%d failures\n", failures); return 1; }
    std::printf("key_schedule_test: ok\n");
    return 0;
}
