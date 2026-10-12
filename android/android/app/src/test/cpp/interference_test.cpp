// Host test for interference.h (pure DSP, no Android): feeds it every
// combination of extreme and random settings and checks that the output stays
// finite and within the limiter's range, and that nothing reads or writes out
// of bounds (build with -fsanitize=address,undefined, see
// tools/run_native_cpp_tests.sh).
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

#include "../../main/cpp/interference.h"

static int failures = 0;
static long long samples = 0;

#define CHECK(cond, ...)                                  \
    do {                                                  \
        if (!(cond)) {                                    \
            std::printf("FAIL %s:%d: ", __FILE__, __LINE__); \
            std::printf(__VA_ARGS__);                     \
            std::printf("\n");                            \
            ++failures;                                   \
            return;                                       \
        }                                                 \
    } while (0)

static float frand(float lo, float hi) {
    return lo + (hi - lo) * (std::rand() / (float)RAND_MAX);
}

// One scenario: `blocks` blocks of `frames` frames. The "tone" input is a
// keyed sine, as the audio callback produces it.
static void run(double sr, double fc, float noise, float qrm, float qsb, float drift,
                float filter, float color, bool rx, bool ambient, bool clean,
                int frames, int blocks, float vol, bool boundedOutput) {
    Interference in;
    in.setParams(noise, qrm, qsb, drift, filter, color);
    in.setRx(rx);
    in.setAmbient(ambient);
    in.setClean(clean);
    double phase = 0.0;
    for (int b = 0; b < blocks; ++b) {
        in.beginBlock(sr, fc, vol, frames);
        const double step = 2.0 * M_PI * (fc + in.freqOffsetHz()) / sr;
        CHECK(std::isfinite(step), "step not finite (sr %.0f fc %.0f)", sr, fc);
        const bool keyDown = (b / 3) % 2 == 0;
        for (int i = 0; i < frames; ++i) {
            const float tone = keyDown ? static_cast<float>(std::sin(phase) * vol) : 0.0f;
            phase += step;
            if (phase > 2.0 * M_PI) phase -= 2.0 * M_PI;
            const float y = in.process(tone);
            ++samples;
            CHECK(std::isfinite(y),
                  "non-finite output sr=%.0f fc=%.0f n=%.2f q=%.2f s=%.2f d=%.2f f=%.2f c=%.2f "
                  "rx=%d amb=%d clean=%d frames=%d",
                  sr, fc, noise, qrm, qsb, drift, filter, color, rx, ambient, clean, frames);
            if (boundedOutput)
                CHECK(std::fabs(y) <= 1.0001f, "output %.4f outside [-1,1] sr=%.0f fc=%.0f", y, sr, fc);
        }
    }
}

int main() {
    std::srand(12345);
    const double rates[]  = {8000, 16000, 22050, 44100, 48000, 96000};
    const double pitches[] = {100, 300, 600, 1000, 2000, 3500};
    const int    frames[] = {1, 17, 64, 192, 480, 4096};
    const float  levels[] = {0.0f, 0.25f, 0.5f, 1.0f};

    // fixed corners: everything off, everything at maximum, each switch alone
    for (double sr : rates)
        for (double fc : pitches)
            for (int fr : frames) {
                run(sr, fc, 0, 0, 0, 0, 0, 0.5f, true, false, false, fr, 12, 0.7f, true);
                run(sr, fc, 1, 1, 1, 1, 1, 1.0f, true, true, false, fr, 12, 1.0f, true);
                run(sr, fc, 1, 1, 1, 1, 1, 0.0f, true, true, true, fr, 12, 1.0f, true);
                run(sr, fc, 1, 0, 0, 0, 1, 0.5f, false, true, false, fr, 12, 0.7f, true);
            }

    // random combinations of the levels
    for (int n = 0; n < 400; ++n) {
        const double sr = rates[std::rand() % 6];
        const double fc = pitches[std::rand() % 6];
        run(sr, fc, levels[std::rand() % 4], levels[std::rand() % 4], levels[std::rand() % 4],
            levels[std::rand() % 4], frand(0, 1), frand(0, 1), std::rand() % 2, std::rand() % 2,
            std::rand() % 2, frames[std::rand() % 6], 30, frand(0.05f, 1.0f), true);
    }

    // out-of-range settings must not produce NaN/Inf or crash (only finiteness is required)
    for (double sr : rates)
        run(sr, 600, -0.5f, 2.0f, -1.0f, 3.0f, 5.0f, -2.0f, true, true, false, 192, 20, 0.7f, false);
    run(48000, 5.0, 1, 1, 1, 1, 1, 1, true, true, false, 192, 20, 0.7f, false);   // very low pitch
    run(48000, 20000.0, 1, 1, 1, 1, 1, 1, true, true, false, 192, 20, 0.7f, false);   // near Nyquist

    if (failures == 0) std::printf("interference_test: all scenarios passed (%lld samples)\n", samples);
    return failures == 0 ? 0 : 1;
}
